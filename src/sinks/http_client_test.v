module sinks

fn test_base64_encode_empty() {
	assert base64_encode('') == ''
}

fn test_base64_encode_simple() {
	assert base64_encode('f') == 'Zg=='
	assert base64_encode('fo') == 'Zm8='
	assert base64_encode('foo') == 'Zm9v'
	assert base64_encode('foob') == 'Zm9vYg=='
	assert base64_encode('fooba') == 'Zm9vYmE='
	assert base64_encode('foobar') == 'Zm9vYmFy'
}

fn test_new_http_batch_defaults() {
	b := new_http_batch({
		'endpoint': 'http://localhost:8080'
	})
	assert b.endpoint == 'http://localhost:8080'
	assert b.batch_size == 100
	assert b.timeout_ms == 10000
}

fn test_new_http_batch_with_auth() {
	b := new_http_batch({
		'endpoint':      'http://localhost:8080'
		'auth.user':     'admin'
		'auth.password': 'secret'
	})
	assert b.auth_header.starts_with('Basic ')
}

fn test_new_http_batch_with_bearer() {
	b := new_http_batch({
		'endpoint':   'http://localhost:8080'
		'auth.token': 'my-token'
	})
	assert b.auth_header == 'Bearer my-token'
}
