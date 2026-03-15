module sinks

import aws
import event
import json
import time

// CloudWatchLogsSink sends log events to AWS CloudWatch Logs.
// Mirrors Vector's aws_cloudwatch_logs sink.
//
// Events are batched and sent via the PutLogEvents API. The sink
// auto-creates log groups and streams on first use.
//
// Config options:
//   region:                    AWS region (e.g., us-east-1)
//   group_name:                CloudWatch log group name
//   stream_name:               CloudWatch log stream name
//   create_missing_group:      Auto-create log group (default: true)
//   create_missing_stream:     Auto-create log stream (default: true)
//   encoding.codec:            json or text (default: json)
//   batch.max_events:          Max events per PutLogEvents call (default: 100, max 10000)
//   batch.timeout_secs:        Max seconds to wait before flushing (default: 1)
//   endpoint:                  Custom endpoint URL (for testing/localstack)
//   auth.access_key_id:        Explicit AWS access key
//   auth.secret_access_key:    Explicit AWS secret key
//   auth.session_token:        Explicit session token
//   auth.profile:              AWS profile name
pub struct CloudWatchLogsSink {
	group_name             string
	stream_name            string
	region                 string
	endpoint               string
	creds                  aws.AwsCredentials
	codec                  CwlCodec
	create_missing_group   bool = true
	create_missing_stream  bool = true
	batch_max              int  = 100
	batch_timeout          time.Duration = 1 * time.second
mut:
	buffer       []CwlLogEntry
	last_flush   time.Time
	initialized  bool
}

enum CwlCodec {
	json_codec
	text_codec
}

struct CwlLogEntry {
	timestamp_ms i64
	message      string
}

// new_cloudwatch_logs creates a new CloudWatchLogsSink from config options.
pub fn new_cloudwatch_logs(opts map[string]string) !CloudWatchLogsSink {
	resolved := aws.resolve_credentials(opts)!
	if resolved.creds.access_key_id.len == 0 && resolved.source != .none {
		return error('aws_cloudwatch_logs: no AWS credentials found')
	}

	region := if resolved.creds.region.len > 0 {
		resolved.creds.region
	} else {
		opts['region'] or { 'us-east-1' }
	}

	group_name := opts['group_name'] or {
		return error('aws_cloudwatch_logs: group_name is required')
	}
	stream_name := opts['stream_name'] or {
		return error('aws_cloudwatch_logs: stream_name is required')
	}

	endpoint := opts['endpoint'] or { 'https://logs.${region}.amazonaws.com' }

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { CwlCodec.text_codec }
		else { CwlCodec.json_codec }
	}

	cmg_val := opts['create_missing_group'] or { 'true' }
	cms_val := opts['create_missing_stream'] or { 'true' }

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
		if batch_max > 10000 {
			batch_max = 10000 // AWS API limit
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return CloudWatchLogsSink{
		group_name: group_name
		stream_name: stream_name
		region: region
		endpoint: endpoint
		creds: aws.AwsCredentials{
			access_key_id: resolved.creds.access_key_id
			secret_access_key: resolved.creds.secret_access_key
			session_token: resolved.creds.session_token
			region: region
		}
		codec: codec
		create_missing_group: cmg_val == 'true'
		create_missing_stream: cms_val == 'true'
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s CloudWatchLogsSink) send(e event.Event) ! {
	match e {
		event.LogEvent {
			now := time.now()
			ts_ms := now.unix_milli()

			message := match s.codec {
				.text_codec { e.message() }
				.json_codec { e.to_json() }
			}

			s.buffer << CwlLogEntry{
				timestamp_ms: ts_ms
				message: message
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

fn (mut s CloudWatchLogsSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	// Ensure log group and stream exist on first flush
	if !s.initialized {
		if s.create_missing_group {
			s.ensure_log_group() or {
				eprintln('cloudwatch_logs: failed to create log group: ${err}')
			}
		}
		if s.create_missing_stream {
			s.ensure_log_stream() or {
				eprintln('cloudwatch_logs: failed to create log stream: ${err}')
			}
		}
		s.initialized = true
	}

	s.put_log_events() or {
		eprintln('cloudwatch_logs: PutLogEvents failed: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

fn (s &CloudWatchLogsSink) put_log_events() ! {
	// Build PutLogEvents payload
	mut log_events := []string{}
	for entry in s.buffer {
		escaped := json.encode(entry.message)
		log_events << '{"timestamp":${entry.timestamp_ms},"message":${escaped}}'
	}

	payload := '{"logGroupName":${json.encode(s.group_name)},"logStreamName":${json.encode(s.stream_name)},"logEvents":[${log_events.join(",")}]}'

	s.call_api('Logs_20140328.PutLogEvents', payload)!
}

fn (s &CloudWatchLogsSink) ensure_log_group() ! {
	payload := '{"logGroupName":${json.encode(s.group_name)}}'
	s.call_api('Logs_20140328.CreateLogGroup', payload) or {
		// ResourceAlreadyExistsException is expected
		if err.msg().contains('ResourceAlreadyExistsException') || err.msg().contains('already exists') {
			return
		}
		return err
	}
}

fn (s &CloudWatchLogsSink) ensure_log_stream() ! {
	payload := '{"logGroupName":${json.encode(s.group_name)},"logStreamName":${json.encode(s.stream_name)}}'
	s.call_api('Logs_20140328.CreateLogStream', payload) or {
		if err.msg().contains('ResourceAlreadyExistsException') || err.msg().contains('already exists') {
			return
		}
		return err
	}
}

fn (s &CloudWatchLogsSink) call_api(target string, payload string) ! {
	aws_send_payload(s.endpoint, s.creds, s.region, 'logs', target, payload)!
}

// total_buffered returns the number of events currently buffered.
pub fn (s &CloudWatchLogsSink) total_buffered() int {
	return s.buffer.len
}

// build_put_log_events_payload builds the PutLogEvents JSON payload.
// Exported for testing.
pub fn (s &CloudWatchLogsSink) build_put_log_events_payload() string {
	mut log_events := []string{}
	for entry in s.buffer {
		escaped := json.encode(entry.message)
		log_events << '{"timestamp":${entry.timestamp_ms},"message":${escaped}}'
	}
	return '{"logGroupName":${json.encode(s.group_name)},"logStreamName":${json.encode(s.stream_name)},"logEvents":[${log_events.join(",")}]}'
}
