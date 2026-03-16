module sinks

import event
import json
import net.http
import time

// GcpChronicleSink sends log events to Google Chronicle (Security Operations)
// via the Unstructured Log Entries API. Mirrors Vector's gcp_chronicle sink.
//
// Events are batched and sent via batchCreate endpoint.
//
// Config options:
//   region:                Chronicle region (default: us)
//                          us, europe, asia-southeast1, etc.
//   customer_id:           Chronicle customer ID (required)
//   log_type:              Chronicle log type (required, e.g. "WINEVTLOG")
//   namespace:             Log namespace (optional)
//   auth.api_key:          API key for authentication
//   auth.credentials_file: Service account JSON file
//   encoding.codec:        json or text (default: json)
//   batch.max_events:      Max events per API call (default: 100)
//   batch.timeout_ms:      Flush timeout in milliseconds (default: 1000)
pub struct GcpChronicleSink {
pub mut:
	region           string = 'us'
	customer_id      string
	log_type         string
	namespace        string
	api_key          string
	credentials_file string
	encoding_codec   string = 'json'
	batch_max_events int    = 100
	batch_timeout_ms int    = 1000
	buffer           []string
	last_flush       time.Time
}

// new_gcp_chronicle creates a new GcpChronicleSink from config options.
pub fn new_gcp_chronicle(opts map[string]string) !GcpChronicleSink {
	customer_id := opts['customer_id'] or {
		return error('gcp_chronicle: customer_id is required')
	}
	if customer_id.len == 0 {
		return error('gcp_chronicle: customer_id is required')
	}

	log_type := opts['log_type'] or {
		return error('gcp_chronicle: log_type is required')
	}
	if log_type.len == 0 {
		return error('gcp_chronicle: log_type is required')
	}

	region := opts['region'] or { 'us' }
	namespace := opts['namespace'] or { '' }
	api_key := opts['auth.api_key'] or { '' }
	credentials_file := opts['auth.credentials_file'] or { '' }
	encoding_codec := opts['encoding.codec'] or { 'json' }

	mut batch_max_events := 100
	if v := opts['batch.max_events'] {
		batch_max_events = v.int()
		if batch_max_events <= 0 {
			batch_max_events = 100
		}
	}

	mut batch_timeout_ms := 1000
	if v := opts['batch.timeout_ms'] {
		batch_timeout_ms = v.int()
		if batch_timeout_ms <= 0 {
			batch_timeout_ms = 1000
		}
	}

	return GcpChronicleSink{
		region: region
		customer_id: customer_id
		log_type: log_type
		namespace: namespace
		api_key: api_key
		credentials_file: credentials_file
		encoding_codec: encoding_codec
		batch_max_events: batch_max_events
		batch_timeout_ms: batch_timeout_ms
		last_flush: time.now()
	}
}

// build_chronicle_url constructs the Chronicle batchCreate API URL.
pub fn build_chronicle_url(region string) string {
	return 'https://${region}-malachiteingestion-pa.googleapis.com/v2/unstructuredlogentries:batchCreate'
}

// build_chronicle_url_with_endpoint constructs the URL using a custom endpoint.
pub fn build_chronicle_url_with_endpoint(endpoint string) string {
	return '${endpoint}/v2/unstructuredlogentries:batchCreate'
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s GcpChronicleSink) send(e event.Event) ! {
	match e {
		event.LogEvent {
			message := match s.encoding_codec {
				'text' { e.message() }
				else { e.to_json() }
			}

			s.buffer << message

			if s.buffer.len >= s.batch_max_events {
				s.flush()!
			}
		}
		else {}
	}

	if time.since(s.last_flush) > time.Duration(i64(s.batch_timeout_ms) * 1_000_000) && s.buffer.len > 0 {
		s.flush()!
	}
}

// flush sends buffered entries to the Chronicle API.
pub fn (mut s GcpChronicleSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	url := build_chronicle_url(s.region)
	payload := s.build_entries_payload()

	mut header := http.Header{}
	header.add_custom('Content-Type', 'application/json') or {}
	if s.api_key.len > 0 {
		header.add_custom('X-Goog-Api-Key', s.api_key) or {}
	}

	resp := http.fetch(http.FetchConfig{
		url: url
		method: .post
		data: payload
		header: header
		verbose: false
	}) or {
		return error('gcp_chronicle: request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('gcp_chronicle: HTTP ${resp.status_code}: ${resp.body}')
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of log entries currently buffered.
pub fn (s &GcpChronicleSink) total_buffered() int {
	return s.buffer.len
}

// build_entries_payload constructs the batchCreate JSON payload.
pub fn (s &GcpChronicleSink) build_entries_payload() string {
	now := time.utc()
	timestamp := '${now.year:04d}-${now.month:02d}-${now.day:02d}T${now.hour:02d}:${now.minute:02d}:${now.second:02d}Z'

	mut entries := []string{}
	for msg in s.buffer {
		mut entry := '{"log_text":${json.encode(msg)},"ts_rfc3339":"${timestamp}"'
		entry += '}'
		entries << entry
	}

	mut payload := '{"customer_id":${json.encode(s.customer_id)}'
	payload += ',"log_type":${json.encode(s.log_type)}'
	if s.namespace.len > 0 {
		payload += ',"namespace":${json.encode(s.namespace)}'
	}
	payload += ',"entries":[${entries.join(",")}]}'

	return payload
}
