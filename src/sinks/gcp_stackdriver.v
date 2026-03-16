module sinks

import event
import json
import net.http
import os
import time

// GcpStackdriverSink sends log events to Google Cloud Logging (formerly Stackdriver).
// Mirrors Vector's gcp_stackdriver_logs sink.
//
// Events are batched and sent via the Cloud Logging REST API (entries.write).
//
// Config options:
//   project_id:            GCP project ID (required)
//   log_id:                Log name identifier (required, e.g. "my-app-logs")
//   endpoint:              Cloud Logging API endpoint (default: https://logging.googleapis.com)
//   auth.api_key:          API key auth
//   auth.credentials_file: Service account JSON file path
//   resource.type:         Monitored resource type (default: "global")
//   resource.labels.*:     Monitored resource labels (optional)
//   labels.*:              Additional log entry labels (optional)
//   severity_key:          Field to extract severity from (optional)
//   encoding.codec:        json or text (default: json)
//   batch.max_events:      Max events per API call (default: 1000)
//   batch.timeout_ms:      Flush timeout in milliseconds (default: 1000)
pub struct GcpStackdriverSink {
pub mut:
	project_id       string
	log_id           string
	endpoint         string = 'https://logging.googleapis.com'
	api_key          string
	credentials_file string
	resource_type    string = 'global'
	resource_labels  map[string]string
	labels           map[string]string
	severity_key     string
	encoding_codec   string = 'json'
	batch_max_events int    = 1000
	batch_timeout_ms int    = 1000
	buffer           []string
	last_flush       time.Time
}

// new_gcp_stackdriver creates a new GcpStackdriverSink from config options.
pub fn new_gcp_stackdriver(opts map[string]string) !GcpStackdriverSink {
	project_id := opts['project_id'] or {
		return error('gcp_stackdriver: project_id is required')
	}
	if project_id.len == 0 {
		return error('gcp_stackdriver: project_id is required')
	}

	log_id := opts['log_id'] or {
		return error('gcp_stackdriver: log_id is required')
	}
	if log_id.len == 0 {
		return error('gcp_stackdriver: log_id is required')
	}

	endpoint := opts['endpoint'] or { 'https://logging.googleapis.com' }
	api_key := opts['auth.api_key'] or { '' }

	credentials_file := opts['auth.credentials_file'] or {
		os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
	}

	resource_type := opts['resource.type'] or { 'global' }
	severity_key := opts['severity_key'] or { '' }
	encoding_codec := opts['encoding.codec'] or { 'json' }

	// Collect resource.labels.* options
	mut resource_labels := map[string]string{}
	for k, v in opts {
		if k.starts_with('resource.labels.') {
			label_key := k[16..] // strip "resource.labels." prefix
			resource_labels[label_key] = v
		}
	}

	// Collect labels.* options
	mut labels := map[string]string{}
	for k, v in opts {
		if k.starts_with('labels.') {
			label_key := k[7..] // strip "labels." prefix
			labels[label_key] = v
		}
	}

	mut batch_max_events := 1000
	if v := opts['batch.max_events'] {
		batch_max_events = v.int()
		if batch_max_events <= 0 {
			batch_max_events = 1000
		}
	}

	mut batch_timeout_ms := 1000
	if v := opts['batch.timeout_ms'] {
		batch_timeout_ms = v.int()
		if batch_timeout_ms <= 0 {
			batch_timeout_ms = 1000
		}
	}

	return GcpStackdriverSink{
		project_id: project_id
		log_id: log_id
		endpoint: endpoint
		api_key: api_key
		credentials_file: credentials_file
		resource_type: resource_type
		resource_labels: resource_labels
		labels: labels
		severity_key: severity_key
		encoding_codec: encoding_codec
		batch_max_events: batch_max_events
		batch_timeout_ms: batch_timeout_ms
		last_flush: time.now()
	}
}

// build_stackdriver_url constructs the Cloud Logging entries.write URL.
pub fn build_stackdriver_url(endpoint string) string {
	return '${endpoint}/v2/entries:write'
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s GcpStackdriverSink) send(e event.Event) ! {
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

// flush sends buffered entries to the Cloud Logging API.
pub fn (mut s GcpStackdriverSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	url := build_stackdriver_url(s.endpoint)
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
		return error('gcp_stackdriver: write failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('gcp_stackdriver: write HTTP ${resp.status_code}: ${resp.body}')
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of log entries currently buffered.
pub fn (s &GcpStackdriverSink) total_buffered() int {
	return s.buffer.len
}

// build_entries_payload constructs the entries.write JSON payload.
pub fn (s &GcpStackdriverSink) build_entries_payload() string {
	log_name := 'projects/${s.project_id}/logs/${s.log_id}'

	// Build resource JSON
	mut resource_labels_json := ''
	if s.resource_labels.len > 0 {
		mut label_parts := []string{}
		for k, v in s.resource_labels {
			label_parts << '${json.encode(k)}:${json.encode(v)}'
		}
		resource_labels_json = ',${label_parts.join(",")}'
	}
	resource_json := '{"type":${json.encode(s.resource_type)}${resource_labels_json}}'

	// Build labels JSON if present
	mut labels_json := ''
	if s.labels.len > 0 {
		mut label_parts := []string{}
		for k, v in s.labels {
			label_parts << '${json.encode(k)}:${json.encode(v)}'
		}
		labels_json = ',"labels":{${label_parts.join(",")}}'
	}

	// Build entries
	mut entries := []string{}
	now := time.utc()
	timestamp := '${now.year:04d}-${now.month:02d}-${now.day:02d}T${now.hour:02d}:${now.minute:02d}:${now.second:02d}Z'

	for msg in s.buffer {
		mut entry := '{"logName":${json.encode(log_name)}'
		entry += ',"resource":${resource_json}'
		entry += ',"timestamp":"${timestamp}"'

		if s.encoding_codec == 'text' {
			entry += ',"textPayload":${json.encode(msg)}'
		} else {
			entry += ',"jsonPayload":${msg}'
		}
		entry += '}'
		entries << entry
	}

	return '{"entries":[${entries.join(",")}]${labels_json}}'
}
