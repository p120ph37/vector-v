module vrl

// Tests for parse functions in vrllib_parse.v and vrllib_parse_new.v
// Targets uncovered lines to increase code coverage.

// Helper to pass a string input via the event object and parse it
fn parse_via_obj(prog string, input string) !VrlValue {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(input)
	return execute(prog, obj)
}

// ============================================================================
// parse_key_value tests
// ============================================================================

fn test_parse_key_value_basic() {
	cases := [
		['parse_key_value!("key1=val1 key2=val2")', '{"key1":"val1","key2":"val2"}'],
		['parse_key_value!("name=John age=30 city=NYC")', '{"age":"30","city":"NYC","name":"John"}'],
	]
	for c in cases {
		result := execute(c[0], map[string]VrlValue{}) or { panic('${c[0]}: ${err}') }
		assert vrl_to_json(result) == c[1], '${c[0]}: expected ${c[1]}, got ${vrl_to_json(result)}'
	}
}

fn test_parse_key_value_custom_delimiters() {
	cases := [
		['parse_key_value!("key1:val1 key2:val2", key_value_delimiter: ":")', '{"key1":"val1","key2":"val2"}'],
		['parse_key_value!("key1=val1&key2=val2", field_delimiter: "&")', '{"key1":"val1","key2":"val2"}'],
		['parse_key_value!("key1:val1|key2:val2", key_value_delimiter: ":", field_delimiter: "|")', '{"key1":"val1","key2":"val2"}'],
	]
	for c in cases {
		result := execute(c[0], map[string]VrlValue{}) or { panic('${c[0]}: ${err}') }
		assert vrl_to_json(result) == c[1], '${c[0]}: expected ${c[1]}, got ${vrl_to_json(result)}'
	}
}

fn test_parse_key_value_quoted_values() {
	result := parse_via_obj('parse_key_value!(.input)', 'key1="hello world" key2=simple') or {
		panic('parse_key_value quoted: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"key1":"hello world"'), 'expected quoted value, got ${j}'
	assert j.contains('"key2":"simple"'), 'expected simple value, got ${j}'
}

fn test_parse_key_value_standalone_keys() {
	result := execute('parse_key_value!("key1=val1 standalone key2=val2")', map[string]VrlValue{}) or {
		panic('parse_key_value standalone: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"standalone":true'), 'expected standalone key as true, got ${j}'
}

fn test_parse_key_value_empty_input() {
	result := execute('parse_key_value!("")', map[string]VrlValue{}) or {
		panic('parse_key_value empty: ${err}')
	}
	j := vrl_to_json(result)
	assert j == '{}', 'expected empty object for empty input'
}

// ============================================================================
// parse_json tests (edge cases)
// ============================================================================

fn test_parse_json_nested() {
	result := parse_via_obj('parse_json!(.input)', '{"a":{"b":1}}') or {
		panic('parse_json nested: ${err}')
	}
	assert vrl_to_json(result) == '{"a":{"b":1}}', 'nested mismatch: ${vrl_to_json(result)}'
}

fn test_parse_json_array() {
	result := execute('parse_json!("[1,2,3]")', map[string]VrlValue{}) or {
		panic('parse_json array: ${err}')
	}
	assert vrl_to_json(result) == '[1,2,3]'
}

fn test_parse_json_scalars() {
	cases := [
		['parse_json!("null")', 'null'],
		['parse_json!("true")', 'true'],
		['parse_json!("false")', 'false'],
		['parse_json!("42")', '42'],
		['parse_json!("3.14")', '3.14'],
	]
	for c in cases {
		result := execute(c[0], map[string]VrlValue{}) or { panic('${c[0]}: ${err}') }
		assert vrl_to_json(result) == c[1], '${c[0]}: expected ${c[1]}, got ${vrl_to_json(result)}'
	}
}

fn test_parse_json_deeply_nested() {
	result := parse_via_obj('parse_json!(.input)', '{"a":{"b":{"c":[1,2]}}}') or {
		panic('parse_json deeply nested: ${err}')
	}
	assert vrl_to_json(result) == '{"a":{"b":{"c":[1,2]}}}', 'deeply nested mismatch'
}

fn test_parse_json_error_on_invalid() {
	execute('parse_json!("not json at all")', map[string]VrlValue{}) or {
		assert err.msg().len > 0
		return
	}
	panic('expected parse_json to fail on invalid input')
}

// ============================================================================
// parse_int tests
// ============================================================================

fn test_parse_int_decimal() {
	result := execute('parse_int!("42")', map[string]VrlValue{}) or { panic('parse_int: ${err}') }
	assert vrl_to_json(result) == '42'
}

fn test_parse_int_hex() {
	result := execute('parse_int!("0xff")', map[string]VrlValue{}) or {
		panic('parse_int hex: ${err}')
	}
	assert vrl_to_json(result) == '255'
}

fn test_parse_int_octal() {
	result := execute('parse_int!("0o77")', map[string]VrlValue{}) or {
		panic('parse_int octal: ${err}')
	}
	assert vrl_to_json(result) == '63'
}

fn test_parse_int_binary() {
	result := execute('parse_int!("0b1010")', map[string]VrlValue{}) or {
		panic('parse_int binary: ${err}')
	}
	assert vrl_to_json(result) == '10'
}

fn test_parse_int_negative() {
	result := execute('parse_int!("-123")', map[string]VrlValue{}) or {
		panic('parse_int negative: ${err}')
	}
	assert vrl_to_json(result) == '-123'
}

fn test_parse_int_with_base() {
	result := execute('parse_int!("ff", base: 16)', map[string]VrlValue{}) or {
		panic('parse_int base16: ${err}')
	}
	assert vrl_to_json(result) == '255'
}

// ============================================================================
// parse_float tests
// ============================================================================

fn test_parse_float_basic() {
	result := execute('parse_float!("3.14")', map[string]VrlValue{}) or {
		panic('parse_float: ${err}')
	}
	assert vrl_to_json(result) == '3.14'
}

fn test_parse_float_integer_input() {
	result := execute('parse_float!("42")', map[string]VrlValue{}) or {
		panic('parse_float int: ${err}')
	}
	j := vrl_to_json(result)
	assert j == '42.0' || j == '42', 'parse_float int: got ${j}'
}

// ============================================================================
// parse_url tests
// ============================================================================

fn test_parse_url_basic() {
	result := execute('parse_url!("https://example.com/path?key=value#frag")', map[string]VrlValue{}) or {
		panic('parse_url: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"scheme":"https"'), 'expected scheme https, got ${j}'
	assert j.contains('"host":"example.com"'), 'expected host, got ${j}'
	assert j.contains('"path":"/path"'), 'expected path, got ${j}'
	assert j.contains('"fragment":"frag"'), 'expected fragment, got ${j}'
}

fn test_parse_url_with_port() {
	result := execute('parse_url!("http://localhost:8080/api")', map[string]VrlValue{}) or {
		panic('parse_url port: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"port":8080'), 'expected port 8080, got ${j}'
	assert j.contains('"host":"localhost"'), 'expected host localhost, got ${j}'
}

fn test_parse_url_with_userinfo() {
	result := execute('parse_url!("http://user:pass@example.com/")', map[string]VrlValue{}) or {
		panic('parse_url userinfo: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"username":"user"'), 'expected username, got ${j}'
	assert j.contains('"password":"pass"'), 'expected password, got ${j}'
}

fn test_parse_url_with_query_params() {
	result := execute('parse_url!("https://example.com/?a=1&b=2")', map[string]VrlValue{}) or {
		panic('parse_url query: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a":"1"'), 'expected query param a, got ${j}'
	assert j.contains('"b":"2"'), 'expected query param b, got ${j}'
}

// ============================================================================
// parse_query_string tests
// ============================================================================

fn test_parse_query_string_basic() {
	result := execute('parse_query_string!("foo=bar&baz=qux")', map[string]VrlValue{}) or {
		panic('parse_query_string: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"foo":"bar"'), 'expected foo=bar, got ${j}'
	assert j.contains('"baz":"qux"'), 'expected baz=qux, got ${j}'
}

fn test_parse_query_string_with_leading_question_mark() {
	result := execute('parse_query_string!("?a=1&b=2")', map[string]VrlValue{}) or {
		panic('parse_query_string leading ?: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a":"1"'), 'expected a=1, got ${j}'
}

fn test_parse_query_string_encoded() {
	result := execute('parse_query_string!("key=hello%20world")', map[string]VrlValue{}) or {
		panic('parse_query_string encoded: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"key":"hello world"'), 'expected decoded value, got ${j}'
}

fn test_parse_query_string_empty() {
	result := execute('parse_query_string!("")', map[string]VrlValue{}) or {
		panic('parse_query_string empty: ${err}')
	}
	j := vrl_to_json(result)
	assert j == '{}', 'expected empty object'
}

fn test_parse_query_string_no_value() {
	result := execute('parse_query_string!("key")', map[string]VrlValue{}) or {
		panic('parse_query_string no value: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"key":""'), 'expected key with empty value, got ${j}'
}

// ============================================================================
// parse_tokens tests
// ============================================================================

fn test_parse_tokens_basic() {
	result := execute('parse_tokens!("hello world")', map[string]VrlValue{}) or {
		panic('parse_tokens: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"hello"'), 'expected hello token, got ${j}'
	assert j.contains('"world"'), 'expected world token, got ${j}'
}

fn test_parse_tokens_quoted() {
	result := parse_via_obj('parse_tokens!(.input)',
		'217.132.10.131 - - [20/Jun/2019:07:45:25] "GET /index.html HTTP/1.1" 200 2000') or {
		panic('parse_tokens quoted: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"217.132.10.131"'), 'expected IP token, got ${j}'
}

fn test_parse_tokens_brackets() {
	result := execute('parse_tokens!("data [bracketed content] more")', map[string]VrlValue{}) or {
		panic('parse_tokens brackets: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"bracketed content"'), 'expected bracketed token, got ${j}'
}

// ============================================================================
// parse_duration tests
// ============================================================================

fn test_parse_duration_seconds() {
	result := execute('parse_duration!("1s", "ms")', map[string]VrlValue{}) or {
		panic('parse_duration s->ms: ${err}')
	}
	assert vrl_to_json(result) == '1000.0', 'expected 1000.0, got ${vrl_to_json(result)}'
}

fn test_parse_duration_minutes() {
	result := execute('parse_duration!("2m", "s")', map[string]VrlValue{}) or {
		panic('parse_duration m->s: ${err}')
	}
	assert vrl_to_json(result) == '120.0', 'expected 120.0, got ${vrl_to_json(result)}'
}

fn test_parse_duration_hours() {
	result := execute('parse_duration!("1h", "m")', map[string]VrlValue{}) or {
		panic('parse_duration h->m: ${err}')
	}
	assert vrl_to_json(result) == '60.0', 'expected 60.0, got ${vrl_to_json(result)}'
}

fn test_parse_duration_nanoseconds() {
	result := execute('parse_duration!("1000000ns", "ms")', map[string]VrlValue{}) or {
		panic('parse_duration ns->ms: ${err}')
	}
	assert vrl_to_json(result) == '1.0', 'expected 1.0, got ${vrl_to_json(result)}'
}

fn test_parse_duration_microseconds() {
	result := execute('parse_duration!("1000us", "ms")', map[string]VrlValue{}) or {
		panic('parse_duration us->ms: ${err}')
	}
	assert vrl_to_json(result) == '1.0', 'expected 1.0, got ${vrl_to_json(result)}'
}

fn test_parse_duration_days() {
	result := execute('parse_duration!("1d", "h")', map[string]VrlValue{}) or {
		panic('parse_duration d->h: ${err}')
	}
	assert vrl_to_json(result) == '24.0', 'expected 24.0, got ${vrl_to_json(result)}'
}

fn test_parse_duration_invalid() {
	execute('parse_duration!("not_a_duration", "s")', map[string]VrlValue{}) or {
		assert err.msg().len > 0
		return
	}
	panic('expected parse_duration to fail on invalid input')
}

// ============================================================================
// parse_csv tests
// ============================================================================

fn test_parse_csv_basic() {
	result := execute('parse_csv!("a,b,c")', map[string]VrlValue{}) or {
		panic('parse_csv: ${err}')
	}
	assert vrl_to_json(result) == '["a","b","c"]', 'got ${vrl_to_json(result)}'
}

fn test_parse_csv_quoted_fields() {
	result := parse_via_obj('parse_csv!(.input)', '"hello, world",b,c') or {
		panic('parse_csv quoted: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"hello, world"'), 'expected quoted field, got ${j}'
}

// ============================================================================
// parse_syslog tests
// ============================================================================

fn test_parse_syslog_rfc5424() {
	result := parse_via_obj('parse_syslog!(.input)',
		'<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 - BOM An application event log entry') or {
		panic('parse_syslog rfc5424: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"appname":"evntslog"'), 'expected appname, got ${j}'
	assert j.contains('"hostname":"mymachine.example.com"'), 'expected hostname, got ${j}'
	assert j.contains('"severity":"notice"'), 'expected severity, got ${j}'
	assert j.contains('"facility":"local4"'), 'expected facility, got ${j}'
	assert j.contains('"msgid":"ID47"'), 'expected msgid, got ${j}'
}

fn test_parse_syslog_rfc3164() {
	result := parse_via_obj('parse_syslog!(.input)',
		'<34>Oct 11 22:14:15 mymachine su: message here') or {
		panic('parse_syslog rfc3164: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"appname":"su"'), 'expected appname su, got ${j}'
	assert j.contains('"hostname":"mymachine"'), 'expected hostname, got ${j}'
}

// ============================================================================
// parse_common_log tests
// ============================================================================

fn test_parse_common_log_basic() {
	result := parse_via_obj('parse_common_log!(.input)',
		'127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326') or {
		panic('parse_common_log: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"host":"127.0.0.1"'), 'expected host, got ${j}'
	assert j.contains('"user":"frank"'), 'expected user, got ${j}'
	assert j.contains('"method":"GET"'), 'expected method, got ${j}'
	assert j.contains('"path":"/apache_pb.gif"'), 'expected path, got ${j}'
	assert j.contains('"protocol":"HTTP/1.0"'), 'expected protocol, got ${j}'
	assert j.contains('"status":200'), 'expected status 200, got ${j}'
	assert j.contains('"size":2326'), 'expected size 2326, got ${j}'
}

fn test_parse_common_log_null_fields() {
	result := parse_via_obj('parse_common_log!(.input)',
		'10.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "POST /api HTTP/1.1" 201 -') or {
		panic('parse_common_log null: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"user":null'), 'expected null user, got ${j}'
	assert j.contains('"size":null'), 'expected null size, got ${j}'
}

// ============================================================================
// parse_apache_log tests
// ============================================================================

fn test_parse_apache_log_common() {
	result := parse_via_obj('parse_apache_log!(.input, "common")',
		'127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326') or {
		panic('parse_apache_log common: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"host":"127.0.0.1"'), 'expected host, got ${j}'
	assert j.contains('"method":"GET"'), 'expected method, got ${j}'
	assert j.contains('"status":200'), 'expected status, got ${j}'
}

fn test_parse_apache_log_combined() {
	result := parse_via_obj('parse_apache_log!(.input, "combined")',
		'127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /index.html HTTP/1.0" 200 2326 "http://www.example.com/start.html" "Mozilla/5.0"') or {
		panic('parse_apache_log combined: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"host":"127.0.0.1"'), 'expected host, got ${j}'
	assert j.contains('"agent":"Mozilla/5.0"'), 'expected agent, got ${j}'
}

fn test_parse_apache_log_invalid_format() {
	execute('parse_apache_log!("some log", "invalid_format")', map[string]VrlValue{}) or {
		assert err.msg().contains('unknown format')
		return
	}
	panic('expected parse_apache_log to fail on invalid format')
}

// ============================================================================
// parse_nginx_log tests
// ============================================================================

fn test_parse_nginx_log_combined() {
	result := parse_via_obj('parse_nginx_log!(.input, "combined")',
		'172.17.0.1 - alice [01/Apr/2021:12:00:00 +0000] "GET /api HTTP/1.1" 200 612 "http://example.com" "curl/7.68"') or {
		panic('parse_nginx_log combined: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"client":"172.17.0.1"'), 'expected client, got ${j}'
	assert j.contains('"status":200'), 'expected status, got ${j}'
	assert j.contains('"agent":"curl/7.68"'), 'expected agent, got ${j}'
}

fn test_parse_nginx_log_error() {
	result := parse_via_obj('parse_nginx_log!(.input, "error")',
		'2021/04/01 12:34:56 [error] 12345#0: *100 message here, client: 10.0.0.1, server: example.com, request: "GET /fail HTTP/1.1"') or {
		panic('parse_nginx_log error: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"severity":"error"'), 'expected severity, got ${j}'
	assert j.contains('"pid":12345'), 'expected pid, got ${j}'
}

fn test_parse_nginx_log_invalid_format() {
	execute('parse_nginx_log!("log line", "badformat")', map[string]VrlValue{}) or {
		assert err.msg().contains('unknown format')
		return
	}
	panic('expected parse_nginx_log to fail on invalid format')
}

// ============================================================================
// parse_aws_vpc_flow_log tests
// ============================================================================

fn test_parse_aws_vpc_flow_log_basic() {
	result := parse_via_obj('parse_aws_vpc_flow_log!(.input)',
		'2 123456789012 eni-abc12345 10.0.0.1 10.0.0.2 12345 80 6 10 840 1616729292 1616729349 ACCEPT OK') or {
		panic('parse_aws_vpc_flow_log: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"version":2'), 'expected version 2, got ${j}'
	assert j.contains('"srcaddr":"10.0.0.1"'), 'expected srcaddr, got ${j}'
	assert j.contains('"dstaddr":"10.0.0.2"'), 'expected dstaddr, got ${j}'
	assert j.contains('"srcport":12345'), 'expected srcport, got ${j}'
	assert j.contains('"dstport":80'), 'expected dstport, got ${j}'
	assert j.contains('"action":"ACCEPT"'), 'expected action, got ${j}'
}

fn test_parse_aws_vpc_flow_log_reject() {
	result := parse_via_obj('parse_aws_vpc_flow_log!(.input)',
		'2 123456789012 eni-abc12345 203.0.113.12 172.31.16.139 46789 3389 6 20 4249 1418530010 1418530070 REJECT OK') or {
		panic('parse_aws_vpc_flow_log reject: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"action":"REJECT"'), 'expected REJECT, got ${j}'
	assert j.contains('"protocol":6'), 'expected protocol, got ${j}'
}

// ============================================================================
// parse_cef tests
// ============================================================================

fn test_parse_cef_basic() {
	result := parse_via_obj('parse_cef!(.input)',
		'CEF:0|Security|Product|1.0|100|Login Attempt|5|src=10.0.0.1 dst=10.0.0.2') or {
		panic('parse_cef: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"cefVersion":"0"'), 'expected cefVersion, got ${j}'
	assert j.contains('"deviceVendor":"Security"'), 'expected deviceVendor, got ${j}'
	assert j.contains('"deviceProduct":"Product"'), 'expected deviceProduct, got ${j}'
	assert j.contains('"severity":"5"'), 'expected severity, got ${j}'
	assert j.contains('"src":"10.0.0.1"'), 'expected src extension, got ${j}'
	assert j.contains('"dst":"10.0.0.2"'), 'expected dst extension, got ${j}'
}

fn test_parse_cef_no_extensions() {
	result := parse_via_obj('parse_cef!(.input)',
		'CEF:0|Vendor|Product|1.0|100|Event Name|3|') or {
		panic('parse_cef no ext: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"name":"Event Name"'), 'expected name, got ${j}'
}

fn test_parse_cef_invalid() {
	execute('parse_cef!("not a CEF message")', map[string]VrlValue{}) or {
		assert err.msg().contains('CEF')
		return
	}
	panic('expected parse_cef to fail on non-CEF input')
}

// ============================================================================
// parse_klog tests
// ============================================================================

fn test_parse_klog_info() {
	result := parse_via_obj('parse_klog!(.input)',
		'I0505 17:59:40.692994   28133 miscellaneous.go:42] some message') or {
		panic('parse_klog info: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"info"'), 'expected level info, got ${j}'
	assert j.contains('"file":"miscellaneous.go"'), 'expected file, got ${j}'
	assert j.contains('"line":42'), 'expected line 42, got ${j}'
	assert j.contains('"message":"some message"'), 'expected message, got ${j}'
	assert j.contains('"id":28133'), 'expected id, got ${j}'
}

fn test_parse_klog_error() {
	result := parse_via_obj('parse_klog!(.input)',
		'E1225 08:15:33.000000       1 main.go:100] fatal error occurred') or {
		panic('parse_klog error: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"error"'), 'expected level error, got ${j}'
	assert j.contains('"message":"fatal error occurred"'), 'expected message, got ${j}'
}

fn test_parse_klog_warning() {
	result := parse_via_obj('parse_klog!(.input)',
		'W0101 00:00:00.000000       1 file.go:1] warning msg') or {
		panic('parse_klog warning: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"warning"'), 'expected level warning, got ${j}'
}

fn test_parse_klog_invalid() {
	execute('parse_klog!("not a klog line")', map[string]VrlValue{}) or {
		assert err.msg().len > 0
		return
	}
	panic('expected parse_klog to fail on invalid input')
}

// ============================================================================
// parse_glog tests
// ============================================================================

fn test_parse_glog_info() {
	result := parse_via_obj('parse_glog!(.input)',
		'I0505 17:59:40.692994   28133 miscellaneous.go:42] some message') or {
		panic('parse_glog info: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"info"'), 'expected level info, got ${j}'
	assert j.contains('"file":"miscellaneous.go"'), 'expected file, got ${j}'
	assert j.contains('"line":42'), 'expected line 42, got ${j}'
	assert j.contains('"message":"some message"'), 'expected message, got ${j}'
}

fn test_parse_glog_fatal() {
	result := parse_via_obj('parse_glog!(.input)',
		'F1225 08:15:33.123456       1 main.go:10] crash') or {
		panic('parse_glog fatal: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"fatal"'), 'expected level fatal, got ${j}'
	assert j.contains('"message":"crash"'), 'expected message, got ${j}'
}

fn test_parse_glog_invalid() {
	parse_via_obj('parse_glog!(.input)',
		'X0101 00:00:00.000000   1 f.go:1] msg') or {
		assert err.msg().len > 0
		return
	}
	panic('expected parse_glog to fail on unknown level')
}

// ============================================================================
// parse_linux_authorization tests
// ============================================================================

fn test_parse_linux_authorization_basic() {
	result := parse_via_obj('parse_linux_authorization!(.input)',
		'Mar  5 14:17:01 myhost CRON[1234]: pam_unix(cron:session): session opened') or {
		panic('parse_linux_authorization: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"hostname":"myhost"'), 'expected hostname, got ${j}'
	assert j.contains('"appname":"CRON"'), 'expected appname, got ${j}'
}

// ============================================================================
// parse_logfmt tests
// ============================================================================

fn test_parse_logfmt_basic() {
	result := parse_via_obj('parse_logfmt!(.input)',
		'level=info msg="hello world" ts=2021-01-01') or {
		panic('parse_logfmt: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"info"'), 'expected level, got ${j}'
	assert j.contains('"msg":"hello world"'), 'expected msg, got ${j}'
	assert j.contains('"ts":"2021-01-01"'), 'expected ts, got ${j}'
}

fn test_parse_logfmt_no_value() {
	result := execute('parse_logfmt!("flag key=val")', map[string]VrlValue{}) or {
		panic('parse_logfmt no value: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"key":"val"'), 'expected key=val, got ${j}'
}

// ============================================================================
// parse_aws_alb_log tests
// ============================================================================

fn test_parse_aws_alb_log_basic() {
	result := parse_via_obj('parse_aws_alb_log!(.input)',
		'http 2018-07-02T22:23:00.186641Z app/my-loadbalancer/50dc6c495c0c9188 192.168.131.39:2817 10.0.0.1:80 0.000 0.001 0.000 200 200 34 366 "GET http://www.example.com:80/ HTTP/1.1" "curl/7.46.0" ECDHE-RSA-AES128-GCM-SHA256 TLSv1.2 arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/my-target/5678 "Root=1-58337262-36d228ad5d99923122bbe354" "www.example.com" "arn:aws:acm:us-east-2:123456789012:certificate/12345678-1234-1234-1234-123456789012" 0 2018-07-02T22:22:48.364000Z "forward" "-" "-"') or {
		panic('parse_aws_alb_log: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"type":"http"'), 'expected type http, got ${j}'
	assert j.contains('"elb_status_code":200'), 'expected elb_status_code, got ${j}'
	assert j.contains('"request_method":"GET"'), 'expected request_method, got ${j}'
}

// ============================================================================
// parse_ruby_hash tests
// ============================================================================

fn test_parse_ruby_hash_basic() {
	result := parse_via_obj('parse_ruby_hash!(.input)', '{"key" => "value"}') or {
		panic('parse_ruby_hash: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"key":"value"'), 'expected key:value, got ${j}'
}

fn test_parse_ruby_hash_symbol_keys() {
	result := parse_via_obj('parse_ruby_hash!(.input)', '{:name => "John", :age => 30}') or {
		panic('parse_ruby_hash symbols: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"name":"John"'), 'expected name, got ${j}'
}

fn test_parse_ruby_hash_nested() {
	result := parse_via_obj('parse_ruby_hash!(.input)', '{"a" => {"b" => 1}}') or {
		panic('parse_ruby_hash nested: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a":{'), 'expected nested object, got ${j}'
}

fn test_parse_ruby_hash_nil() {
	result := parse_via_obj('parse_ruby_hash!(.input)', '{"key" => nil}') or {
		panic('parse_ruby_hash nil: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"key":null'), 'expected null value, got ${j}'
}

fn test_parse_ruby_hash_array() {
	result := parse_via_obj('parse_ruby_hash!(.input)', '{"arr" => [1, 2, 3]}') or {
		panic('parse_ruby_hash array: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"arr":['), 'expected array, got ${j}'
}

fn test_parse_ruby_hash_booleans() {
	result := parse_via_obj('parse_ruby_hash!(.input)', '{"t" => true, "f" => false}') or {
		panic('parse_ruby_hash bools: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"t":true'), 'expected true, got ${j}'
	assert j.contains('"f":false'), 'expected false, got ${j}'
}

fn test_parse_ruby_hash_invalid() {
	parse_via_obj('parse_ruby_hash!(.input)', 'not a hash') or {
		assert err.msg().len > 0
		return
	}
	panic('expected parse_ruby_hash to fail on invalid input')
}

// ============================================================================
// parse_user_agent tests
// ============================================================================

fn test_parse_user_agent_chrome() {
	result := parse_via_obj('parse_user_agent!(.input)',
		'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36') or {
		panic('parse_user_agent chrome: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"browser":{'), 'expected browser object, got ${j}'
	assert j.contains('"os":{'), 'expected os object, got ${j}'
	assert j.contains('"device":{'), 'expected device object, got ${j}'
}

fn test_parse_user_agent_enriched() {
	result := parse_via_obj('parse_user_agent!(.input, mode: "enriched")',
		'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36') or {
		panic('parse_user_agent enriched: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"browser":{'), 'expected browser in enriched mode, got ${j}'
}

// ============================================================================
// parse_influxdb tests
// ============================================================================

fn test_parse_influxdb_basic() {
	result := parse_via_obj('parse_influxdb!(.input)',
		'cpu,host=serverA,region=us-west usage_idle=99.0 1609459200000000000') or {
		panic('parse_influxdb: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"name":"cpu_usage_idle"'), 'expected metric name, got ${j}'
	assert j.contains('"kind":"absolute"'), 'expected kind, got ${j}'
}

fn test_parse_influxdb_multiple_fields() {
	result := parse_via_obj('parse_influxdb!(.input)',
		'mem,host=serverA used=1024i,free=2048i') or {
		panic('parse_influxdb multi: ${err}')
	}
	j := vrl_to_json(result)
	assert j.starts_with('['), 'expected array of metrics, got ${j}'
}

fn test_parse_influxdb_empty() {
	result := execute('parse_influxdb!("")', map[string]VrlValue{}) or {
		panic('parse_influxdb empty: ${err}')
	}
	assert vrl_to_json(result) == '[]', 'expected empty array'
}

// ============================================================================
// parse_bytes tests
// ============================================================================

fn test_parse_bytes_basic() {
	result := execute('parse_bytes!("1KB")', map[string]VrlValue{}) or {
		panic('parse_bytes: ${err}')
	}
	j := vrl_to_json(result)
	assert j == '1024.0', 'expected 1024.0, got ${j}'
}

fn test_parse_bytes_megabytes() {
	result := execute('parse_bytes!("1MB")', map[string]VrlValue{}) or {
		panic('parse_bytes MB: ${err}')
	}
	j := vrl_to_json(result)
	assert j == '1048576.0', 'expected 1048576.0, got ${j}'
}

// ============================================================================
// format_int tests
// ============================================================================

fn test_format_int_hex() {
	result := execute('format_int(255, base: 16)', map[string]VrlValue{}) or {
		panic('format_int hex: ${err}')
	}
	assert vrl_to_json(result) == '"ff"', 'expected "ff", got ${vrl_to_json(result)}'
}

fn test_format_int_binary() {
	result := execute('format_int(10, base: 2)', map[string]VrlValue{}) or {
		panic('format_int bin: ${err}')
	}
	assert vrl_to_json(result) == '"1010"', 'expected "1010", got ${vrl_to_json(result)}'
}
