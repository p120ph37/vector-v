module sinks

import event
import mockserver

fn test_http_flush_to_server() {
	mut mock := mockserver.start(
		mockserver.post('/events', mockserver.respond(200, 'ok'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'path':             '/events'
		'encoding.codec':   'json'
		'batch.max_events': '1000'
	})

	ev1 := event.Event(event.new_log('hello'))
	ev2 := event.Event(event.new_log('world'))
	s.send(ev1) or {}
	s.send(ev2) or {}
	assert s.total_buffered() == 2

	s.flush()!
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].body.contains('hello')
	assert reqs[0].body.contains('world')
}

fn test_http_flush_ndjson_to_server() {
	mut mock := mockserver.start(
		mockserver.post('/ingest', mockserver.respond(204, ''))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'path':             '/ingest'
		'encoding.codec':   'ndjson'
		'batch.max_events': '1000'
	})

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('line ${i}'))
		s.send(ev) or {}
	}
	s.flush()!
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	// ndjson should have Content-Type header
	ct := reqs[0].headers['content-type'] or { '' }
	assert ct.contains('ndjson')
}

fn test_http_flush_text_to_server() {
	mut mock := mockserver.start(
		mockserver.post('/logs', mockserver.respond(200, 'ok'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'path':             '/logs'
		'encoding.codec':   'text'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('plain text line'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body.contains('plain text line')
}

fn test_http_auto_flush_on_batch_full() {
	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, 'ok'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'batch.max_events': '2'
	})

	// Sending 2 events should trigger auto-flush
	ev1 := event.Event(event.new_log('msg1'))
	ev2 := event.Event(event.new_log('msg2'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	// Buffer should be cleared after auto-flush
	assert s.total_buffered() == 0
}

fn test_http_custom_headers_sent() {
	mut mock := mockserver.start(
		mockserver.post('/api', mockserver.respond(200, 'ok'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':          mock.url()
		'path':              '/api'
		'headers.X-Custom':  'test-value'
		'batch.max_events':  '1000'
	})

	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	custom := reqs[0].headers['x-custom'] or { '' }
	assert custom == 'test-value'
}

fn test_http_bearer_auth_sent() {
	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, 'ok'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'auth.token':       'secret-token'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	auth := reqs[0].headers['authorization'] or { '' }
	assert auth == 'Bearer secret-token'
}

fn test_http_with_prefix_suffix_sent() {
	mut mock := mockserver.start(
		mockserver.post('/', mockserver.respond(200, 'ok'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'encoding.codec':   'json'
		'payload_prefix':   '{"wrapper":'
		'payload_suffix':   '}'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('wrapped'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body.starts_with('{"wrapper":')
	assert reqs[0].body.ends_with('}')
}
