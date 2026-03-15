module sinks

import event
import os

fn setup_test_aws_env() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_REGION', 'us-east-1', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
}

fn cleanup_test_aws_env() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.unsetenv('AWS_REGION')
	os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
}

fn test_new_cloudwatch_logs_defaults() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	s := new_cloudwatch_logs({
		'group_name':  '/test/logs'
		'stream_name': 'stream-1'
	})!
	assert s.group_name == '/test/logs'
	assert s.stream_name == 'stream-1'
	assert s.region == 'us-east-1'
	assert s.batch_max == 100
	assert s.create_missing_group == true
	assert s.create_missing_stream == true
	assert s.codec == .json_codec
	assert s.endpoint == 'https://logs.us-east-1.amazonaws.com'
}

fn test_new_cloudwatch_logs_custom_region() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	s := new_cloudwatch_logs({
		'group_name':  '/test/logs'
		'stream_name': 'stream-1'
		'region':      'eu-west-1'
	})!
	assert s.region == 'eu-west-1'
	assert s.endpoint == 'https://logs.eu-west-1.amazonaws.com'
}

fn test_new_cloudwatch_logs_custom_endpoint() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	s := new_cloudwatch_logs({
		'group_name':  '/test/logs'
		'stream_name': 'stream-1'
		'endpoint':    'http://localhost:4566'
	})!
	assert s.endpoint == 'http://localhost:4566'
}

fn test_new_cloudwatch_logs_text_codec() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	s := new_cloudwatch_logs({
		'group_name':     '/test/logs'
		'stream_name':    'stream-1'
		'encoding.codec': 'text'
	})!
	assert s.codec == .text_codec
}

fn test_new_cloudwatch_logs_explicit_credentials() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer { os.unsetenv('AWS_SHARED_CREDENTIALS_FILE') }

	s := new_cloudwatch_logs({
		'group_name':             '/test/logs'
		'stream_name':            'stream-1'
		'region':                 'us-west-2'
		'auth.access_key_id':     'AKIAEXPLICIT'
		'auth.secret_access_key': 'explicitsecret'
		'auth.session_token':     'mytoken'
	})!
	assert s.creds.access_key_id == 'AKIAEXPLICIT'
	assert s.creds.secret_access_key == 'explicitsecret'
	assert s.creds.session_token == 'mytoken'
}

fn test_new_cloudwatch_logs_missing_group_name() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	new_cloudwatch_logs({
		'stream_name': 'stream-1'
	}) or {
		assert err.msg().contains('group_name')
		return
	}
	assert false, 'expected error for missing group_name'
}

fn test_new_cloudwatch_logs_missing_stream_name() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	new_cloudwatch_logs({
		'group_name': '/test/logs'
	}) or {
		assert err.msg().contains('stream_name')
		return
	}
	assert false, 'expected error for missing stream_name'
}

fn test_cloudwatch_logs_batch_max_clamped() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	s := new_cloudwatch_logs({
		'group_name':       '/test/logs'
		'stream_name':      'stream-1'
		'batch.max_events': '50000'
	})!
	assert s.batch_max == 10000 // AWS API limit
}

fn test_cloudwatch_logs_batch_max_invalid() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	s := new_cloudwatch_logs({
		'group_name':       '/test/logs'
		'stream_name':      'stream-1'
		'batch.max_events': '-5'
	})!
	assert s.batch_max == 100
}

fn test_cloudwatch_logs_disable_auto_create() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	s := new_cloudwatch_logs({
		'group_name':            '/test/logs'
		'stream_name':           'stream-1'
		'create_missing_group':  'false'
		'create_missing_stream': 'false'
	})!
	assert s.create_missing_group == false
	assert s.create_missing_stream == false
}

fn test_cloudwatch_logs_buffering() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	mut s := new_cloudwatch_logs({
		'group_name':       '/test/logs'
		'stream_name':      'stream-1'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('test message'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
}

fn test_cloudwatch_logs_multiple_events() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	mut s := new_cloudwatch_logs({
		'group_name':       '/test/logs'
		'stream_name':      'stream-1'
		'batch.max_events': '1000'
	})!

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_cloudwatch_logs_json_codec_format() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	mut s := new_cloudwatch_logs({
		'group_name':       '/test/logs'
		'stream_name':      'stream-1'
		'encoding.codec':   'json'
		'batch.max_events': '1000'
	})!

	mut log := event.new_log('hello world')
	log.set('level', event.Value('info'))
	ev := event.Event(log)
	s.send(ev) or {}
	assert s.buffer.len == 1
	assert s.buffer[0].message.contains('"message"')
	assert s.buffer[0].message.contains('hello world')
}

fn test_cloudwatch_logs_text_codec_format() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	mut s := new_cloudwatch_logs({
		'group_name':       '/test/logs'
		'stream_name':      'stream-1'
		'encoding.codec':   'text'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('plain text message'))
	s.send(ev) or {}
	assert s.buffer.len == 1
	assert s.buffer[0].message == 'plain text message'
}

fn test_cloudwatch_logs_payload_structure() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	mut s := new_cloudwatch_logs({
		'group_name':       '/app/logs'
		'stream_name':      'host-1'
		'encoding.codec':   'text'
		'batch.max_events': '1000'
	})!

	s.buffer << CwlLogEntry{
		timestamp_ms: 1710000000000
		message: 'test message'
	}
	s.buffer << CwlLogEntry{
		timestamp_ms: 1710000001000
		message: 'second message'
	}

	payload := s.build_put_log_events_payload()
	assert payload.contains('"logGroupName":"/app/logs"')
	assert payload.contains('"logStreamName":"host-1"')
	assert payload.contains('"logEvents":[')
	assert payload.contains('"timestamp":1710000000000')
	assert payload.contains('"timestamp":1710000001000')
	assert payload.contains('"message":"test message"')
	assert payload.contains('"message":"second message"')
}

fn test_cloudwatch_logs_payload_json_escaping() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	mut s := new_cloudwatch_logs({
		'group_name':       '/app/logs'
		'stream_name':      'host-1'
		'encoding.codec':   'text'
		'batch.max_events': '1000'
	})!

	s.buffer << CwlLogEntry{
		timestamp_ms: 1710000000000
		message: 'line with "quotes" and \\ backslash'
	}

	payload := s.build_put_log_events_payload()
	// Should be properly JSON-escaped
	assert payload.contains('\\"quotes\\"')
	assert payload.contains('\\\\')
}

fn test_cloudwatch_logs_metric_events_ignored() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	mut s := new_cloudwatch_logs({
		'group_name':       '/test/logs'
		'stream_name':      'stream-1'
		'batch.max_events': '1000'
	})!

	metric := event.Event(event.Metric{
		name: 'cpu.usage'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{ value: 42.0 })
	})
	s.send(metric) or {}
	assert s.total_buffered() == 0
}

fn test_cloudwatch_logs_timestamp_is_positive() {
	setup_test_aws_env()
	defer { cleanup_test_aws_env() }

	mut s := new_cloudwatch_logs({
		'group_name':       '/test/logs'
		'stream_name':      'stream-1'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('timestamp test'))
	s.send(ev) or {}
	assert s.buffer.len == 1
	assert s.buffer[0].timestamp_ms > 0
}
