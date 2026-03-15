module sinks

import event
import json
import net.http
import time

// HttpSink is a generic HTTP sink that sends events to an HTTP endpoint.
// Mirrors Vector's generic HTTP sink (src/sinks/http/). This is also the
// foundation for protocol-specific sinks (Loki, OTLP, CloudWatch) which
// wrap HttpSink with custom encoding and endpoint configuration.
//
// Config options:
//   endpoint:            Target URL (e.g., http://localhost:8080/events)
//   method:              HTTP method (default: POST)
//   encoding.codec:      json, text, or ndjson (default: json)
//   batch.max_events:    Max events per batch (default: 100)
//   batch.timeout_secs:  Max seconds before flushing (default: 1)
//   auth.user/password:  Basic auth
//   auth.token:          Bearer token
//   headers.*:           Custom request headers (e.g., headers.X-Custom = "value")
//   payload_prefix:      String to prepend to payload (default: "")
//   payload_suffix:      String to append to payload (default: "")
pub struct HttpSink {
	http           HttpBatch
	codec          HttpCodec
	custom_headers map[string]string
	payload_prefix string
	payload_suffix string
	batch_max      int = 100
	batch_timeout  time.Duration = 1 * time.second
mut:
	buffer     []string
	last_flush time.Time
}

enum HttpCodec {
	json_codec
	text_codec
	ndjson_codec
}

// new_http creates a new generic HttpSink from config options.
pub fn new_http(opts map[string]string) HttpSink {
	mut http_batch := new_http_batch(opts)

	// Parse method
	method_str := opts['method'] or { 'POST' }
	http_batch.method = parse_http_method(method_str)

	// Parse custom headers
	mut custom_headers := map[string]string{}
	for k, v in opts {
		if k.starts_with('headers.') {
			header_name := k[8..] // len("headers.")
			custom_headers[header_name] = v
		}
	}

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { HttpCodec.text_codec }
		'ndjson' { HttpCodec.ndjson_codec }
		else { HttpCodec.json_codec }
	}

	payload_prefix := opts['payload_prefix'] or { '' }
	payload_suffix := opts['payload_suffix'] or { '' }

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

	return HttpSink{
		http: http_batch
		codec: codec
		custom_headers: custom_headers
		payload_prefix: payload_prefix
		payload_suffix: payload_suffix
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s HttpSink) send(e event.Event) ! {
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

// flush sends all buffered events to the HTTP endpoint.
pub fn (mut s HttpSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	payload := s.build_payload()

	mut extra_headers := map[string]string{}
	for k, v in s.custom_headers {
		extra_headers[k] = v
	}

	// Set content-type based on codec
	match s.codec {
		.ndjson_codec {
			extra_headers['Content-Type'] = 'application/x-ndjson'
		}
		.text_codec {
			extra_headers['Content-Type'] = 'text/plain'
		}
		else {}
	}

	s.http.send_payload(payload, extra_headers) or {
		eprintln('http: failed to send batch: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &HttpSink) total_buffered() int {
	return s.buffer.len
}

// build_payload constructs the payload from buffered encoded events.
pub fn (s &HttpSink) build_payload() string {
	mut payload := ''
	match s.codec {
		.json_codec {
			payload = '[${s.buffer.join(",")}]'
		}
		.ndjson_codec {
			payload = s.buffer.join('\n')
			if payload.len > 0 {
				payload += '\n'
			}
		}
		.text_codec {
			payload = s.buffer.join('\n')
		}
	}

	if s.payload_prefix.len > 0 || s.payload_suffix.len > 0 {
		payload = '${s.payload_prefix}${payload}${s.payload_suffix}'
	}

	return payload
}

fn (s &HttpSink) encode_event(e event.Event) string {
	match e {
		event.LogEvent {
			return match s.codec {
				.json_codec, .ndjson_codec {
					e.to_json()
				}
				.text_codec {
					e.message()
				}
			}
		}
		event.Metric {
			return json.encode(e)
		}
		event.TraceEvent {
			return json.encode(e.fields)
		}
	}
}

fn parse_http_method(method string) http.Method {
	return match method.to_upper() {
		'GET' { http.Method.get }
		'PUT' { http.Method.put }
		'PATCH' { http.Method.patch }
		'DELETE' { http.Method.delete }
		else { http.Method.post }
	}
}
