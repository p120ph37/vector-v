module sinks

import event
import json
import time

// DatadogTracesSink sends trace events to the Datadog Traces API.
// Mirrors Vector's datadog_traces sink (src/sinks/datadog/).
//
// Trace events are buffered as JSON objects and flushed as a JSON array
// to {endpoint}/api/v0.2/traces with the DD-API-KEY header.
//
// Config options:
//   api_key:             Datadog API key (required)
//   site:                Datadog site (default: "datadoghq.com")
//   endpoint:            Override endpoint URL (optional)
//   batch.max_events:    Max events per batch (default: 100)
//   batch.timeout_secs:  Batch timeout in seconds (default: 5)
pub struct DatadogTracesSink {
	api_key       string
	endpoint      string
	batch_max     int = 100
	batch_timeout time.Duration = 5 * time.second
mut:
	buffer     []string
	last_flush time.Time
}

// new_datadog_traces creates a new DatadogTracesSink from config options.
pub fn new_datadog_traces(opts map[string]string) !DatadogTracesSink {
	api_key := opts['api_key'] or {
		opts['default_api_key'] or {
			return error('datadog_traces: api_key is required')
		}
	}

	site := opts['site'] or { 'datadoghq.com' }
	endpoint := opts['endpoint'] or { 'https://trace.agent.${site}' }

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
	}

	mut batch_timeout_secs := 5.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 5.0
		}
	}

	return DatadogTracesSink{
		api_key: api_key
		endpoint: endpoint.trim_right('/')
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers a trace event and flushes when batch is full or timeout expires.
// Non-trace events are encoded as generic JSON and included.
pub fn (mut s DatadogTracesSink) send(e event.Event) ! {
	encoded := s.encode_event(e)
	if encoded.len > 0 {
		s.buffer << encoded
	}

	if s.buffer.len >= s.batch_max {
		s.flush()!
	}

	if time.since(s.last_flush) > s.batch_timeout && s.buffer.len > 0 {
		s.flush()!
	}
}

// flush sends all buffered traces to the Datadog Traces API.
pub fn (mut s DatadogTracesSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	// Datadog trace API expects an array of trace arrays
	payload := '[[${s.buffer.join(",")}]]'
	url := '${s.endpoint}/api/v0.2/traces'

	mut http_batch := new_http_batch({
		'endpoint': url
	})

	mut extra_headers := map[string]string{}
	extra_headers['DD-API-KEY'] = s.api_key
	extra_headers['Content-Type'] = 'application/json'

	http_batch.send_payload(payload, extra_headers) or {
		eprintln('datadog_traces: failed to send batch: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &DatadogTracesSink) total_buffered() int {
	return s.buffer.len
}

// encode_event encodes an event as a Datadog span JSON object.
fn (s &DatadogTracesSink) encode_event(e event.Event) string {
	match e {
		event.TraceEvent {
			return s.encode_trace(e)
		}
		event.LogEvent {
			// Wrap log events as span-like objects
			mut parts := []string{}
			parts << '"name":"log"'
			parts << '"resource":${json.encode(e.message())}'
			parts << '"type":"custom"'
			parts << '"meta":${e.to_json()}'
			return '{${parts.join(",")}}'
		}
		event.Metric {
			return json.encode(e)
		}
	}
}

// encode_trace encodes a trace event as a Datadog span JSON object.
fn (s &DatadogTracesSink) encode_trace(t event.TraceEvent) string {
	mut parts := []string{}

	// Standard span fields
	if name := t.fields['name'] {
		parts << '"name":${json.encode(name)}'
	} else {
		parts << '"name":"span"'
	}

	if resource := t.fields['resource'] {
		parts << '"resource":${json.encode(resource)}'
	}

	if service := t.fields['service'] {
		parts << '"service":${json.encode(service)}'
	}

	if span_type := t.fields['type'] {
		parts << '"type":${json.encode(span_type)}'
	}

	// Include all fields as meta
	parts << '"meta":${json.encode(t.fields)}'

	return '{${parts.join(",")}}'
}
