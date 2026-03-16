module sinks

import aws
import encoding.base64
import event
import json
import time

// KinesisSink sends log events to AWS Kinesis Data Streams via PutRecords API.
// Mirrors Vector's aws_kinesis_streams sink.
//
// Events are batched and sent as base64-encoded records. An optional partition
// key field can be specified; otherwise a default key is used.
//
// Config options:
//   stream_name:               Kinesis stream name (required)
//   partition_key:             Event field to use as partition key (default: "0")
//   region:                    AWS region (e.g., us-east-1)
//   endpoint:                  Custom endpoint URL (for testing/localstack)
//   encoding.codec:            json or text (default: json)
//   batch.max_events:          Max records per PutRecords call (default: 500, AWS max 500)
//   batch.timeout_secs:        Max seconds to wait before flushing (default: 1)
//   auth.access_key_id:        Explicit AWS access key
//   auth.secret_access_key:    Explicit AWS secret key
//   auth.session_token:        Explicit session token
//   auth.profile:              AWS profile name
pub struct KinesisSink {
	stream_name    string
	partition_key  string
	region         string
	endpoint       string
	creds          aws.AwsCredentials
	codec          KinesisCodec
	batch_max      int = 500
	batch_timeout  time.Duration = 1 * time.second
mut:
	buffer      []KinesisRecord
	last_flush  time.Time
}

enum KinesisCodec {
	json_codec
	text_codec
}

struct KinesisRecord {
	data          string // base64-encoded
	partition_key string
}

// new_kinesis creates a new KinesisSink from config options.
pub fn new_kinesis(opts map[string]string) !KinesisSink {
	resolved := aws.resolve_credentials(opts)!
	if resolved.creds.access_key_id.len == 0 && resolved.source != .none {
		return error('aws_kinesis: no AWS credentials found')
	}

	region := if resolved.creds.region.len > 0 {
		resolved.creds.region
	} else {
		opts['region'] or { 'us-east-1' }
	}

	stream_name := opts['stream_name'] or {
		return error('aws_kinesis: stream_name is required')
	}

	partition_key := opts['partition_key'] or { '' }
	endpoint := opts['endpoint'] or { 'https://kinesis.${region}.amazonaws.com' }

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { KinesisCodec.text_codec }
		else { KinesisCodec.json_codec }
	}

	mut batch_max := 500
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 500
		}
		if batch_max > 500 {
			batch_max = 500 // AWS API limit
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return KinesisSink{
		stream_name: stream_name
		partition_key: partition_key
		region: region
		endpoint: endpoint
		creds: aws.AwsCredentials{
			access_key_id: resolved.creds.access_key_id
			secret_access_key: resolved.creds.secret_access_key
			session_token: resolved.creds.session_token
			region: region
		}
		codec: codec
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s KinesisSink) send(e event.Event) ! {
	match e {
		event.LogEvent {
			message := match s.codec {
				.text_codec { e.message() }
				.json_codec { e.to_json() }
			}

			pk := if s.partition_key.len > 0 {
				if v := e.get(s.partition_key) {
					event.value_to_string(v)
				} else {
					'0'
				}
			} else {
				'0'
			}

			s.buffer << KinesisRecord{
				data: base64.encode_str(message)
				partition_key: pk
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

// flush sends buffered records to Kinesis via PutRecords.
pub fn (mut s KinesisSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	s.put_records() or {
		eprintln('aws_kinesis: PutRecords failed: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

fn (s &KinesisSink) put_records() ! {
	mut records := []string{}
	for rec in s.buffer {
		records << '{"Data":${json.encode(rec.data)},"PartitionKey":${json.encode(rec.partition_key)}}'
	}

	payload := '{"StreamName":${json.encode(s.stream_name)},"Records":[${records.join(",")}]}'

	aws_send_payload(s.endpoint, s.creds, s.region, 'kinesis', 'Kinesis_20131202.PutRecords',
		payload)!
}

// total_buffered returns the number of records currently buffered.
pub fn (s &KinesisSink) total_buffered() int {
	return s.buffer.len
}

// build_put_records_payload builds the PutRecords JSON payload.
// Exported for testing.
pub fn (s &KinesisSink) build_put_records_payload() string {
	mut records := []string{}
	for rec in s.buffer {
		records << '{"Data":${json.encode(rec.data)},"PartitionKey":${json.encode(rec.partition_key)}}'
	}
	return '{"StreamName":${json.encode(s.stream_name)},"Records":[${records.join(",")}]}'
}

// ---------------------------------------------------------------------------
// KinesisFirehoseSink — AWS Kinesis Data Firehose via PutRecordBatch API
// ---------------------------------------------------------------------------

// KinesisFirehoseSink sends log events to AWS Kinesis Data Firehose via
// PutRecordBatch API. Mirrors Vector's aws_kinesis_firehose sink.
//
// Config options:
//   delivery_stream_name:      Firehose delivery stream name (required)
//   region:                    AWS region (e.g., us-east-1)
//   endpoint:                  Custom endpoint URL (for testing/localstack)
//   encoding.codec:            json or text (default: json)
//   batch.max_events:          Max records per PutRecordBatch call (default: 500, AWS max 500)
//   batch.timeout_secs:        Max seconds to wait before flushing (default: 1)
//   auth.access_key_id:        Explicit AWS access key
//   auth.secret_access_key:    Explicit AWS secret key
//   auth.session_token:        Explicit session token
//   auth.profile:              AWS profile name
pub struct KinesisFirehoseSink {
	delivery_stream_name string
	region               string
	endpoint             string
	creds                aws.AwsCredentials
	codec                KinesisCodec
	batch_max            int = 500
	batch_timeout        time.Duration = 1 * time.second
mut:
	buffer      []string // base64-encoded records
	last_flush  time.Time
}

// new_kinesis_firehose creates a new KinesisFirehoseSink from config options.
pub fn new_kinesis_firehose(opts map[string]string) !KinesisFirehoseSink {
	resolved := aws.resolve_credentials(opts)!
	if resolved.creds.access_key_id.len == 0 && resolved.source != .none {
		return error('aws_kinesis_firehose: no AWS credentials found')
	}

	region := if resolved.creds.region.len > 0 {
		resolved.creds.region
	} else {
		opts['region'] or { 'us-east-1' }
	}

	delivery_stream_name := opts['delivery_stream_name'] or {
		return error('aws_kinesis_firehose: delivery_stream_name is required')
	}

	endpoint := opts['endpoint'] or { 'https://firehose.${region}.amazonaws.com' }

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { KinesisCodec.text_codec }
		else { KinesisCodec.json_codec }
	}

	mut batch_max := 500
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 500
		}
		if batch_max > 500 {
			batch_max = 500 // AWS API limit
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return KinesisFirehoseSink{
		delivery_stream_name: delivery_stream_name
		region: region
		endpoint: endpoint
		creds: aws.AwsCredentials{
			access_key_id: resolved.creds.access_key_id
			secret_access_key: resolved.creds.secret_access_key
			session_token: resolved.creds.session_token
			region: region
		}
		codec: codec
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s KinesisFirehoseSink) send(e event.Event) ! {
	match e {
		event.LogEvent {
			message := match s.codec {
				.text_codec { e.message() }
				.json_codec { e.to_json() }
			}

			s.buffer << base64.encode_str(message)

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

// flush sends buffered records to Firehose via PutRecordBatch.
pub fn (mut s KinesisFirehoseSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	s.put_record_batch() or {
		eprintln('aws_kinesis_firehose: PutRecordBatch failed: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

fn (s &KinesisFirehoseSink) put_record_batch() ! {
	mut records := []string{}
	for data in s.buffer {
		records << '{"Data":${json.encode(data)}}'
	}

	payload := '{"DeliveryStreamName":${json.encode(s.delivery_stream_name)},"Records":[${records.join(",")}]}'

	aws_send_payload(s.endpoint, s.creds, s.region, 'firehose', 'Firehose_20150804.PutRecordBatch',
		payload)!
}

// total_buffered returns the number of records currently buffered.
pub fn (s &KinesisFirehoseSink) total_buffered() int {
	return s.buffer.len
}

// build_put_record_batch_payload builds the PutRecordBatch JSON payload.
// Exported for testing.
pub fn (s &KinesisFirehoseSink) build_put_record_batch_payload() string {
	mut records := []string{}
	for data in s.buffer {
		records << '{"Data":${json.encode(data)}}'
	}
	return '{"DeliveryStreamName":${json.encode(s.delivery_stream_name)},"Records":[${records.join(",")}]}'
}
