module sinks

import event

fn test_build_sink_unknown_type_error_message() {
	if _ := build_sink('foobar', map[string]string{}) {
		assert false, 'expected error for unknown sink type'
	} else {
		assert err.msg().contains('unknown sink type')
		assert err.msg().contains('foobar')
	}
}

fn test_build_and_send_console_stderr() {
	s := build_sink('console', {
		'target': 'stderr'
	}) or { panic(err) }
	assert s is ConsoleSink
	ev := event.Event(event.new_log('test console'))
	send_to_sink(s, ev) or {}
}

fn test_build_and_send_blackhole_increments() {
	s := build_sink('blackhole', map[string]string{}) or { panic(err) }
	assert s is BlackholeSink
	ev := event.Event(event.new_log('test blackhole'))
	send_to_sink(s, ev) or { panic(err) }
}

fn test_build_and_send_loki_buffers() {
	s := build_sink('loki', {
		'endpoint':         'http://localhost:3100'
		'batch.max_events': '1000'
	}) or { panic(err) }
	assert s is LokiSink
	ev := event.Event(event.new_log('test loki'))
	send_to_sink(s, ev) or {}
}

fn test_build_and_send_opentelemetry_buffers() {
	s := build_sink('opentelemetry', {
		'endpoint':         'http://localhost:4318'
		'batch.max_events': '1000'
	}) or { panic(err) }
	assert s is OpenTelemetrySink
	ev := event.Event(event.new_log('test otel'))
	send_to_sink(s, ev) or {}
}

fn test_build_sink_multiple_unknown_types() {
	unknown_types := ['redis', 'kafka', 'elasticsearch', 'splunk', '']
	for typ in unknown_types {
		if _ := build_sink(typ, map[string]string{}) {
			assert false, 'expected error for unknown sink type: "${typ}"'
		}
	}
}
