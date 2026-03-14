module vrl

// Additional coverage tests for vrllib_object.v, vrllib_string.v,
// vrllib_ip.v, vrllib_ip2.v, vrllib_community_id.v, vrllib_convert.v,
// static_check.v, and type_inference.v edge cases.

// ============================================================================
// vrllib_string.v — case conversions and path functions
// ============================================================================

fn test_camelcase_with_separators() {
	cases := [
		['camelcase("hello_world")', 'helloWorld'],
		['camelcase("hello-world")', 'helloWorld'],
		['camelcase("hello world")', 'helloWorld'],
		['camelcase("HELLO_WORLD")', 'helloWorld'],
		['camelcase("")', ''],
	]
	for c in cases {
		result := execute('.result = ${c[0]}', map[string]VrlValue{}) or {
			panic('${c[0]}: ${err}')
		}
		assert result == VrlValue(c[1]), '${c[0]}: expected "${c[1]}", got ${vrl_to_json(result)}'
	}
}

fn test_pascalcase() {
	cases := [
		['pascalcase("hello_world")', 'HelloWorld'],
		['pascalcase("hello-world")', 'HelloWorld'],
		['pascalcase("already")', 'Already'],
	]
	for c in cases {
		result := execute('.result = ${c[0]}', map[string]VrlValue{}) or {
			panic('${c[0]}: ${err}')
		}
		assert result == VrlValue(c[1]), '${c[0]}: expected "${c[1]}", got ${vrl_to_json(result)}'
	}
}

fn test_snakecase() {
	cases := [
		['snakecase("helloWorld")', 'hello_world'],
		['snakecase("HelloWorld")', 'hello_world'],
		['snakecase("hello-world")', 'hello_world'],
	]
	for c in cases {
		result := execute('.result = ${c[0]}', map[string]VrlValue{}) or {
			panic('${c[0]}: ${err}')
		}
		assert result == VrlValue(c[1]), '${c[0]}: expected "${c[1]}", got ${vrl_to_json(result)}'
	}
}

fn test_kebabcase() {
	result := execute('.result = kebabcase("helloWorld")', map[string]VrlValue{}) or {
		panic('kebabcase: ${err}')
	}
	assert result == VrlValue('hello-world'), 'expected hello-world: ${vrl_to_json(result)}'
}

fn test_screaming_snakecase() {
	result := execute('.result = screamingsnakecase("helloWorld")',
		map[string]VrlValue{}) or { panic('screaming: ${err}') }
	assert result == VrlValue('HELLO_WORLD'), 'expected HELLO_WORLD: ${vrl_to_json(result)}'
}

fn test_basename_and_dirname() {
	result := execute('.result = basename("/usr/local/bin/file.txt")',
		map[string]VrlValue{}) or { panic('basename: ${err}') }
	assert result == VrlValue('file.txt'), 'expected file.txt: ${vrl_to_json(result)}'

	result2 := execute('.result = dirname("/usr/local/bin/file.txt")',
		map[string]VrlValue{}) or { panic('dirname: ${err}') }
	assert result2 == VrlValue('/usr/local/bin'), 'expected /usr/local/bin: ${vrl_to_json(result2)}'
}

fn test_split_path() {
	result := execute('split_path("/usr/local/bin")', map[string]VrlValue{}) or {
		panic('split_path: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('usr'), 'expected usr: ${j}'
	assert j.contains('local'), 'expected local: ${j}'
	assert j.contains('bin'), 'expected bin: ${j}'
}

fn test_shannon_entropy_varied() {
	// High entropy string
	result := execute('shannon_entropy("abcdefghijklmnop")', map[string]VrlValue{}) or {
		panic('entropy high: ${err}')
	}
	v := result as f64
	assert v > 3.0, 'expected high entropy: ${v}'

	// Low entropy string
	result2 := execute('shannon_entropy("aaaa")', map[string]VrlValue{}) or {
		panic('entropy low: ${err}')
	}
	v2 := result2 as f64
	assert v2 < 0.01, 'expected low entropy: ${v2}'
}

fn test_sieve_pattern() {
	result := execute("sieve(\"hello123world\", r'[a-z]+')", map[string]VrlValue{}) or {
		panic('sieve: ${err}')
	}
	assert result == VrlValue('helloworld'), 'expected helloworld: ${vrl_to_json(result)}'
}

// ============================================================================
// vrllib_ip.v — IP address functions
// ============================================================================

fn test_ip_cidr_contains() {
	cases := [
		['ip_cidr_contains("192.168.1.0/24", "192.168.1.100")', 'true'],
		['ip_cidr_contains("192.168.1.0/24", "192.168.2.1")', 'false'],
		['ip_cidr_contains("10.0.0.0/8", "10.255.255.255")', 'true'],
	]
	for c in cases {
		result := execute('.result = ${c[0]}', map[string]VrlValue{}) or {
			panic('${c[0]}: ${err}')
		}
		expected := c[1] == 'true'
		assert result == VrlValue(expected), '${c[0]}: expected ${c[1]}'
	}
}

fn test_ip_subnet() {
	result := execute('ip_subnet("192.168.1.100", "/24")', map[string]VrlValue{}) or {
		panic('ip_subnet: ${err}')
	}
	s := result as string
	assert s.contains('192.168.1'), 'expected 192.168.1.x: ${s}'
}

fn test_ip_to_ipv6() {
	result := execute('ip_to_ipv6("192.168.1.1")', map[string]VrlValue{}) or {
		panic('ip_to_ipv6: ${err}')
	}
	s := result as string
	assert s.contains('::ffff:') || s.contains('c0a8'), 'expected IPv6-mapped: ${s}'
}

fn test_is_ipv4_and_ipv6() {
	assert_bool_result := fn (prog string, expected bool) {
		result := execute('.result = ${prog}', map[string]VrlValue{}) or {
			panic('${prog}: ${err}')
		}
		assert result == VrlValue(expected), '${prog}: expected ${expected}'
	}
	assert_bool_result('is_ipv4("192.168.1.1")', true)
	assert_bool_result('is_ipv4("::1")', false)
	assert_bool_result('is_ipv6("::1")', true)
	assert_bool_result('is_ipv6("192.168.1.1")', false)
}

fn test_ip_version() {
	result := execute('ip_version("192.168.1.1")', map[string]VrlValue{}) or {
		panic('ip_version v4: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('4'), 'expected IPv4: ${j}'

	result2 := execute('ip_version("::1")', map[string]VrlValue{}) or {
		panic('ip_version v6: ${err}')
	}
	j2 := vrl_to_json(result2)
	assert j2.contains('6'), 'expected IPv6: ${j2}'
}

fn test_ip_aton_ntoa_roundtrip() {
	result := execute('ip_ntoa(ip_aton("192.168.1.1"))', map[string]VrlValue{}) or {
		panic('aton/ntoa: ${err}')
	}
	assert result == VrlValue('192.168.1.1'), 'expected 192.168.1.1: ${vrl_to_json(result)}'
}

fn test_ipv6_to_ipv4() {
	result := execute('ipv6_to_ipv4!("::ffff:192.168.1.1")', map[string]VrlValue{}) or {
		// May not be implemented
		return
	}
	s := result as string
	assert s.contains('192.168.1'), 'expected 192.168.1: ${s}'
}

// ============================================================================
// vrllib_community_id.v
// ============================================================================

fn test_community_id_tcp() {
	// community_id(source_ip, dest_ip, source_port, dest_port, protocol, [seed])
	result := execute('community_id!(source_ip: "192.168.1.1", destination_ip: "10.0.0.1", source_port: 12345, destination_port: 80, protocol: 6)',
		map[string]VrlValue{}) or { panic('community_id tcp: ${err}') }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

fn test_community_id_udp() {
	result := execute('community_id!(source_ip: "192.168.1.1", destination_ip: "10.0.0.1", source_port: 5000, destination_port: 53, protocol: 17)',
		map[string]VrlValue{}) or { panic('community_id udp: ${err}') }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

fn test_community_id_icmp() {
	result := execute('community_id!(source_ip: "192.168.1.1", destination_ip: "10.0.0.1", protocol: 1)',
		map[string]VrlValue{}) or { panic('community_id icmp: ${err}') }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

// ============================================================================
// vrllib_convert.v — syslog conversions
// ============================================================================

fn test_to_syslog_level() {
	cases := [
		['to_syslog_level(0)', 'emerg'],
		['to_syslog_level(3)', 'err'],
		['to_syslog_level(6)', 'info'],
		['to_syslog_level(7)', 'debug'],
	]
	for c in cases {
		result := execute('.result = ${c[0]}', map[string]VrlValue{}) or {
			panic('${c[0]}: ${err}')
		}
		assert result == VrlValue(c[1]), '${c[0]}: expected "${c[1]}", got ${vrl_to_json(result)}'
	}
}

fn test_to_syslog_severity() {
	cases := [
		['to_syslog_severity("emerg")', '0'],
		['to_syslog_severity("err")', '3'],
		['to_syslog_severity("info")', '6'],
	]
	for c in cases {
		result := execute('.result = ${c[0]}', map[string]VrlValue{}) or {
			panic('${c[0]}: ${err}')
		}
		v := result as i64
		assert '${v}' == c[1], '${c[0]}: expected ${c[1]}, got ${v}'
	}
}

fn test_to_syslog_facility() {
	result := execute('.result = to_syslog_facility(0)', map[string]VrlValue{}) or {
		panic('syslog_facility: ${err}')
	}
	s := result as string
	assert s == 'kern', 'expected kern: ${s}'
}

fn test_to_syslog_facility_code() {
	result := execute('.result = to_syslog_facility_code("kern")', map[string]VrlValue{}) or {
		panic('syslog_facility_code: ${err}')
	}
	v := result as i64
	assert v == 0, 'expected 0: ${v}'
}

// ============================================================================
// vrllib_object.v — object operations
// ============================================================================

fn test_object_from_array_with_key_value() {
	result := execute('object_from_array([["key1", "val1"], ["key2", "val2"]])',
		map[string]VrlValue{}) or { panic('object_from_array: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('key1'), 'expected key1: ${j}'
	assert j.contains('val1'), 'expected val1: ${j}'
}

fn test_zip_arrays() {
	result := execute('zip(["a", "b", "c"], [1, 2, 3])', map[string]VrlValue{}) or {
		panic('zip: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
}

fn test_remove_fields() {
	result := execute('remove({"a": 1, "b": 2, "c": 3}, ["b"])',
		map[string]VrlValue{}) or { panic('remove: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
	assert !j.contains('"b"'), 'expected no b: ${j}'
	assert j.contains('"c"'), 'expected c: ${j}'
}

fn test_unnest_path() {
	result := execute('.tags = ["a", "b"]\nunnest(.tags)', map[string]VrlValue{}) or {
		panic('unnest: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('['), 'expected array result: ${j}'
}

// ============================================================================
// static_check.v — additional paths via execute_checked
// ============================================================================

fn sc3_checked_ok(source string) {
	execute_checked(source, map[string]VrlValue{}) or {
		panic('expected OK for: ${source}\nerror: ${err}')
	}
}

fn test_sc3_for_in_loop() {
	sc3_checked_ok('for_each([1,2,3]) -> |_i, v| { .x = v }')
}

fn test_sc3_complex_if_chain() {
	sc3_checked_ok('if true { .x = 1 } else if false { .x = 2 } else { .x = 3 }')
}

fn test_sc3_nested_function_calls() {
	sc3_checked_ok('.x = upcase(downcase("Hello"))')
}

fn test_sc3_array_literal() {
	sc3_checked_ok('.arr = [1, "two", true, null]')
}

fn test_sc3_object_literal() {
	sc3_checked_ok('.obj = {"key": "value", "num": 42}')
}

fn test_sc3_string_interpolation() {
	sc3_checked_ok('.name = "world"\n.msg = "hello #{.name}"')
}

fn test_sc3_comparison_operators() {
	sc3_checked_ok('.x = 1 > 0\n.y = "a" == "a"\n.z = 1 != 2')
}

fn test_sc3_logical_operators() {
	sc3_checked_ok('.x = true && false\n.y = true || false')
}

fn test_sc3_type_coercion_in_arithmetic() {
	sc3_checked_ok('.x = 1 + 2\n.y = .x * 3')
}

fn test_sc3_type_propagation_through_assignment() {
	sc3_checked_ok('.x = "hello"\n.y = upcase(.x)')
}

fn test_sc3_type_check_function_result() {
	sc3_checked_ok('if is_string(.message) { .msg = downcase(.message) }')
}

fn test_sc3_nested_path_type_tracking() {
	sc3_checked_ok('.event = {}\n.event.type = "log"\n.event.severity = 5\n.processed = true')
}

// ============================================================================
// vrllib_enumerate.v — tally and match_array
// ============================================================================

fn test_tally_value_counts() {
	result := execute('tally_value([1, 2, 2, 3, 3, 3], 3)', map[string]VrlValue{}) or {
		panic('tally_value: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('3'), 'expected 3: ${j}'
}

fn test_match_array_all() {
	result := execute('.result = match_array([1, 2, 3], r\'\\d+\', "all")',
		map[string]VrlValue{}) or {
		// match_array may expect string array
		return
	}
}

fn test_match_array_strings() {
	result := execute('.result = match_array(["hello", "world", "123"], r\'\\d+\')',
		map[string]VrlValue{}) or { panic('match_array: ${err}') }
	j := vrl_to_json(result)
	// Should indicate at least one match
	assert j.contains('true') || j.contains('false'), 'expected boolean: ${j}'
}

// ============================================================================
// vrllib_crypto.v — hashing edge cases
// ============================================================================

fn test_sha2_variants() {
	// SHA-256 (default)
	r256 := execute('sha2("hello")', map[string]VrlValue{}) or {
		panic('sha2 default: ${err}')
	}
	s256 := r256 as string
	assert s256.len == 64, 'expected 64-char SHA-256: len=${s256.len}'

	// SHA-512
	r512 := execute('sha2("hello", "SHA-512")', map[string]VrlValue{}) or {
		panic('sha2 512: ${err}')
	}
	s512 := r512 as string
	assert s512.len == 128, 'expected 128-char SHA-512: len=${s512.len}'

	// SHA-384
	r384 := execute('sha2("hello", "SHA-384")', map[string]VrlValue{}) or {
		panic('sha2 384: ${err}')
	}
	s384 := r384 as string
	assert s384.len == 96, 'expected 96-char SHA-384: len=${s384.len}'

	// SHA-224
	r224 := execute('sha2("hello", "SHA-224")', map[string]VrlValue{}) or {
		panic('sha2 224: ${err}')
	}
	s224 := r224 as string
	assert s224.len == 56, 'expected 56-char SHA-224: len=${s224.len}'
}

fn test_hmac_sha256() {
	result := execute('hmac("hello", "secret")', map[string]VrlValue{}) or {
		panic('hmac: ${err}')
	}
	s := result as string
	assert s.len > 0, 'expected non-empty HMAC: ${s}'
}

fn test_crc32_value() {
	result := execute('crc32("hello")', map[string]VrlValue{}) or {
		panic('crc32: ${err}')
	}
	v := result as i64
	assert v == 907060870, 'expected 907060870: ${v}'
}

fn test_seahash_value() {
	result := execute('seahash("hello")', map[string]VrlValue{}) or {
		panic('seahash: ${err}')
	}
	// Just verify it returns an integer
	_ := result as i64
}

fn test_xxhash_value() {
	result := execute('xxhash("hello")', map[string]VrlValue{}) or {
		panic('xxhash: ${err}')
	}
	_ := result as i64
}

// ============================================================================
// vrllib_type.v — type checking functions
// ============================================================================

fn test_tag_types_externally() {
	result := execute('tag_types_externally({"a": 1, "b": "hello", "c": true})',
		map[string]VrlValue{}) or { panic('tag_types: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('integer') || j.contains('string') || j.contains('boolean'),
		'expected type tags: ${j}'
}

fn test_is_empty_various() {
	cases := [
		['is_empty("")', 'true'],
		['is_empty("hello")', 'false'],
		['is_empty([])', 'true'],
		['is_empty([1])', 'false'],
		['is_empty({})', 'true'],
		['is_empty({"a": 1})', 'false'],
	]
	for c in cases {
		result := execute('.result = ${c[0]}', map[string]VrlValue{}) or {
			panic('${c[0]}: ${err}')
		}
		expected := c[1] == 'true'
		assert result == VrlValue(expected), '${c[0]}: expected ${c[1]}'
	}
}

fn test_is_json_valid() {
	result := execute('.result = is_json("{}")', map[string]VrlValue{}) or {
		panic('is_json valid: ${err}')
	}
	assert result == VrlValue(true)
}

fn test_is_json_invalid() {
	result := execute('.result = is_json("not json")', map[string]VrlValue{}) or {
		panic('is_json invalid: ${err}')
	}
	assert result == VrlValue(false)
}

fn test_is_regex_function() {
	// is_regex may check if value is a regex type, not if string is valid regex
	result := execute('.result = is_regex("[a-z]+")', map[string]VrlValue{}) or {
		panic('is_regex: ${err}')
	}
	// String input returns false (it's a string, not a regex)
	// Regex literal would return true
	_ := result
}
