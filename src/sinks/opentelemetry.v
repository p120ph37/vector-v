module sinks

import event
import json
import time

// OpenTelemetrySink sends events to an OTLP-compatible endpoint over HTTP.
// Mirrors Vector's opentelemetry sink (src/sinks/opentelemetry/).
//
// The upstream Rust implementation is a thin wrapper around the generic HTTP
// sink with JSON encoding. We follow the same approach: serialize events as
// OTLP JSON and POST to the configured endpoint.
//
// Config options:
//   endpoint:            OTLP HTTP endpoint (e.g., http://localhost:4318)
//   path:                API path (default: /v1/logs)
//   encoding.codec:      Always JSON for OTLP (default: json)
//   batch.max_events:    Max events per batch (default: 100)
//   batch.timeout_secs:  Max seconds before flushing (default: 1)
//   auth.user/password:  Basic auth
//   auth.token:          Bearer token
//   resource.*:          Resource attributes added to all exports
pub struct OpenTelemetrySink {
	http              HttpBatch
	resource_attrs    map[string]string
	batch_max         int = 100
	batch_timeout     time.Duration = 1 * time.second
mut:
	buffer     []OtlpLogRecord
	last_flush time.Time
}

struct OtlpLogRecord {
	timestamp_ns  string
	severity_text string
	body          string
	attributes    map[string]string
}

// new_opentelemetry creates a new OpenTelemetrySink from config options.
pub fn new_opentelemetry(opts map[string]string) OpenTelemetrySink {
	mut http_batch := new_http_batch(opts)
	if http_batch.path.len == 0 {
		http_batch.path = '/v1/logs'
	}
	http_batch.headers['Content-Type'] = 'application/json'

	mut resource_attrs := map[string]string{}
	for k, v in opts {
		if k.starts_with('resource.') {
			resource_attrs[k[9..]] = v
		}
	}

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

	return OpenTelemetrySink{
		http: http_batch
		resource_attrs: resource_attrs
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full.
pub fn (mut s OpenTelemetrySink) send(e event.Event) ! {
	match e {
		event.LogEvent {
			now := time.now()
			ts_ns := '${now.unix()}000000000'

			severity := if sev := e.get('severity') {
				event.value_to_string(sev)
			} else if lvl := e.get('level') {
				event.value_to_string(lvl)
			} else {
				'INFO'
			}

			body := e.message()

			mut attrs := map[string]string{}
			for k, v in e.fields {
				if k != 'message' && k != 'severity' && k != 'level' {
					attrs[k] = event.value_to_string(v)
				}
			}

			s.buffer << OtlpLogRecord{
				timestamp_ns: ts_ns
				severity_text: severity
				body: body
				attributes: attrs
			}

			if s.buffer.len >= s.batch_max {
				s.flush()!
			}
		}
		else {}
	}

	if time.since(s.last_flush) > s.batch_timeout && s.buffer.len > 0 {
		s.flush()!
	}
}

fn (mut s OpenTelemetrySink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	payload := s.build_otlp_payload()

	s.http.send_payload(payload, map[string]string{}) or {
		eprintln('opentelemetry: failed to send batch: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

fn (s &OpenTelemetrySink) build_otlp_payload() string {
	// Build OTLP JSON Logs Export payload
	// See: https://opentelemetry.io/docs/specs/otlp/#json-protobuf-encoding

	// Resource attributes
	mut resource_attr_json := []string{}
	for k, v in s.resource_attrs {
		resource_attr_json << '{"key":${json.encode(k)},"value":{"stringValue":${json.encode(v)}}}'
	}

	// Log records
	mut records := []string{}
	for rec in s.buffer {
		mut attr_json := []string{}
		for k, v in rec.attributes {
			attr_json << '{"key":${json.encode(k)},"value":{"stringValue":${json.encode(v)}}}'
		}

		record := '{"timeUnixNano":"${rec.timestamp_ns}","severityText":${json.encode(rec.severity_text)},"body":{"stringValue":${json.encode(rec.body)}},"attributes":[${attr_json.join(",")}]}'
		records << record
	}

	scope_logs := '{"scope":{},"logRecords":[${records.join(",")}]}'
	resource_logs := '{"resource":{"attributes":[${resource_attr_json.join(",")}]},"scopeLogs":[${scope_logs}]}'

	return '{"resourceLogs":[${resource_logs}]}'
}
