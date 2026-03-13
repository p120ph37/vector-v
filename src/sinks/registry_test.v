module sinks

import event

fn test_build_sink_console() {
	s := build_sink('console', map[string]string{}) or { panic(err) }
	assert s is ConsoleSink
}

fn test_build_sink_blackhole() {
	s := build_sink('blackhole', map[string]string{}) or { panic(err) }
	assert s is BlackholeSink
}

fn test_build_sink_loki() {
	s := build_sink('loki', {
		'endpoint': 'http://localhost:3100'
	}) or { panic(err) }
	assert s is LokiSink
}

fn test_build_sink_opentelemetry() {
	s := build_sink('opentelemetry', {
		'endpoint': 'http://localhost:4318'
	}) or { panic(err) }
	assert s is OpenTelemetrySink
}

fn test_build_sink_unknown_errors() {
	if _ := build_sink('nonexistent', map[string]string{}) {
		assert false, 'expected error for unknown sink type'
	}
}

fn test_send_to_sink_console() {
	s := build_sink('console', {
		'target': 'stderr'
	}) or { panic(err) }
	ev := event.Event(event.new_log('test'))
	// ConsoleSink.send writes to stdout/stderr, which is fine in tests
	send_to_sink(s, ev) or {}
}

fn test_send_to_sink_blackhole() {
	s := build_sink('blackhole', map[string]string{}) or { panic(err) }
	ev := event.Event(event.new_log('test'))
	send_to_sink(s, ev) or { panic(err) }
}
