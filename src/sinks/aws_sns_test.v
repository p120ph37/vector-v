module sinks

import event
import mockserver
import os

// ---------------------------------------------------------------------------
// SnsSink tests
// ---------------------------------------------------------------------------

fn test_new_sns_sink_defaults() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_REGION', 'us-east-1', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_REGION')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_sns({
		'topic_arn': 'arn:aws:sns:us-east-1:123456789:my-topic'
	}) or { panic(err.str()) }
	assert s.topic_arn == 'arn:aws:sns:us-east-1:123456789:my-topic'
	assert s.batch_max == 10
	assert s.codec == .json_codec
	assert s.region == 'us-east-1'
	assert s.endpoint == 'https://sns.us-east-1.amazonaws.com'
	assert s.message_group_id == ''
	assert s.subject == ''
}

fn test_new_sns_sink_missing_topic_arn() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	new_sns(map[string]string{}) or {
		assert err.msg().contains('topic_arn is required')
		return
	}
	assert false, 'expected error for missing topic_arn'
}

fn test_new_sns_sink_empty_topic_arn() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	new_sns({
		'topic_arn': ''
	}) or {
		assert err.msg().contains('topic_arn is required')
		return
	}
	assert false, 'expected error for empty topic_arn'
}

fn test_new_sns_sink_custom_config() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_sns({
		'topic_arn':          'arn:aws:sns:eu-west-1:123:my-topic'
		'region':             'eu-west-1'
		'endpoint':           'http://localhost:4566'
		'encoding.codec':     'text'
		'batch.max_events':   '5'
		'message_group_id':   'group-a'
		'subject':            'Alert'
		'batch.timeout_secs': '10'
	}) or { panic(err.str()) }
	assert s.topic_arn == 'arn:aws:sns:eu-west-1:123:my-topic'
	assert s.region == 'eu-west-1'
	assert s.endpoint == 'http://localhost:4566'
	assert s.codec == .text_codec
	assert s.batch_max == 5
	assert s.message_group_id == 'group-a'
	assert s.subject == 'Alert'
}

fn test_sns_sink_send_buffers() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sns({
		'topic_arn':          'arn:aws:sns:us-east-1:123:test'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('hello sns'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1

	ev2 := event.Event(event.new_log('second message'))
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 2
}

fn test_sns_sink_total_buffered() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sns({
		'topic_arn':          'arn:aws:sns:us-east-1:123:test'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	for i in 0 .. 5 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or { panic(err.str()) }
	}
	assert s.total_buffered() == 5
}

fn test_sns_sink_flush_empty() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sns({
		'topic_arn': 'arn:aws:sns:us-east-1:123:test'
	}) or { panic(err.str()) }

	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_sns_sink_drops_non_log() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sns({
		'topic_arn':          'arn:aws:sns:us-east-1:123:test'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	metric := event.Event(event.Metric{
		name: 'test.gauge'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 42.0})
	})
	s.send(metric) or { panic(err.str()) }
	assert s.total_buffered() == 0
}

fn test_sns_sink_build_publish_payload() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_sns({
		'topic_arn': 'arn:aws:sns:us-east-1:123:my-topic'
	}) or { panic(err.str()) }

	payload := s.build_publish_payload('hello world')
	assert payload.contains('"TopicArn"')
	assert payload.contains('my-topic')
	assert payload.contains('"Message"')
	assert payload.contains('hello world')
	// No Subject or MessageGroupId by default
	assert !payload.contains('"Subject"')
	assert !payload.contains('"MessageGroupId"')
}

fn test_sns_sink_build_publish_payload_with_subject() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_sns({
		'topic_arn': 'arn:aws:sns:us-east-1:123:my-topic'
		'subject':   'Alert Notification'
	}) or { panic(err.str()) }

	payload := s.build_publish_payload('alert body')
	assert payload.contains('"Subject"')
	assert payload.contains('Alert Notification')
}

fn test_sns_sink_build_publish_payload_with_group_id() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_sns({
		'topic_arn':        'arn:aws:sns:us-east-1:123:my-topic.fifo'
		'message_group_id': 'group-1'
	}) or { panic(err.str()) }

	payload := s.build_publish_payload('fifo message')
	assert payload.contains('"MessageGroupId"')
	assert payload.contains('"group-1"')
}

fn test_sns_sink_text_codec() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sns({
		'topic_arn':          'arn:aws:sns:us-east-1:123:test'
		'encoding.codec':     'text'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('plain text sns'))
	s.send(ev) or { panic(err.str()) }

	assert s.buffer.len == 1
	assert s.buffer[0] == 'plain text sns'
}

fn test_sns_sink_negative_batch_max() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_sns({
		'topic_arn':        'arn:aws:sns:us-east-1:123:test'
		'batch.max_events': '-1'
	}) or { panic(err.str()) }
	assert s.batch_max == 10
}

fn test_sns_sink_explicit_credentials() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer { os.unsetenv('AWS_SHARED_CREDENTIALS_FILE') }

	s := new_sns({
		'topic_arn':              'arn:aws:sns:us-west-2:123:test'
		'region':                 'us-west-2'
		'auth.access_key_id':     'AKIAEXPLICIT'
		'auth.secret_access_key': 'explicitsecret'
	}) or { panic(err.str()) }
	assert s.creds.access_key_id == 'AKIAEXPLICIT'
	assert s.creds.secret_access_key == 'explicitsecret'
	assert s.region == 'us-west-2'
}

// ---------------------------------------------------------------------------
// Mock server integration tests
// ---------------------------------------------------------------------------

fn test_sns_flush_to_mock_server() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, '{"MessageId":"12345"}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_sns({
		'topic_arn':          'arn:aws:sns:us-east-1:123:mock-topic'
		'endpoint':           mock.url()
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev1 := event.Event(event.new_log('sns-flush-1'))
	ev2 := event.Event(event.new_log('sns-flush-2'))
	s.send(ev1) or { panic(err.str()) }
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 2

	s.flush() or { panic(err.str()) }
	assert s.total_buffered() == 0

	// Each message is published individually, so 2 requests
	reqs := mock.wait_for_requests(2, 5000)
	assert reqs.len >= 2
	assert reqs[0].method == 'POST'
	assert reqs[0].body.contains('"TopicArn"')
	assert reqs[0].body.contains('"Message"')
}

fn test_sns_flush_error_handling() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(500, '{"message":"Internal Server Error"}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_sns({
		'topic_arn':          'arn:aws:sns:us-east-1:123:error-topic'
		'endpoint':           mock.url()
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('will-fail'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1

	s.flush() or {
		// Expected: flush fails
		assert s.total_buffered() == 1
		return
	}
	assert s.total_buffered() == 0
}
