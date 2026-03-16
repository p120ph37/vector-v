module sinks

import event
import json
import net.http
import os
import time

// GcpCloudStorageSink sends events to Google Cloud Storage (GCS).
// Mirrors Vector's gcp_cloud_storage sink.
//
// Events are batched, encoded, and uploaded as GCS objects using the JSON API.
// Object names support time-based partitioning via strftime patterns.
//
// Config options:
//   bucket:                GCS bucket name (required)
//   key_prefix:            Object name prefix with optional strftime patterns
//                          (default: "date=%Y-%m-%d/")
//   encoding.codec:        json, text, or ndjson (default: ndjson)
//   batch.max_events:      Max events per GCS object (default: 1000)
//   batch.timeout_secs:    Max seconds before flushing (default: 300)
//   endpoint:              Custom GCS endpoint (for emulator)
//   auth.credentials_file: Service account JSON file path
//   auth.api_key:          API key for simple auth
//   content_type:          Object content type (auto-detected from codec if not set)
//   acl:                   Predefined ACL for uploaded objects (optional)
//   storage_class:         Storage class for objects (optional, e.g. STANDARD, NEARLINE)
//   metadata.*:            Custom metadata key-value pairs (optional)
pub struct GcpCloudStorageSink {
	bucket           string
	key_prefix       string
	endpoint         string
	api_key          string
	credentials_file string
	codec            GcsCodec
	content_type     string
	acl              string
	storage_class    string
	metadata         map[string]string
	batch_max        int = 1000
	batch_timeout    time.Duration = 300 * time.second
mut:
	buffer     []string
	last_flush time.Time
	seq        int
}

enum GcsCodec {
	json_codec
	text_codec
	ndjson_codec
}

// new_gcp_cloud_storage creates a new GcpCloudStorageSink from config options.
pub fn new_gcp_cloud_storage(opts map[string]string) !GcpCloudStorageSink {
	bucket := opts['bucket'] or {
		return error('gcp_cloud_storage: bucket is required')
	}
	if bucket.len == 0 {
		return error('gcp_cloud_storage: bucket is required')
	}

	key_prefix := opts['key_prefix'] or { 'date=%Y-%m-%d/' }
	endpoint := opts['endpoint'] or { 'https://storage.googleapis.com' }

	api_key := opts['auth.api_key'] or { '' }

	credentials_file := opts['auth.credentials_file'] or {
		os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
	}

	codec := match opts['encoding.codec'] or { 'ndjson' } {
		'json' { GcsCodec.json_codec }
		'text' { GcsCodec.text_codec }
		else { GcsCodec.ndjson_codec }
	}

	content_type := opts['content_type'] or {
		match codec {
			.json_codec { 'application/json' }
			.text_codec { 'text/plain' }
			.ndjson_codec { 'application/x-ndjson' }
		}
	}

	acl := opts['acl'] or { '' }
	storage_class := opts['storage_class'] or { '' }

	// Collect metadata.* options
	mut metadata := map[string]string{}
	for k, v in opts {
		if k.starts_with('metadata.') {
			meta_key := k[9..] // strip "metadata." prefix
			metadata[meta_key] = v
		}
	}

	mut batch_max := 1000
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 1000
		}
	}

	mut batch_timeout_secs := 300.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 300.0
		}
	}

	return GcpCloudStorageSink{
		bucket: bucket
		key_prefix: key_prefix
		endpoint: endpoint
		api_key: api_key
		credentials_file: credentials_file
		codec: codec
		content_type: content_type
		acl: acl
		storage_class: storage_class
		metadata: metadata
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s GcpCloudStorageSink) send(e event.Event) ! {
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

// flush uploads all buffered events as a GCS object.
pub fn (mut s GcpCloudStorageSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	payload := s.build_payload()
	object_name := s.generate_object_name()

	s.upload_object(object_name, payload) or {
		eprintln('gcp_cloud_storage: upload failed: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &GcpCloudStorageSink) total_buffered() int {
	return s.buffer.len
}

// build_payload constructs the file content from buffered events.
pub fn (s &GcpCloudStorageSink) build_payload() string {
	return match s.codec {
		.json_codec {
			'[${s.buffer.join(",")}]'
		}
		.ndjson_codec {
			mut p := s.buffer.join('\n')
			if p.len > 0 {
				p += '\n'
			}
			p
		}
		.text_codec {
			s.buffer.join('\n')
		}
	}
}

// generate_object_name produces a GCS object name from the prefix template.
pub fn (mut s GcpCloudStorageSink) generate_object_name() string {
	now := time.now()
	prefix := resolve_file_path(s.key_prefix, now)
	s.seq++
	ts := now.unix()
	return '${prefix}${ts}-${s.seq}.log'
}

// build_gcs_upload_url constructs the JSON API upload URL for a GCS object.
pub fn build_gcs_upload_url(endpoint string, bucket string, object_name string) string {
	return '${endpoint}/upload/storage/v1/b/${bucket}/o?uploadType=media&name=${object_name}'
}

fn (s &GcpCloudStorageSink) encode_event(e event.Event) string {
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

fn (s &GcpCloudStorageSink) upload_object(object_name string, payload string) ! {
	url := build_gcs_upload_url(s.endpoint, s.bucket, object_name)

	mut header := http.Header{}
	header.add_custom('Content-Type', s.content_type) or {}
	header.add_custom('Content-Length', payload.len.str()) or {}

	if s.api_key.len > 0 {
		header.add_custom('X-Goog-Api-Key', s.api_key) or {}
	}

	if s.acl.len > 0 {
		header.add_custom('x-goog-acl', s.acl) or {}
	}
	if s.storage_class.len > 0 {
		header.add_custom('x-goog-storage-class', s.storage_class) or {}
	}
	for k, v in s.metadata {
		header.add_custom('x-goog-meta-${k}', v) or {}
	}

	resp := http.fetch(http.FetchConfig{
		url: url
		method: .post
		data: payload
		header: header
		verbose: false
	}) or {
		return error('GCS upload HTTP request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('GCS upload HTTP ${resp.status_code}: ${resp.body}')
	}
}
