module sinks

import event

fn test_new_nats_sink_defaults() {
	s := new_nats_sink({
		'subject': 'events'
	}) or { panic(err.str()) }
	assert s.url == 'nats://127.0.0.1:4222'
	assert s.subject == 'events'
	assert s.connection_name == 'vector'
	assert s.auth_token == ''
	assert s.auth_user == ''
	assert s.auth_password == ''
	assert s.jetstream == false
	assert s.encoding_codec == 'json'
	assert s.tls_enabled == false
	assert s.batch_max_events == 100
	assert s.buffer.len == 0
}

fn test_new_nats_sink_missing_subject() {
	new_nats_sink(map[string]string{}) or {
		assert err.msg().contains('subject is required')
		return
	}
	assert false, 'expected error for missing subject'
}

fn test_new_nats_sink_custom() {
	s := new_nats_sink({
		'url':              'nats://nats.example.com:5222'
		'subject':          'logs.{{host}}'
		'connection_name':  'my-vector'
		'auth.token':       'my-token'
		'encoding.codec':   'text'
		'tls.enabled':      'true'
		'batch.max_events': '50'
	}) or { panic(err.str()) }
	assert s.url == 'nats://nats.example.com:5222'
	assert s.subject == 'logs.{{host}}'
	assert s.connection_name == 'my-vector'
	assert s.auth_token == 'my-token'
	assert s.encoding_codec == 'text'
	assert s.tls_enabled == true
	assert s.batch_max_events == 50
}

fn test_nats_sink_send_buffers() {
	mut s := new_nats_sink({
		'subject':          'test'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_nats_sink_total_buffered() {
	mut s := new_nats_sink({
		'subject':          'test'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	s.send(ev) or {}
	assert s.total_buffered() == 2
}

fn test_nats_sink_flush_empty() {
	mut s := new_nats_sink({
		'subject': 'test'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_nats_sink_jetstream_config() {
	// JetStream disabled by default
	s1 := new_nats_sink({
		'subject': 'test'
	}) or { panic(err.str()) }
	assert s1.jetstream == false

	// JetStream enabled
	s2 := new_nats_sink({
		'subject':   'test'
		'jetstream': 'true'
	}) or { panic(err.str()) }
	assert s2.jetstream == true
}

fn test_encode_nats_payload_json() {
	ev := event.Event(event.new_log('hello world'))
	result := encode_nats_payload(ev, 'json')
	assert result.contains('"message"')
	assert result.contains('hello world')
}

fn test_encode_nats_payload_text() {
	ev := event.Event(event.new_log('hello world'))
	result := encode_nats_payload(ev, 'text')
	assert result == 'hello world'
}

fn test_nats_sink_auth_config() {
	// Token auth
	s1 := new_nats_sink({
		'subject':    'events'
		'auth.token': 'secret-token'
	}) or { panic(err.str()) }
	assert s1.auth_token == 'secret-token'
	assert s1.auth_user == ''
	assert s1.auth_password == ''

	// User/password auth
	s2 := new_nats_sink({
		'subject':       'events'
		'auth.user':     'admin'
		'auth.password': 'pass123'
	}) or { panic(err.str()) }
	assert s2.auth_user == 'admin'
	assert s2.auth_password == 'pass123'
	assert s2.auth_token == ''
}
