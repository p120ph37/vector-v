module sinks

import event
import mockserver

fn test_otlp_flush_to_server() {
	mut mock := mockserver.start(
		mockserver.post('/v1/logs', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_opentelemetry({
		'endpoint':              mock.url()
		'resource.service.name': 'test-svc'
		'batch.max_events':      '1000'
	})

	ev := event.Event(event.new_log('hello otlp'))
	s.send(ev) or {}
	assert s.buffer.len == 1

	s.flush()!
	assert s.buffer.len == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].path == '/v1/logs'
	body := reqs[0].body
	assert body.contains('"resourceLogs"')
	assert body.contains('"scopeLogs"')
	assert body.contains('"logRecords"')
	assert body.contains('"hello otlp"')
	assert body.contains('"service.name"')
	assert body.contains('"test-svc"')
}

fn test_otlp_severity_in_payload() {
	mut mock := mockserver.start(
		mockserver.post('/v1/logs', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_opentelemetry({
		'endpoint':         mock.url()
		'batch.max_events': '1000'
	})

	mut log := event.new_log('error happened')
	log.set('severity', event.Value('ERROR'))
	s.send(event.Event(log)) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body.contains('"ERROR"')
}

fn test_otlp_auto_flush_on_batch_full() {
	mut mock := mockserver.start(
		mockserver.post('/v1/logs', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_opentelemetry({
		'endpoint':         mock.url()
		'batch.max_events': '2'
	})

	ev1 := event.Event(event.new_log('msg1'))
	ev2 := event.Event(event.new_log('msg2'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	assert s.buffer.len == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
}

fn test_otlp_multiple_records_in_batch() {
	mut mock := mockserver.start(
		mockserver.post('/v1/logs', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_opentelemetry({
		'endpoint':         mock.url()
		'batch.max_events': '1000'
	})

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('record ${i}'))
		s.send(ev) or {}
	}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	body := reqs[0].body
	assert body.contains('"record 0"')
	assert body.contains('"record 1"')
	assert body.contains('"record 2"')
}

fn test_otlp_resource_attributes_in_payload() {
	mut mock := mockserver.start(
		mockserver.post('/v1/logs', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_opentelemetry({
		'endpoint':              mock.url()
		'resource.service.name': 'my-app'
		'resource.env':          'production'
		'batch.max_events':      '1000'
	})

	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	body := reqs[0].body
	assert body.contains('"service.name"')
	assert body.contains('"my-app"')
	assert body.contains('"env"')
	assert body.contains('"production"')
}

fn test_otlp_bearer_auth_sent() {
	mut mock := mockserver.start(
		mockserver.post('/v1/logs', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_opentelemetry({
		'endpoint':         mock.url()
		'auth.token':       'otlp-secret'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('auth test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	auth := reqs[0].headers['authorization'] or { '' }
	assert auth == 'Bearer otlp-secret'
}

fn test_otlp_server_error_returns_error() {
	mut mock := mockserver.start(
		mockserver.post('/v1/logs', mockserver.respond(500, '{"error":"internal"}'))
	)!
	defer { mock.stop() }

	mut s := new_opentelemetry({
		'endpoint':         mock.url()
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('will fail'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('500')
		return
	}
	assert false, 'expected error on 500 response'
}

fn test_otlp_server_503_unavailable() {
	mut mock := mockserver.start(
		mockserver.sequence('POST', '/v1/logs', [
			mockserver.respond(503, '{"error":"unavailable"}'),
			mockserver.respond(200, '{}'),
		])
	)!
	defer { mock.stop() }

	mut s := new_opentelemetry({
		'endpoint':         mock.url()
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('retry msg'))
	s.send(ev) or {}

	// First flush fails
	s.flush() or {
		assert err.msg().contains('503')
		return
	}
	assert false, 'expected error on 503 response'
}

fn test_otlp_content_type_json() {
	mut mock := mockserver.start(
		mockserver.post('/v1/logs', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_opentelemetry({
		'endpoint':         mock.url()
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	ct := reqs[0].headers['content-type'] or { '' }
	assert ct.contains('json')
}
