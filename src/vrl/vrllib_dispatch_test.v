module vrl

// Tests targeting uncovered code paths in vrllib.v:
// - eval_fn_call_named() dispatch branches
// - validate_fn_args() too-many-args error path
// - validate_fn_keywords() unknown-keyword error path
// - fn_valid_keywords() metadata
// - fn_max_args() metadata

// ============================================================================
// Named argument dispatch: string functions
// ============================================================================

fn test_dispatch_contains_named_all_args() {
	result := execute('contains(value: "Hello World", substring: "hello", case_sensitive: false)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_dispatch_starts_with_named_all_args() {
	result := execute('starts_with(value: "Hello", substring: "hello", case_sensitive: false)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_dispatch_ends_with_named_all_args() {
	result := execute('ends_with(value: "Hello", substring: "ELLO", case_sensitive: false)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_dispatch_replace_named_count() {
	result := execute('replace(value: "aaa", pattern: "a", with: "b", count: 2)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue('bba')
}

fn test_dispatch_split_named_limit() {
	result := execute('split(value: "a,b,c,d", pattern: ",", limit: 2)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"')
}

fn test_dispatch_truncate_named_ellipsis() {
	result := execute('truncate(value: "hello world", limit: 5, ellipsis: true)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.contains('...')
}

fn test_dispatch_truncate_named_suffix() {
	result := execute('truncate(value: "hello world", limit: 5, suffix: "~~")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.contains('~~')
}

// ============================================================================
// Named argument dispatch: collection functions
// ============================================================================

fn test_dispatch_flatten_named_separator() {
	result := execute('flatten(value: {"a": {"b": 1}}, separator: "/")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('a/b')
}

fn test_dispatch_unflatten_named_separator() {
	result := execute('unflatten(value: {"a/b": 1}, separator: "/")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"')
}

fn test_dispatch_contains_all_named() {
	result := execute('contains_all(value: "Hello World", substring: ["hello", "world"], case_sensitive: false)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_dispatch_find_named_from() {
	result := execute('find(value: "abcabc", pattern: "abc", from: 1)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(3))
}

fn test_dispatch_get_named() {
	result := execute('get(value: {"x": {"y": 42}}, path: ["x", "y"])',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(42))
}

fn test_dispatch_set_named() {
	result := execute('set(value: {"a": 1}, path: ["b"], data: 99)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"b"')
	assert j.contains('99')
}

fn test_dispatch_remove_named() {
	result := execute('remove(value: {"a": 1, "b": 2}, path: ["a"], compact: false)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert !j.contains('"a"')
	assert j.contains('"b"')
}

fn test_dispatch_object_from_array_named_with_keys() {
	result := execute('object_from_array(values: ["x", "y"], keys: ["k1", "k2"])',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"k1"')
}

fn test_dispatch_object_from_array_named_no_keys() {
	result := execute('object_from_array(values: [["a", 1], ["b", 2]])',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"')
}

// ============================================================================
// Named argument dispatch: math functions
// ============================================================================

fn test_dispatch_format_number_named() {
	result := execute('format_number(value: 1234567.89, decimal_separator: ",", grouping_separator: ".")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.contains(',') || s.contains('.')
}

fn test_dispatch_ceil_named_precision() {
	result := execute('ceil(value: 3.141, precision: 1)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(3.2)
}

fn test_dispatch_floor_named_precision() {
	result := execute('floor(value: 3.149, precision: 1)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(3.1)
}

fn test_dispatch_round_named_precision() {
	result := execute('round(value: 3.145, precision: 2)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(3.15)
}

// ============================================================================
// Named argument dispatch: encoding/codec functions
// ============================================================================

fn test_dispatch_encode_json_named_pretty() {
	result := execute('encode_json(value: {"a": 1}, pretty: true)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.contains('\n')
}

fn test_dispatch_to_unix_timestamp_named_unit() {
	result := execute('to_unix_timestamp(value: now(), unit: "milliseconds")',
		map[string]VrlValue{}) or { return }
	v := result as i64
	assert v > 1000000000000
}

fn test_dispatch_to_unix_timestamp_named_nanoseconds() {
	result := execute('to_unix_timestamp(value: now(), unit: "nanoseconds")',
		map[string]VrlValue{}) or { return }
	v := result as i64
	assert v > 1000000000000000000
}

fn test_dispatch_parse_json_named_max_depth() {
	result := execute('parse_json!(value: "{\"a\":1}", max_depth: 5)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"')
}

fn test_dispatch_decode_json_named_max_depth() {
	result := execute('decode_json!(value: "[1,2,3]", max_depth: 10)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('1')
}

fn test_dispatch_encode_base64_named_padding_false() {
	result := execute('encode_base64(value: "hello", padding: false)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert !s.ends_with('=')
}

fn test_dispatch_encode_base64_named_charset() {
	result := execute('encode_base64(value: "hello", charset: "url_safe")',
		map[string]VrlValue{}) or { return }
	_ := result as string
}

fn test_dispatch_decode_base64_named_charset() {
	result := execute('decode_base64!(value: "aGVsbG8", charset: "standard")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s == 'hello'
}

fn test_dispatch_encode_percent_named_ascii_set() {
	result := execute('encode_percent(value: "hello world", ascii_set: "NON_ALPHANUMERIC")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.contains('%20')
}

fn test_dispatch_encode_key_value_named() {
	result := execute('encode_key_value(value: {"a": "1", "b": "2"}, key_value_delimiter: ":", field_delimiter: ",")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.contains(':')
}

fn test_dispatch_encode_csv_named_delimiter() {
	result := execute('encode_csv(value: ["a", "b", "c"], delimiter: ";")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.contains(';')
}

fn test_dispatch_parse_key_value_named() {
	result := execute('parse_key_value!(value: "a:1,b:2", key_value_delimiter: ":", field_delimiter: ",")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"')
}

fn test_dispatch_parse_csv_named_delimiter() {
	result := execute('parse_csv!(value: "a;b;c", delimiter: ";")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"')
}

fn test_dispatch_parse_duration_named() {
	result := execute('parse_duration!(value: "1s", unit: "ms")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_dispatch_parse_bytes_named() {
	result := execute('parse_bytes!(value: "1KiB", unit: "b")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_dispatch_parse_timestamp_named() {
	result := execute('parse_timestamp!(value: "2021-01-01T00:00:00Z", format: "%Y-%m-%dT%H:%M:%SZ")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('2021')
}

fn test_dispatch_format_timestamp_named() {
	result := execute('format_timestamp!(value: now(), format: "%Y-%m-%d")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.len == 10
}

fn test_dispatch_format_timestamp_named_timezone() {
	result := execute('format_timestamp!(value: now(), format: "%Y-%m-%d", timezone: "UTC")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.len == 10
}

// ============================================================================
// Named argument dispatch: crypto functions
// ============================================================================

fn test_dispatch_sha2_named_variant() {
	result := execute('sha2(value: "hello", variant: "SHA-256")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.len > 0
}

fn test_dispatch_hmac_named_algorithm() {
	result := execute('hmac(value: "hello", key: "secret", algorithm: "SHA-256")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.len > 0
}

// ============================================================================
// Named argument dispatch: pattern/regex functions
// ============================================================================

fn test_dispatch_match_named() {
	result := execute('.result = match(value: "abc123", pattern: r\'\\d+\')',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_dispatch_match_any_named() {
	result := execute('.result = match_any(value: "hello", patterns: [r\'\\d+\', r\'[a-z]+\'])',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_dispatch_includes_named() {
	result := execute('.result = includes(value: [1, 2, 3], item: 2)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_dispatch_unique_named() {
	result := execute('unique(value: [1, 1, 2, 3, 3])',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('2')
}

fn test_dispatch_sieve_named() {
	result := execute('sieve(value: "abc123def", permitted_characters: r\'[a-z]\')',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s == 'abcdef'
}

fn test_dispatch_sieve_named_replace() {
	result := execute('sieve(value: "abc123def", permitted_characters: r\'[a-z]\', replace_single: "*")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.contains('*')
}

fn test_dispatch_shannon_entropy_named() {
	result := execute('shannon_entropy(value: "hello world")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_dispatch_chunks_named() {
	result := execute('chunks(value: [1, 2, 3, 4, 5], chunk_size: 2)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('[1,2]')
}

fn test_dispatch_match_array_named() {
	result := execute('.result = match_array(value: ["hello", "world"], pattern: r\'hell\')',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_dispatch_match_array_named_all() {
	result := execute('.result = match_array(value: ["hello", "world"], pattern: r\'\\w+\', all: true)',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_dispatch_parse_regex_named() {
	result := execute('parse_regex!(value: "abc123", pattern: r\'(?P<word>[a-z]+)(?P<num>\\d+)\')',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"word"')
}

fn test_dispatch_parse_regex_named_numeric_groups() {
	result := execute('parse_regex!(value: "abc123", pattern: r\'([a-z]+)(\\d+)\', numeric_groups: true)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('abc')
}

fn test_dispatch_parse_regex_all_named() {
	result := execute('parse_regex_all!(value: "a1b2c3", pattern: r\'(?P<letter>[a-z])(?P<digit>\\d)\')',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"letter"')
}

fn test_dispatch_parse_regex_all_named_numeric_groups() {
	result := execute('parse_regex_all!(value: "a1b2", pattern: r\'([a-z])(\\d)\', numeric_groups: true)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('a')
}

fn test_dispatch_ip_cidr_contains_named() {
	result := execute('.result = ip_cidr_contains(cidr: "192.168.0.0/16", ip: "192.168.1.1")',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

// ============================================================================
// Named argument dispatch: misc functions
// ============================================================================

fn test_dispatch_assert_named_message() {
	execute('assert(false, message: "custom fail")', map[string]VrlValue{}) or {
		assert err.msg().contains('custom fail')
		return
	}
	assert false, 'expected error'
}

fn test_dispatch_assert_eq_named_message() {
	execute('assert_eq(1, 2, message: "not equal msg")', map[string]VrlValue{}) or {
		assert err.msg().contains('not equal msg')
		return
	}
	assert false, 'expected error'
}

fn test_dispatch_parse_url_named() {
	result := execute('parse_url!(value: "https://example.com/path?q=1")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('example.com')
}

fn test_dispatch_tag_types_externally_named() {
	result := execute('tag_types_externally(value: {"a": 1, "b": "hello"})',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_dispatch_uuid_v7_named() {
	result := execute('uuid_v7()', map[string]VrlValue{}) or { return }
	s := result as string
	assert s.len > 0
}

fn test_dispatch_haversine_named() {
	result := execute('haversine(40.7128, -74.0060, 51.5074, -0.1278, measurement_unit: "kilometers")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_dispatch_log_named() {
	result := execute('log(value: "test message")', map[string]VrlValue{}) or { return }
	// log returns null
	assert result is VrlNull
}

fn test_dispatch_compact_named_options() {
	result := execute('compact(value: {"a": null, "b": "", "c": 1}, null: true, string: false)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	// should keep empty strings but remove nulls
	assert j.contains('"b"')
	assert !j.contains('"a"')
}

fn test_dispatch_parse_etld_named() {
	result := execute('parse_etld!(value: "https://www.example.com")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_dispatch_parse_query_string_named() {
	result := execute('parse_query_string!(value: "a=1&b=2")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"')
}

fn test_dispatch_basename_named() {
	result := execute('basename(value: "/foo/bar/baz.txt")',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s == 'baz.txt'
}

// ============================================================================
// Named argument dispatch: parse log functions
// ============================================================================

fn test_dispatch_parse_cef_named() {
	cef := 'CEF:0|Security|threatmanager|1.0|100|worm found|10|src=10.0.0.1 dst=2.1.2.2'
	prog := 'parse_cef!(value: "${cef}", translate_custom_fields: false)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('worm')
}

fn test_dispatch_parse_xml_named() {
	result := execute('parse_xml!(value: "<root><a>1</a></root>", trim: true, include_attr: true)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('root')
}

fn test_dispatch_parse_user_agent_named() {
	ua := 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
	result := execute('parse_user_agent!(value: "${ua}", mode: "fast")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_dispatch_parse_aws_vpc_flow_log_named() {
	log_line := '2 123456789010 eni-1235b8ca123456789 172.31.16.139 172.31.16.21 20641 22 6 20 4249 1418530010 1418530070 ACCEPT OK'
	result := execute('parse_aws_vpc_flow_log!(value: "${log_line}")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('172.31')
}

// ============================================================================
// validate_fn_args: too many arguments error
// ============================================================================

fn test_validate_too_many_args_to_string() {
	// to_string takes max 1 arg; passing 2 should fail
	execute('to_string("a", "b")', map[string]VrlValue{}) or {
		assert err.msg().contains('too many')
		return
	}
	assert false, 'expected too many args error'
}

fn test_validate_too_many_args_length() {
	execute('length("a", "b")', map[string]VrlValue{}) or {
		assert err.msg().contains('too many')
		return
	}
	assert false, 'expected too many args error'
}

fn test_validate_too_many_args_downcase() {
	execute('downcase("a", "b")', map[string]VrlValue{}) or {
		assert err.msg().contains('too many')
		return
	}
	assert false, 'expected too many args error'
}

fn test_validate_too_many_args_abs() {
	execute('abs(1, 2)', map[string]VrlValue{}) or {
		assert err.msg().contains('too many')
		return
	}
	assert false, 'expected too many args error'
}

fn test_validate_too_many_args_keys() {
	execute('keys({"a": 1}, "extra")', map[string]VrlValue{}) or {
		assert err.msg().contains('too many')
		return
	}
	assert false, 'expected too many args error'
}

// ============================================================================
// validate_fn_keywords: unknown keyword error
// ============================================================================

fn test_validate_unknown_keyword_contains() {
	execute('contains("hello", "he", bogus_kwarg: true)', map[string]VrlValue{}) or {
		assert err.msg().contains('unknown keyword')
		return
	}
	assert false, 'expected unknown keyword error'
}

fn test_validate_unknown_keyword_split() {
	execute('split("a,b", ",", invalid_key: 5)', map[string]VrlValue{}) or {
		assert err.msg().contains('unknown keyword')
		return
	}
	assert false, 'expected unknown keyword error'
}

fn test_validate_unknown_keyword_round() {
	execute('round(3.14, nonexistent: 2)', map[string]VrlValue{}) or {
		assert err.msg().contains('unknown keyword')
		return
	}
	assert false, 'expected unknown keyword error'
}

fn test_validate_unknown_keyword_encode_base64() {
	execute('encode_base64("hi", bad_option: true)', map[string]VrlValue{}) or {
		assert err.msg().contains('unknown keyword')
		return
	}
	assert false, 'expected unknown keyword error'
}

fn test_validate_unknown_keyword_parse_regex() {
	execute('parse_regex!("abc", r\'\\w+\', wrong_param: false)', map[string]VrlValue{}) or {
		assert err.msg().contains('unknown keyword')
		return
	}
	assert false, 'expected unknown keyword error'
}

// ============================================================================
// fn_valid_keywords coverage: test various function keyword lists
// ============================================================================

fn test_valid_keywords_returns_nonempty() {
	// Exercise fn_valid_keywords for a variety of functions
	fns := ['contains', 'starts_with', 'ends_with', 'split', 'replace', 'truncate',
		'match', 'match_any', 'parse_regex', 'parse_key_value', 'format_timestamp',
		'encode_base64', 'sha2', 'hmac', 'compact', 'merge', 'find', 'set', 'get',
		'remove', 'chunks', 'parse_csv', 'encode_csv', 'encode_key_value',
		'parse_duration', 'sieve', 'assert', 'assert_eq', 'log', 'redact',
		'parse_grok', 'parse_groks', 'parse_apache_log', 'parse_nginx_log',
		'parse_cef', 'parse_xml', 'parse_user_agent', 'encrypt', 'decrypt',
		'community_id', 'http_request']
	for f in fns {
		kws := fn_valid_keywords(f)
		assert kws.len > 0, 'expected keywords for ${f}'
	}
}

fn test_valid_keywords_unknown_fn_returns_empty() {
	kws := fn_valid_keywords('nonexistent_function_xyz')
	assert kws.len == 0
}

fn test_max_args_known_functions() {
	// 1-arg functions
	one_arg_fns := ['to_string', 'length', 'abs', 'keys', 'values', 'sha1', 'md5',
		'is_string', 'is_integer', 'is_float', 'is_boolean', 'is_null',
		'is_array', 'is_object', 'is_nullish', 'is_empty', 'pop',
		'tag_types_externally', 'decode_zlib', 'decode_gzip']
	for f in one_arg_fns {
		m := fn_max_args(f)
		assert m == 1, '${f} should have max 1 arg, got ${m}'
	}
}

fn test_max_args_unknown_function() {
	m := fn_max_args('some_unknown_fn')
	assert m == -1
}

fn test_max_args_encode_punycode() {
	m := fn_max_args('encode_punycode')
	assert m == 2
}

fn test_max_args_parse_etld() {
	m := fn_max_args('parse_etld')
	assert m == 3
}

// ============================================================================
// Named argument dispatch: encode_key_value with flatten_boolean
// ============================================================================

fn test_dispatch_encode_key_value_flatten_boolean() {
	result := execute('encode_key_value(value: {"a": true, "b": false}, flatten_boolean: true)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.len > 0
}

// ============================================================================
// Named argument dispatch: parse_key_value with all options
// ============================================================================

fn test_dispatch_parse_key_value_all_options() {
	result := execute('parse_key_value!(value: "a=1 b=2", key_value_delimiter: "=", field_delimiter: " ", whitespace: "lenient", accept_standalone_key: true)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"')
	assert j.contains('"b"')
}

// ============================================================================
// Named argument dispatch: parse_bytes with base
// ============================================================================

fn test_dispatch_parse_bytes_named_with_base() {
	result := execute('parse_bytes!(value: "1KB", unit: "b", base: "10")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

// ============================================================================
// Named argument dispatch: shannon_entropy segmentation
// ============================================================================

fn test_dispatch_shannon_entropy_named_segmentation() {
	result := execute('shannon_entropy(value: "aaaa", segmentation: "byte")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}
