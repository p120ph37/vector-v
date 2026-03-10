module sinks

import event
import json
import time

// LokiSink sends log events to Grafana Loki via the HTTP push API.
// Mirrors Vector's loki sink (src/sinks/loki/).
//
// Events are batched by label set and sent as JSON to /loki/api/v1/push.
// Each batch is a Loki streams payload:
//   {"streams": [{"stream": {labels}, "values": [[ts_ns, line], ...]}]}
//
// Config options:
//   endpoint:            Base URL (e.g., http://localhost:3100)
//   path:                API path (default: /loki/api/v1/push)
//   tenant_id:           X-Scope-OrgID header for multi-tenant Loki
//   labels.*:            Static labels (e.g., labels.job = "vector")
//   remove_label_fields: Remove label fields from event (default: false)
//   encoding.codec:      json or text (default: json)
//   batch.max_events:    Max events per batch (default: 100)
//   batch.timeout_secs:  Max seconds to wait before flushing (default: 1)
//   auth.user/password:  Basic auth
//   auth.token:          Bearer token auth
pub struct LokiSink {
	http      HttpBatch
	labels    map[string]string
	tenant_id string
	codec     LokiCodec
	remove_label_fields bool
	batch_max   int = 100
	batch_timeout time.Duration = 1 * time.second
mut:
	// Batch buffer: label_key -> []LokiEntry
	batches map[string]LokiBatch
	last_flush time.Time
}

enum LokiCodec {
	json_codec
	text_codec
	logfmt_codec
}

struct LokiBatch {
mut:
	labels  map[string]string
	entries []LokiEntry
}

struct LokiEntry {
	timestamp_ns string // nanosecond unix timestamp as string
	line         string
}

// new_loki creates a new LokiSink from config options.
pub fn new_loki(opts map[string]string) LokiSink {
	mut http_batch := new_http_batch(opts)
	if http_batch.path.len == 0 {
		http_batch.path = '/loki/api/v1/push'
	}
	http_batch.headers['Content-Type'] = 'application/json'

	tenant_id := opts['tenant_id'] or { '' }

	mut labels := map[string]string{}
	for k, v in opts {
		if k.starts_with('labels.') {
			label_key := k[7..] // len("labels.")
			labels[label_key] = v
		}
	}

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { LokiCodec.text_codec }
		'logfmt' { LokiCodec.logfmt_codec }
		else { LokiCodec.json_codec }
	}

	rlf_val := opts['remove_label_fields'] or { 'false' }
	remove_label_fields := rlf_val == 'true'

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

	return LokiSink{
		http: http_batch
		labels: labels
		tenant_id: tenant_id
		codec: codec
		remove_label_fields: remove_label_fields
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s LokiSink) send(e event.Event) ! {
	match e {
		event.LogEvent {
			// Resolve labels for this event
			mut resolved_labels := map[string]string{}
			for lk, lv in s.labels {
				// Check if label value is a field reference like "{{ field }}"
				if lv.starts_with('{{') && lv.ends_with('}}') {
					field_name := lv[2..lv.len - 2].trim_space().trim_left('.')
					if val := e.get(field_name) {
						resolved_labels[lk] = event.value_to_string(val)
					}
				} else {
					resolved_labels[lk] = lv
				}
			}

			// Build the log line
			mut log_event := e
			if s.remove_label_fields {
				for _, lv in s.labels {
					if lv.starts_with('{{') && lv.ends_with('}}') {
						field_name := lv[2..lv.len - 2].trim_space().trim_left('.')
						log_event.remove(field_name)
					}
				}
			}

			line := match s.codec {
				.text_codec {
					log_event.message()
				}
				.logfmt_codec {
					mut parts := []string{}
					for k, v in log_event.fields {
						parts << '${k}=${event.value_to_string(v)}'
					}
					parts.join(' ')
				}
				.json_codec {
					log_event.to_json()
				}
			}

			// Create label key for batching
			label_key := format_label_key(resolved_labels)

			if label_key !in s.batches {
				s.batches[label_key] = LokiBatch{
					labels: resolved_labels
				}
			}
			mut batch := s.batches[label_key]
			now := time.now()
			ts_ns := '${now.unix()}' + '000000000'
			batch.entries << LokiEntry{
				timestamp_ns: ts_ns
				line: line
			}
			s.batches[label_key] = batch

			// Flush if batch full
			total_entries := s.total_buffered()
			if total_entries >= s.batch_max {
				s.flush()!
			}
		}
		else {}
	}

	// Flush on timeout
	if time.since(s.last_flush) > s.batch_timeout && s.total_buffered() > 0 {
		s.flush()!
	}
}

fn (s &LokiSink) total_buffered() int {
	mut total := 0
	for _, batch in s.batches {
		total += batch.entries.len
	}
	return total
}

fn (mut s LokiSink) flush() ! {
	if s.batches.len == 0 {
		return
	}

	// Build Loki push payload
	mut streams := []string{}
	for _, batch in s.batches {
		mut label_parts := []string{}
		for k, v in batch.labels {
			label_parts << '"${k}":"${v}"'
		}
		labels_json := '{${label_parts.join(",")}}'

		mut values := []string{}
		for entry in batch.entries {
			// Escape the line for JSON
			escaped_line := json.encode(entry.line)
			values << '["${entry.timestamp_ns}",${escaped_line}]'
		}
		streams << '{"stream":${labels_json},"values":[${values.join(",")}]}'
	}

	payload := '{"streams":[${streams.join(",")}]}'

	mut extra_headers := map[string]string{}
	if s.tenant_id.len > 0 {
		extra_headers['X-Scope-OrgID'] = s.tenant_id
	}

	s.http.send_payload(payload, extra_headers) or {
		eprintln('loki: failed to send batch: ${err}')
		// Don't clear batches on failure - will retry
		return error(err.msg())
	}

	s.batches.clear()
	s.last_flush = time.now()
}

fn format_label_key(labels map[string]string) string {
	mut parts := []string{}
	for k, v in labels {
		parts << '${k}=${v}'
	}
	parts.sort()
	return parts.join(',')
}
