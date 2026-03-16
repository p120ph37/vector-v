module sources

fn test_new_nats_source_defaults() {
	s := new_nats_source({
		'subject': 'test.events'
	}) or { panic(err.str()) }
	assert s.url == 'nats://127.0.0.1:4222'
	assert s.subject == 'test.events'
	assert s.queue == ''
	assert s.connection_name == 'vector'
	assert s.auth_token == ''
	assert s.auth_user == ''
	assert s.auth_password == ''
	assert s.auth_nkey == ''
	assert s.credentials_file == ''
	assert s.jetstream == false
	assert s.jetstream_stream == ''
	assert s.subscriber_capacity == 4096
	assert s.subject_key_field == 'nats_subject'
	assert s.tls_enabled == false
	assert s.decoding_codec == 'bytes'
}

fn test_new_nats_source_missing_subject() {
	new_nats_source(map[string]string{}) or {
		assert err.msg().contains('subject is required')
		return
	}
	assert false, 'expected error for missing subject'
}

fn test_new_nats_source_custom() {
	s := new_nats_source({
		'url':                  'nats://nats.example.com:5222'
		'subject':              'logs.>'
		'queue':                'workers'
		'connection_name':      'my-vector'
		'auth.token':           'secret-token'
		'jetstream':            'true'
		'jetstream.stream':     'LOGS'
		'subscriber_capacity':  '8192'
		'subject_key_field':    'subject'
		'tls.enabled':          'true'
		'decoding.codec':       'json'
	}) or { panic(err.str()) }
	assert s.url == 'nats://nats.example.com:5222'
	assert s.subject == 'logs.>'
	assert s.queue == 'workers'
	assert s.connection_name == 'my-vector'
	assert s.auth_token == 'secret-token'
	assert s.jetstream == true
	assert s.jetstream_stream == 'LOGS'
	assert s.subscriber_capacity == 8192
	assert s.subject_key_field == 'subject'
	assert s.tls_enabled == true
	assert s.decoding_codec == 'json'
}

fn test_parse_nats_url() {
	// Standard URL with host and port
	host1, port1 := parse_nats_url('nats://myhost:4222') or { panic(err.str()) }
	assert host1 == 'myhost'
	assert port1 == 4222

	// Custom port
	host2, port2 := parse_nats_url('nats://nats.example.com:5222') or { panic(err.str()) }
	assert host2 == 'nats.example.com'
	assert port2 == 5222

	// Host only, default port
	host3, port3 := parse_nats_url('nats://myhost') or { panic(err.str()) }
	assert host3 == 'myhost'
	assert port3 == 4222

	// TLS scheme
	host4, port4 := parse_nats_url('tls://secure.nats.io:4222') or { panic(err.str()) }
	assert host4 == 'secure.nats.io'
	assert port4 == 4222

	// Default host and port
	host5, port5 := parse_nats_url('nats://') or { panic(err.str()) }
	assert host5 == '127.0.0.1'
	assert port5 == 4222
}

fn test_parse_nats_url_invalid() {
	// Invalid scheme
	parse_nats_url('http://myhost:4222') or {
		assert err.msg().contains('invalid NATS URL scheme')
		return
	}
	assert false, 'expected error for invalid URL scheme'
}

fn test_validate_nats_source_config() {
	// Valid config
	result := validate_nats_source_config({
		'subject': 'test.>'
	}) or { panic(err.str()) }
	assert result == true

	// Missing subject
	validate_nats_source_config(map[string]string{}) or {
		assert err.msg().contains('subject is required')
		return
	}
	assert false, 'expected error for missing subject'
}

fn test_build_nats_connect_payload() {
	// Without auth
	payload := build_nats_connect_payload('vector', '', '', '')
	assert payload.starts_with('CONNECT {')
	assert payload.ends_with('}\r\n')
	assert payload.contains('"name":"vector"')
	assert payload.contains('"verbose":false')
	assert payload.contains('"lang":"vlang"')
	assert payload.contains('"protocol":1')
	assert !payload.contains('"auth_token"')
	assert !payload.contains('"user"')
	assert !payload.contains('"pass"')
}

fn test_build_nats_connect_payload_with_auth() {
	// With token auth
	payload := build_nats_connect_payload('my-app', '', '', 'my-token')
	assert payload.contains('"auth_token":"my-token"')
	assert !payload.contains('"user"')

	// With user/password auth
	payload2 := build_nats_connect_payload('my-app', 'admin', 'secret', '')
	assert payload2.contains('"user":"admin"')
	assert payload2.contains('"pass":"secret"')
	assert !payload2.contains('"auth_token"')
}

fn test_nats_source_jetstream_config() {
	// JetStream disabled by default
	s1 := new_nats_source({
		'subject': 'test'
	}) or { panic(err.str()) }
	assert s1.jetstream == false
	assert s1.jetstream_stream == ''

	// JetStream enabled with stream
	s2 := new_nats_source({
		'subject':          'test'
		'jetstream':        'true'
		'jetstream.stream': 'MYSTREAM'
	}) or { panic(err.str()) }
	assert s2.jetstream == true
	assert s2.jetstream_stream == 'MYSTREAM'
}

fn test_new_nats_source_empty_subject() {
	new_nats_source({
		'subject': ''
	}) or {
		assert err.msg().contains('subject is required')
		return
	}
	assert false, 'expected error for empty subject'
}

fn test_new_nats_source_negative_subscriber_capacity() {
	s := new_nats_source({
		'subject':             'test'
		'subscriber_capacity': '-10'
	}) or { panic(err.str()) }
	assert s.subscriber_capacity == 4096
}

fn test_new_nats_source_zero_subscriber_capacity() {
	s := new_nats_source({
		'subject':             'test'
		'subscriber_capacity': '0'
	}) or { panic(err.str()) }
	assert s.subscriber_capacity == 4096
}

fn test_parse_nats_url_with_trailing_path() {
	host, port := parse_nats_url('nats://myhost:4222/some/path') or { panic(err.str()) }
	assert host == 'myhost'
	assert port == 4222
}

fn test_parse_nats_url_empty_host_with_port() {
	// nats://:4222 - empty host before colon => defaults to 127.0.0.1
	host, port := parse_nats_url('nats://:4222') or { panic(err.str()) }
	assert host == '127.0.0.1'
	assert port == 4222
}

fn test_parse_nats_url_invalid_port() {
	// Invalid port string falls back to default
	host, port := parse_nats_url('nats://myhost:abc') or { panic(err.str()) }
	assert host == 'myhost'
	assert port == 4222
}

fn test_validate_nats_source_config_empty_subject() {
	validate_nats_source_config({
		'subject': ''
	}) or {
		assert err.msg().contains('subject is required')
		return
	}
	assert false, 'expected error for empty subject'
}

fn test_validate_nats_source_config_invalid_url() {
	validate_nats_source_config({
		'subject': 'test'
		'url':     'http://invalid:4222'
	}) or {
		assert err.msg().contains('invalid url')
		return
	}
	assert false, 'expected error for invalid url'
}

fn test_validate_nats_source_config_with_valid_url() {
	result := validate_nats_source_config({
		'subject': 'test'
		'url':     'nats://myhost:4222'
	}) or { panic(err.str()) }
	assert result == true
}

fn test_new_nats_source_nkey_and_credentials() {
	s := new_nats_source({
		'subject':              'test'
		'auth.nkey':            'SUAM2FG...'
		'auth.credentials_file': '/path/to/creds'
	}) or { panic(err.str()) }
	assert s.auth_nkey == 'SUAM2FG...'
	assert s.credentials_file == '/path/to/creds'
}

fn test_nats_source_auth_token() {
	s := new_nats_source({
		'subject':    'events'
		'auth.token': 's3cr3t'
	}) or { panic(err.str()) }
	assert s.auth_token == 's3cr3t'
	assert s.auth_user == ''
	assert s.auth_password == ''
}

fn test_nats_source_auth_user_password() {
	s := new_nats_source({
		'subject':       'events'
		'auth.user':     'admin'
		'auth.password': 'hunter2'
	}) or { panic(err.str()) }
	assert s.auth_user == 'admin'
	assert s.auth_password == 'hunter2'
	assert s.auth_token == ''
}
