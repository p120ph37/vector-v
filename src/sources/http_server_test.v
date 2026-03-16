module sources

fn test_new_http_server_defaults() {
	s := new_http_server({})
	assert s.address == '0.0.0.0:80'
	assert s.path == '/'
	assert s.encoding == .json_enc
	assert s.token == ''
}

fn test_new_http_server_custom_address() {
	s := new_http_server({
		'address': '127.0.0.1:8080'
	})
	assert s.address == '127.0.0.1:8080'
}

fn test_new_http_server_custom_path() {
	s := new_http_server({
		'path': '/events'
	})
	assert s.path == '/events'
}

fn test_new_http_server_encoding_text() {
	s := new_http_server({
		'encoding': 'text'
	})
	assert s.encoding == .text
}

fn test_new_http_server_encoding_ndjson() {
	s := new_http_server({
		'encoding': 'ndjson'
	})
	assert s.encoding == .ndjson
}

fn test_new_http_server_encoding_json() {
	s := new_http_server({
		'encoding': 'json'
	})
	assert s.encoding == .json_enc
}

fn test_new_http_server_encoding_invalid_defaults_json() {
	s := new_http_server({
		'encoding': 'invalid'
	})
	assert s.encoding == .json_enc
}

fn test_new_http_server_auth_token() {
	s := new_http_server({
		'auth.token': 'my-secret-token'
	})
	assert s.token == 'my-secret-token'
}

fn test_new_http_server_all_options() {
	s := new_http_server({
		'address':    '0.0.0.0:9090'
		'path':       '/v1/events'
		'encoding':   'ndjson'
		'auth.token': 'tok123'
	})
	assert s.address == '0.0.0.0:9090'
	assert s.path == '/v1/events'
	assert s.encoding == .ndjson
	assert s.token == 'tok123'
}

fn test_parse_http_server_body_json_array() {
	body := '["hello","world"]'
	events := parse_http_server_body(body, .json_enc)
	assert events.len == 2
	assert events[0].message() == 'hello'
	assert events[1].message() == 'world'
	assert events[0].meta.source_type == 'http_server'
}

fn test_parse_http_server_body_json_single() {
	body := '{"key":"value"}'
	events := parse_http_server_body(body, .json_enc)
	assert events.len == 1
	assert events[0].message() == '{"key":"value"}'
}

fn test_parse_http_server_body_json_empty() {
	body := ''
	events := parse_http_server_body(body, .json_enc)
	assert events.len == 0
}

fn test_parse_http_server_body_text() {
	body := 'line one\nline two\nline three'
	events := parse_http_server_body(body, .text)
	assert events.len == 3
	assert events[0].message() == 'line one'
	assert events[1].message() == 'line two'
	assert events[2].message() == 'line three'
}

fn test_parse_http_server_body_text_with_crlf() {
	body := 'line one\r\nline two\r\n'
	events := parse_http_server_body(body, .text)
	assert events.len == 2
	assert events[0].message() == 'line one'
	assert events[1].message() == 'line two'
}

fn test_parse_http_server_body_text_empty_lines() {
	body := 'line one\n\nline two\n'
	events := parse_http_server_body(body, .text)
	assert events.len == 2
}

fn test_parse_http_server_body_ndjson() {
	body := '{"a":1}\n{"b":2}\n{"c":3}'
	events := parse_http_server_body(body, .ndjson)
	assert events.len == 3
	assert events[0].message() == '{"a":1}'
	assert events[1].message() == '{"b":2}'
	assert events[2].message() == '{"c":3}'
}

fn test_parse_http_server_body_ndjson_empty_lines() {
	body := '{"a":1}\n\n{"b":2}\n'
	events := parse_http_server_body(body, .ndjson)
	assert events.len == 2
}

fn test_parse_http_server_body_text_source_type() {
	body := 'hello'
	events := parse_http_server_body(body, .text)
	assert events.len == 1
	assert events[0].meta.source_type == 'http_server'
}
