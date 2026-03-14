module mockserver

import net.http

fn test_start_and_url() {
	mut mock := start(
		get('/health', respond(200, '{"status":"ok"}')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	assert mock.port > 0
	assert mock.url().starts_with('http://127.0.0.1:')
}

fn test_get_request() {
	mut mock := start(
		get('/health', respond(200, '{"status":"ok"}')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	resp := http.get('${mock.url()}/health') or { panic(err) }
	assert resp.status_code == 200
	assert resp.body == '{"status":"ok"}'

	reqs := mock.wait_for_requests(1, 2000)
	assert reqs.len == 1
	assert reqs[0].method == 'GET'
	assert reqs[0].path == '/health'
}

fn test_post_request_with_body() {
	mut mock := start(
		post('/api/push', respond(204, '')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	payload := '{"data":"test payload"}'
	resp := http.post('${mock.url()}/api/push', payload) or { panic(err) }
	assert resp.status_code == 204

	reqs := mock.wait_for_requests(1, 2000)
	assert reqs.len == 1
	assert reqs[0].method == 'POST'
	assert reqs[0].path == '/api/push'
	assert reqs[0].body == payload
}

fn test_put_request() {
	mut mock := start(
		put('/token', respond(200, 'my-token-123')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	header := http.new_custom_header_from_map({
		'X-Custom': 'value'
	}) or { panic(err) }
	resp := http.fetch(http.FetchConfig{
		url: '${mock.url()}/token'
		method: .put
		header: header
	}) or { panic(err) }
	assert resp.status_code == 200
	assert resp.body == 'my-token-123'

	reqs := mock.wait_for_requests(1, 2000)
	assert reqs[0].method == 'PUT'
	assert reqs[0].headers['x-custom'] == 'value'
}

fn test_unmatched_route_returns_404() {
	mut mock := start(
		get('/exists', respond(200, 'ok')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	resp := http.get('${mock.url()}/does-not-exist') or { panic(err) }
	assert resp.status_code == 404
}

fn test_multiple_routes() {
	mut mock := start(
		get('/health', respond(200, '{"status":"ok"}')),
		get('/ready', respond(200, '{"status":"ready"}')),
		post('/ingest', respond(201, '{"id":"1"}')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	r1 := http.get('${mock.url()}/health') or { panic(err) }
	assert r1.status_code == 200
	assert r1.body == '{"status":"ok"}'

	r2 := http.get('${mock.url()}/ready') or { panic(err) }
	assert r2.status_code == 200
	assert r2.body == '{"status":"ready"}'

	r3 := http.post('${mock.url()}/ingest', '{}') or { panic(err) }
	assert r3.status_code == 201
	assert r3.body == '{"id":"1"}'

	reqs := mock.wait_for_requests(3, 2000)
	assert reqs.len == 3
	assert reqs[0].path == '/health'
	assert reqs[1].path == '/ready'
	assert reqs[2].path == '/ingest'
}

fn test_response_cycling() {
	// First call returns 200, second returns 503, third wraps back to 200
	mut mock := start(
		sequence('GET', '/status', [
			respond(200, '{"ok":true}'),
			respond(503, '{"ok":false}'),
		]),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	r1 := http.get('${mock.url()}/status') or { panic(err) }
	assert r1.status_code == 200

	r2 := http.get('${mock.url()}/status') or { panic(err) }
	assert r2.status_code == 503

	r3 := http.get('${mock.url()}/status') or { panic(err) }
	assert r3.status_code == 200 // wraps around

	reqs := mock.wait_for_requests(3, 2000)
	assert reqs.len == 3
}

fn test_request_headers_captured() {
	mut mock := start(
		post('/api', respond(200, 'ok')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	header := http.new_custom_header_from_map({
		'Authorization':  'Bearer secret'
		'X-Scope-OrgID': 'tenant-1'
	}) or { panic(err) }

	http.fetch(http.FetchConfig{
		url: '${mock.url()}/api'
		method: .post
		data: 'body'
		header: header
	}) or { panic(err) }

	reqs := mock.wait_for_requests(1, 2000)
	assert reqs[0].headers['authorization'] == 'Bearer secret'
	assert reqs[0].headers['x-scope-orgid'] == 'tenant-1'
}

fn test_request_count() {
	mut mock := start(
		get('/ping', respond(200, 'pong')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	for _ in 0 .. 5 {
		http.get('${mock.url()}/ping') or { panic(err) }
	}

	reqs := mock.wait_for_requests(5, 3000)
	assert reqs.len == 5
	assert mock.request_count() == 5
}

fn test_respond_with_headers() {
	mut mock := start(
		get('/download', respond_with_headers(200, 'file contents', {
			'Content-Disposition': 'attachment; filename="test.txt"'
			'X-Request-Id':        'abc-123'
		})),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	resp := http.get('${mock.url()}/download') or { panic(err) }
	assert resp.status_code == 200
	assert resp.body == 'file contents'

	// The custom headers should be present in the HTTP response
	assert resp.header.get_custom('X-Request-Id') or { '' } == 'abc-123'
}

fn test_route_helper() {
	mut mock := start(
		route('DELETE', '/resource/1', respond(204, '')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	resp := http.fetch(http.FetchConfig{
		url: '${mock.url()}/resource/1'
		method: .delete
	}) or { panic(err) }
	assert resp.status_code == 204

	reqs := mock.wait_for_requests(1, 2000)
	assert reqs[0].method == 'DELETE'
}

fn test_empty_response_route() {
	// Route with no explicit response returns 200 OK
	mut mock := start(
		Route{
			method: 'GET'
			path: '/noop'
			responses: []
		},
	) or { panic(err) }
	defer {
		mock.stop()
	}

	resp := http.get('${mock.url()}/noop') or { panic(err) }
	assert resp.status_code == 200
}

fn test_multiple_mock_servers() {
	// Two servers should bind to different ports
	mut mock1 := start(
		get('/a', respond(200, 'server1')),
	) or { panic(err) }
	defer {
		mock1.stop()
	}

	mut mock2 := start(
		get('/b', respond(200, 'server2')),
	) or { panic(err) }
	defer {
		mock2.stop()
	}

	assert mock1.port != mock2.port

	r1 := http.get('${mock1.url()}/a') or { panic(err) }
	assert r1.body == 'server1'

	r2 := http.get('${mock2.url()}/b') or { panic(err) }
	assert r2.body == 'server2'
}

fn test_start_with_routes() {
	routes := [
		get('/one', respond(200, '1')),
		get('/two', respond(200, '2')),
	]
	mut mock := start_with_routes(routes) or { panic(err) }
	defer {
		mock.stop()
	}

	r1 := http.get('${mock.url()}/one') or { panic(err) }
	assert r1.body == '1'

	r2 := http.get('${mock.url()}/two') or { panic(err) }
	assert r2.body == '2'
}
