module sinks

import event
import encoding.base64
import mockserver
import os

// Helper to set up AWS env vars for Kinesis tests and return a defer-compatible cleanup.
fn setup_aws_env() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_REGION', 'us-east-1', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
}

fn cleanup_aws_env() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.unsetenv('AWS_REGION')
	os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
}

// ---------------------------------------------------------------------------
// KinesisSink tests
// ---------------------------------------------------------------------------

fn test_new_kinesis_defaults() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	s := new_kinesis({
		'stream_name': 'test-stream'
	}) or { panic(err.str()) }
	assert s.stream_name == 'test-stream'
	assert s.batch_max == 500
	assert s.codec == .json_codec
	assert s.partition_key == ''
	assert s.region == 'us-east-1'
	assert s.endpoint == 'https://kinesis.us-east-1.amazonaws.com'
}

fn test_new_kinesis_missing_stream() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	new_kinesis(map[string]string{}) or {
		assert err.msg().contains('stream_name is required')
		return
	}
	assert false, 'expected error for missing stream_name'
}

fn test_new_kinesis_custom_config() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	s := new_kinesis({
		'stream_name':      'custom-stream'
		'region':           'eu-west-1'
		'endpoint':         'http://localhost:4566'
		'encoding.codec':   'text'
		'batch.max_events': '200'
		'partition_key':    'host'
		'batch.timeout_secs': '5'
	}) or { panic(err.str()) }
	assert s.stream_name == 'custom-stream'
	assert s.region == 'eu-west-1'
	assert s.endpoint == 'http://localhost:4566'
	assert s.codec == .text_codec
	assert s.batch_max == 200
	assert s.partition_key == 'host'
}

fn test_kinesis_send_buffers() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis({
		'stream_name':      'test'
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('hello'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1

	ev2 := event.Event(event.new_log('world'))
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 2
}

fn test_kinesis_build_payload() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis({
		'stream_name':      'my-stream'
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('test message'))
	s.send(ev) or { panic(err.str()) }

	payload := s.build_put_records_payload()
	assert payload.contains('"StreamName"')
	assert payload.contains('"my-stream"')
	assert payload.contains('"Records"')
	assert payload.contains('"Data"')
	assert payload.contains('"PartitionKey"')
	// Default partition key is "0"
	assert payload.contains('"0"')
}

fn test_kinesis_partition_key() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis({
		'stream_name':      'test'
		'partition_key':    'host'
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	mut log := event.new_log('test')
	log.set('host', event.Value('server-1'))
	ev := event.Event(log)
	s.send(ev) or { panic(err.str()) }

	payload := s.build_put_records_payload()
	assert payload.contains('"server-1"')
}

fn test_kinesis_text_codec() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis({
		'stream_name':      'test'
		'encoding.codec':   'text'
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('plain text message'))
	s.send(ev) or { panic(err.str()) }

	assert s.buffer.len == 1
	// Text codec should base64-encode just the message text
	decoded := base64.decode_str(s.buffer[0].data)
	assert decoded == 'plain text message'
}

fn test_kinesis_batch_limit() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	// Request batch_max > 500, should be capped to 500
	s := new_kinesis({
		'stream_name':      'test'
		'batch.max_events': '1000'
	}) or { panic(err.str()) }
	assert s.batch_max == 500

	// Request batch_max <= 0, should default to 500
	s2 := new_kinesis({
		'stream_name':      'test'
		'batch.max_events': '-1'
	}) or { panic(err.str()) }
	assert s2.batch_max == 500

	// Request batch_max = 0, should default to 500
	s3 := new_kinesis({
		'stream_name':      'test'
		'batch.max_events': '0'
	}) or { panic(err.str()) }
	assert s3.batch_max == 500
}

fn test_kinesis_total_buffered() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis({
		'stream_name':      'test'
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or { panic(err.str()) }
	}
	assert s.total_buffered() == 5
}

fn test_kinesis_flush_empty() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis({
		'stream_name': 'test'
	}) or { panic(err.str()) }

	// flush on empty buffer should be a no-op (no error)
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_kinesis_registry() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	s := build_sink('aws_kinesis_streams', {
		'stream_name': 'registry-test'
	}) or { panic(err.str()) }
	assert s is KinesisSink
}

fn test_kinesis_partition_key_missing_field() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis({
		'stream_name':      'test'
		'partition_key':    'nonexistent_field'
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('test'))
	s.send(ev) or { panic(err.str()) }

	// When partition_key field is missing from event, should fall back to "0"
	payload := s.build_put_records_payload()
	assert payload.contains('"0"')
}

fn test_kinesis_invalid_batch_timeout() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	s := new_kinesis({
		'stream_name':        'test'
		'batch.timeout_secs': '-10'
	}) or { panic(err.str()) }
	assert s.batch_timeout > 0
}

fn test_kinesis_drops_non_log() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis({
		'stream_name':      'test'
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	// Send a metric event -- should be silently dropped
	metric := event.Event(event.Metric{
		name: 'test.counter'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	s.send(metric) or { panic(err.str()) }
	assert s.total_buffered() == 0
}

fn test_kinesis_explicit_credentials() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer { os.unsetenv('AWS_SHARED_CREDENTIALS_FILE') }

	s := new_kinesis({
		'stream_name':            'test'
		'region':                 'us-west-2'
		'auth.access_key_id':     'AKIAEXPLICIT'
		'auth.secret_access_key': 'explicitsecret'
	}) or { panic(err.str()) }
	assert s.creds.access_key_id == 'AKIAEXPLICIT'
	assert s.creds.secret_access_key == 'explicitsecret'
	assert s.region == 'us-west-2'
}

fn test_kinesis_build_payload_multiple_records() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis({
		'stream_name':      'multi-test'
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('record ${i}'))
		s.send(ev) or { panic(err.str()) }
	}

	payload := s.build_put_records_payload()
	assert payload.contains('"multi-test"')
	// Should have 3 records
	assert s.total_buffered() == 3
	// Payload should contain multiple Data entries
	mut count := 0
	mut idx := 0
	for {
		pos := payload.index_after('"Data"', idx) or { break }
		count++
		idx = pos + 6
	}
	assert count == 3
}

// ---------------------------------------------------------------------------
// KinesisFirehoseSink tests
// ---------------------------------------------------------------------------

fn test_new_kinesis_firehose_defaults() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	s := new_kinesis_firehose({
		'delivery_stream_name': 'test-delivery'
	}) or { panic(err.str()) }
	assert s.delivery_stream_name == 'test-delivery'
	assert s.batch_max == 500
	assert s.codec == .json_codec
	assert s.region == 'us-east-1'
	assert s.endpoint == 'https://firehose.us-east-1.amazonaws.com'
}

fn test_new_kinesis_firehose_missing_stream() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	new_kinesis_firehose(map[string]string{}) or {
		assert err.msg().contains('delivery_stream_name is required')
		return
	}
	assert false, 'expected error for missing delivery_stream_name'
}

fn test_new_kinesis_firehose_custom_config() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	s := new_kinesis_firehose({
		'delivery_stream_name': 'custom-delivery'
		'region':               'ap-southeast-1'
		'endpoint':             'http://localhost:4566'
		'encoding.codec':       'text'
		'batch.max_events':     '100'
		'batch.timeout_secs':   '10'
	}) or { panic(err.str()) }
	assert s.delivery_stream_name == 'custom-delivery'
	assert s.region == 'ap-southeast-1'
	assert s.endpoint == 'http://localhost:4566'
	assert s.codec == .text_codec
	assert s.batch_max == 100
}

fn test_kinesis_firehose_send_buffers() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis_firehose({
		'delivery_stream_name': 'test'
		'batch.max_events':     '500'
		'batch.timeout_secs':   '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('hello firehose'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1

	ev2 := event.Event(event.new_log('second'))
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 2
}

fn test_kinesis_firehose_build_payload() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis_firehose({
		'delivery_stream_name': 'my-delivery'
		'batch.max_events':     '500'
		'batch.timeout_secs':   '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('firehose test'))
	s.send(ev) or { panic(err.str()) }

	payload := s.build_put_record_batch_payload()
	assert payload.contains('"DeliveryStreamName"')
	assert payload.contains('"my-delivery"')
	assert payload.contains('"Records"')
	assert payload.contains('"Data"')
	// Firehose records do NOT have PartitionKey
	assert !payload.contains('"PartitionKey"')
}

fn test_kinesis_firehose_total_buffered() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis_firehose({
		'delivery_stream_name': 'test'
		'batch.max_events':     '500'
		'batch.timeout_secs':   '3600'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	for i in 0 .. 4 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or { panic(err.str()) }
	}
	assert s.total_buffered() == 4
}

fn test_kinesis_firehose_registry() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	s := build_sink('aws_kinesis_firehose', {
		'delivery_stream_name': 'registry-test'
	}) or { panic(err.str()) }
	assert s is KinesisFirehoseSink
}

fn test_kinesis_firehose_flush_empty() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis_firehose({
		'delivery_stream_name': 'test'
	}) or { panic(err.str()) }

	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_kinesis_firehose_batch_limit() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	s := new_kinesis_firehose({
		'delivery_stream_name': 'test'
		'batch.max_events':     '1000'
	}) or { panic(err.str()) }
	assert s.batch_max == 500

	s2 := new_kinesis_firehose({
		'delivery_stream_name': 'test'
		'batch.max_events':     '0'
	}) or { panic(err.str()) }
	assert s2.batch_max == 500
}

fn test_kinesis_firehose_drops_non_log() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis_firehose({
		'delivery_stream_name': 'test'
		'batch.max_events':     '500'
		'batch.timeout_secs':   '3600'
	}) or { panic(err.str()) }

	metric := event.Event(event.Metric{
		name: 'test.counter'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	s.send(metric) or { panic(err.str()) }
	assert s.total_buffered() == 0
}

fn test_kinesis_firehose_text_codec() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut s := new_kinesis_firehose({
		'delivery_stream_name': 'test'
		'encoding.codec':       'text'
		'batch.max_events':     '500'
		'batch.timeout_secs':   '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('plain firehose text'))
	s.send(ev) or { panic(err.str()) }

	assert s.buffer.len == 1
	decoded := base64.decode_str(s.buffer[0])
	assert decoded == 'plain firehose text'
}

fn test_kinesis_firehose_explicit_credentials() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer { os.unsetenv('AWS_SHARED_CREDENTIALS_FILE') }

	s := new_kinesis_firehose({
		'delivery_stream_name':   'test'
		'region':                 'eu-central-1'
		'auth.access_key_id':     'AKIAEXPLICIT'
		'auth.secret_access_key': 'explicitsecret'
	}) or { panic(err.str()) }
	assert s.creds.access_key_id == 'AKIAEXPLICIT'
	assert s.creds.secret_access_key == 'explicitsecret'
	assert s.region == 'eu-central-1'
}

fn test_kinesis_firehose_invalid_batch_timeout() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	s := new_kinesis_firehose({
		'delivery_stream_name': 'test'
		'batch.timeout_secs':   '-5'
	}) or { panic(err.str()) }
	assert s.batch_timeout > 0
}

// ---------------------------------------------------------------------------
// Mock server integration tests — cover flush/put_records/put_record_batch
// ---------------------------------------------------------------------------

fn test_kinesis_flush_to_mock_server() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, '{"FailedRecordCount":0,"Records":[]}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_kinesis({
		'stream_name':      'mock-stream'
		'endpoint':         mock.url()
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev1 := event.Event(event.new_log('flush-test-1'))
	ev2 := event.Event(event.new_log('flush-test-2'))
	s.send(ev1) or { panic(err.str()) }
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 2

	s.flush() or { panic(err.str()) }
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].body.contains('"StreamName"')
	assert reqs[0].body.contains('"mock-stream"')
	assert reqs[0].body.contains('"Records"')
}

fn test_kinesis_flush_error_handling() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(500, '{"message":"Internal Server Error"}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_kinesis({
		'stream_name':      'error-stream'
		'endpoint':         mock.url()
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('will-fail'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1

	// flush should return error on HTTP failure
	s.flush() or {
		// Expected: flush fails, buffer is NOT cleared
		assert s.total_buffered() == 1
		return
	}
	// If flush succeeded (mock returned 500 but sink treated as success), buffer should be cleared
	assert s.total_buffered() == 0
}

fn test_kinesis_firehose_flush_to_mock_server() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, '{"FailedPutCount":0,"RequestResponses":[]}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_kinesis_firehose({
		'delivery_stream_name': 'mock-delivery'
		'endpoint':             mock.url()
		'batch.max_events':     '500'
		'batch.timeout_secs':   '3600'
	}) or { panic(err.str()) }

	ev1 := event.Event(event.new_log('firehose-flush-1'))
	ev2 := event.Event(event.new_log('firehose-flush-2'))
	s.send(ev1) or { panic(err.str()) }
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 2

	s.flush() or { panic(err.str()) }
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].body.contains('"DeliveryStreamName"')
	assert reqs[0].body.contains('"mock-delivery"')
	assert reqs[0].body.contains('"Records"')
}

fn test_kinesis_firehose_flush_error_handling() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(500, '{"message":"Internal Server Error"}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_kinesis_firehose({
		'delivery_stream_name': 'error-delivery'
		'endpoint':             mock.url()
		'batch.max_events':     '500'
		'batch.timeout_secs':   '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('will-fail'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1

	s.flush() or {
		assert s.total_buffered() == 1
		return
	}
	assert s.total_buffered() == 0
}

fn test_kinesis_region_default_fallback() {
	// No AWS_REGION, no opts['region'] => resolved.creds.region is empty,
	// forcing the else branch to use default 'us-east-1'
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.unsetenv('AWS_REGION')
	os.unsetenv('AWS_DEFAULT_REGION')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_kinesis({
		'stream_name': 'test'
	}) or { panic(err.str()) }
	assert s.region == 'us-east-1'
}

fn test_kinesis_firehose_region_default_fallback() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.unsetenv('AWS_REGION')
	os.unsetenv('AWS_DEFAULT_REGION')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_kinesis_firehose({
		'delivery_stream_name': 'test'
	}) or { panic(err.str()) }
	assert s.region == 'us-east-1'
}

fn test_kinesis_auto_flush_on_batch_full() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, '{"FailedRecordCount":0,"Records":[]}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	// Set batch_max=2 so that sending 2 events triggers auto-flush
	mut s := new_kinesis({
		'stream_name':        'auto-flush-stream'
		'endpoint':           mock.url()
		'batch.max_events':   '2'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev1 := event.Event(event.new_log('auto-1'))
	ev2 := event.Event(event.new_log('auto-2'))
	s.send(ev1) or { panic(err.str()) }
	// Second send triggers auto-flush since buffer.len >= batch_max
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
}

fn test_kinesis_firehose_auto_flush_on_batch_full() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, '{"FailedPutCount":0,"RequestResponses":[]}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_kinesis_firehose({
		'delivery_stream_name': 'auto-flush-delivery'
		'endpoint':             mock.url()
		'batch.max_events':     '2'
		'batch.timeout_secs':   '3600'
	}) or { panic(err.str()) }

	ev1 := event.Event(event.new_log('auto-fh-1'))
	ev2 := event.Event(event.new_log('auto-fh-2'))
	s.send(ev1) or { panic(err.str()) }
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
}

fn test_kinesis_send_with_partition_key_via_mock() {
	setup_aws_env()
	defer { cleanup_aws_env() }

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, '{"FailedRecordCount":0,"Records":[]}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_kinesis({
		'stream_name':      'pk-stream'
		'partition_key':    'host'
		'endpoint':         mock.url()
		'batch.max_events': '500'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	mut log := event.new_log('pk test')
	log.set('host', event.Value('my-host'))
	ev := event.Event(log)
	s.send(ev) or { panic(err.str()) }
	s.flush() or { panic(err.str()) }

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body.contains('"my-host"')
}
