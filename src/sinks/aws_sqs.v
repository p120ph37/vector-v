module sinks

import aws
import event
import json
import time

// SqsSink sends log events as messages to an AWS SQS queue via the
// SendMessageBatch API (JSON protocol). Mirrors Vector's aws_sqs sink.
//
// Events are batched (up to 10 per call, the AWS maximum) and sent using
// the JSON API format with application/x-amz-json-1.0 content type.
//
// Config options:
//   queue_url:                 SQS queue URL (required)
//   region:                    AWS region (e.g., us-east-1)
//   endpoint:                  Custom endpoint URL (for testing/localstack)
//   encoding.codec:            json or text (default: json)
//   batch.max_events:          Max messages per SendMessageBatch call (default: 10, AWS max 10)
//   batch.timeout_secs:        Max seconds to wait before flushing (default: 1)
//   message_group_id:          FIFO queue message group ID (optional)
//   auth.access_key_id:        Explicit AWS access key
//   auth.secret_access_key:    Explicit AWS secret key
//   auth.session_token:        Explicit session token
//   auth.profile:              AWS profile name
pub struct SqsSink {
	queue_url         string
	region            string
	endpoint          string
	creds             aws.AwsCredentials
	codec             SqsCodec
	message_group_id  string
	batch_max         int = 10
	batch_timeout     time.Duration = 1 * time.second
mut:
	buffer      []string
	last_flush  time.Time
	msg_counter u64
}

enum SqsCodec {
	json_codec
	text_codec
}

// new_sqs creates a new SqsSink from config options.
pub fn new_sqs(opts map[string]string) !SqsSink {
	resolved := aws.resolve_credentials(opts)!
	if resolved.creds.access_key_id.len == 0 && resolved.source != .none {
		return error('aws_sqs: no AWS credentials found')
	}

	region := if resolved.creds.region.len > 0 {
		resolved.creds.region
	} else {
		opts['region'] or { 'us-east-1' }
	}

	queue_url := opts['queue_url'] or {
		return error('aws_sqs: queue_url is required')
	}

	endpoint := opts['endpoint'] or { 'https://sqs.${region}.amazonaws.com' }

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { SqsCodec.text_codec }
		else { SqsCodec.json_codec }
	}

	message_group_id := opts['message_group_id'] or { '' }

	mut batch_max := 10
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 10
		}
		if batch_max > 10 {
			batch_max = 10 // AWS API limit
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return SqsSink{
		queue_url: queue_url
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
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s SqsSink) send(e event.Event) ! {
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

// flush sends buffered messages to SQS via SendMessageBatch.
pub fn (mut s SqsSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	s.send_message_batch() or {
		eprintln('aws_sqs: SendMessageBatch failed: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

fn (mut s SqsSink) send_message_batch() ! {
	mut entries := []string{}
	for msg in s.buffer {
		s.msg_counter++
		id := '${s.msg_counter}'

		mut entry := '{"Id":${json.encode(id)},"MessageBody":${json.encode(msg)}'
		if s.message_group_id.len > 0 {
			entry += ',"MessageGroupId":${json.encode(s.message_group_id)}'
		}
		entry += '}'

		entries << entry
	}

	payload := '{"QueueUrl":${json.encode(s.queue_url)},"Entries":[${entries.join(",")}]}'

	aws_send_payload(s.endpoint, s.creds, s.region, 'sqs', 'AmazonSQS.SendMessageBatch',
		payload)!
}

// total_buffered returns the number of messages currently buffered.
pub fn (s &SqsSink) total_buffered() int {
	return s.buffer.len
}

// build_send_message_batch_payload builds the SendMessageBatch JSON payload.
// Exported for testing.
pub fn (s &SqsSink) build_send_message_batch_payload() string {
	mut entries := []string{}
	mut counter := s.msg_counter
	for msg in s.buffer {
		counter++
		id := '${counter}'

		mut entry := '{"Id":${json.encode(id)},"MessageBody":${json.encode(msg)}'
		if s.message_group_id.len > 0 {
			entry += ',"MessageGroupId":${json.encode(s.message_group_id)}'
		}
		entry += '}'

		entries << entry
	}
	return '{"QueueUrl":${json.encode(s.queue_url)},"Entries":[${entries.join(",")}]}'
}
