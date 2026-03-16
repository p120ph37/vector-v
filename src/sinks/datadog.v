module sinks

import event
import json
import time

// DatadogSink sends log events to the Datadog Logs API.
// Mirrors Vector's datadog_logs sink (src/sinks/datadog/).
//
// Events are buffered as Datadog log JSON objects and flushed as a JSON array
// to {endpoint}/api/v2/logs with the DD-API-KEY header.
//
// Config options:
//   api_key:             Datadog API key (required)
//   site:                Datadog site (default: "datadoghq.com")
//   endpoint:            Override endpoint URL (optional)
//   encoding.codec:      json or text (default: json)
//   default_api_key:     Fallback API key (optional)
//   batch.max_events:    Max events per batch (default: 100)
//   batch.timeout_secs:  Batch timeout in seconds (default: 5)
pub struct DatadogSink {
	api_key       string
	endpoint      string
	codec         DatadogCodec
	batch_max     int = 100
	batch_timeout time.Duration = 5 * time.second
mut:
	buffer     []string
	last_flush time.Time
}

enum DatadogCodec {
	json_codec
	text_codec
}

// new_datadog creates a new DatadogSink from config options.
pub fn new_datadog(opts map[string]string) !DatadogSink {
	api_key := opts['api_key'] or {
		opts['default_api_key'] or {
			return error('datadog: api_key is required')
		}
	}

	site := opts['site'] or { 'datadoghq.com' }
	endpoint := opts['endpoint'] or { 'https://http-intake.logs.${site}' }

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { DatadogCodec.text_codec }
		else { DatadogCodec.json_codec }
	}

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

	return DatadogSink{
		api_key: api_key
		endpoint: endpoint.trim_right('/')
		codec: codec
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s DatadogSink) send(e event.Event) ! {
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

// flush sends all buffered events to the Datadog Logs API.
pub fn (mut s DatadogSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	// Datadog expects a JSON array of log entries
	payload := '[${s.buffer.join(",")}]'

	url := '${s.endpoint}/api/v2/logs'

	mut http_batch := new_http_batch({
		'endpoint': url
	})

	mut extra_headers := map[string]string{}
	extra_headers['DD-API-KEY'] = s.api_key
	extra_headers['Content-Type'] = 'application/json'

	http_batch.send_payload(payload, extra_headers) or {
		eprintln('datadog: failed to send batch: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &DatadogSink) total_buffered() int {
	return s.buffer.len
}

// encode_event encodes a single event as a Datadog log JSON object.
fn (s &DatadogSink) encode_event(e event.Event) string {
	match e {
		event.LogEvent {
			return s.encode_log_event(e)
		}
		event.Metric {
			return json.encode(e)
		}
		event.TraceEvent {
			return json.encode(e.fields)
		}
	}
}

// encode_log_event encodes a log event as a Datadog log JSON object.
fn (s &DatadogSink) encode_log_event(e event.LogEvent) string {
	mut parts := []string{}

	// Message field
	if s.codec == .text_codec {
		parts << '"message":${json.encode(e.message())}'
	} else {
		parts << '"message":${e.to_json()}'
	}

	// Extract hostname from event if available
	if h := e.get('hostname') {
		parts << '"hostname":${json.encode(event.value_to_string(h))}'
	} else if h := e.get('host') {
		parts << '"hostname":${json.encode(event.value_to_string(h))}'
	}

	// Extract service from event if available
	if svc := e.get('service') {
		parts << '"service":${json.encode(event.value_to_string(svc))}'
	}

	// Standard Datadog fields
	parts << '"ddsource":"vector"'

	// Extract ddtags from event if available
	if tags := e.get('ddtags') {
		parts << '"ddtags":${json.encode(event.value_to_string(tags))}'
	}

	return '{${parts.join(",")}}'
}
