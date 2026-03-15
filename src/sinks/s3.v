module sinks

import aws
import event
import json
import net.http
import time

// S3Sink sends events to an AWS S3 bucket.
// Mirrors Vector's aws_s3 sink (src/sinks/aws_s3/).
//
// Events are batched, encoded, and uploaded as S3 objects using the PutObject API
// with SigV4 signing. Object keys support time-based partitioning via strftime patterns.
//
// Config options:
//   bucket:                S3 bucket name (required)
//   key_prefix:            Object key prefix with optional strftime patterns
//                          (default: "date=%Y-%m-%d/")
//   encoding.codec:        json, text, or ndjson (default: ndjson)
//   compression:           none or gzip (default: none) — gzip not yet implemented
//   batch.max_events:      Max events per S3 object (default: 1000)
//   batch.timeout_secs:    Max seconds before flushing (default: 300)
//   region:                AWS region
//   endpoint:              Custom S3 endpoint (for MinIO/localstack)
//   auth.access_key_id:    Explicit AWS access key
//   auth.secret_access_key: Explicit AWS secret key
//   auth.session_token:    Explicit session token
//   auth.profile:          AWS profile name
//   content_type:          S3 object content type (default: application/x-ndjson)
pub struct S3Sink {
	bucket         string
	key_prefix     string
	region         string
	endpoint       string
	creds          aws.AwsCredentials
	codec          S3Codec
	content_type   string
	batch_max      int = 1000
	batch_timeout  time.Duration = 300 * time.second
mut:
	buffer     []string
	last_flush time.Time
	seq        int // sequence counter for unique keys within same second
}

enum S3Codec {
	json_codec
	text_codec
	ndjson_codec
}

// new_s3 creates a new S3Sink from config options.
pub fn new_s3(opts map[string]string) !S3Sink {
	resolved := aws.resolve_credentials(opts)!
	if resolved.creds.access_key_id.len == 0 && resolved.source != .none {
		return error('aws_s3: no AWS credentials found')
	}

	region := if resolved.creds.region.len > 0 {
		resolved.creds.region
	} else {
		opts['region'] or { 'us-east-1' }
	}

	bucket := opts['bucket'] or {
		return error('aws_s3: bucket is required')
	}

	key_prefix := opts['key_prefix'] or { 'date=%Y-%m-%d/' }
	endpoint := opts['endpoint'] or { 'https://s3.${region}.amazonaws.com' }

	codec := match opts['encoding.codec'] or { 'ndjson' } {
		'json' { S3Codec.json_codec }
		'text' { S3Codec.text_codec }
		else { S3Codec.ndjson_codec }
	}

	content_type := opts['content_type'] or {
		match codec {
			.json_codec { 'application/json' }
			.text_codec { 'text/plain' }
			.ndjson_codec { 'application/x-ndjson' }
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

	return S3Sink{
		bucket: bucket
		key_prefix: key_prefix
		region: region
		endpoint: endpoint
		creds: aws.AwsCredentials{
			access_key_id: resolved.creds.access_key_id
			secret_access_key: resolved.creds.secret_access_key
			session_token: resolved.creds.session_token
			region: region
		}
		codec: codec
		content_type: content_type
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s S3Sink) send(e event.Event) ! {
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

// flush uploads all buffered events as an S3 object.
pub fn (mut s S3Sink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	payload := s.build_payload()
	key := s.generate_key()

	s.put_object(key, payload) or {
		eprintln('s3: PutObject failed: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &S3Sink) total_buffered() int {
	return s.buffer.len
}

// build_payload constructs the file content from buffered events.
pub fn (s &S3Sink) build_payload() string {
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

// generate_key produces an S3 object key from the key_prefix template.
pub fn (mut s S3Sink) generate_key() string {
	now := time.now()
	prefix := resolve_file_path(s.key_prefix, now)
	s.seq++
	ts := now.unix()
	return '${prefix}${ts}-${s.seq}.log'
}

fn (s &S3Sink) encode_event(e event.Event) string {
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

fn (s &S3Sink) put_object(key string, payload string) ! {
	// S3 PutObject uses path-style: PUT /{bucket}/{key}
	path := '/${s.bucket}/${key}'
	host := s.endpoint.replace('https://', '').replace('http://', '')

	signed := aws.sign_request(aws.SignConfig{
		creds: s.creds
		method: 'PUT'
		host: host
		path: path
		content_type: s.content_type
		payload: payload
		region: s.region
		service: 's3'
	})!

	mut header := http.Header{}
	for k, v in signed.headers {
		header.add_custom(k, v)!
	}

	resp := http.fetch(http.FetchConfig{
		url: '${s.endpoint}${path}'
		method: .put
		data: payload
		header: header
		verbose: false
	}) or {
		return error('S3 PutObject HTTP request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('S3 PutObject HTTP ${resp.status_code}: ${resp.body}')
	}
}
