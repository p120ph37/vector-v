module sinks

import event
import mockserver

fn test_loki_flush_to_server() {
	mut mock := mockserver.start(
		mockserver.post('/loki/api/v1/push', mockserver.respond(204, ''))
	)!
	defer { mock.stop() }

	mut s := new_loki({
		'endpoint':         mock.url()
		'labels.job':       'vector'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('hello loki'))
	s.send(ev) or {}
	assert s.total_buffered() == 1

	s.flush()!
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].path == '/loki/api/v1/push'
	assert reqs[0].body.contains('"streams"')
	assert reqs[0].body.contains('hello loki')
}

fn test_loki_label_batching_to_server() {
	mut mock := mockserver.start(
		mockserver.post('/loki/api/v1/push', mockserver.respond(204, ''))
	)!
	defer { mock.stop() }

	mut s := new_loki({
		'endpoint':         mock.url()
		'labels.env':       '{{ env }}'
		'labels.job':       'test'
		'batch.max_events': '1000'
	})

	mut log1 := event.new_log('msg from prod')
	log1.set('env', event.Value('production'))
	s.send(event.Event(log1)) or {}

	mut log2 := event.new_log('msg from staging')
	log2.set('env', event.Value('staging'))
	s.send(event.Event(log2)) or {}

	assert s.total_buffered() == 2

	s.flush()!
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	body := reqs[0].body
	// Should contain both streams with different label sets
	assert body.contains('"streams"')
	assert body.contains('production')
	assert body.contains('staging')
}

fn test_loki_tenant_id_header() {
	mut mock := mockserver.start(
		mockserver.post('/loki/api/v1/push', mockserver.respond(204, ''))
	)!
	defer { mock.stop() }

	mut s := new_loki({
		'endpoint':         mock.url()
		'tenant_id':        'my-tenant'
		'labels.job':       'test'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('tenant test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	org_id := reqs[0].headers['x-scope-orgid'] or { '' }
	assert org_id == 'my-tenant'
}

fn test_loki_auto_flush_on_batch_full() {
	mut mock := mockserver.start(
		mockserver.post('/loki/api/v1/push', mockserver.respond(204, ''))
	)!
	defer { mock.stop() }

	mut s := new_loki({
		'endpoint':         mock.url()
		'labels.job':       'test'
		'batch.max_events': '2'
	})

	ev1 := event.Event(event.new_log('msg1'))
	ev2 := event.Event(event.new_log('msg2'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	// Should have auto-flushed
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
}

fn test_loki_text_codec_to_server() {
	mut mock := mockserver.start(
		mockserver.post('/loki/api/v1/push', mockserver.respond(204, ''))
	)!
	defer { mock.stop() }

	mut s := new_loki({
		'endpoint':         mock.url()
		'labels.job':       'test'
		'encoding.codec':   'text'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('plain text message'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	// With text codec the line should be the raw message, not JSON
	assert reqs[0].body.contains('plain text message')
}

fn test_loki_server_error_returns_error() {
	mut mock := mockserver.start(
		mockserver.post('/loki/api/v1/push', mockserver.respond(500, '{"error":"internal"}'))
	)!
	defer { mock.stop() }

	mut s := new_loki({
		'endpoint':         mock.url()
		'labels.job':       'test'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('will fail'))
	s.send(ev) or {}

	// flush should return error on 500
	s.flush() or {
		assert err.msg().contains('500')
		return
	}
	assert false, 'expected error on 500 response'
}

fn test_loki_server_429_rate_limit() {
	mut mock := mockserver.start(
		mockserver.sequence('POST', '/loki/api/v1/push', [
			mockserver.respond(429, '{"error":"rate limited"}'),
			mockserver.respond(204, ''),
		])
	)!
	defer { mock.stop() }

	mut s := new_loki({
		'endpoint':         mock.url()
		'labels.job':       'test'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('rate limited msg'))
	s.send(ev) or {}

	// First flush should fail (429)
	s.flush() or {
		assert err.msg().contains('429')
		// Buffer should NOT be cleared on failure - data retained for retry
		assert s.total_buffered() == 1
		return
	}
	assert false, 'expected error on 429 response'
}

fn test_loki_basic_auth_sent() {
	mut mock := mockserver.start(
		mockserver.post('/loki/api/v1/push', mockserver.respond(204, ''))
	)!
	defer { mock.stop() }

	mut s := new_loki({
		'endpoint':      mock.url()
		'labels.job':    'test'
		'auth.user':     'admin'
		'auth.password': 'secret'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('auth test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	auth := reqs[0].headers['authorization'] or { '' }
	assert auth.starts_with('Basic ')
}
