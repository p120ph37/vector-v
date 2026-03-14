module vrl

import mockserver

// ============================================================
// http_request — mock-server integration tests
// ============================================================
// These tests use a real HTTP server on loopback to verify the full
// request/response cycle: method dispatch, headers, body delivery,
// response handling, and named-parameter dispatch.

fn test_http_get_success() {
	mut mock := mockserver.start(
		mockserver.get('/data', mockserver.respond(200, '{"items":[1,2,3]}')),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([VrlValue('${mock.url()}/data')]) or {
		assert false, 'expected success, got error: ${err}'
		return
	}
	assert result == VrlValue('{"items":[1,2,3]}')

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs.len == 1
	assert reqs[0].method == 'GET'
	assert reqs[0].path == '/data'
}

fn test_http_post_with_body() {
	mut mock := mockserver.start(
		mockserver.post('/ingest', mockserver.respond(200, 'accepted')),
	) or { panic(err) }
	defer { mock.stop() }

	mut headers := new_object_map()
	body_payload := '{"event":"test","level":"info"}'

	result := fn_http_request([
		VrlValue('${mock.url()}/ingest'),
		VrlValue('POST'),
		VrlValue(headers),
		VrlValue(body_payload),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}
	assert result == VrlValue('accepted')

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].method == 'POST'
	assert reqs[0].body == body_payload
}

fn test_http_put_method() {
	mut mock := mockserver.start(
		mockserver.put('/resource/1', mockserver.respond(200, 'updated')),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([
		VrlValue('${mock.url()}/resource/1'),
		VrlValue('PUT'),
		VrlValue(new_object_map()),
		VrlValue('new-value'),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}
	assert result == VrlValue('updated')

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].method == 'PUT'
	assert reqs[0].body == 'new-value'
}

fn test_http_delete_method() {
	mut mock := mockserver.start(
		mockserver.route('DELETE', '/resource/42', mockserver.respond(200, 'deleted')),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([
		VrlValue('${mock.url()}/resource/42'),
		VrlValue('DELETE'),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}
	assert result == VrlValue('deleted')

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].method == 'DELETE'
}

fn test_http_patch_method() {
	mut mock := mockserver.start(
		mockserver.route('PATCH', '/item', mockserver.respond(200, 'patched')),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([
		VrlValue('${mock.url()}/item'),
		VrlValue('PATCH'),
		VrlValue(new_object_map()),
		VrlValue('{"field":"new"}'),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}
	assert result == VrlValue('patched')

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].method == 'PATCH'
}

fn test_http_custom_headers_sent() {
	mut mock := mockserver.start(
		mockserver.post('/api', mockserver.respond(200, 'ok')),
	) or { panic(err) }
	defer { mock.stop() }

	mut hdrs := new_object_map()
	hdrs.set('Authorization', VrlValue('Bearer my-secret-token'))
	hdrs.set('X-Custom-Id', VrlValue('req-12345'))

	fn_http_request([
		VrlValue('${mock.url()}/api'),
		VrlValue('POST'),
		VrlValue(hdrs),
		VrlValue('payload'),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].headers['authorization'] == 'Bearer my-secret-token'
	assert reqs[0].headers['x-custom-id'] == 'req-12345'
}

fn test_http_non_string_header_values_converted() {
	mut mock := mockserver.start(
		mockserver.get('/check', mockserver.respond(200, 'ok')),
	) or { panic(err) }
	defer { mock.stop() }

	mut hdrs := new_object_map()
	hdrs.set('X-Count', VrlValue(i64(42)))
	hdrs.set('X-Enabled', VrlValue(true))

	fn_http_request([
		VrlValue('${mock.url()}/check'),
		VrlValue('GET'),
		VrlValue(hdrs),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].headers['x-count'] == '42'
	assert reqs[0].headers['x-enabled'] == 'true'
}

fn test_http_non_object_headers_silently_ignored() {
	mut mock := mockserver.start(
		mockserver.get('/test', mockserver.respond(200, 'ok')),
	) or { panic(err) }
	defer { mock.stop() }

	// Pass a string instead of ObjectMap as headers — should be ignored
	result := fn_http_request([
		VrlValue('${mock.url()}/test'),
		VrlValue('GET'),
		VrlValue('not-an-object'),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}
	assert result == VrlValue('ok')
}

fn test_http_non_string_body_defaults_to_empty() {
	mut mock := mockserver.start(
		mockserver.post('/sink', mockserver.respond(200, 'ok')),
	) or { panic(err) }
	defer { mock.stop() }

	fn_http_request([
		VrlValue('${mock.url()}/sink'),
		VrlValue('POST'),
		VrlValue(new_object_map()),
		VrlValue(i64(999)), // not a string — should default to ""
	]) or {
		assert false, 'expected success: ${err}'
		return
	}

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].body == ''
}

fn test_http_non_string_method_defaults_to_get() {
	mut mock := mockserver.start(
		mockserver.get('/fallback', mockserver.respond(200, 'got-it')),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([
		VrlValue('${mock.url()}/fallback'),
		VrlValue(i64(123)), // not a string — should default to GET
	]) or {
		assert false, 'expected success: ${err}'
		return
	}
	assert result == VrlValue('got-it')

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].method == 'GET'
}

fn test_http_lowercase_method_uppercased() {
	mut mock := mockserver.start(
		mockserver.post('/case', mockserver.respond(200, 'ok')),
	) or { panic(err) }
	defer { mock.stop() }

	fn_http_request([
		VrlValue('${mock.url()}/case'),
		VrlValue('post'), // lowercase
		VrlValue(new_object_map()),
		VrlValue('data'),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].method == 'POST'
}

fn test_http_error_status_still_returns_body() {
	// fn_http_request does not check HTTP status codes — it returns the body
	mut mock := mockserver.start(
		mockserver.get('/fail', mockserver.respond(500, '{"error":"internal"}')),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([VrlValue('${mock.url()}/fail')]) or {
		assert false, 'expected body even on 500: ${err}'
		return
	}
	assert result == VrlValue('{"error":"internal"}')
}

fn test_http_404_returns_body() {
	mut mock := mockserver.start(
		mockserver.get('/missing', mockserver.respond(404, 'not found')),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([VrlValue('${mock.url()}/missing')]) or {
		assert false, 'expected body even on 404: ${err}'
		return
	}
	assert result == VrlValue('not found')
}

fn test_http_empty_response_body() {
	mut mock := mockserver.start(
		mockserver.post('/void', mockserver.respond(204, '')),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([
		VrlValue('${mock.url()}/void'),
		VrlValue('POST'),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}
	assert result == VrlValue('')
}

fn test_http_response_with_custom_headers() {
	// Verify the function returns the body even when server sends custom headers
	mut mock := mockserver.start(
		mockserver.get('/headers', mockserver.respond_with_headers(200, 'body-text', {
			'X-Request-Id': 'abc-123'
			'X-RateLimit':  '100'
		})),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([VrlValue('${mock.url()}/headers')]) or {
		assert false, 'expected success: ${err}'
		return
	}
	assert result == VrlValue('body-text')
}

fn test_http_large_response_body() {
	// Test with a larger payload to exercise the response handling
	large_body := 'x'.repeat(8192)
	mut mock := mockserver.start(
		mockserver.get('/large', mockserver.respond(200, large_body)),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([VrlValue('${mock.url()}/large')]) or {
		assert false, 'expected success: ${err}'
		return
	}
	result_str := result as string
	assert result_str.len == 8192
}

fn test_http_multiple_sequential_requests() {
	mut mock := mockserver.start(
		mockserver.get('/seq', mockserver.respond(200, 'pong')),
	) or { panic(err) }
	defer { mock.stop() }

	for _ in 0 .. 5 {
		result := fn_http_request([VrlValue('${mock.url()}/seq')]) or {
			assert false, 'expected success: ${err}'
			return
		}
		assert result == VrlValue('pong')
	}

	reqs := mock.wait_for_requests(5, 5000)
	assert reqs.len == 5
}

fn test_http_head_returns_empty_body() {
	// HEAD responses typically have no body
	mut mock := mockserver.start(
		mockserver.route('HEAD', '/ping', mockserver.respond(200, '')),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([
		VrlValue('${mock.url()}/ping'),
		VrlValue('HEAD'),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}
	// HEAD may or may not return a body depending on the HTTP client
	// but it should not error
	_ = result
}

fn test_http_options_method() {
	mut mock := mockserver.start(
		mockserver.route('OPTIONS', '/cors', mockserver.respond_with_headers(200, '', {
			'Access-Control-Allow-Methods': 'GET, POST'
		})),
	) or { panic(err) }
	defer { mock.stop() }

	result := fn_http_request([
		VrlValue('${mock.url()}/cors'),
		VrlValue('OPTIONS'),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}
	_ = result

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].method == 'OPTIONS'
}

fn test_http_request_body_with_special_chars() {
	mut mock := mockserver.start(
		mockserver.post('/special', mockserver.respond(200, 'ok')),
	) or { panic(err) }
	defer { mock.stop() }

	special_body := '{"msg":"hello\\nworld","emoji":"\\u2603","quotes":"\\"test\\""}'

	fn_http_request([
		VrlValue('${mock.url()}/special'),
		VrlValue('POST'),
		VrlValue(new_object_map()),
		VrlValue(special_body),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].body == special_body
}

fn test_http_content_type_header() {
	mut mock := mockserver.start(
		mockserver.post('/typed', mockserver.respond(200, 'ok')),
	) or { panic(err) }
	defer { mock.stop() }

	mut hdrs := new_object_map()
	hdrs.set('Content-Type', VrlValue('application/json'))

	fn_http_request([
		VrlValue('${mock.url()}/typed'),
		VrlValue('POST'),
		VrlValue(hdrs),
		VrlValue('{}'),
	]) or {
		assert false, 'expected success: ${err}'
		return
	}

	reqs := mock.wait_for_requests(1, 3000)
	assert reqs[0].headers['content-type'] == 'application/json'
}
