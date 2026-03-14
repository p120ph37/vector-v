module vrl

// Tests for vrllib_dns.v (fn_dns_lookup, fn_reverse_dns) and
// vrllib_http.v (fn_http_request).
//
// These tests call the internal functions directly to avoid dispatch-routing
// issues and to exercise as many code paths as possible.  Network-dependent
// tests are written defensively: they accept either a valid result or a
// sensible error so they pass in sandboxed environments.

// ============================================================
// dns_lookup
// ============================================================

fn test_dns_lookup_no_args() {
	fn_dns_lookup([]VrlValue{}, map[string]VrlValue{}) or {
		assert err.msg().contains('requires 1 argument'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for missing args'
}

fn test_dns_lookup_wrong_type_int() {
	fn_dns_lookup([VrlValue(i64(42))], map[string]VrlValue{}) or {
		assert err.msg().contains('requires a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for int arg'
}

fn test_dns_lookup_wrong_type_bool() {
	fn_dns_lookup([VrlValue(true)], map[string]VrlValue{}) or {
		assert err.msg().contains('requires a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for bool arg'
}

fn test_dns_lookup_wrong_type_float() {
	fn_dns_lookup([VrlValue(f64(3.14))], map[string]VrlValue{}) or {
		assert err.msg().contains('requires a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for float arg'
}

fn test_dns_lookup_wrong_type_null() {
	fn_dns_lookup([VrlValue(VrlNull{})], map[string]VrlValue{}) or {
		assert err.msg().contains('requires a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for null arg'
}

fn test_dns_lookup_wrong_type_array() {
	fn_dns_lookup([VrlValue([]VrlValue{})], map[string]VrlValue{}) or {
		assert err.msg().contains('requires a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for array arg'
}

// NOTE: Actual DNS resolution tests removed to avoid slow network timeouts.
// The error-path tests above exercise the function argument validation.

// ============================================================
// reverse_dns
// ============================================================

fn test_reverse_dns_no_args() {
	fn_reverse_dns([]VrlValue{}) or {
		assert err.msg().contains('requires 1 argument'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for missing args'
}

fn test_reverse_dns_wrong_type_int() {
	fn_reverse_dns([VrlValue(i64(42))]) or {
		assert err.msg().contains('requires a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for int arg'
}

fn test_reverse_dns_wrong_type_bool() {
	fn_reverse_dns([VrlValue(true)]) or {
		assert err.msg().contains('requires a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for bool arg'
}

fn test_reverse_dns_wrong_type_float() {
	fn_reverse_dns([VrlValue(f64(1.0))]) or {
		assert err.msg().contains('requires a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for float arg'
}

fn test_reverse_dns_wrong_type_null() {
	fn_reverse_dns([VrlValue(VrlNull{})]) or {
		assert err.msg().contains('requires a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for null arg'
}

fn test_reverse_dns_wrong_type_array() {
	fn_reverse_dns([VrlValue([]VrlValue{})]) or {
		assert err.msg().contains('requires a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for array arg'
}

fn test_reverse_dns_invalid_no_dots_or_colons() {
	fn_reverse_dns([VrlValue('notanip')]) or {
		assert err.msg().contains('unable to parse IP address'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for non-IP string'
}

fn test_reverse_dns_empty_string() {
	fn_reverse_dns([VrlValue('')]) or {
		assert err.msg().contains('unable to parse IP address'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for empty string'
}

fn test_reverse_dns_invalid_ipv4_too_few_octets() {
	fn_reverse_dns([VrlValue('1.2.3')]) or {
		assert err.msg().contains('invalid IPv4'), 'expected invalid IPv4: ${err}'
		return
	}
	assert false, 'expected error for 3-octet address'
}

fn test_reverse_dns_invalid_ipv4_too_many_octets() {
	fn_reverse_dns([VrlValue('1.2.3.4.5')]) or {
		assert err.msg().contains('invalid IPv4') || err.msg().contains('getnameinfo'),
			'expected IPv4 parse or lookup error: ${err}'
		return
	}
	assert false, 'expected error for 5-octet address'
}

fn test_reverse_dns_invalid_ipv4_octet_out_of_range() {
	fn_reverse_dns([VrlValue('256.1.2.3')]) or {
		assert err.msg().contains('invalid IPv4 octet'), 'expected octet range error: ${err}'
		return
	}
	assert false, 'expected error for out-of-range octet'
}

fn test_reverse_dns_invalid_ipv4_negative_octet() {
	// "-1" parsed as int gives a negative value
	fn_reverse_dns([VrlValue('-1.0.0.1')]) or {
		assert err.msg().contains('invalid IPv4 octet') || err.msg().contains('getnameinfo'),
			'expected octet error: ${err}'
		return
	}
	// If it succeeds (unlikely), acceptable
}

// NOTE: Actual reverse DNS network tests removed to avoid slow timeouts.
// The error-path tests above exercise the function argument validation
// and input parsing code paths.

// ============================================================
// http_request
// ============================================================

fn test_http_request_no_args() {
	fn_http_request([]VrlValue{}) or {
		assert err.msg().contains('requires at least 1 argument'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for missing args'
}

fn test_http_request_wrong_type_int() {
	fn_http_request([VrlValue(i64(42))]) or {
		assert err.msg().contains('url must be a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for int url'
}

fn test_http_request_wrong_type_bool() {
	fn_http_request([VrlValue(true)]) or {
		assert err.msg().contains('url must be a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for bool url'
}

fn test_http_request_wrong_type_null() {
	fn_http_request([VrlValue(VrlNull{})]) or {
		assert err.msg().contains('url must be a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for null url'
}

fn test_http_request_wrong_type_float() {
	fn_http_request([VrlValue(f64(1.5))]) or {
		assert err.msg().contains('url must be a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for float url'
}

fn test_http_request_wrong_type_array() {
	fn_http_request([VrlValue([]VrlValue{})]) or {
		assert err.msg().contains('url must be a string'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for array url'
}

fn test_http_request_empty_url() {
	fn_http_request([VrlValue('')]) or {
		assert err.msg().contains('url must not be empty'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for empty url'
}

fn test_http_request_unsupported_method() {
	fn_http_request([VrlValue('http://localhost'), VrlValue('FOOBAR')]) or {
		assert err.msg().contains('Unsupported HTTP method: FOOBAR'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for unsupported method'
}

fn test_http_request_unsupported_method_trace() {
	fn_http_request([VrlValue('http://localhost'), VrlValue('TRACE')]) or {
		assert err.msg().contains('Unsupported HTTP method: TRACE'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for TRACE method'
}

fn test_http_request_unsupported_method_connect() {
	fn_http_request([VrlValue('http://localhost'), VrlValue('CONNECT')]) or {
		assert err.msg().contains('Unsupported HTTP method: CONNECT'), 'unexpected: ${err}'
		return
	}
	assert false, 'expected error for CONNECT method'
}

fn test_http_request_method_case_insensitive() {
	// "get" should be uppercased to "GET" internally
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('get')]) or {
		assert !err.msg().contains('Unsupported HTTP method'),
			'lowercase method should be accepted: ${err}'
		return
	}
}

fn test_http_request_method_mixed_case() {
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('Post')]) or {
		assert !err.msg().contains('Unsupported HTTP method'),
			'mixed-case method should be accepted: ${err}'
		return
	}
}

fn test_http_request_default_method_get() {
	// Only URL arg — should default to GET
	fn_http_request([VrlValue('http://192.0.2.1:1')]) or {
		assert !err.msg().contains('Unsupported HTTP method'),
			'default method should be GET: ${err}'
		return
	}
}

fn test_http_request_non_string_method_defaults_to_get() {
	// When method arg is not a string, it should default to GET
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue(i64(99))]) or {
		assert !err.msg().contains('Unsupported HTTP method'),
			'non-string method should default to GET: ${err}'
		return
	}
}

fn test_http_request_method_put() {
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('PUT')]) or {
		assert !err.msg().contains('Unsupported HTTP method'),
			'PUT should be supported: ${err}'
		return
	}
}

fn test_http_request_method_delete() {
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('DELETE')]) or {
		assert !err.msg().contains('Unsupported HTTP method'),
			'DELETE should be supported: ${err}'
		return
	}
}

fn test_http_request_method_patch() {
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('PATCH')]) or {
		assert !err.msg().contains('Unsupported HTTP method'),
			'PATCH should be supported: ${err}'
		return
	}
}

fn test_http_request_method_head() {
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('HEAD')]) or {
		assert !err.msg().contains('Unsupported HTTP method'),
			'HEAD should be supported: ${err}'
		return
	}
}

fn test_http_request_method_options() {
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('OPTIONS')]) or {
		assert !err.msg().contains('Unsupported HTTP method'),
			'OPTIONS should be supported: ${err}'
		return
	}
}

fn test_http_request_with_headers_object() {
	// Create an ObjectMap with headers
	mut om := new_object_map()
	om.set('Content-Type', VrlValue('application/json'))
	om.set('Authorization', VrlValue('Bearer token123'))

	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('POST'), VrlValue(om)]) or {
		// Should fail with connection error, not header error
		assert err.msg().contains('failed') || err.msg().contains('HTTP'),
			'expected connection failure, not header error: ${err}'
		return
	}
}

fn test_http_request_non_object_headers_ignored() {
	// When headers arg is not an ObjectMap, it should be silently ignored
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('GET'), VrlValue('not-an-object')]) or {
		assert !err.msg().contains('Invalid header'),
			'non-object headers should be ignored: ${err}'
		return
	}
}

fn test_http_request_non_string_body_defaults_to_empty() {
	// When body arg is not a string, it should default to empty
	mut om := new_object_map()
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('POST'), VrlValue(om),
		VrlValue(i64(42))]) or {
		assert !err.msg().contains('body'),
			'non-string body should default to empty: ${err}'
		return
	}
}

fn test_http_request_with_string_body() {
	mut om := new_object_map()
	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('POST'), VrlValue(om),
		VrlValue('{"key":"value"}')]) or {
		assert err.msg().contains('failed') || err.msg().contains('HTTP'),
			'expected connection failure: ${err}'
		return
	}
}

fn test_http_request_unreachable_host() {
	// RFC 5737 TEST-NET address — should time out or refuse connection
	fn_http_request([VrlValue('http://192.0.2.1:1')]) or {
		assert err.msg().contains('HTTP request failed'), 'expected HTTP failure: ${err}'
		return
	}
	// If it somehow succeeds, acceptable
}

fn test_http_request_header_with_non_string_value() {
	// Header values that are not strings should be converted via vrl_to_string
	mut om := new_object_map()
	om.set('X-Count', VrlValue(i64(42)))

	fn_http_request([VrlValue('http://192.0.2.1:1'), VrlValue('GET'), VrlValue(om)]) or {
		// Should not fail due to header type — should fail with connection error
		assert !err.msg().contains('Invalid header'),
			'non-string header value should be converted: ${err}'
		return
	}
}
