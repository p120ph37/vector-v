module sinks

import aws
import event
import json
import time

// SnsSink sends log events as messages to an AWS SNS topic via the
// Publish API (JSON protocol). Mirrors Vector's aws_sns sink.
//
// Events are sent individually via the SNS Publish API using the
// JSON API format with application/x-amz-json-1.1 content type.
//
// Config options:
//   topic_arn:                 SNS topic ARN (required)
//   region:                    AWS region (e.g., us-east-1)
//   endpoint:                  Custom endpoint URL (for testing/localstack)
//   encoding.codec:            json or text (default: json)
//   batch.max_events:          Max messages per batch before flush (default: 10)
//   batch.timeout_secs:        Max seconds to wait before flushing (default: 1)
//   message_group_id:          FIFO topic message group ID (optional)
//   subject:                   SNS message subject (optional)
//   auth.access_key_id:        Explicit AWS access key
//   auth.secret_access_key:    Explicit AWS secret key
//   auth.session_token:        Explicit session token
//   auth.profile:              AWS profile name
pub struct SnsSink {
	topic_arn         string
	region            string
	endpoint          string
	creds             aws.AwsCredentials
	codec             SnsCodec
	message_group_id  string
	subject           string
	batch_max         int = 10
	batch_timeout     time.Duration = 1 * time.second
mut:
	buffer     []string
	last_flush time.Time
}

enum SnsCodec {
	json_codec
	text_codec
}

// new_sns creates a new SnsSink from config options.
pub fn new_sns(opts map[string]string) !SnsSink {
	resolved := aws.resolve_credentials(opts)!
	if resolved.creds.access_key_id.len == 0 && resolved.source != .none {
		return error('aws_sns: no AWS credentials found')
	}

	region := if resolved.creds.region.len > 0 {
		resolved.creds.region
	} else {
		opts['region'] or { 'us-east-1' }
	}

	topic_arn := opts['topic_arn'] or {
		return error('aws_sns: topic_arn is required')
	}
	if topic_arn.len == 0 {
		return error('aws_sns: topic_arn is required')
	}

	endpoint := opts['endpoint'] or { 'https://sns.${region}.amazonaws.com' }

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { SnsCodec.text_codec }
		else { SnsCodec.json_codec }
	}

	message_group_id := opts['message_group_id'] or { '' }
	subject := opts['subject'] or { '' }

	mut batch_max := 10
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 10
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return SnsSink{
		topic_arn: topic_arn
		region: region
		endpoint: endpoint
		creds: aws.AwsCredentials{
			access_key_id: resolved.creds.access_key_id
			secret_access_key: resolved.creds.secret_access_key
			session_token: resolved.creds.session_token
			region: region
		}
		codec: codec
		message_group_id: message_group_id
		subject: subject
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s SnsSink) send(e event.Event) ! {
	match e {
		event.LogEvent {
			message := match s.codec {
				.text_codec { e.message() }
				.json_codec { e.to_json() }
			}

			s.buffer << message

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

// flush sends all buffered messages to SNS via Publish API.
pub fn (mut s SnsSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	for msg in s.buffer {
		s.publish_message(msg) or {
			eprintln('aws_sns: Publish failed: ${err}')
			return error(err.msg())
		}
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

fn (s &SnsSink) publish_message(message string) ! {
	payload := s.build_publish_payload(message)
	aws_send_payload(s.endpoint, s.creds, s.region, 'sns', 'SNS.Publish', payload)!
}

// build_publish_payload constructs the SNS Publish JSON payload.
// Exported for testing.
pub fn (s &SnsSink) build_publish_payload(message string) string {
	mut payload := '{"TopicArn":${json.encode(s.topic_arn)},"Message":${json.encode(message)}'
	if s.subject.len > 0 {
		payload += ',"Subject":${json.encode(s.subject)}'
	}
	if s.message_group_id.len > 0 {
		payload += ',"MessageGroupId":${json.encode(s.message_group_id)}'
	}
	payload += '}'
	return payload
}

// total_buffered returns the number of messages currently buffered.
pub fn (s &SnsSink) total_buffered() int {
	return s.buffer.len
}
