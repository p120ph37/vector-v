module sinks

import event
import json
import net.http
import os
import time

// GcpPubsubSink publishes log events to a Google Cloud Pub/Sub topic via the
// REST API. Mirrors Vector's gcp_pubsub sink.
//
// Config options:
//   project:              GCP project ID (required)
//   topic:                Pub/Sub topic name (required)
//   endpoint:             Pub/Sub API endpoint (default: https://pubsub.googleapis.com)
//   auth.api_key:         API key auth
//   auth.credentials_file: Service account JSON file path (also checks GOOGLE_APPLICATION_CREDENTIALS env)
//   encoding.codec:       Encoding format: json or text (default: "json")
//   batch.max_events:     Max batch size (default: 1000)
//   batch.timeout_ms:     Flush timeout in milliseconds (default: 1000)
//   ordering_key_field:   Field for message ordering key (optional)
//   attributes_key:       Field containing attributes map (optional)
pub struct GcpPubsubSink {
pub mut:
	project            string
	topic              string
	endpoint           string = 'https://pubsub.googleapis.com'
	api_key            string
	credentials_file   string
	encoding_codec     string = 'json'
	batch_max_events   int    = 1000
	batch_timeout_ms   int    = 1000
	ordering_key_field string // optional: field for message ordering
	attributes_key     string // optional: field containing attributes map
	buffer             []string
	last_flush         time.Time
}

// new_gcp_pubsub_sink creates a new GcpPubsubSink from config options.
pub fn new_gcp_pubsub_sink(opts map[string]string) !GcpPubsubSink {
	project := opts['project'] or {
		return error('gcp_pubsub sink: project is required')
	}
	if project.len == 0 {
		return error('gcp_pubsub sink: project is required')
	}

	topic := opts['topic'] or {
		return error('gcp_pubsub sink: topic is required')
	}
	if topic.len == 0 {
		return error('gcp_pubsub sink: topic is required')
	}

	endpoint := opts['endpoint'] or { 'https://pubsub.googleapis.com' }

	api_key := opts['auth.api_key'] or { '' }

	// Resolve credentials file: explicit config > GOOGLE_APPLICATION_CREDENTIALS env
	credentials_file := opts['auth.credentials_file'] or {
		os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
	}

	encoding_codec := opts['encoding.codec'] or { 'json' }

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

	ordering_key_field := opts['ordering_key_field'] or { '' }
	attributes_key := opts['attributes_key'] or { '' }

	return GcpPubsubSink{
		project: project
		topic: topic
		endpoint: endpoint
		api_key: api_key
		credentials_file: credentials_file
		encoding_codec: encoding_codec
		batch_max_events: batch_max_events
		batch_timeout_ms: batch_timeout_ms
		ordering_key_field: ordering_key_field
		attributes_key: attributes_key
		last_flush: time.now()
	}
}

// build_pubsub_publish_url constructs the REST API publish URL for a Pub/Sub topic.
pub fn build_pubsub_publish_url(endpoint string, project string, topic string) string {
	return '${endpoint}/v1/projects/${project}/topics/${topic}:publish'
}

// send buffers an event and flushes when the batch is full or timeout expires.
pub fn (mut s GcpPubsubSink) send(e event.Event) ! {
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

// flush publishes buffered messages to the Pub/Sub topic via the REST API.
pub fn (mut s GcpPubsubSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	url := build_pubsub_publish_url(s.endpoint, s.project, s.topic)

	// Build publish request body with base64-encoded messages
	mut messages := []string{}
	for msg in s.buffer {
		// Base64-encode the message data for Pub/Sub API
		encoded := encode_base64(msg.bytes())
		mut entry := '{"data":"${encoded}"'
		if s.ordering_key_field.len > 0 {
			entry += ',"orderingKey":${json.encode(s.ordering_key_field)}'
		}
		entry += '}'
		messages << entry
	}

	payload := '{"messages":[${messages.join(",")}]}'

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
		return error('gcp_pubsub: publish failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('gcp_pubsub: publish HTTP ${resp.status_code}: ${resp.body}')
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of messages currently buffered.
pub fn (s &GcpPubsubSink) total_buffered() int {
	return s.buffer.len
}

// encode_base64 encodes bytes to base64 string (RFC 4648).
fn encode_base64(data []u8) string {
	alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	mut result := []u8{}
	mut i := 0
	for i + 2 < data.len {
		a := data[i]
		b := data[i + 1]
		c := data[i + 2]
		result << alphabet[a >> 2]
		result << alphabet[((a & 0x03) << 4) | (b >> 4)]
		result << alphabet[((b & 0x0f) << 2) | (c >> 6)]
		result << alphabet[c & 0x3f]
		i += 3
	}
	remaining := data.len - i
	if remaining == 1 {
		a := data[i]
		result << alphabet[a >> 2]
		result << alphabet[(a & 0x03) << 4]
		result << `=`
		result << `=`
	} else if remaining == 2 {
		a := data[i]
		b := data[i + 1]
		result << alphabet[a >> 2]
		result << alphabet[((a & 0x03) << 4) | (b >> 4)]
		result << alphabet[(b & 0x0f) << 2]
		result << `=`
	}
	return result.bytestr()
}
