module vrl

// Comprehensive data-driven tests for VRL vrllib functions.
// Each test exercises the full pipeline: lexer -> parser -> runtime -> stdlib function.

fn assert_str(program string, expected string) {
	result := execute(program, map[string]VrlValue{}) or { panic('${program}: ${err}') }
	assert result == VrlValue(expected), '${program}: expected "${expected}", got ${vrl_to_json(result)}'
}

fn assert_int(program string, expected i64) {
	result := execute(program, map[string]VrlValue{}) or { panic('${program}: ${err}') }
	assert result == VrlValue(expected), '${program}: expected ${expected}, got ${vrl_to_json(result)}'
}

fn assert_bool_result(program string, expected bool) {
	result := execute(program, map[string]VrlValue{}) or { panic('${program}: ${err}') }
	assert result == VrlValue(expected), '${program}: expected ${expected}, got ${vrl_to_json(result)}'
}

fn assert_json(program string, expected string) {
	result := execute(program, map[string]VrlValue{}) or { panic('${program}: ${err}') }
	json := vrl_to_json(result)
	assert json == expected, '${program}: expected ${expected}, got ${json}'
}

fn assert_json_contains(program string, expected string) {
	result := execute(program, map[string]VrlValue{}) or { panic('${program}: ${err}') }
	json := vrl_to_json(result)
	assert json.contains(expected), '${program}: expected json to contain "${expected}", got ${json}'
}

// ============================================================
// String case conversion functions
// ============================================================

fn test_camelcase() {
	assert_str('camelcase("hello_world")', 'helloWorld')
	assert_str('camelcase("Hello World")', 'helloWorld')
	assert_str('camelcase("hello-world")', 'helloWorld')
	assert_str('camelcase("HELLO_WORLD")', 'helloWorld')
	assert_str('camelcase("hello")', 'hello')
	assert_str('camelcase("")', '')
	assert_str('camelcase("already_camel_case")', 'alreadyCamelCase')
	assert_str('camelcase("XMLParser")', 'xmlParser')
	assert_str('camelcase("one_two_three")', 'oneTwoThree')
	assert_str('camelcase("foo__bar")', 'fooBar')
}

fn test_snakecase() {
	assert_str('snakecase("helloWorld")', 'hello_world')
	assert_str('snakecase("HelloWorld")', 'hello_world')
	assert_str('snakecase("hello-world")', 'hello_world')
	assert_str('snakecase("hello world")', 'hello_world')
	assert_str('snakecase("hello")', 'hello')
	assert_str('snakecase("")', '')
	assert_str('snakecase("XMLParser")', 'xml_parser')
	assert_str('snakecase("HELLO")', 'hello')
	assert_str('snakecase("oneTwoThree")', 'one_two_three')
}

fn test_pascalcase() {
	assert_str('pascalcase("hello_world")', 'HelloWorld')
	assert_str('pascalcase("helloWorld")', 'HelloWorld')
	assert_str('pascalcase("hello-world")', 'HelloWorld')
	assert_str('pascalcase("hello world")', 'HelloWorld')
	assert_str('pascalcase("")', '')
	assert_str('pascalcase("hello")', 'Hello')
	assert_str('pascalcase("one_two_three")', 'OneTwoThree')
}

fn test_kebabcase() {
	assert_str('kebabcase("helloWorld")', 'hello-world')
	assert_str('kebabcase("HelloWorld")', 'hello-world')
	assert_str('kebabcase("hello_world")', 'hello-world')
	assert_str('kebabcase("hello world")', 'hello-world')
	assert_str('kebabcase("")', '')
	assert_str('kebabcase("hello")', 'hello')
	assert_str('kebabcase("XMLParser")', 'xml-parser')
}

fn test_screamingsnakecase() {
	assert_str('screamingsnakecase("hello_world")', 'HELLO_WORLD')
	assert_str('screamingsnakecase("helloWorld")', 'HELLO_WORLD')
	assert_str('screamingsnakecase("HelloWorld")', 'HELLO_WORLD')
	assert_str('screamingsnakecase("hello-world")', 'HELLO_WORLD')
	assert_str('screamingsnakecase("")', '')
	assert_str('screamingsnakecase("hello")', 'HELLO')
	assert_str('screamingsnakecase("one_two_three")', 'ONE_TWO_THREE')
}

// ============================================================
// Path functions: basename, dirname, split_path
// ============================================================

fn test_basename() {
	assert_str('basename("/home/user/file.txt")', 'file.txt')
	assert_str('basename("/home/user/")', 'user')
	assert_str('basename("file.txt")', 'file.txt')
	assert_str('basename("/home/user/file.txt", ".txt")', 'file')
	assert_str('basename("/a/b/c")', 'c')
	assert_str('basename("no_slashes")', 'no_slashes')
}

fn test_basename_root() {
	result := execute('basename("/")', map[string]VrlValue{}) or { panic('basename("/"): ${err}') }
	assert result is VrlNull, 'basename("/") should return null'
}

fn test_dirname() {
	assert_str('dirname("/home/user/file.txt")', '/home/user')
	assert_str('dirname("/home/user/")', '/home')
	assert_str('dirname("file.txt")', '.')
	assert_str('dirname("/a/b/c")', '/a/b')
	assert_str('dirname("/file")', '/')
	assert_str('dirname("/")', '/')
}

fn test_split_path() {
	assert_json('split_path("/home/user/file.txt")', '["/","home","user","file.txt"]')
	assert_json('split_path("a/b/c")', '["a","b","c"]')
	assert_json('split_path("file")', '["file"]')
}

// ============================================================
// strip_ansi_escape_codes
// ============================================================

fn test_strip_ansi_escape_codes() {
	// Build a string with ANSI codes using raw byte construction
	// ESC[31m = red, ESC[0m = reset
	mut input := map[string]VrlValue{}
	mut ansi_str := []u8{}
	ansi_str << 0x1B // ESC
	ansi_str << `[`
	ansi_str << `3`
	ansi_str << `1`
	ansi_str << `m`
	for c in 'hello'.bytes() {
		ansi_str << c
	}
	ansi_str << 0x1B // ESC
	ansi_str << `[`
	ansi_str << `0`
	ansi_str << `m`
	input['msg'] = VrlValue(ansi_str.bytestr())
	result := execute('strip_ansi_escape_codes(.msg)', input) or {
		panic('strip_ansi: ${err}')
	}
	assert result == VrlValue('hello'), 'strip_ansi: got ${vrl_to_json(result)}'
}

fn test_strip_ansi_no_codes() {
	assert_str('strip_ansi_escape_codes("plain text")', 'plain text')
}

fn test_strip_ansi_empty() {
	assert_str('strip_ansi_escape_codes("")', '')
}

// ============================================================
// shannon_entropy
// ============================================================

fn test_shannon_entropy_uniform() {
	// "aabb" has 2 symbols each appearing twice: entropy = 1.0
	result := execute('shannon_entropy("aabb")', map[string]VrlValue{}) or {
		panic('shannon_entropy: ${err}')
	}
	v := result as f64
	assert v > 0.99 && v < 1.01, 'shannon_entropy("aabb"): expected ~1.0, got ${v}'
}

fn test_shannon_entropy_single_char() {
	// "aaaa" has entropy 0 (only one symbol)
	result := execute('shannon_entropy("aaaa")', map[string]VrlValue{}) or {
		panic('shannon_entropy single: ${err}')
	}
	v := result as f64
	assert v == 0.0, 'shannon_entropy("aaaa"): expected 0.0, got ${v}'
}

fn test_shannon_entropy_empty() {
	result := execute('shannon_entropy("")', map[string]VrlValue{}) or {
		panic('shannon_entropy empty: ${err}')
	}
	v := result as f64
	assert v == 0.0, 'shannon_entropy(""): expected 0.0, got ${v}'
}

fn test_shannon_entropy_two_chars() {
	// "ab" gives log2(2) = 1.0
	result := execute('shannon_entropy("ab")', map[string]VrlValue{}) or {
		panic('shannon_entropy two: ${err}')
	}
	v := result as f64
	assert v > 0.99 && v < 1.01, 'shannon_entropy("ab"): expected ~1.0, got ${v}'
}

fn test_shannon_entropy_four_distinct() {
	// "abcd" has 4 distinct symbols, each once: entropy = log2(4) = 2.0
	result := execute('shannon_entropy("abcd")', map[string]VrlValue{}) or {
		panic('shannon_entropy four: ${err}')
	}
	v := result as f64
	assert v > 1.99 && v < 2.01, 'shannon_entropy("abcd"): expected ~2.0, got ${v}'
}

// ============================================================
// sieve
// ============================================================

fn test_sieve_basic() {
	assert_str("sieve(\"h3llo w0rld!\", r'[a-zA-Z0-9]')", 'h3llow0rld')
}

fn test_sieve_digits_only() {
	assert_str("sieve(\"abc123def456\", r'[0-9]')", '123456')
}

fn test_sieve_empty() {
	assert_str("sieve(\"\", r'[a-z]')", '')
}

fn test_sieve_keep_letters_only() {
	assert_str("sieve(\"a1b2c3\", r'[a-z]')", 'abc')
}

// ============================================================
// chunks (array and string)
// ============================================================

fn test_chunks_string() {
	assert_json('chunks("abcdefg", 3)', '["abc","def","g"]')
}

fn test_chunks_string_exact() {
	assert_json('chunks("abcdef", 3)', '["abc","def"]')
}

fn test_chunks_string_single() {
	assert_json('chunks("abc", 1)', '["a","b","c"]')
}

fn test_chunks_string_larger_than_input() {
	assert_json('chunks("ab", 10)', '["ab"]')
}

fn test_chunks_array() {
	assert_json('chunks([1, 2, 3, 4, 5], 2)', '[[1,2],[3,4],[5]]')
}

fn test_chunks_empty_string() {
	assert_json('chunks("", 3)', '[]')
}

fn test_chunks_boundary() {
	assert_json('chunks("abc", 3)', '["abc"]')
}

// ============================================================
// Object functions: unnest, object_from_array, zip, remove
// ============================================================

fn test_unnest_basic() {
	src := '
.tags = ["a", "b", "c"]
unnest!(.tags)
'
	result := execute(src, map[string]VrlValue{}) or { panic('unnest: ${err}') }
	json := vrl_to_json(result)
	assert json.contains('"tags":"a"'), 'unnest should contain tags:a, got ${json}'
	assert json.contains('"tags":"b"'), 'unnest should contain tags:b, got ${json}'
	assert json.contains('"tags":"c"'), 'unnest should contain tags:c, got ${json}'
}

fn test_object_from_array_pairs() {
	result := execute('object_from_array!([["a", 1], ["b", 2]])', map[string]VrlValue{}) or {
		panic('object_from_array: ${err}')
	}
	json := vrl_to_json(result)
	assert json.contains('"a":1'), 'object_from_array pairs: got ${json}'
	assert json.contains('"b":2'), 'object_from_array pairs: got ${json}'
}

fn test_object_from_array_keys_values() {
	result := execute('object_from_array!([10, 20, 30], ["x", "y", "z"])', map[string]VrlValue{}) or {
		panic('object_from_array keys: ${err}')
	}
	json := vrl_to_json(result)
	assert json.contains('"x":10'), 'object_from_array keys: got ${json}'
	assert json.contains('"y":20'), 'object_from_array keys: got ${json}'
	assert json.contains('"z":30'), 'object_from_array keys: got ${json}'
}

fn test_zip_two_arrays() {
	assert_json('zip(["a", "b", "c"], [1, 2, 3])', '[["a",1],["b",2],["c",3]]')
}

fn test_zip_unequal_lengths() {
	assert_json('zip(["a", "b"], [1, 2, 3])', '[["a",1],["b",2]]')
}

fn test_zip_empty() {
	assert_json('zip([], [1, 2])', '[]')
}

fn test_zip_three_arrays() {
	assert_json('zip(["a", "b"], [1, 2], [true, false])', '[["a",1,true],["b",2,false]]')
}

fn test_remove_object_key() {
	result := execute('remove!({"a": 1, "b": 2, "c": 3}, ["b"])', map[string]VrlValue{}) or {
		panic('remove: ${err}')
	}
	json := vrl_to_json(result)
	assert json.contains('"a":1'), 'remove should keep a, got ${json}'
	assert !json.contains('"b"'), 'remove should drop b, got ${json}'
	assert json.contains('"c":3'), 'remove should keep c, got ${json}'
}

fn test_remove_nested() {
	result := execute('remove!({"a": {"b": 1, "c": 2}}, ["a", "b"])', map[string]VrlValue{}) or {
		panic('remove nested: ${err}')
	}
	json := vrl_to_json(result)
	assert json.contains('"c":2'), 'remove nested should keep c, got ${json}'
	assert !json.contains('"b":1'), 'remove nested should drop b, got ${json}'
}

fn test_remove_array_index() {
	assert_json('remove!([10, 20, 30], [1])', '[10,30]')
}

// ============================================================
// Type checking functions
// ============================================================

fn test_is_empty_cases() {
	assert_bool_result('is_empty("")', true)
	assert_bool_result('is_empty("hello")', false)
	assert_bool_result('is_empty([])', true)
	assert_bool_result('is_empty([1])', false)
	assert_bool_result('is_empty({})', true)
	assert_bool_result('is_empty(null)', true)
}

fn test_is_json_cases() {
	assert_bool_result('is_json("{}")', true)
	assert_bool_result('is_json("[]")', true)
	assert_bool_result('is_json("42")', true)
	assert_bool_result('is_json("\\"hello\\"")', true)
	assert_bool_result('is_json("true")', true)
	assert_bool_result('is_json("null")', true)
	assert_bool_result('is_json("not json")', false)
	assert_bool_result('is_json("")', false)
	// Note: is_json with variant arg is not exposed via execute() (max 1 positional arg)
}

fn test_is_regex() {
	assert_bool_result("is_regex(r'[a-z]+')", true)
	assert_bool_result('is_regex("hello")', false)
	assert_bool_result('is_regex(42)', false)
}

fn test_is_timestamp() {
	assert_bool_result('is_timestamp(now())', true)
	assert_bool_result('is_timestamp("2021-01-01")', false)
	assert_bool_result('is_timestamp(42)', false)
}

fn test_tag_types_externally_string() {
	assert_json_contains('tag_types_externally("hello")', '"string":"hello"')
}

fn test_tag_types_externally_integer() {
	assert_json_contains('tag_types_externally(42)', '"integer":42')
}

fn test_tag_types_externally_float() {
	assert_json_contains('tag_types_externally(3.14)', '"float":3.14')
}

fn test_tag_types_externally_bool() {
	assert_json_contains('tag_types_externally(true)', '"boolean":true')
}

fn test_tag_types_externally_null() {
	result := execute('tag_types_externally(null)', map[string]VrlValue{}) or {
		panic('tag_types null: ${err}')
	}
	assert result is VrlNull, 'tag_types null should return null'
}

fn test_tag_types_externally_array() {
	result := execute('tag_types_externally([1, "two"])', map[string]VrlValue{}) or {
		panic('tag_types array: ${err}')
	}
	json := vrl_to_json(result)
	assert json.contains('"integer":1'), 'tag_types array int: got ${json}'
	assert json.contains('"string":"two"'), 'tag_types array string: got ${json}'
}

fn test_tag_types_externally_object() {
	result := execute('tag_types_externally({"key": "val"})', map[string]VrlValue{}) or {
		panic('tag_types object: ${err}')
	}
	json := vrl_to_json(result)
	assert json.contains('"object"'), 'tag_types object: got ${json}'
	assert json.contains('"string":"val"'), 'tag_types object value: got ${json}'
}

// ============================================================
// Syslog functions (RFC 5424 values)
// ============================================================

fn test_to_syslog_level() {
	// RFC 5424 severity codes 0-7
	expected := ['emerg', 'alert', 'crit', 'err', 'warning', 'notice', 'info', 'debug']
	for i, exp in expected {
		assert_str('to_syslog_level!(${i})', exp)
	}
}

fn test_to_syslog_level_invalid() {
	_ := execute('to_syslog_level!(8)', map[string]VrlValue{}) or {
		assert err.msg().contains('invalid syslog severity')
		return
	}
	panic('expected error for invalid severity 8')
}

fn test_to_syslog_severity() {
	assert_int('to_syslog_severity!("emerg")', 0)
	assert_int('to_syslog_severity!("emergency")', 0)
	assert_int('to_syslog_severity!("alert")', 1)
	assert_int('to_syslog_severity!("crit")', 2)
	assert_int('to_syslog_severity!("critical")', 2)
	assert_int('to_syslog_severity!("err")', 3)
	assert_int('to_syslog_severity!("error")', 3)
	assert_int('to_syslog_severity!("warning")', 4)
	assert_int('to_syslog_severity!("warn")', 4)
	assert_int('to_syslog_severity!("notice")', 5)
	assert_int('to_syslog_severity!("info")', 6)
	assert_int('to_syslog_severity!("informational")', 6)
	assert_int('to_syslog_severity!("debug")', 7)
}

fn test_to_syslog_severity_invalid() {
	_ := execute('to_syslog_severity!("bogus")', map[string]VrlValue{}) or {
		assert err.msg().contains('invalid syslog level')
		return
	}
	panic('expected error for invalid level')
}

fn test_to_syslog_facility() {
	expected := ['kern', 'user', 'mail', 'daemon', 'auth', 'syslog', 'lpr', 'news',
		'uucp', 'cron', 'authpriv', 'ftp', 'ntp', 'security', 'console', 'solaris-cron',
		'local0', 'local1', 'local2', 'local3', 'local4', 'local5', 'local6', 'local7']
	for i, exp in expected {
		assert_str('to_syslog_facility!(${i})', exp)
	}
}

fn test_to_syslog_facility_invalid() {
	_ := execute('to_syslog_facility!(24)', map[string]VrlValue{}) or {
		assert err.msg().contains('invalid syslog facility code')
		return
	}
	panic('expected error for invalid facility 24')
}

fn test_to_syslog_facility_code() {
	facilities := {
		'kern': i64(0), 'user': i64(1), 'mail': i64(2), 'daemon': i64(3),
		'auth': i64(4), 'syslog': i64(5), 'lpr': i64(6), 'news': i64(7),
		'uucp': i64(8), 'cron': i64(9), 'local0': i64(16), 'local7': i64(23)
	}
	for name, code in facilities {
		assert_int('to_syslog_facility_code!("${name}")', code)
	}
}

fn test_to_syslog_facility_code_invalid() {
	_ := execute('to_syslog_facility_code!("unknown")', map[string]VrlValue{}) or {
		assert err.msg().contains('invalid syslog facility')
		return
	}
	panic('expected error for invalid facility name')
}

fn test_syslog_roundtrip() {
	for code in 0 .. 8 {
		src := 'to_syslog_severity!(to_syslog_level!(${code}))'
		assert_int(src, i64(code))
	}
}

fn test_syslog_facility_roundtrip() {
	for code in 0 .. 24 {
		src := 'to_syslog_facility_code!(to_syslog_facility!(${code}))'
		assert_int(src, i64(code))
	}
}

// ============================================================
// Enumerate functions: tally, tally_value, match_array
// ============================================================

fn test_tally() {
	result := execute('tally(["a", "b", "a", "c", "b", "a"])', map[string]VrlValue{}) or {
		panic('tally: ${err}')
	}
	json := vrl_to_json(result)
	assert json.contains('"a":3'), 'tally a: got ${json}'
	assert json.contains('"b":2'), 'tally b: got ${json}'
	assert json.contains('"c":1'), 'tally c: got ${json}'
}

fn test_tally_empty() {
	assert_json('tally([])', '{}')
}

fn test_tally_single_element() {
	assert_json_contains('tally(["x"])', '"x":1')
}

fn test_tally_integers() {
	result := execute('tally([1, 2, 1, 3, 2, 1])', map[string]VrlValue{}) or {
		panic('tally integers: ${err}')
	}
	json := vrl_to_json(result)
	assert json.contains('"1":3'), 'tally 1: got ${json}'
	assert json.contains('"2":2'), 'tally 2: got ${json}'
	assert json.contains('"3":1'), 'tally 3: got ${json}'
}

fn test_tally_all_same() {
	assert_json_contains('tally(["x", "x", "x"])', '"x":3')
}

fn test_tally_value() {
	assert_int('tally_value(["a", "b", "a", "c"], "a")', 2)
	assert_int('tally_value(["a", "b", "a", "c"], "b")', 1)
	assert_int('tally_value(["a", "b", "a", "c"], "d")', 0)
	assert_int('tally_value([], "a")', 0)
	assert_int('tally_value([1, 2, 3, 2, 1], 2)', 2)
}

fn test_match_array_any() {
	assert_bool_result("match_array([\"foo\", \"bar\", \"baz\"], r'ba')", true)
}

fn test_match_array_none() {
	assert_bool_result("match_array([\"foo\", \"bar\"], r'xyz')", false)
}

fn test_match_array_empty() {
	assert_bool_result("match_array([], r'test')", false)
}

// ============================================================
// IP functions
// ============================================================

fn test_ip_aton() {
	assert_int('ip_aton!("0.0.0.0")', 0)
	assert_int('ip_aton!("0.0.0.1")', 1)
	assert_int('ip_aton!("0.0.1.0")', 256)
	assert_int('ip_aton!("1.0.0.0")', 16777216)
	assert_int('ip_aton!("10.0.0.1")', 167772161)
	assert_int('ip_aton!("192.168.1.1")', 3232235777)
	assert_int('ip_aton!("255.255.255.255")', 4294967295)
	assert_int('ip_aton!("127.0.0.1")', 2130706433)
}

fn test_ip_ntoa() {
	assert_str('ip_ntoa!(0)', '0.0.0.0')
	assert_str('ip_ntoa!(1)', '0.0.0.1')
	assert_str('ip_ntoa!(256)', '0.0.1.0')
	assert_str('ip_ntoa!(16777216)', '1.0.0.0')
	assert_str('ip_ntoa!(167772161)', '10.0.0.1')
	assert_str('ip_ntoa!(3232235777)', '192.168.1.1')
	assert_str('ip_ntoa!(4294967295)', '255.255.255.255')
	assert_str('ip_ntoa!(2130706433)', '127.0.0.1')
}

fn test_ip_aton_ntoa_roundtrip() {
	ips := ['0.0.0.0', '127.0.0.1', '192.168.0.1', '10.0.0.1', '255.255.255.255', '172.16.0.1']
	for ip in ips {
		assert_str('ip_ntoa!(ip_aton!("${ip}"))', ip)
	}
}

fn test_ip_cidr_contains() {
	assert_bool_result('ip_cidr_contains!("192.168.0.0/16", "192.168.1.1")', true)
	assert_bool_result('ip_cidr_contains!("192.168.0.0/16", "10.0.0.1")', false)
	assert_bool_result('ip_cidr_contains!("10.0.0.0/8", "10.255.255.255")', true)
	assert_bool_result('ip_cidr_contains!("10.0.0.0/8", "11.0.0.0")', false)
	assert_bool_result('ip_cidr_contains!("0.0.0.0/0", "1.2.3.4")', true)
	assert_bool_result('ip_cidr_contains!("192.168.1.0/24", "192.168.1.255")', true)
	assert_bool_result('ip_cidr_contains!("192.168.1.0/24", "192.168.2.0")', false)
	assert_bool_result('ip_cidr_contains!("172.16.0.0/12", "172.31.255.255")', true)
	assert_bool_result('ip_cidr_contains!("172.16.0.0/12", "172.32.0.0")', false)
}

fn test_ip_cidr_contains_host_route() {
	assert_bool_result('ip_cidr_contains!("10.0.0.1/32", "10.0.0.1")', true)
	assert_bool_result('ip_cidr_contains!("10.0.0.1/32", "10.0.0.2")', false)
}

fn test_ip_cidr_contains_array() {
	assert_bool_result('ip_cidr_contains!(["10.0.0.0/8", "172.16.0.0/12"], "172.20.1.1")', true)
	assert_bool_result('ip_cidr_contains!(["10.0.0.0/8", "172.16.0.0/12"], "8.8.8.8")', false)
}

fn test_ip_subnet() {
	assert_str('ip_subnet!("192.168.1.100", "/24")', '192.168.1.0')
	assert_str('ip_subnet!("192.168.1.100", "/16")', '192.168.0.0')
	assert_str('ip_subnet!("192.168.1.100", "/8")', '192.0.0.0')
	assert_str('ip_subnet!("10.20.30.40", "/24")', '10.20.30.0')
	assert_str('ip_subnet!("10.20.30.40", "255.255.0.0")', '10.20.0.0')
	assert_str('ip_subnet!("255.255.255.255", "/32")', '255.255.255.255')
	assert_str('ip_subnet!("192.168.1.100", "255.255.255.0")', '192.168.1.0')
}

fn test_ip_to_ipv6() {
	assert_str('ip_to_ipv6!("192.168.1.1")', '::ffff:192.168.1.1')
	assert_str('ip_to_ipv6!("10.0.0.1")', '::ffff:10.0.0.1')
	assert_str('ip_to_ipv6!("::1")', '::1')
}

fn test_ipv6_to_ipv4() {
	assert_str('ipv6_to_ipv4!("::ffff:192.168.1.1")', '192.168.1.1')
	assert_str('ipv6_to_ipv4!("::ffff:10.0.0.1")', '10.0.0.1')
}

fn test_ipv6_to_ipv4_not_mapped() {
	_ := execute('ipv6_to_ipv4!("::1")', map[string]VrlValue{}) or {
		assert err.msg().contains('not an IPv4-mapped')
		return
	}
	panic('expected error for non-mapped address')
}

fn test_is_ipv4() {
	assert_bool_result('is_ipv4("192.168.1.1")', true)
	assert_bool_result('is_ipv4("10.0.0.1")', true)
	assert_bool_result('is_ipv4("255.255.255.255")', true)
	assert_bool_result('is_ipv4("0.0.0.0")', true)
	assert_bool_result('is_ipv4("::1")', false)
	assert_bool_result('is_ipv4("not-an-ip")', false)
	assert_bool_result('is_ipv4("999.999.999.999")', false)
	assert_bool_result('is_ipv4("1.2.3")', false)
	assert_bool_result('is_ipv4("")', false)
}

fn test_is_ipv6() {
	assert_bool_result('is_ipv6("::1")', true)
	assert_bool_result('is_ipv6("fe80::1")', true)
	assert_bool_result('is_ipv6("2001:db8::1")', true)
	assert_bool_result('is_ipv6("192.168.1.1")', false)
	assert_bool_result('is_ipv6("not-an-ip")', false)
	assert_bool_result('is_ipv6("")', false)
}

fn test_ip_version() {
	assert_str('ip_version!("192.168.1.1")', 'IPv4')
	assert_str('ip_version!("10.0.0.1")', 'IPv4')
	assert_str('ip_version!("::1")', 'IPv6')
	assert_str('ip_version!("2001:db8::1")', 'IPv6')
	assert_str('ip_version!("fe80::1")', 'IPv6')
}

fn test_ip_ipv4_ipv6_roundtrip() {
	assert_str('ipv6_to_ipv4!(ip_to_ipv6!("10.0.0.1"))', '10.0.0.1')
	assert_str('ipv6_to_ipv4!(ip_to_ipv6!("192.168.1.1"))', '192.168.1.1')
}

// ============================================================
// Codec functions: base64 (RFC 4648 Section 10 test vectors)
// ============================================================

fn test_encode_base64_rfc4648() {
	assert_str('encode_base64("")', '')
	assert_str('encode_base64("f")', 'Zg==')
	assert_str('encode_base64("fo")', 'Zm8=')
	assert_str('encode_base64("foo")', 'Zm9v')
	assert_str('encode_base64("foob")', 'Zm9vYg==')
	assert_str('encode_base64("fooba")', 'Zm9vYmE=')
	assert_str('encode_base64("foobar")', 'Zm9vYmFy')
}

fn test_decode_base64_rfc4648() {
	assert_str('decode_base64!("")', '')
	assert_str('decode_base64!("Zg==")', 'f')
	assert_str('decode_base64!("Zm8=")', 'fo')
	assert_str('decode_base64!("Zm9v")', 'foo')
	assert_str('decode_base64!("Zm9vYg==")', 'foob')
	assert_str('decode_base64!("Zm9vYmE=")', 'fooba')
	assert_str('decode_base64!("Zm9vYmFy")', 'foobar')
}

fn test_base64_no_padding() {
	assert_str('encode_base64("f", padding: false)', 'Zg')
	assert_str('encode_base64("fo", padding: false)', 'Zm8')
	assert_str('encode_base64("foo", padding: false)', 'Zm9v')
}

fn test_decode_base64_no_padding() {
	assert_str('decode_base64!("Zg")', 'f')
	assert_str('decode_base64!("Zm8")', 'fo')
}

fn test_base64_roundtrip() {
	strings := ['', 'hello', 'hello world', 'foobar', 'test data 123']
	for s in strings {
		assert_str('decode_base64!(encode_base64("${s}"))', s)
	}
}

// ============================================================
// Codec functions: base16 (hex)
// ============================================================

fn test_encode_base16() {
	assert_str('encode_base16("")', '')
	assert_str('encode_base16("f")', '66')
	assert_str('encode_base16("fo")', '666f')
	assert_str('encode_base16("foo")', '666f6f')
	assert_str('encode_base16("hello")', '68656c6c6f')
	assert_str('encode_base16("AB")', '4142')
}

fn test_decode_base16() {
	assert_str('decode_base16!("")', '')
	assert_str('decode_base16!("66")', 'f')
	assert_str('decode_base16!("666f")', 'fo')
	assert_str('decode_base16!("666f6f")', 'foo')
	assert_str('decode_base16!("68656c6c6f")', 'hello')
	assert_str('decode_base16!("4142")', 'AB')
}

fn test_base16_roundtrip() {
	strings := ['', 'hello', 'test123', 'UPPER']
	for s in strings {
		assert_str('decode_base16!(encode_base16("${s}"))', s)
	}
}

// ============================================================
// Codec functions: percent encoding
// ============================================================

fn test_encode_percent() {
	assert_str('encode_percent("hello world")', 'hello%20world')
	assert_str('encode_percent("hello")', 'hello')
	assert_str('encode_percent("")', '')
	assert_str('encode_percent("a b+c")', 'a%20b%2Bc')
	assert_str('encode_percent("100%")', '100%25')
	assert_str('encode_percent("foo/bar")', 'foo%2Fbar')
	assert_str('encode_percent("a=1&b=2")', 'a%3D1%26b%3D2')
}

fn test_decode_percent() {
	assert_str('decode_percent("hello%20world")', 'hello world')
	assert_str('decode_percent("hello")', 'hello')
	assert_str('decode_percent("")', '')
	assert_str('decode_percent("a%20b%2Bc")', 'a b+c')
	assert_str('decode_percent("100%25")', '100%')
	assert_str('decode_percent("foo%2Fbar")', 'foo/bar')
}

fn test_percent_roundtrip() {
	strings := ['hello world', 'a=1&b=2', 'path/to/file', '100%']
	for s in strings {
		assert_str('decode_percent(encode_percent("${s}"))', s)
	}
}

// ============================================================
// Codec functions: CSV encoding
// ============================================================

fn test_encode_csv_simple() {
	assert_str('encode_csv(["a", "b", "c"])', 'a,b,c')
}

fn test_encode_csv_empty() {
	assert_str('encode_csv([])', '')
}

fn test_encode_csv_integers() {
	assert_str('encode_csv([1, 2, 3])', '1,2,3')
}

fn test_encode_csv_mixed() {
	assert_str('encode_csv(["a", 1, true])', 'a,1,true')
}

fn test_encode_csv_with_quotes() {
	result := execute('encode_csv(["hello world", "foo,bar", "plain"])', map[string]VrlValue{}) or {
		panic('encode_csv quotes: ${err}')
	}
	s := result as string
	assert s.contains('"foo,bar"'), 'encode_csv should quote comma field, got ${s}'
}

fn test_encode_csv_with_double_quotes() {
	result := execute('encode_csv(["say \\"hi\\""])', map[string]VrlValue{}) or {
		panic('encode_csv dquote: ${err}')
	}
	s := result as string
	assert s.contains('""'), 'encode_csv should escape quotes, got ${s}'
}

// ============================================================
// Codec functions: key-value and logfmt encoding
// ============================================================

fn test_encode_key_value_simple() {
	result := execute('encode_key_value({"host": "localhost", "port": 8080})', map[string]VrlValue{}) or {
		panic('encode_kv: ${err}')
	}
	s := result as string
	assert s.contains('host=localhost'), 'encode_kv host: got ${s}'
	assert s.contains('port=8080'), 'encode_kv port: got ${s}'
}

fn test_encode_key_value_with_spaces() {
	result := execute('encode_key_value({"msg": "hello world"})', map[string]VrlValue{}) or {
		panic('encode_kv spaces: ${err}')
	}
	s := result as string
	assert s.contains('msg="hello world"'), 'encode_kv quoted: got ${s}'
}

fn test_encode_logfmt_simple() {
	result := execute('encode_logfmt({"level": "info", "msg": "started"})', map[string]VrlValue{}) or {
		panic('encode_logfmt: ${err}')
	}
	s := result as string
	assert s.contains('level=info'), 'encode_logfmt level: got ${s}'
	assert s.contains('msg=started'), 'encode_logfmt msg: got ${s}'
}

fn test_encode_logfmt_bool() {
	result := execute('encode_logfmt({"active": true, "debug": false})', map[string]VrlValue{}) or {
		panic('encode_logfmt bool: ${err}')
	}
	s := result as string
	assert s.contains('active=true'), 'encode_logfmt active: got ${s}'
	assert s.contains('debug=false'), 'encode_logfmt debug: got ${s}'
}

fn test_encode_logfmt_sorted_keys() {
	result := execute('encode_logfmt({"z": 1, "a": 2, "m": 3})', map[string]VrlValue{}) or {
		panic('encode_logfmt sorted: ${err}')
	}
	s := result as string
	a_pos := s.index('a=') or { -1 }
	m_pos := s.index('m=') or { -1 }
	z_pos := s.index('z=') or { -1 }
	assert a_pos < m_pos && m_pos < z_pos, 'encode_logfmt should sort keys, got ${s}'
}

fn test_encode_logfmt_quoted_value() {
	result := execute('encode_logfmt({"msg": "hello world"})', map[string]VrlValue{}) or {
		panic('encode_logfmt quoted: ${err}')
	}
	s := result as string
	assert s.contains('msg="hello world"'), 'encode_logfmt quoted value: got ${s}'
}

// ============================================================
// Codec functions: MIME Q-encoding (RFC 2047)
// ============================================================

fn test_decode_mime_q_basic() {
	assert_str('decode_mime_q!("=?UTF-8?Q?hello?=")', 'hello')
}

fn test_decode_mime_q_with_underscore() {
	assert_str('decode_mime_q!("=?UTF-8?Q?hello_world?=")', 'hello world')
}

fn test_decode_mime_q_base64() {
	assert_str('decode_mime_q!("=?UTF-8?B?aGVsbG8=?=")', 'hello')
}

fn test_decode_mime_q_base64_foobar() {
	assert_str('decode_mime_q!("=?UTF-8?B?Zm9vYmFy?=")', 'foobar')
}

fn test_decode_mime_q_hex_encoded() {
	result := execute('decode_mime_q!("=?UTF-8?Q?caf=C3=A9?=")', map[string]VrlValue{}) or {
		panic('decode_mime_q hex: ${err}')
	}
	s := result as string
	expected_bytes := [u8(0x63), 0x61, 0x66, 0xC3, 0xA9]
	assert s.bytes() == expected_bytes, 'decode_mime_q hex: got bytes ${s.bytes()}'
}

fn test_decode_mime_q_mixed_text() {
	assert_str('decode_mime_q!("Hello =?UTF-8?Q?world?= test")', 'Hello world test')
}

fn test_decode_mime_q_plain_text_preserved() {
	assert_str('decode_mime_q!("prefix =?UTF-8?Q?mid?= suffix")', 'prefix mid suffix')
}
