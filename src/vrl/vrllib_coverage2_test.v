module vrl

// Comprehensive data-driven tests for VRL vrllib parsing, misc, redact, random, and punycode functions.

// ============================================================================
// parse_regex
// ============================================================================

fn test_parse_regex_named_groups() {
	result := execute('parse_regex!("2023-01-15 ERROR something failed", r\'(?P<date>\\d{4}-\\d{2}-\\d{2})\\s+(?P<level>\\w+)\\s+(?P<msg>.+)\')', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"date":"2023-01-15"'), 'parse_regex date: got ${j}'
	assert j.contains('"level":"ERROR"'), 'parse_regex level: got ${j}'
	assert j.contains('"msg":"something failed"'), 'parse_regex msg: got ${j}'
}

fn test_parse_regex_no_match_errors() {
	execute('parse_regex!("hello", r\'(?P<num>\\d+)\')', map[string]VrlValue{}) or {
		assert err.msg().contains('no match')
		return
	}
	panic('expected error for non-matching regex')
}

fn test_parse_regex_numeric_groups() {
	result := execute('parse_regex!("abc123", r\'([a-z]+)(\\d+)\', numeric_groups: true)', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"0":"abc123"'), 'parse_regex numeric group 0: got ${j}'
	assert j.contains('"1":"abc"'), 'parse_regex numeric group 1: got ${j}'
	assert j.contains('"2":"123"'), 'parse_regex numeric group 2: got ${j}'
}

// ============================================================================
// parse_regex_all
// ============================================================================

fn test_parse_regex_all_basic() {
	result := execute('parse_regex_all!("foo123bar456baz789", r\'(?P<word>[a-z]+)(?P<num>\\d+)\')', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"word":"foo"'), 'parse_regex_all first word: got ${j}'
	assert j.contains('"num":"123"'), 'parse_regex_all first num: got ${j}'
	assert j.contains('"word":"bar"'), 'parse_regex_all second word: got ${j}'
	assert j.contains('"num":"789"'), 'parse_regex_all third num: got ${j}'
}

fn test_parse_regex_all_no_match_returns_empty() {
	result := execute('parse_regex_all!("hello world", r\'(?P<digit>\\d+)\')', map[string]VrlValue{}) or {
		// Some implementations might return empty array; check
		panic(err)
	}
	j := vrl_to_json(result)
	assert j == '[]', 'parse_regex_all no match should be empty: got ${j}'
}

// ============================================================================
// parse_csv
// ============================================================================

fn test_parse_csv_basic() {
	result := execute('parse_csv!("foo,bar,baz")', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j == '["foo","bar","baz"]', 'parse_csv basic: got ${j}'
}

fn test_parse_csv_with_custom_delimiter() {
	result := execute('parse_csv!("a;b;c", ";")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j == '["a","b","c"]', 'parse_csv custom delim: got ${j}'
}

fn test_parse_csv_empty_fields() {
	result := execute('parse_csv!("a,,c")', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j == '["a","","c"]', 'parse_csv empty field: got ${j}'
}

// ============================================================================
// parse_key_value
// ============================================================================

fn test_parse_key_value_default() {
	mut obj := map[string]VrlValue{}
	obj['message'] = VrlValue('level=info count=42 status=ok')
	result := execute('parse_key_value!(.message)', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"info"'), 'parse_kv level: got ${j}'
	assert j.contains('"count":"42"'), 'parse_kv count: got ${j}'
	assert j.contains('"status":"ok"'), 'parse_kv status: got ${j}'
}

fn test_parse_key_value_custom_delimiters() {
	result := execute('parse_key_value!("level:info|msg:hello", ":", "|")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"info"'), 'parse_kv custom level: got ${j}'
	assert j.contains('"msg":"hello"'), 'parse_kv custom msg: got ${j}'
}

// ============================================================================
// parse_url
// ============================================================================

fn test_parse_url_full() {
	result := execute('parse_url!("https://user:pass@example.com:8080/path/to/page?key=value&foo=bar#section")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"scheme":"https"'), 'parse_url scheme: got ${j}'
	assert j.contains('"host":"example.com"'), 'parse_url host: got ${j}'
	assert j.contains('"port":8080'), 'parse_url port: got ${j}'
	assert j.contains('"path":"/path/to/page"'), 'parse_url path: got ${j}'
	assert j.contains('"username":"user"'), 'parse_url username: got ${j}'
	assert j.contains('"password":"pass"'), 'parse_url password: got ${j}'
	assert j.contains('"fragment":"section"'), 'parse_url fragment: got ${j}'
}

fn test_parse_url_simple() {
	result := execute('parse_url!("http://example.com")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"scheme":"http"'), 'parse_url simple scheme: got ${j}'
	assert j.contains('"host":"example.com"'), 'parse_url simple host: got ${j}'
}

// ============================================================================
// parse_query_string
// ============================================================================

fn test_parse_query_string_basic() {
	result := execute('parse_query_string!("foo=bar&baz=qux")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"foo":"bar"'), 'parse_qs foo: got ${j}'
	assert j.contains('"baz":"qux"'), 'parse_qs baz: got ${j}'
}

fn test_parse_query_string_with_leading_question_mark() {
	result := execute('parse_query_string!("?a=1&b=2")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"a":"1"'), 'parse_qs with ?: got ${j}'
	assert j.contains('"b":"2"'), 'parse_qs with ? b: got ${j}'
}

fn test_parse_query_string_duplicate_keys() {
	result := execute('parse_query_string!("x=1&x=2")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	// Duplicate keys should produce an array
	assert j.contains('"x":["1","2"]'), 'parse_qs duplicate keys: got ${j}'
}

// ============================================================================
// parse_duration
// ============================================================================

fn test_parse_duration_1s() {
	result := execute('parse_duration!("1s", "ms")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(1000.0), 'parse_duration 1s: got ${vrl_to_json(result)}'
}

fn test_parse_duration_500ms() {
	result := execute('parse_duration!("500ms", "s")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(0.5), 'parse_duration 500ms: got ${vrl_to_json(result)}'
}

fn test_parse_duration_2h30m() {
	result := execute('parse_duration!("2h30m", "m")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(150.0), 'parse_duration 2h30m: got ${vrl_to_json(result)}'
}

fn test_parse_duration_1d() {
	result := execute('parse_duration!("1d", "h")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(24.0), 'parse_duration 1d: got ${vrl_to_json(result)}'
}

fn test_parse_duration_ns() {
	result := execute('parse_duration!("1s", "ns")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(1_000_000_000.0), 'parse_duration 1s to ns: got ${vrl_to_json(result)}'
}

// ============================================================================
// parse_bytes
// ============================================================================

fn test_parse_bytes_1kb() {
	result := execute('parse_bytes!("1KB")', map[string]VrlValue{}) or { panic(err) }
	v := result as f64
	assert v == 1024.0, 'parse_bytes 1KB: got ${v}'
}

fn test_parse_bytes_1_5mb() {
	result := execute('parse_bytes!("1.5MB")', map[string]VrlValue{}) or { panic(err) }
	v := result as f64
	expected := 1.5 * 1024.0 * 1024.0
	assert v == expected, 'parse_bytes 1.5MB: got ${v}'
}

fn test_parse_bytes_2gib() {
	result := execute('parse_bytes!("2GiB")', map[string]VrlValue{}) or { panic(err) }
	v := result as f64
	expected := 2.0 * 1024.0 * 1024.0 * 1024.0
	assert v == expected, 'parse_bytes 2GiB: got ${v}'
}

// ============================================================================
// parse_int
// ============================================================================

fn test_parse_int_decimal() {
	result := execute('parse_int!("42")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(42)), 'parse_int 42: got ${vrl_to_json(result)}'
}

fn test_parse_int_hex() {
	result := execute('parse_int!("0xff")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(255)), 'parse_int 0xff: got ${vrl_to_json(result)}'
}

fn test_parse_int_octal() {
	result := execute('parse_int!("0o17")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(15)), 'parse_int 0o17: got ${vrl_to_json(result)}'
}

fn test_parse_int_binary() {
	result := execute('parse_int!("0b1010")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(10)), 'parse_int 0b1010: got ${vrl_to_json(result)}'
}

fn test_parse_int_negative() {
	result := execute('parse_int!("-123")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(-123)), 'parse_int -123: got ${vrl_to_json(result)}'
}

fn test_parse_int_with_explicit_base() {
	result := execute('parse_int!("ff", 16)', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(255)), 'parse_int ff base 16: got ${vrl_to_json(result)}'
}

// ============================================================================
// parse_float
// ============================================================================

fn test_parse_float_basic() {
	result := execute('parse_float!("3.14")', map[string]VrlValue{}) or { panic(err) }
	v := result as f64
	assert v > 3.13 && v < 3.15, 'parse_float 3.14: got ${v}'
}

fn test_parse_float_integer_string() {
	result := execute('parse_float!("42")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(42.0), 'parse_float 42: got ${vrl_to_json(result)}'
}

fn test_parse_float_negative() {
	result := execute('parse_float!("-2.5")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(-2.5), 'parse_float -2.5: got ${vrl_to_json(result)}'
}

// ============================================================================
// parse_timestamp
// ============================================================================

fn test_parse_timestamp_rfc3339() {
	result := execute('parse_timestamp!("2023-06-15T10:30:00Z", "%+")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('2023-06-15'), 'parse_timestamp rfc3339: got ${j}'
}

fn test_parse_timestamp_iso8601() {
	result := execute('parse_timestamp!("2023-06-15T10:30:00Z", "%Y-%m-%dT%H:%M:%SZ")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('2023'), 'parse_timestamp iso8601: got ${j}'
}

// ============================================================================
// parse_common_log (Apache CLF format)
// ============================================================================

fn test_parse_common_log() {
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.1" 200 2326')
	result := execute('parse_common_log!(.msg)', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"host":"127.0.0.1"'), 'parse_common_log host: got ${j}'
	assert j.contains('"user":"frank"'), 'parse_common_log user: got ${j}'
	assert j.contains('"method":"GET"'), 'parse_common_log method: got ${j}'
	assert j.contains('"path":"/apache_pb.gif"'), 'parse_common_log path: got ${j}'
	assert j.contains('"status":200') || j.contains('"status":"200"'), 'parse_common_log status: got ${j}'
}

// ============================================================================
// parse_syslog (RFC 5424)
// ============================================================================

fn test_parse_syslog_rfc5424() {
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue('<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 [exampleSDID@32473 iut="3"] An application event log entry...')
	result := execute('parse_syslog!(.msg)', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"hostname":"mymachine.example.com"'), 'parse_syslog hostname: got ${j}'
	assert j.contains('"appname":"evntslog"'), 'parse_syslog appname: got ${j}'
	assert j.contains('"msgid":"ID47"'), 'parse_syslog msgid: got ${j}'
	assert j.contains('"severity"') || j.contains('"facility"'), 'parse_syslog severity/facility: got ${j}'
}

fn test_parse_syslog_rfc3164() {
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue("<34>Oct 11 22:14:15 mymachine su: 'su root' failed for lonvick on /dev/pts/8")
	result := execute('parse_syslog!(.msg)', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"hostname":"mymachine"'), 'parse_syslog rfc3164 hostname: got ${j}'
	assert j.contains('"appname":"su"'), 'parse_syslog rfc3164 appname: got ${j}'
}

// ============================================================================
// parse_logfmt
// ============================================================================

fn test_parse_logfmt_basic() {
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue('level=info msg="request handled" duration=0.5s')
	result := execute('parse_logfmt!(.msg)', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"info"'), 'parse_logfmt level: got ${j}'
	assert j.contains('"msg":"request handled"'), 'parse_logfmt msg: got ${j}'
}

fn test_parse_logfmt_unquoted_values() {
	result := execute('parse_logfmt!("host=localhost port=8080 method=GET")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"host":"localhost"'), 'parse_logfmt host: got ${j}'
	assert j.contains('"port":"8080"'), 'parse_logfmt port: got ${j}'
	assert j.contains('"method":"GET"'), 'parse_logfmt method: got ${j}'
}

// ============================================================================
// parse_tokens
// ============================================================================

fn test_parse_tokens_basic() {
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.1" 200 2326')
	result := execute('parse_tokens!(.msg)', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"127.0.0.1"'), 'parse_tokens host: got ${j}'
	assert j.contains('"frank"'), 'parse_tokens user: got ${j}'
}

// ============================================================================
// parse_yaml
// ============================================================================

fn test_parse_yaml_simple() {
	prog := 'parse_yaml!("name: John\\nage: 30")'
	result := execute(prog, map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"name":"John"') || j.contains('"name": "John"'), 'parse_yaml name: got ${j}'
	assert j.contains('"age":30') || j.contains('"age":"30"'), 'parse_yaml age: got ${j}'
}

fn test_parse_yaml_nested() {
	prog := 'parse_yaml!("server:\\n  host: localhost\\n  port: 8080")'
	result := execute(prog, map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"host"'), 'parse_yaml nested host: got ${j}'
	assert j.contains('localhost'), 'parse_yaml nested localhost: got ${j}'
}

// ============================================================================
// parse_klog
// ============================================================================

fn test_parse_klog_info() {
	result := execute('parse_klog!("I0505 17:59:40.692994   28133 example.go:156] Some log message")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"info"'), 'parse_klog level: got ${j}'
	assert j.contains('"file":"example.go"'), 'parse_klog file: got ${j}'
	assert j.contains('"msg"') || j.contains('"message"'), 'parse_klog msg: got ${j}'
}

fn test_parse_klog_error() {
	result := execute('parse_klog!("E0505 17:59:40.692994   28133 server.go:42] Error occurred")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"error"'), 'parse_klog error level: got ${j}'
}

// ============================================================================
// parse_linux_authorization
// ============================================================================

fn test_parse_linux_authorization() {
	result := execute('parse_linux_authorization!("Jan  5 16:13:02 hostname sshd[1234]: Accepted publickey for root from 192.168.1.1 port 22 ssh2")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"hostname":"hostname"') || j.contains('"host":"hostname"'), 'parse_linux_auth hostname: got ${j}'
	assert j.contains('"appname":"sshd"') || j.contains('"process":"sshd"'), 'parse_linux_auth appname: got ${j}'
	assert j.contains('"message"') || j.contains('"msg"'), 'parse_linux_auth message: got ${j}'
}

// ============================================================================
// parse_apache_log
// ============================================================================

fn test_parse_apache_log_common() {
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.1" 200 2326')
	result := execute('parse_apache_log!(.msg, "common")', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"host":"127.0.0.1"'), 'parse_apache_log host: got ${j}'
	assert j.contains('"user":"frank"'), 'parse_apache_log user: got ${j}'
	assert j.contains('"method":"GET"'), 'parse_apache_log method: got ${j}'
}

fn test_parse_apache_log_combined() {
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue('127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.1" 200 2326 "http://www.example.com/start.html" "Mozilla/4.08"')
	result := execute('parse_apache_log!(.msg, "combined")', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"host":"127.0.0.1"'), 'parse_apache_combined host: got ${j}'
	assert j.contains('"method":"GET"'), 'parse_apache_combined method: got ${j}'
	assert j.contains('"referrer"') || j.contains('"referer"'), 'parse_apache_combined referrer: got ${j}'
}

// ============================================================================
// parse_nginx_log
// ============================================================================

fn test_parse_nginx_log_combined() {
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue('93.180.71.3 - - [17/May/2015:08:05:32 +0000] "GET /downloads/product_1 HTTP/1.1" 304 0 "-" "Debian APT-HTTP/1.3 (0.8.16~exp12ubuntu10.21)"')
	result := execute('parse_nginx_log!(.msg, "combined")', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"client":"93.180.71.3"') || j.contains('"host":"93.180.71.3"'), 'parse_nginx client: got ${j}'
	assert j.contains('"request"') || j.contains('"method"'), 'parse_nginx request: got ${j}'
	assert j.contains('"status":304') || j.contains('"status":"304"'), 'parse_nginx status: got ${j}'
}

// ============================================================================
// parse_aws_vpc_flow_log
// ============================================================================

fn test_parse_aws_vpc_flow_log() {
	result := execute('parse_aws_vpc_flow_log!("2 123456789012 eni-abc12345 10.0.1.5 10.0.2.5 12345 80 6 10 840 1616729292 1616729349 ACCEPT OK")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"srcaddr":"10.0.1.5"') || j.contains('"srcaddr"'), 'parse_aws_vpc srcaddr: got ${j}'
	assert j.contains('"dstaddr":"10.0.2.5"') || j.contains('"dstaddr"'), 'parse_aws_vpc dstaddr: got ${j}'
	assert j.contains('"action":"ACCEPT"') || j.contains('"ACCEPT"'), 'parse_aws_vpc action: got ${j}'
}

// ============================================================================
// parse_cef
// ============================================================================

fn test_parse_cef() {
	result := execute('parse_cef!("CEF:0|Security|threatmanager|1.0|100|worm successfully stopped|10|src=10.0.0.1 dst=2.1.2.2 spt=1232")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"deviceVendor":"Security"') || j.contains('"Security"'), 'parse_cef vendor: got ${j}'
	assert j.contains('"severity":"10"') || j.contains('"severity":10'), 'parse_cef severity: got ${j}'
	assert j.contains('"src":"10.0.0.1"') || j.contains('"10.0.0.1"'), 'parse_cef src: got ${j}'
}

// ============================================================================
// parse_glog
// ============================================================================

fn test_parse_glog() {
	result := execute('parse_glog!("I0719 16:15:43.906468   12345 main.go:42] Starting server on port 8080")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"level"'), 'parse_glog level: got ${j}'
	assert j.contains('"file"') || j.contains('"source"'), 'parse_glog file: got ${j}'
	assert j.contains('"message"') || j.contains('"msg"'), 'parse_glog message: got ${j}'
}

// ============================================================================
// parse_influxdb
// ============================================================================

fn test_parse_influxdb() {
	result := execute('parse_influxdb!("cpu,host=server01,region=us-west value=0.64 1434055562000000000")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"name":"cpu_value"') || j.contains('"name":"cpu"'), 'parse_influxdb name: got ${j}'
	assert j.contains('"host":"server01"') || j.contains('"server01"'), 'parse_influxdb host tag: got ${j}'
}

// ============================================================================
// parse_ruby_hash
// ============================================================================

fn test_parse_ruby_hash() {
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue('{"name" => "John", "age" => 30}')
	result := execute('parse_ruby_hash!(.msg)', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"name":"John"') || j.contains('"name": "John"'), 'parse_ruby_hash name: got ${j}'
}

fn test_parse_ruby_hash_symbols() {
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue('{:name => "Alice", :active => true}')
	result := execute('parse_ruby_hash!(.msg)', obj) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"name":"Alice"') || j.contains('"name": "Alice"'), 'parse_ruby_hash symbol name: got ${j}'
}

// ============================================================================
// parse_user_agent
// ============================================================================

fn test_parse_user_agent() {
	result := execute('parse_user_agent!("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"browser"') || j.contains('"family"') || j.contains('"user_agent"'), 'parse_user_agent browser: got ${j}'
}

// ============================================================================
// get_hostname
// ============================================================================

fn test_get_hostname_returns_string() {
	result := execute('get_hostname!()', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s.len > 0, 'get_hostname should return non-empty string'
}

// ============================================================================
// log (VRL log function - should be a no-op that returns null)
// ============================================================================

fn test_log_returns_null() {
	result := execute('log("hello from VRL")', map[string]VrlValue{}) or { panic(err) }
	assert result is VrlNull, 'log should return null: got ${vrl_to_json(result)}'
}

fn test_log_with_level() {
	result := execute('log("test message", level: "error")', map[string]VrlValue{}) or { panic(err) }
	assert result is VrlNull, 'log with level should return null'
}

// ============================================================================
// redact
// ============================================================================

fn test_redact_credit_card() {
	result := execute('redact("My card is 4111111111111111 please", ["credit_card"])', map[string]VrlValue{}) or {
		panic(err)
	}
	s := result as string
	assert s.contains('[REDACTED]'), 'redact credit card: got ${s}'
	assert !s.contains('4111111111111111'), 'redact should remove CC number: got ${s}'
}

fn test_redact_us_ssn() {
	result := execute('redact("SSN: 123-45-6789 here", ["us_social_security_number"])', map[string]VrlValue{}) or {
		panic(err)
	}
	s := result as string
	assert s.contains('[REDACTED]'), 'redact SSN: got ${s}'
	assert !s.contains('123-45-6789'), 'redact should remove SSN: got ${s}'
}

fn test_redact_with_pattern() {
	result := execute('redact("email: foo@bar.com end", [r\'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}\'])', map[string]VrlValue{}) or {
		panic(err)
	}
	s := result as string
	assert s.contains('[REDACTED]'), 'redact pattern: got ${s}'
	assert !s.contains('foo@bar.com'), 'redact should remove email: got ${s}'
}

// ============================================================================
// random_int
// ============================================================================

fn test_random_int_in_range() {
	result := execute('random_int(1, 100)', map[string]VrlValue{}) or { panic(err) }
	v := result as i64
	assert v >= 1 && v <= 100, 'random_int should be in [1,100]: got ${v}'
}

fn test_random_int_same_min_max() {
	result := execute('random_int(42, 42)', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(42)), 'random_int(42,42) should be 42'
}

// ============================================================================
// random_float
// ============================================================================

fn test_random_float_in_range() {
	result := execute('random_float(0.0, 1.0)', map[string]VrlValue{}) or { panic(err) }
	v := result as f64
	assert v >= 0.0 && v <= 1.0, 'random_float should be in [0,1]: got ${v}'
}

// ============================================================================
// random_bool
// ============================================================================

fn test_random_bool_type() {
	result := execute('random_bool()', map[string]VrlValue{}) or { panic(err) }
	_ := result as bool // Just ensure it's a bool
}

// ============================================================================
// random_bytes
// ============================================================================

fn test_random_bytes_length() {
	result := execute('length(random_bytes(16))', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(16)), 'random_bytes should produce 16 bytes: got ${vrl_to_json(result)}'
}

fn test_random_bytes_zero() {
	result := execute('length(random_bytes(0))', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(0)), 'random_bytes(0) should produce 0 bytes'
}

// ============================================================================
// uuid_v4
// ============================================================================

fn test_uuid_v4_format() {
	result := execute('uuid_v4()', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s.len == 36, 'uuid_v4 should be 36 chars: got ${s.len}'
	assert s[8] == `-`, 'uuid_v4 dash at 8'
	assert s[13] == `-`, 'uuid_v4 dash at 13'
	assert s[18] == `-`, 'uuid_v4 dash at 18'
	assert s[23] == `-`, 'uuid_v4 dash at 23'
	// Version nibble should be '4'
	assert s[14] == `4`, 'uuid_v4 version nibble should be 4: got ${[s[14]].bytestr()}'
}

fn test_uuid_v4_uniqueness() {
	r1 := execute('uuid_v4()', map[string]VrlValue{}) or { panic(err) }
	r2 := execute('uuid_v4()', map[string]VrlValue{}) or { panic(err) }
	s1 := r1 as string
	s2 := r2 as string
	assert s1 != s2, 'uuid_v4 should produce unique values'
}

// ============================================================================
// uuid_v7
// ============================================================================

fn test_uuid_v7_format() {
	result := execute('uuid_v7()', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s.len == 36, 'uuid_v7 should be 36 chars: got ${s.len}'
	assert s[8] == `-`, 'uuid_v7 dash at 8'
	assert s[13] == `-`, 'uuid_v7 dash at 13'
	assert s[18] == `-`, 'uuid_v7 dash at 18'
	assert s[23] == `-`, 'uuid_v7 dash at 23'
	// Version nibble should be '7'
	assert s[14] == `7`, 'uuid_v7 version nibble should be 7: got ${[s[14]].bytestr()}'
}

fn test_uuid_v7_uniqueness() {
	r1 := execute('uuid_v7()', map[string]VrlValue{}) or { panic(err) }
	r2 := execute('uuid_v7()', map[string]VrlValue{}) or { panic(err) }
	s1 := r1 as string
	s2 := r2 as string
	assert s1 != s2, 'uuid_v7 should produce unique values'
}

// ============================================================================
// encode_punycode / decode_punycode
// ============================================================================

fn test_encode_punycode_ascii() {
	result := execute('encode_punycode!("example.com")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('example.com'), 'encode_punycode ascii passthrough'
}

fn test_encode_punycode_unicode() {
	// Standard test: "münchen.de" -> "xn--mnchen-3ya.de"
	result := execute('encode_punycode!("münchen.de")', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s == 'xn--mnchen-3ya.de', 'encode_punycode münchen.de: got ${s}'
}

fn test_decode_punycode_ascii() {
	result := execute('decode_punycode!("example.com")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('example.com'), 'decode_punycode ascii passthrough'
}

fn test_decode_punycode_unicode() {
	result := execute('decode_punycode!("xn--mnchen-3ya.de")', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s == 'münchen.de', 'decode_punycode xn--mnchen-3ya.de: got ${s}'
}

fn test_punycode_roundtrip() {
	encoded := execute('encode_punycode!("bücher.example")', map[string]VrlValue{}) or { panic(err) }
	enc_s := encoded as string
	assert enc_s.starts_with('xn--'), 'punycode roundtrip should produce xn-- prefix: got ${enc_s}'
	decoded := execute('decode_punycode!("${enc_s}")', map[string]VrlValue{}) or { panic(err) }
	dec_s := decoded as string
	assert dec_s == 'bücher.example', 'punycode roundtrip: got ${dec_s}'
}

fn test_encode_punycode_japanese() {
	// "東京.jp" is a common test vector
	result := execute('encode_punycode!("東京.jp")', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s.starts_with('xn--'), 'encode_punycode Japanese should have xn-- prefix: got ${s}'
	assert s.ends_with('.jp'), 'encode_punycode Japanese should end with .jp: got ${s}'
}
