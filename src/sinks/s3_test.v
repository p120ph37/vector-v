module sinks

import event
import os

fn test_new_s3_defaults() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_REGION', 'us-east-1', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_REGION')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_s3({
		'bucket': 'my-bucket'
	})!
	assert s.bucket == 'my-bucket'
	assert s.key_prefix == 'date=%Y-%m-%d/'
	assert s.region == 'us-east-1'
	assert s.codec == .ndjson_codec
	assert s.batch_max == 1000
	assert s.content_type == 'application/x-ndjson'
}

fn test_new_s3_missing_bucket() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	new_s3(map[string]string{}) or {
		assert err.msg().contains('bucket is required')
		return
	}
	assert false, 'expected error for missing bucket'
}

fn test_new_s3_custom_config() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_s3({
		'bucket':          'custom-bucket'
		'key_prefix':      'logs/%Y/%m/'
		'region':          'eu-west-1'
		'encoding.codec':  'json'
		'batch.max_events': '500'
		'content_type':    'application/json'
	})!
	assert s.bucket == 'custom-bucket'
	assert s.key_prefix == 'logs/%Y/%m/'
	assert s.region == 'eu-west-1'
	assert s.codec == .json_codec
	assert s.batch_max == 500
	assert s.content_type == 'application/json'
}

fn test_new_s3_custom_endpoint() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_s3({
		'bucket':   'test'
		'endpoint': 'http://localhost:9000'
	})!
	assert s.endpoint == 'http://localhost:9000'
}

fn test_new_s3_explicit_credentials() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer { os.unsetenv('AWS_SHARED_CREDENTIALS_FILE') }

	s := new_s3({
		'bucket':                 'test'
		'region':                 'us-west-2'
		'auth.access_key_id':     'AKIAEXPLICIT'
		'auth.secret_access_key': 'explicitsecret'
	})!
	assert s.creds.access_key_id == 'AKIAEXPLICIT'
	assert s.creds.secret_access_key == 'explicitsecret'
}

fn test_s3_buffering() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_s3({
		'bucket':          'test'
		'batch.max_events': '10000'
	})!

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_s3_build_payload_ndjson() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_s3({
		'bucket':          'test'
		'batch.max_events': '10000'
	})!

	ev1 := event.Event(event.new_log('line1'))
	ev2 := event.Event(event.new_log('line2'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	payload := s.build_payload()
	lines := payload.trim_right('\n').split('\n')
	assert lines.len == 2
	assert lines[0].contains('line1')
	assert lines[1].contains('line2')
}

fn test_s3_build_payload_json() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_s3({
		'bucket':          'test'
		'encoding.codec':  'json'
		'batch.max_events': '10000'
	})!

	ev := event.Event(event.new_log('json test'))
	s.send(ev) or {}

	payload := s.build_payload()
	assert payload.starts_with('[')
	assert payload.ends_with(']')
}

fn test_s3_build_payload_text() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_s3({
		'bucket':          'test'
		'encoding.codec':  'text'
		'batch.max_events': '10000'
	})!

	ev1 := event.Event(event.new_log('hello'))
	ev2 := event.Event(event.new_log('world'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	payload := s.build_payload()
	assert payload == 'hello\nworld'
}

fn test_s3_generate_key() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_s3({
		'bucket':     'test'
		'key_prefix': 'logs/'
	})!

	key := s.generate_key()
	assert key.starts_with('logs/')
	assert key.ends_with('.log')
	assert s.seq == 1

	key2 := s.generate_key()
	assert key2 != key // sequence counter should differ
	assert s.seq == 2
}

fn test_s3_text_codec_content_type() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_s3({
		'bucket':         'test'
		'encoding.codec': 'text'
	})!
	assert s.content_type == 'text/plain'
}

fn test_s3_flush_empty() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_s3({
		'bucket': 'test'
	})!
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_s3_encode_metric() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_s3({
		'bucket': 'test'
	})!
	metric := event.Event(event.Metric{
		name: 'test.counter'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{ value: 1.0 })
	})
	result := s.encode_event(metric)
	assert result.contains('test.counter')
}

fn test_s3_encode_trace() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_s3({
		'bucket': 'test'
	})!
	trace := event.Event(event.TraceEvent{})
	result := s.encode_event(trace)
	assert result.len > 0
}

fn test_s3_encode_text() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_s3({
		'bucket':         'test'
		'encoding.codec': 'text'
	})!
	ev := event.Event(event.new_log('plain text'))
	result := s.encode_event(ev)
	assert result == 'plain text'
}

fn test_s3_invalid_batch_timeout() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_s3({
		'bucket':             'test'
		'batch.timeout_secs': '-10'
	})!
	assert s.batch_timeout > 0
}

fn test_s3_invalid_batch_max() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_s3({
		'bucket':          'test'
		'batch.max_events': '-1'
	})!
	assert s.batch_max == 1000
}

fn test_s3_json_content_type() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_s3({
		'bucket':         'test'
		'encoding.codec': 'json'
	})!
	assert s.content_type == 'application/json'
}
