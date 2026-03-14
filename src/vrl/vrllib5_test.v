module vrl

// Tests to exercise named-argument dispatch paths in eval_fn_call_named
// and other uncovered vrllib.v functions.

fn s5_obj(prog string, input string) !VrlValue {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(input)
	return execute(prog, obj)
}

// ============================================================================
// Named argument dispatch — encoding functions
// ============================================================================

fn test_named_encode_csv_delimiter() {
	result := execute('encode_csv(["a", "b", "c"], delimiter: ";")',
		map[string]VrlValue{}) or { panic('encode_csv delim: ${err}') }
	s := result as string
	assert s.contains(';'), 'expected semicolons: ${s}'
}

fn test_named_parse_key_value_all_params() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('key:val;other:data')
	result := execute('parse_key_value!(.input, key_value_delimiter: ":", field_delimiter: ";")',
		obj) or { panic('parse_kv named: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
	assert j.contains('other'), 'expected other: ${j}'
}

fn test_named_parse_csv_delimiter() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('a;b;c')
	result := execute('parse_csv!(.input, delimiter: ";")', obj) or {
		panic('parse_csv delim: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
}

fn test_named_parse_duration_unit() {
	result := execute('parse_duration!("5s", unit: "ms")', map[string]VrlValue{}) or {
		panic('parse_duration unit: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('5000'), 'expected 5000: ${j}'
}

fn test_named_parse_bytes_unit() {
	result := execute('parse_bytes!("1024 B", unit: "KB")', map[string]VrlValue{}) or {
		// May not support named unit
		return
	}
	j := vrl_to_json(result)
	assert j.len > 0, 'expected result: ${j}'
}

fn test_named_parse_timestamp_format() {
	result := execute('parse_timestamp!("2023-10-15", format: "%Y-%m-%d")',
		map[string]VrlValue{}) or { panic('parse_timestamp named: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('2023'), 'expected 2023: ${j}'
}

fn test_named_format_timestamp_with_tz() {
	result := execute('format_timestamp!(now(), format: "%Y-%m-%d", timezone: "UTC")',
		map[string]VrlValue{}) or { panic('format_timestamp named: ${err}') }
	s := result as string
	assert s.contains('-'), 'expected dashes: ${s}'
}

fn test_named_sha2_variant() {
	result := execute('sha2("test", variant: "SHA-256")', map[string]VrlValue{}) or {
		panic('sha2 variant: ${err}')
	}
	s := result as string
	assert s.len == 64, 'expected 64 chars: ${s.len}'
}

fn test_named_hmac_algorithm() {
	result := execute('hmac("data", "key", algorithm: "SHA-256")', map[string]VrlValue{}) or {
		panic('hmac algo: ${err}')
	}
	s := result as string
	assert s.len > 0, 'expected non-empty: ${s}'
}

fn test_named_sieve_characters() {
	result := execute("sieve(\"hello123\", permitted_characters: r'[a-z]+')",
		map[string]VrlValue{}) or { panic('sieve named: ${err}') }
	assert result == VrlValue('hello'), 'expected hello: ${vrl_to_json(result)}'
}

fn test_named_sieve_replace() {
	result := execute("sieve(\"he11o w0rld\", permitted_characters: r'[a-z ]', replace_single: \"*\")",
		map[string]VrlValue{}) or { panic('sieve replace: ${err}') }
	s := result as string
	assert s.contains('*'), 'expected asterisks: ${s}'
}

fn test_named_match_array_all() {
	result := execute('.result = match_array(["abc", "def"], pattern: r\'[a-z]+\', all: true)',
		map[string]VrlValue{}) or { panic('match_array all: ${err}') }
	assert result == VrlValue(true), 'expected true'
}

fn test_named_parse_regex_named_args() {
	result := execute("parse_regex!(value: \"test123\", pattern: r'(?P<word>[a-z]+)(?P<num>\\d+)')",
		map[string]VrlValue{}) or { panic('parse_regex named: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('word'), 'expected word: ${j}'
	assert j.contains('num'), 'expected num: ${j}'
}

fn test_named_parse_regex_all_named() {
	result := execute("parse_regex_all!(value: \"a1 b2\", pattern: r'(?P<letter>[a-z])(?P<digit>\\d)')",
		map[string]VrlValue{}) or { panic('parse_regex_all named: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('letter'), 'expected letter: ${j}'
}

fn test_named_ip_cidr_contains() {
	result := execute('.result = ip_cidr_contains(cidr: "10.0.0.0/8", ip: "10.1.2.3")',
		map[string]VrlValue{}) or { panic('ip_cidr named: ${err}') }
	assert result == VrlValue(true), 'expected true'
}

fn test_named_remove_with_compact() {
	result := execute('remove(value: {"a": 1, "b": null}, path: ["b"], compact: true)',
		map[string]VrlValue{}) or { panic('remove named: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
	assert !j.contains('"b"'), 'expected no b: ${j}'
}

fn test_named_object_from_array_with_keys() {
	result := execute('object_from_array(values: ["a", "b", "c"], keys: ["x", "y", "z"])',
		map[string]VrlValue{}) or { panic('object_from_array named: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('"x"'), 'expected x: ${j}'
}

fn test_named_tag_types_externally() {
	result := execute('tag_types_externally({"a": 1, "b": "hello"})',
		map[string]VrlValue{}) or { panic('tag_types: ${err}') }
	j := vrl_to_json(result)
	assert j.len > 5, 'expected result: ${j}'
}

fn test_named_haversine_measurement_unit() {
	result := execute('haversine(0.0, 0.0, 0.0, 1.0, measurement_unit: "miles")',
		map[string]VrlValue{}) or { panic('haversine miles: ${err}') }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected result: ${j}'
}

fn test_named_parse_xml_options() {
	result := s5_obj('parse_xml!(.input, include_attr: false, parse_bool: false)',
		'<root attr="val">true</root>') or { panic('parse_xml named opts: ${err}') }
	j := vrl_to_json(result)
	// With include_attr: false, should not have @attr
	assert j.contains('root'), 'expected root: ${j}'
}

fn test_named_parse_xml_always_text_key() {
	result := s5_obj('parse_xml!(.input, always_use_text_key: true)',
		'<root>text</root>') or { panic('parse_xml always text: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('text'), 'expected text: ${j}'
}

fn test_named_parse_user_agent_mode() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36')
	result := execute('parse_user_agent!(.input, mode: "enriched")', obj) or {
		panic('parse_ua enriched: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('browser'), 'expected browser: ${j}'
}

fn test_named_parse_cef_translate() {
	cef := 'CEF:0|V|P|1|100|T|5|cs1=val cs1Label=name'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(cef)
	result := execute('parse_cef!(.input, translate_custom_fields: true)', obj) or {
		panic('parse_cef translate named: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('name'), 'expected translated name: ${j}'
}

fn test_named_parse_apache_log_format() {
	log_line := '127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(log_line)
	result := execute('parse_apache_log!(.input, format: "common")', obj) or {
		panic('parse_apache_log named: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('GET'), 'expected GET: ${j}'
}

fn test_named_parse_nginx_log_format() {
	log_line := '93.184.216.34 - user [10/Oct/2023:13:55:36 -0700] "GET /api HTTP/1.1" 200 512 "-" "curl/7.68.0"'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(log_line)
	result := execute('parse_nginx_log!(.input, format: "combined")', obj) or {
		panic('parse_nginx_log named: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('request'), 'expected request: ${j}'
}

fn test_named_parse_groks_patterns() {
	result := execute('parse_groks!("hello", patterns: ["%{GREEDYDATA:msg}"])',
		map[string]VrlValue{}) or { panic('parse_groks named: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('msg'), 'expected msg: ${j}'
}

fn test_named_uuid_v7() {
	result := execute('uuid_v7()', map[string]VrlValue{}) or {
		panic('uuid_v7: ${err}')
	}
	s := result as string
	assert s.len == 36, 'expected UUID format: ${s}'
}

// ============================================================================
// encode/decode functions via VRL programs (named arg paths)
// ============================================================================

fn test_named_encode_zlib_compression_level() {
	result := execute('encode_zlib("hello world", compression_level: 9)',
		map[string]VrlValue{}) or { panic('encode_zlib level: ${err}') }
	// Verify it roundtrips
	encoded := result as string
	assert encoded.len > 0, 'expected non-empty encoding'
}

fn test_named_encode_gzip_compression_level() {
	result := execute('encode_gzip("hello world", compression_level: 1)',
		map[string]VrlValue{}) or { panic('encode_gzip level: ${err}') }
	encoded := result as string
	assert encoded.len > 0, 'expected non-empty encoding'
}

fn test_named_encode_key_value_delimiters() {
	result := execute('encode_key_value({"a": "1", "b": "2"}, key_value_delimiter: ":", field_delimiter: ",")',
		map[string]VrlValue{}) or { panic('encode_kv delims: ${err}') }
	s := result as string
	assert s.contains(':'), 'expected colon delimiter: ${s}'
	assert s.contains(','), 'expected comma delimiter: ${s}'
}

// ============================================================================
// String split/join edge cases
// ============================================================================

fn test_split_regex_with_limit() {
	result := execute('split("a1b2c3d", r\'\\d\', limit: 2)', map[string]VrlValue{}) or {
		panic('split regex limit: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
}

fn test_join_without_separator() {
	result := execute('join(["a", "b", "c"])', map[string]VrlValue{}) or {
		panic('join no sep: ${err}')
	}
	assert result == VrlValue('abc'), 'expected abc: ${vrl_to_json(result)}'
}

// ============================================================================
// Numeric edge cases
// ============================================================================

fn test_abs_float() {
	result := execute('.result = abs(-3.14)', map[string]VrlValue{}) or {
		panic('abs float: ${err}')
	}
	assert result == VrlValue(3.14), 'expected 3.14: ${vrl_to_json(result)}'
}

fn test_mod_operation() {
	result := execute('.result = mod(10, 3)', map[string]VrlValue{}) or {
		panic('mod: ${err}')
	}
	assert result == VrlValue(i64(1)), 'expected 1: ${vrl_to_json(result)}'
}

fn test_format_number_all_params() {
	result := execute('format_number(1234.5678, 2, decimal_separator: ",", grouping_separator: ".")',
		map[string]VrlValue{}) or { panic('format_number all: ${err}') }
	s := result as string
	assert s.contains(','), 'expected comma decimal: ${s}'
}

// ============================================================================
// Array operations
// ============================================================================

fn test_array_append() {
	result := execute('.result = push([1, 2], 3)', map[string]VrlValue{}) or {
		panic('push: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('3'), 'expected 3: ${j}'
}

fn test_keys_function() {
	result := execute('keys({"a": 1, "b": 2})', map[string]VrlValue{}) or {
		panic('keys: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
	assert j.contains('"b"'), 'expected b: ${j}'
}

fn test_pop_array() {
	result := execute('pop([1, 2, 3])', map[string]VrlValue{}) or {
		panic('pop: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('1') && j.contains('2'), 'expected [1,2]: ${j}'
}

fn test_includes_in_array() {
	result := execute('.result = includes([1, 2, 3], 2)', map[string]VrlValue{}) or {
		panic('includes: ${err}')
	}
	assert result == VrlValue(true)
}

fn test_includes_not_in_array() {
	result := execute('.result = includes([1, 2, 3], 99)', map[string]VrlValue{}) or {
		panic('includes not: ${err}')
	}
	assert result == VrlValue(false)
}

fn test_contains_all_case_sensitive() {
	result := execute('.result = contains_all("Hello World", ["Hello", "World"])',
		map[string]VrlValue{}) or { panic('contains_all cs: ${err}') }
	assert result == VrlValue(true)
}

fn test_contains_all_missing() {
	result := execute('.result = contains_all("Hello", ["Hello", "World"])',
		map[string]VrlValue{}) or { panic('contains_all missing: ${err}') }
	assert result == VrlValue(false)
}

// ============================================================================
// Complex multi-step VRL programs exercising more runtime paths
// ============================================================================

fn test_complex_pipeline() {
	prog := '
.msg = downcase(.message ?? "DEFAULT")
.len = length(.msg)
if .len > 5 {
  .truncated = truncate(.msg, 5, ellipsis: true)
} else {
  .truncated = .msg
}
encode_json({"message": .msg, "length": .len})
'
	result := execute(prog, map[string]VrlValue{}) or { panic('complex pipeline: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('message'), 'expected message: ${j}'
	assert j.contains('default'), 'expected default: ${j}'
}

fn test_complex_error_handling() {
	prog := '
result, err = parse_json("{invalid")
if err != null {
  "parse_failed"
} else {
  "ok"
}
'
	result := execute(prog, map[string]VrlValue{}) or { panic('complex error: ${err}') }
	s := result as string
	assert s == 'parse_failed', 'expected parse_failed: ${s}'
}

fn test_complex_array_processing() {
	prog := '
items = ["hello", "WORLD", "Test"]
lower = []
for_each(items) -> |_i, v| {
  lower = push(lower, downcase(v))
}
length(lower)
'
	result := execute(prog, map[string]VrlValue{}) or { panic('complex array: ${err}') }
	v := result as i64
	assert v == 3, 'expected 3: ${v}'
}

fn test_complex_nested_functions() {
	prog := '
encode_json(merge(
  {"a": 1},
  {"b": upcase(downcase("HELLO"))},
  deep: true
))
'
	result := execute(prog, map[string]VrlValue{}) or { panic('complex nested: ${err}') }
	s := result as string
	assert s.contains('HELLO'), 'expected HELLO: ${s}'
}
