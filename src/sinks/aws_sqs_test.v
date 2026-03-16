module sinks

import event
import mockserver
import os

// ---------------------------------------------------------------------------
// SqsSink tests
// ---------------------------------------------------------------------------

fn test_new_sqs_sink_defaults() {
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

	s := new_sqs({
		'queue_url': 'https://sqs.us-east-1.amazonaws.com/123456789/test-queue'
	}) or { panic(err.str()) }
	assert s.batch_max == 10
	assert s.queue_url == 'https://sqs.us-east-1.amazonaws.com/123456789/test-queue'
	assert s.codec == .json_codec
	assert s.region == 'us-east-1'
	assert s.endpoint == 'https://sqs.us-east-1.amazonaws.com'
	assert s.message_group_id == ''
}

fn test_new_sqs_sink_missing_queue_url() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	new_sqs(map[string]string{}) or {
		assert err.msg().contains('queue_url is required')
		return
	}
	assert false, 'expected error for missing queue_url'
}

fn test_new_sqs_sink_custom_config() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_sqs({
		'queue_url':          'https://sqs.eu-west-1.amazonaws.com/123/my-queue'
		'region':             'eu-west-1'
		'endpoint':           'http://localhost:4566'
		'encoding.codec':     'text'
		'batch.max_events':   '5'
		'message_group_id':   'group-a'
		'batch.timeout_secs': '10'
	}) or { panic(err.str()) }
	assert s.queue_url == 'https://sqs.eu-west-1.amazonaws.com/123/my-queue'
	assert s.region == 'eu-west-1'
	assert s.endpoint == 'http://localhost:4566'
	assert s.codec == .text_codec
	assert s.batch_max == 5
	assert s.message_group_id == 'group-a'
}

fn test_sqs_sink_batch_limit() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	// Request batch_max > 10, should be capped to 10
	s := new_sqs({
		'queue_url':        'https://sqs.us-east-1.amazonaws.com/123/q'
		'batch.max_events': '50'
	}) or { panic(err.str()) }
	assert s.batch_max == 10

	// Request batch_max <= 0, should default to 10
	s2 := new_sqs({
		'queue_url':        'https://sqs.us-east-1.amazonaws.com/123/q'
		'batch.max_events': '-1'
	}) or { panic(err.str()) }
	assert s2.batch_max == 10

	// Request batch_max = 0, should default to 10
	s3 := new_sqs({
		'queue_url':        'https://sqs.us-east-1.amazonaws.com/123/q'
		'batch.max_events': '0'
	}) or { panic(err.str()) }
	assert s3.batch_max == 10
}

fn test_sqs_sink_send_buffers() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('hello sqs'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1

	ev2 := event.Event(event.new_log('second message'))
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 2
}

fn test_sqs_sink_build_payload() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/my-queue'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('payload test'))
	s.send(ev) or { panic(err.str()) }

	payload := s.build_send_message_batch_payload()
	assert payload.contains('"QueueUrl"')
	assert payload.contains('my-queue')
	assert payload.contains('"Entries"')
	assert payload.contains('"Id"')
	assert payload.contains('"MessageBody"')
	// No MessageGroupId for non-FIFO queue
	assert !payload.contains('"MessageGroupId"')
}

fn test_sqs_sink_message_group_id() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/my-queue.fifo'
		'message_group_id':   'my-group'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('fifo message'))
	s.send(ev) or { panic(err.str()) }

	payload := s.build_send_message_batch_payload()
	assert payload.contains('"MessageGroupId"')
	assert payload.contains('"my-group"')
}

fn test_sqs_sink_total_buffered() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	for i in 0 .. 7 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or { panic(err.str()) }
	}
	assert s.total_buffered() == 7
}

fn test_sqs_sink_flush_empty() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sqs({
		'queue_url': 'https://sqs.us-east-1.amazonaws.com/123/q'
	}) or { panic(err.str()) }

	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_sqs_sink_text_codec() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'encoding.codec':     'text'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('plain text sqs'))
	s.send(ev) or { panic(err.str()) }

	assert s.buffer.len == 1
	// Text codec stores the message text directly (not JSON)
	assert s.buffer[0] == 'plain text sqs'
}

fn test_sqs_sink_drops_non_log() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	// Send a metric event -- should be silently dropped
	metric := event.Event(event.Metric{
		name: 'test.gauge'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 42.0})
	})
	s.send(metric) or { panic(err.str()) }
	assert s.total_buffered() == 0
}

fn test_sqs_sink_registry() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := build_sink('aws_sqs', {
		'queue_url': 'https://sqs.us-east-1.amazonaws.com/123/registry-test'
	}) or { panic(err.str()) }
	assert s is SqsSink
}

fn test_sqs_sink_explicit_credentials() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer { os.unsetenv('AWS_SHARED_CREDENTIALS_FILE') }

	s := new_sqs({
		'queue_url':              'https://sqs.us-west-2.amazonaws.com/123/q'
		'region':                 'us-west-2'
		'auth.access_key_id':     'AKIAEXPLICIT'
		'auth.secret_access_key': 'explicitsecret'
	}) or { panic(err.str()) }
	assert s.creds.access_key_id == 'AKIAEXPLICIT'
	assert s.creds.secret_access_key == 'explicitsecret'
	assert s.region == 'us-west-2'
}

fn test_sqs_sink_invalid_batch_timeout() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'batch.timeout_secs': '-10'
	}) or { panic(err.str()) }
	assert s.batch_timeout > 0
}

fn test_sqs_sink_build_payload_multiple_entries() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('entry ${i}'))
		s.send(ev) or { panic(err.str()) }
	}

	payload := s.build_send_message_batch_payload()
	// Should have 3 entries with unique IDs
	assert payload.contains('"Entries"')
	mut count := 0
	mut idx := 0
	for {
		pos := payload.index_after('"Id"', idx) or { break }
		count++
		idx = pos + 4
	}
	assert count == 3
}

fn test_sqs_sink_json_codec_format() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'encoding.codec':     'json'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('json sqs test'))
	s.send(ev) or { panic(err.str()) }

	assert s.buffer.len == 1
	// JSON codec should produce JSON containing the message
	assert s.buffer[0].contains('json sqs test')
	assert s.buffer[0].contains('{')
}

// ---------------------------------------------------------------------------
// Mock server integration tests — cover flush/send_message_batch
// ---------------------------------------------------------------------------

fn test_sqs_flush_to_mock_server() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, '{"Successful":[],"Failed":[]}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/mock-queue'
		'endpoint':           mock.url()
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev1 := event.Event(event.new_log('sqs-flush-1'))
	ev2 := event.Event(event.new_log('sqs-flush-2'))
	s.send(ev1) or { panic(err.str()) }
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 2

	s.flush() or { panic(err.str()) }
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].body.contains('"QueueUrl"')
	assert reqs[0].body.contains('"Entries"')
	assert reqs[0].body.contains('"MessageBody"')
}

fn test_sqs_flush_error_handling() {
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

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/error-queue'
		'endpoint':           mock.url()
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('will-fail'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1

	s.flush() or {
		// Expected: flush fails, buffer is NOT cleared
		assert s.total_buffered() == 1
		return
	}
	// If flush succeeded despite 500, buffer should be cleared
	assert s.total_buffered() == 0
}

fn test_sqs_flush_with_message_group_id_via_mock() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, '{"Successful":[],"Failed":[]}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/fifo-queue.fifo'
		'endpoint':           mock.url()
		'message_group_id':   'test-group'
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('fifo msg'))
	s.send(ev) or { panic(err.str()) }
	s.flush() or { panic(err.str()) }

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body.contains('"MessageGroupId"')
	assert reqs[0].body.contains('"test-group"')
}

fn test_sqs_msg_counter_increments() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, '{"Successful":[],"Failed":[]}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'endpoint':           mock.url()
		'batch.max_events':   '10'
		'batch.timeout_secs': '3600'
	}) or { panic(err.str()) }

	// Send and flush two batches to verify msg_counter increments across batches
	for i in 0 .. 2 {
		ev := event.Event(event.new_log('batch1-${i}'))
		s.send(ev) or { panic(err.str()) }
	}
	s.flush() or { panic(err.str()) }
	assert s.msg_counter == 2

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('batch2-${i}'))
		s.send(ev) or { panic(err.str()) }
	}
	s.flush() or { panic(err.str()) }
	assert s.msg_counter == 5
}
