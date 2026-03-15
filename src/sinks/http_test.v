module sinks

import event

fn test_new_http_defaults() {
	s := new_http({
		'endpoint': 'http://localhost:8080'
	})
	assert s.http.endpoint == 'http://localhost:8080'
	assert s.batch_max == 100
	assert s.codec == .json_codec
}

fn test_new_http_with_path() {
	s := new_http({
		'endpoint': 'http://localhost:8080'
		'path':     '/api/v1/events'
	})
	assert s.http.path == '/api/v1/events'
}

fn test_new_http_text_codec() {
	s := new_http({
		'endpoint':       'http://localhost:8080'
		'encoding.codec': 'text'
	})
	assert s.codec == .text_codec
}

fn test_new_http_ndjson_codec() {
	s := new_http({
		'endpoint':       'http://localhost:8080'
		'encoding.codec': 'ndjson'
	})
	assert s.codec == .ndjson_codec
}

fn test_new_http_custom_headers() {
	s := new_http({
		'endpoint':          'http://localhost:8080'
		'headers.X-Api-Key': 'secret123'
		'headers.X-Source':  'vector'
	})
	assert s.custom_headers['X-Api-Key'] == 'secret123'
	assert s.custom_headers['X-Source'] == 'vector'
}

fn test_new_http_custom_batch() {
	s := new_http({
		'endpoint':         'http://localhost:8080'
		'batch.max_events': '50'
	})
	assert s.batch_max == 50
}

fn test_new_http_method() {
	s := new_http({
		'endpoint': 'http://localhost:8080'
		'method':   'PUT'
	})
	assert s.http.method == .put
}

fn test_new_http_payload_prefix_suffix() {
	s := new_http({
		'endpoint':       'http://localhost:8080'
		'payload_prefix': '{"data":'
		'payload_suffix': '}'
	})
	assert s.payload_prefix == '{"data":'
	assert s.payload_suffix == '}'
}

fn test_http_buffering() {
	mut s := new_http({
		'endpoint':         'http://localhost:8080'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('test message'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
}

fn test_http_multiple_events() {
	mut s := new_http({
		'endpoint':         'http://localhost:8080'
		'batch.max_events': '1000'
	})

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_http_build_payload_json() {
	mut s := new_http({
		'endpoint':         'http://localhost:8080'
		'encoding.codec':   'json'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}

	payload := s.build_payload()
	assert payload.starts_with('[')
	assert payload.ends_with(']')
	assert payload.contains('"message"')
}

fn test_http_build_payload_ndjson() {
	mut s := new_http({
		'endpoint':         'http://localhost:8080'
		'encoding.codec':   'ndjson'
		'batch.max_events': '1000'
	})

	ev1 := event.Event(event.new_log('line1'))
	ev2 := event.Event(event.new_log('line2'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	payload := s.build_payload()
	// ndjson: each JSON on its own line, trailing newline
	lines := payload.trim_right('\n').split('\n')
	assert lines.len == 2
	assert lines[0].contains('line1')
	assert lines[1].contains('line2')
}

fn test_http_build_payload_text() {
	mut s := new_http({
		'endpoint':         'http://localhost:8080'
		'encoding.codec':   'text'
		'batch.max_events': '1000'
	})

	ev1 := event.Event(event.new_log('hello'))
	ev2 := event.Event(event.new_log('world'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	payload := s.build_payload()
	assert payload == 'hello\nworld'
}

fn test_http_build_payload_with_prefix_suffix() {
	mut s := new_http({
		'endpoint':         'http://localhost:8080'
		'encoding.codec':   'json'
		'payload_prefix':   '{"data":'
		'payload_suffix':   '}'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}

	payload := s.build_payload()
	assert payload.starts_with('{"data":')
	assert payload.ends_with('}')
}

fn test_http_auth_basic() {
	s := new_http({
		'endpoint':      'http://localhost:8080'
		'auth.user':     'admin'
		'auth.password': 'secret'
	})
	assert s.http.auth_header.starts_with('Basic ')
}

fn test_http_auth_bearer() {
	s := new_http({
		'endpoint':   'http://localhost:8080'
		'auth.token': 'my-token'
	})
	assert s.http.auth_header == 'Bearer my-token'
}

fn test_http_metric_events() {
	mut s := new_http({
		'endpoint':         'http://localhost:8080'
		'batch.max_events': '1000'
	})

	metric := event.Event(event.Metric{
		name: 'cpu.usage'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{ value: 42.0 })
	})
	s.send(metric) or {}
	assert s.total_buffered() == 1
}

fn test_parse_http_method_cases() {
	assert parse_http_method('GET') == .get
	assert parse_http_method('get') == .get
	assert parse_http_method('PUT') == .put
	assert parse_http_method('PATCH') == .patch
	assert parse_http_method('DELETE') == .delete
	assert parse_http_method('POST') == .post
	assert parse_http_method('unknown') == .post
}
