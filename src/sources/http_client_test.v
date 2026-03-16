module sources

fn test_new_http_client_defaults() {
	s := new_http_client({
		'endpoint': 'http://localhost:8080/metrics'
	})!
	assert s.endpoint == 'http://localhost:8080/metrics'
	assert s.method == .get
	assert s.codec == .bytes_codec
	assert s.max_length == 1048576
}

fn test_new_http_client_missing_endpoint() {
	new_http_client(map[string]string{}) or {
		assert err.msg().contains('endpoint is required')
		return
	}
	assert false, 'expected error for missing endpoint'
}

fn test_new_http_client_post_method() {
	s := new_http_client({
		'endpoint': 'http://localhost:8080'
		'method':   'POST'
	})!
	assert s.method == .post
}

fn test_new_http_client_put_method() {
	s := new_http_client({
		'endpoint': 'http://localhost:8080'
		'method':   'PUT'
	})!
	assert s.method == .put
}

fn test_new_http_client_json_codec() {
	s := new_http_client({
		'endpoint':       'http://localhost:8080'
		'decoding.codec': 'json'
	})!
	assert s.codec == .json_codec
}

fn test_new_http_client_custom_interval() {
	s := new_http_client({
		'endpoint':             'http://localhost:8080'
		'scrape_interval_secs': '30'
	})!
	assert s.scrape_interval > 0
}

fn test_new_http_client_custom_headers() {
	s := new_http_client({
		'endpoint':          'http://localhost:8080'
		'headers.X-Api-Key': 'secret'
		'headers.Accept':    'application/json'
	})!
	assert s.headers['X-Api-Key'] == 'secret'
	assert s.headers['Accept'] == 'application/json'
}

fn test_new_http_client_bearer_auth() {
	s := new_http_client({
		'endpoint':   'http://localhost:8080'
		'auth.token': 'my-bearer-token'
	})!
	assert s.auth_header == 'Bearer my-bearer-token'
}

fn test_new_http_client_basic_auth() {
	s := new_http_client({
		'endpoint':      'http://localhost:8080'
		'auth.user':     'admin'
		'auth.password': 'secret'
	})!
	assert s.auth_header.starts_with('Basic ')
}

fn test_new_http_client_max_length() {
	s := new_http_client({
		'endpoint':   'http://localhost:8080'
		'max_length': '4096'
	})!
	assert s.max_length == 4096
}

fn test_http_client_sources_base64() {
	assert sources_base64('') == ''
	assert sources_base64('f') == 'Zg=='
	assert sources_base64('fo') == 'Zm8='
	assert sources_base64('foo') == 'Zm9v'
	assert sources_base64('foobar') == 'Zm9vYmFy'
}

fn test_new_http_client_invalid_interval() {
	s := new_http_client({
		'endpoint':             'http://localhost:8080'
		'scrape_interval_secs': '-5'
	})!
	// Should fall back to default
	assert s.scrape_interval > 0
}
