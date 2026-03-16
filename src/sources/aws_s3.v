module sources

import aws
import event
import net.http
import time

// S3Source polls an AWS S3 bucket for new objects and emits their contents
// as log events. Mirrors Vector's aws_s3 source.
//
// Config options:
//   bucket:                 S3 bucket name (required)
//   prefix:                 Object key prefix filter (default: "")
//   region:                 AWS region
//   endpoint:               Custom S3 endpoint (for localstack)
//   poll_interval_secs:     How often to check for new objects (default: 15)
//   codec:                  "text" or "json" (default: text)
//   auth.access_key_id:     Explicit AWS access key
//   auth.secret_access_key: Explicit AWS secret key
//   auth.session_token:     Explicit session token
pub struct S3Source {
	bucket        string
	prefix        string
	region        string
	endpoint      string
	creds         aws.AwsCredentials
	poll_interval time.Duration = 15 * time.second
	codec         string = 'text'
}

// new_s3_source creates a new S3Source from config options.
pub fn new_s3_source(opts map[string]string) !S3Source {
	resolved := aws.resolve_credentials(opts)!
	if resolved.creds.access_key_id.len == 0 && resolved.source != .none {
		return error('aws_s3 source: no AWS credentials found')
	}

	region := if resolved.creds.region.len > 0 {
		resolved.creds.region
	} else {
		opts['region'] or { 'us-east-1' }
	}

	bucket := opts['bucket'] or {
		return error('aws_s3 source: bucket is required')
	}

	prefix := opts['prefix'] or { '' }
	endpoint := opts['endpoint'] or { 'https://s3.${region}.amazonaws.com' }

	mut poll_secs := 15.0
	if s := opts['poll_interval_secs'] {
		poll_secs = s.f64()
		if poll_secs <= 0 {
			poll_secs = 15.0
		}
	}

	codec := opts['codec'] or { 'text' }

	return S3Source{
		bucket: bucket
		prefix: prefix
		region: region
		endpoint: endpoint
		creds: aws.AwsCredentials{
			access_key_id: resolved.creds.access_key_id
			secret_access_key: resolved.creds.secret_access_key
			session_token: resolved.creds.session_token
			region: region
		}
		poll_interval: time.Duration(i64(poll_secs * 1_000_000_000))
		codec: codec
	}
}

// run polls S3 for new objects and emits their contents as log events.
pub fn (s &S3Source) run(output chan event.Event) {
	mut seen := map[string]bool{}

	for {
		s.poll(output, mut seen)
		time.sleep(s.poll_interval)
	}
}

fn (s &S3Source) poll(output chan event.Event, mut seen map[string]bool) {
	keys := s.list_objects() or {
		eprintln('aws_s3 source: ListObjectsV2 failed: ${err}')
		return
	}

	for key in keys {
		if seen[key] {
			continue
		}
		seen[key] = true

		body := s.get_object(key) or {
			eprintln('aws_s3 source: GetObject failed for ${key}: ${err}')
			continue
		}

		lines := body.split('\n')
		for line in lines {
			trimmed := line.trim_right('\r\n')
			if trimmed.len == 0 {
				continue
			}
			mut ev := event.new_log(trimmed)
			ev.meta.source_type = 'aws_s3'
			ev.set('bucket', event.Value(s.bucket))
			ev.set('key', event.Value(key))
			output <- event.Event(ev)
		}
	}
}

fn (s &S3Source) list_objects() ![]string {
	host := s.endpoint.replace('https://', '').replace('http://', '')
	path := '/${s.bucket}/'
	mut query := 'list-type=2'
	if s.prefix.len > 0 {
		query += '&prefix=${s.prefix}'
	}

	signed := aws.sign_request(aws.SignConfig{
		creds: s.creds
		method: 'GET'
		host: host
		path: path
		query: query
		region: s.region
		service: 's3'
		content_type: ''
		payload: ''
	})!

	mut header := http.Header{}
	for k, v in signed.headers {
		header.add_custom(k, v)!
	}

	resp := http.fetch(http.FetchConfig{
		url: '${s.endpoint}${path}?${query}'
		method: .get
		header: header
		verbose: false
	}) or {
		return error('ListObjectsV2 HTTP request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('ListObjectsV2 HTTP ${resp.status_code}: ${resp.body}')
	}

	return parse_s3_keys(resp.body)
}

fn (s &S3Source) get_object(key string) !string {
	host := s.endpoint.replace('https://', '').replace('http://', '')
	path := '/${s.bucket}/${key}'

	signed := aws.sign_request(aws.SignConfig{
		creds: s.creds
		method: 'GET'
		host: host
		path: path
		region: s.region
		service: 's3'
		content_type: ''
		payload: ''
	})!

	mut header := http.Header{}
	for k, v in signed.headers {
		header.add_custom(k, v)!
	}

	resp := http.fetch(http.FetchConfig{
		url: '${s.endpoint}${path}'
		method: .get
		header: header
		verbose: false
	}) or {
		return error('GetObject HTTP request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('GetObject HTTP ${resp.status_code}: ${resp.body}')
	}

	return resp.body
}

// parse_s3_keys extracts <Key> values from ListObjectsV2 XML response.
fn parse_s3_keys(xml string) []string {
	mut keys := []string{}
	mut rest := xml
	for {
		start_idx := rest.index('<Key>') or { break }
		after_tag := rest[start_idx + 5..]
		end_idx := after_tag.index('</Key>') or { break }
		keys << after_tag[..end_idx]
		rest = after_tag[end_idx + 6..]
	}
	return keys
}
