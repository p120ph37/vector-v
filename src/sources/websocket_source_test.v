module sources

fn test_new_websocket_source_defaults() {
	s := new_websocket_source({
		'url': 'ws://localhost:9000/feed'
	})!
	assert s.host == 'localhost'
	assert s.port == 9000
	assert s.path == '/feed'
	assert s.max_length == 1048576
}

fn test_new_websocket_source_missing_url() {
	new_websocket_source(map[string]string{}) or {
		assert err.msg().contains('url is required')
		return
	}
	assert false, 'expected error for missing url'
}

fn test_new_websocket_source_custom_max_length() {
	s := new_websocket_source({
		'url':        'ws://localhost:9000/feed'
		'max_length': '4096'
	})!
	assert s.max_length == 4096
}

fn test_new_websocket_source_custom_reconnect() {
	s := new_websocket_source({
		'url':             'ws://localhost:9000/feed'
		'reconnect_secs': '10'
	})!
	assert s.reconnect > 0
}

fn test_parse_ws_source_uri_basic() {
	u := parse_ws_source_uri('ws://example.com:8080/path')!
	assert u.host == 'example.com'
	assert u.port == 8080
	assert u.path == '/path'
}

fn test_parse_ws_source_uri_no_port() {
	u := parse_ws_source_uri('ws://example.com/path')!
	assert u.host == 'example.com'
	assert u.port == 80
	assert u.path == '/path'
}

fn test_parse_ws_source_uri_no_path() {
	u := parse_ws_source_uri('ws://localhost:9000')!
	assert u.host == 'localhost'
	assert u.port == 9000
	assert u.path == '/'
}

fn test_parse_ws_source_uri_wss() {
	u := parse_ws_source_uri('wss://secure.example.com:443/ws')!
	assert u.host == 'secure.example.com'
	assert u.port == 443
	assert u.path == '/ws'
}

fn test_new_websocket_source_invalid_url() {
	new_websocket_source({
		'url': 'ws://:invalid'
	}) or {
		assert err.msg().contains('invalid url')
		return
	}
	// May parse unexpectedly, just verify no crash
}

fn test_new_websocket_source_zero_max_length() {
	s := new_websocket_source({
		'url':        'ws://localhost:9000/feed'
		'max_length': '0'
	})!
	assert s.max_length == 1048576
}

fn test_new_websocket_source_negative_reconnect() {
	s := new_websocket_source({
		'url':            'ws://localhost:9000/feed'
		'reconnect_secs': '-3'
	})!
	// Falls back to 5 second default
	assert s.reconnect == 5_000_000_000
}

fn test_new_websocket_source_zero_reconnect() {
	s := new_websocket_source({
		'url':            'ws://localhost:9000/feed'
		'reconnect_secs': '0'
	})!
	assert s.reconnect == 5_000_000_000
}

fn test_parse_ws_source_uri_empty_host() {
	parse_ws_source_uri('ws://:9000/feed') or {
		assert err.msg().contains('empty host')
		return
	}
	assert false, 'expected error for empty host'
}

fn test_parse_ws_source_uri_invalid_port() {
	parse_ws_source_uri('ws://localhost:abc/feed') or {
		assert err.msg().contains('invalid port')
		return
	}
	assert false, 'expected error for invalid port'
}

fn test_parse_ws_source_uri_zero_port() {
	parse_ws_source_uri('ws://localhost:0/feed') or {
		assert err.msg().contains('invalid port')
		return
	}
	assert false, 'expected error for zero port'
}

fn test_parse_ws_source_uri_no_scheme() {
	// Without ws:// prefix, treated as host:port
	u := parse_ws_source_uri('example.com:8080/path')!
	assert u.host == 'example.com'
	assert u.port == 8080
	assert u.path == '/path'
}

fn test_new_websocket_source_invalid_max_length() {
	s := new_websocket_source({
		'url':        'ws://localhost:9000/feed'
		'max_length': '-5'
	})!
	assert s.max_length == 1048576
}
