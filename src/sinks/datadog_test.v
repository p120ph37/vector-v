module sinks

import event

fn test_new_datadog_defaults() {
	s := new_datadog({
		'api_key': 'my-api-key'
	}) or { panic(err.str()) }
	assert s.api_key == 'my-api-key'
	assert s.endpoint == 'https://http-intake.logs.datadoghq.com'
	assert s.codec == .json_codec
	assert s.batch_max == 100
}

fn test_new_datadog_missing_api_key() {
	new_datadog(map[string]string{}) or {
		assert err.msg().contains('api_key is required')
		return
	}
	assert false, 'expected error for missing api_key'
}

fn test_new_datadog_custom() {
	s := new_datadog({
		'api_key':           'custom-key'
		'site':              'datadoghq.eu'
		'endpoint':          'https://custom.intake.example.com/'
		'encoding.codec':    'text'
		'batch.max_events':  '200'
		'batch.timeout_secs': '10'
	}) or { panic(err.str()) }
	assert s.api_key == 'custom-key'
	assert s.endpoint == 'https://custom.intake.example.com'
	assert s.codec == .text_codec
	assert s.batch_max == 200
}

fn test_datadog_send_buffers() {
	mut s := new_datadog({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	for i in 0 .. 4 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 4
}

fn test_datadog_total_buffered() {
	mut s := new_datadog({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	s.send(ev) or {}
	assert s.total_buffered() == 2
}

fn test_datadog_flush_empty() {
	mut s := new_datadog({
		'api_key': 'key'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_datadog_text_codec() {
	mut s := new_datadog({
		'api_key':          'key'
		'encoding.codec':   'text'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('plain text message'))
	s.send(ev) or {}
	assert s.total_buffered() == 1

	// The encoded event should contain the message as text
	encoded := s.encode_event(event.Event(event.new_log('hello world')))
	assert encoded.contains('message')
	assert encoded.contains('ddsource')
}

fn test_datadog_registry() {
	sink := build_sink('datadog', {
		'api_key': 'test-key'
	}) or { panic(err.str()) }
	match sink {
		DatadogSink {
			assert sink.api_key == 'test-key'
			assert sink.endpoint == 'https://http-intake.logs.datadoghq.com'
		}
		else {
			assert false, 'expected DatadogSink'
		}
	}
}
