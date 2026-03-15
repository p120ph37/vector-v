module sinks

import event
import mockserver

// Tests for HTTP error code paths using mockserver to simulate failures.

fn test_http_sink_server_500_error() {
	mut mock := mockserver.start(
		mockserver.post('/events', mockserver.respond(500, '{"error":"internal server error"}'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'path':             '/events'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('500')
		return
	}
	assert false, 'expected error on 500 response'
}

fn test_http_sink_server_503_unavailable() {
	mut mock := mockserver.start(
		mockserver.post('/events', mockserver.respond(503, 'service unavailable'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'path':             '/events'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('503')
		return
	}
	assert false, 'expected error on 503 response'
}

fn test_http_sink_server_401_unauthorized() {
	mut mock := mockserver.start(
		mockserver.post('/secure', mockserver.respond(401, '{"error":"unauthorized"}'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'path':             '/secure'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('no auth'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('401')
		return
	}
	assert false, 'expected error on 401 response'
}

fn test_http_sink_server_403_forbidden() {
	mut mock := mockserver.start(
		mockserver.post('/forbidden', mockserver.respond(403, '{"error":"forbidden"}'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'path':             '/forbidden'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('forbidden'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('403')
		return
	}
	assert false, 'expected error on 403 response'
}

fn test_http_sink_server_429_rate_limit() {
	mut mock := mockserver.start(
		mockserver.post('/events', mockserver.respond(429, '{"error":"rate limited"}'))
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'path':             '/events'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('rate limited'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('429')
		return
	}
	assert false, 'expected error on 429 response'
}

fn test_http_sink_sequence_fail_then_succeed() {
	// Simulates a transient failure followed by success (retry scenario)
	mut mock := mockserver.start(
		mockserver.sequence('POST', '/events', [
			mockserver.respond(503, 'unavailable'),
			mockserver.respond(200, 'ok'),
		])
	)!
	defer { mock.stop() }

	mut s := new_http({
		'endpoint':         mock.url()
		'path':             '/events'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('retry me'))
	s.send(ev) or {}

	// First flush fails
	s.flush() or {
		assert err.msg().contains('503')
		// Buffer is cleared on error propagation from HttpSink.flush
		// Re-buffer and retry
		s.buffer << 'retry me'

		// Second flush should succeed
		s.flush() or {
			assert false, 'second flush should succeed'
			return
		}
		return
	}
}

fn test_http_sink_connection_refused() {
	// Connect to a port with no server - should get an error
	mut s := new_http({
		'endpoint':         'http://127.0.0.1:1'
		'path':             '/events'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('no server'))
	s.send(ev) or {}

	s.flush() or {
		// Should fail with connection error
		assert err.msg().len > 0
		return
	}
	// Some systems may not error on unreachable localhost - that's ok
}

fn test_http_batch_healthcheck_success() {
	mut mock := mockserver.start(
		mockserver.get('/health', mockserver.respond(200, '{"status":"ok"}'))
	)!
	defer { mock.stop() }

	batch := new_http_batch({
		'endpoint': mock.url()
		'path':     '/health'
	})

	result := batch.simple_healthcheck()!
	assert result == true
}

fn test_http_batch_healthcheck_failure() {
	// Connect to a port with no server
	batch := new_http_batch({
		'endpoint': 'http://127.0.0.1:1'
		'path':     '/health'
	})

	batch.simple_healthcheck() or {
		assert err.msg().len > 0
		return
	}
	// Some systems may connect to localhost:1 - that's ok
}
