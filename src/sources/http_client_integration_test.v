module sources

import event
import mockserver
import time

fn test_http_client_scrape_success() {
	mut mock := mockserver.start(
		mockserver.get('/metrics', mockserver.respond(200, '{"cpu":42}'))
	)!
	defer { mock.stop() }

	s := new_http_client({
		'endpoint': '${mock.url()}/metrics'
	})!

	output := chan event.Event{cap: 10}
	s.scrape(output)

	mut ev := event.Event(event.new_log(''))
	if output.try_pop(mut ev) == .success {
		json_str := ev.to_json_string()
		// The response body is stored as the message field value
		assert json_str.contains('cpu')
		assert json_str.contains('42')
	} else {
		assert false, 'expected event from scrape'
	}

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs.len >= 1
	assert reqs[0].method == 'GET'
	assert reqs[0].path == '/metrics'
}

fn test_http_client_scrape_with_auth() {
	mut mock := mockserver.start(
		mockserver.get('/api/data', mockserver.respond(200, 'ok'))
	)!
	defer { mock.stop() }

	s := new_http_client({
		'endpoint':   '${mock.url()}/api/data'
		'auth.token': 'my-token'
	})!

	output := chan event.Event{cap: 10}
	s.scrape(output)

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs.len >= 1
	auth := reqs[0].headers['authorization'] or { '' }
	assert auth == 'Bearer my-token'
}

fn test_http_client_scrape_with_custom_headers() {
	mut mock := mockserver.start(
		mockserver.get('/data', mockserver.respond(200, 'ok'))
	)!
	defer { mock.stop() }

	s := new_http_client({
		'endpoint':          '${mock.url()}/data'
		'headers.X-Api-Key': 'secret-key'
		'headers.Accept':    'text/plain'
	})!

	output := chan event.Event{cap: 10}
	s.scrape(output)

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs.len >= 1
	api_key := reqs[0].headers['x-api-key'] or { '' }
	assert api_key == 'secret-key'
}

fn test_http_client_scrape_server_error_no_event() {
	mut mock := mockserver.start(
		mockserver.get('/fail', mockserver.respond(500, '{"error":"fail"}'))
	)!
	defer { mock.stop() }

	s := new_http_client({
		'endpoint': '${mock.url()}/fail'
	})!

	output := chan event.Event{cap: 10}
	s.scrape(output)

	// On HTTP >= 400, no event should be emitted
	time.sleep(100 * time.millisecond)
	mut ev := event.Event(event.new_log(''))
	assert output.try_pop(mut ev) != .success
}

fn test_http_client_scrape_404_no_event() {
	mut mock := mockserver.start(
		mockserver.get('/exists', mockserver.respond(200, 'ok'))
	)!
	defer { mock.stop() }

	s := new_http_client({
		'endpoint': '${mock.url()}/missing'
	})!

	output := chan event.Event{cap: 10}
	s.scrape(output)

	// 404 from mock (no matching route) means no event
	time.sleep(100 * time.millisecond)
	mut ev := event.Event(event.new_log(''))
	assert output.try_pop(mut ev) != .success
}

fn test_http_client_scrape_max_length_truncation() {
	long_body := 'A'.repeat(500)
	mut mock := mockserver.start(
		mockserver.get('/big', mockserver.respond(200, long_body))
	)!
	defer { mock.stop() }

	s := new_http_client({
		'endpoint':   '${mock.url()}/big'
		'max_length': '100'
	})!

	output := chan event.Event{cap: 10}
	s.scrape(output)

	mut ev := event.Event(event.new_log(''))
	if output.try_pop(mut ev) == .success {
		// The JSON representation should show the message was truncated
		json_str := ev.to_json_string()
		// 100 A's (max_length) should be present, but not the full 500
		assert json_str.len > 0
		assert !json_str.contains('A'.repeat(500))
	}
}

fn test_http_client_scrape_post_method() {
	mut mock := mockserver.start(
		mockserver.route('POST', '/collect', mockserver.respond(200, 'collected'))
	)!
	defer { mock.stop() }

	s := new_http_client({
		'endpoint': '${mock.url()}/collect'
		'method':   'POST'
	})!

	output := chan event.Event{cap: 10}
	s.scrape(output)

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
}

fn test_http_client_scrape_sequence_different_responses() {
	mut mock := mockserver.start(
		mockserver.sequence('GET', '/status', [
			mockserver.respond(200, '{"status":"ok"}'),
			mockserver.respond(200, '{"status":"degraded"}'),
		])
	)!
	defer { mock.stop() }

	s := new_http_client({
		'endpoint': '${mock.url()}/status'
	})!

	output := chan event.Event{cap: 10}

	// First scrape
	s.scrape(output)
	mut ev1 := event.Event(event.new_log(''))
	if output.try_pop(mut ev1) == .success {
		msg1 := ev1.to_json_string()
		assert msg1.contains('ok')
	}

	// Second scrape
	s.scrape(output)
	mut ev2 := event.Event(event.new_log(''))
	if output.try_pop(mut ev2) == .success {
		msg2 := ev2.to_json_string()
		assert msg2.contains('degraded')
	}
}
