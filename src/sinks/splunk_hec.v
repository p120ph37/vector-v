module sinks

import event
import json
import time

// SplunkHecSink sends events to Splunk via the HTTP Event Collector (HEC).
// Mirrors Vector's splunk_hec_logs sink (src/sinks/splunk_hec/).
//
// Events are buffered and flushed as newline-separated HEC JSON objects to
// {endpoint}/services/collector/event with a Splunk token authorization header.
//
// Config options:
//   endpoint:            Splunk HEC endpoint URL (required, e.g., "https://splunk:8088")
//   token:               HEC token (required)
//   encoding.codec:      json or text (default: json)
//   index:               Default Splunk index (optional)
//   source:              Default source field (optional)
//   sourcetype:          Default sourcetype (optional)
//   host_key:            Field to use as host (default: "host")
//   batch.max_events:    Max events per batch (default: 100)
//   batch.timeout_secs:  Batch timeout in seconds (default: 1)
pub struct SplunkHecSink {
	endpoint      string
	token         string
	codec         SplunkHecCodec
	index         string
	source        string
	sourcetype    string
	host_key      string = 'host'
	batch_max     int = 100
	batch_timeout time.Duration = 1 * time.second
mut:
	buffer     []string
	last_flush time.Time
}

enum SplunkHecCodec {
	json_codec
	text_codec
}

// new_splunk_hec creates a new SplunkHecSink from config options.
pub fn new_splunk_hec(opts map[string]string) !SplunkHecSink {
	endpoint := opts['endpoint'] or {
		return error('splunk_hec: endpoint is required')
	}
	token := opts['token'] or {
		return error('splunk_hec: token is required')
	}

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { SplunkHecCodec.text_codec }
		else { SplunkHecCodec.json_codec }
	}

	index := opts['index'] or { '' }
	source := opts['source'] or { '' }
	sourcetype := opts['sourcetype'] or { '' }
	host_key := opts['host_key'] or { 'host' }

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return SplunkHecSink{
		endpoint: endpoint.trim_right('/')
		token: token
		codec: codec
		index: index
		source: source
		sourcetype: sourcetype
		host_key: host_key
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s SplunkHecSink) send(e event.Event) ! {
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

// flush sends all buffered events to the Splunk HEC endpoint.
pub fn (mut s SplunkHecSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	// HEC batch format: newline-separated JSON objects
	payload := s.buffer.join('\n')

	url := '${s.endpoint}/services/collector/event'

	mut http_batch := new_http_batch({
		'endpoint': url
	})
	http_batch.auth_header = 'Splunk ${s.token}'

	mut extra_headers := map[string]string{}
	extra_headers['Content-Type'] = 'application/json'

	http_batch.send_payload(payload, extra_headers) or {
		eprintln('splunk_hec: failed to send batch: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &SplunkHecSink) total_buffered() int {
	return s.buffer.len
}

// encode_event encodes a single event as a Splunk HEC JSON object.
fn (s &SplunkHecSink) encode_event(e event.Event) string {
	now := time.now()
	timestamp := '${now.unix()}.${now.nanosecond / 1_000_000}'

	host := s.extract_host(e)
	event_body := s.encode_event_body(e)

	if event_body.len == 0 {
		return ''
	}

	// Build HEC JSON object
	mut parts := []string{}
	parts << '"event":${event_body}'
	parts << '"time":${timestamp}'

	if host.len > 0 {
		parts << '"host":${json.encode(host)}'
	}
	if s.source.len > 0 {
		parts << '"source":${json.encode(s.source)}'
	}
	if s.sourcetype.len > 0 {
		parts << '"sourcetype":${json.encode(s.sourcetype)}'
	}
	if s.index.len > 0 {
		parts << '"index":${json.encode(s.index)}'
	}

	return '{${parts.join(",")}}'
}

// extract_host extracts the host field from a log event.
fn (s &SplunkHecSink) extract_host(e event.Event) string {
	match e {
		event.LogEvent {
			if h := e.get(s.host_key) {
				return event.value_to_string(h)
			}
			return ''
		}
		else {
			return ''
		}
	}
}

// encode_event_body encodes the event body based on codec.
fn (s &SplunkHecSink) encode_event_body(e event.Event) string {
	match e {
		event.LogEvent {
			if s.codec == .text_codec {
				return json.encode(e.message())
			}
			return e.to_json()
		}
		event.Metric {
			return json.encode(e)
		}
		event.TraceEvent {
			return json.encode(e.fields)
		}
	}
}
