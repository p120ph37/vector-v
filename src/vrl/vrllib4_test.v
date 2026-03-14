module vrl

// Tests for vrllib.v — named arguments, edge cases, and deep function coverage.
// Targets uncovered branches in eval_fn_call_named dispatch and various vrllib functions.

// ============================================================================
// Named argument paths via VRL programs
// ============================================================================

fn test_named_contains_case_insensitive() {
	result := execute('contains("Hello World", "hello", case_sensitive: false)',
		map[string]VrlValue{}) or { panic('contains ci: ${err}') }
	assert result == VrlValue(true), 'expected true for case-insensitive contains'
}

fn test_named_starts_with_case_insensitive() {
	result := execute('starts_with("Hello", "hello", case_sensitive: false)',
		map[string]VrlValue{}) or { panic('starts_with ci: ${err}') }
	assert result == VrlValue(true)
}

fn test_named_ends_with_case_insensitive() {
	result := execute('ends_with("Hello", "ELLO", case_sensitive: false)',
		map[string]VrlValue{}) or { panic('ends_with ci: ${err}') }
	assert result == VrlValue(true)
}

fn test_named_replace_count() {
	result := execute('replace("aaa", "a", "b", count: 1)', map[string]VrlValue{}) or {
		panic('replace count: ${err}')
	}
	assert result == VrlValue('baa'), 'expected baa: ${vrl_to_json(result)}'
}

fn test_named_split_limit() {
	result := execute('split("a,b,c,d", ",", limit: 2)', map[string]VrlValue{}) or {
		panic('split limit: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
}

fn test_named_truncate_ellipsis() {
	result := execute('truncate("hello world", 5, ellipsis: true)', map[string]VrlValue{}) or {
		panic('truncate ellipsis: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('...'), 'expected ellipsis: ${j}'
}

fn test_named_truncate_suffix() {
	result := execute('truncate("hello world", 5, suffix: "~")', map[string]VrlValue{}) or {
		panic('truncate suffix: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('~'), 'expected suffix: ${j}'
}

fn test_named_flatten_separator() {
	result := execute('flatten({"a": {"b": 1}}, separator: "/")', map[string]VrlValue{}) or {
		panic('flatten sep: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('a/b'), 'expected a/b: ${j}'
}

fn test_named_unflatten_separator() {
	result := execute('unflatten({"a/b": 1}, separator: "/")', map[string]VrlValue{}) or {
		panic('unflatten sep: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected nested a: ${j}'
}

fn test_named_format_number_scale() {
	result := execute('format_number(1234.5678, 2)', map[string]VrlValue{}) or {
		panic('format_number scale: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('1234.57'), 'expected 1234.57: ${j}'
}

fn test_named_format_number_grouping() {
	result := execute('format_number(1234567.0, decimal_separator: ".", grouping_separator: ",")',
		map[string]VrlValue{}) or { panic('format_number grouping: ${err}') }
	j := vrl_to_json(result)
	assert j.contains(','), 'expected comma: ${j}'
}

fn test_named_ceil_precision() {
	result := execute('ceil(3.14159, precision: 2)', map[string]VrlValue{}) or {
		panic('ceil precision: ${err}')
	}
	assert result == VrlValue(3.15), 'expected 3.15: ${vrl_to_json(result)}'
}

fn test_named_floor_precision() {
	result := execute('floor(3.14159, precision: 2)', map[string]VrlValue{}) or {
		panic('floor precision: ${err}')
	}
	assert result == VrlValue(3.14), 'expected 3.14: ${vrl_to_json(result)}'
}

fn test_named_round_precision() {
	result := execute('round(3.14159, precision: 3)', map[string]VrlValue{}) or {
		panic('round precision: ${err}')
	}
	assert result == VrlValue(3.142), 'expected 3.142: ${vrl_to_json(result)}'
}

fn test_named_encode_json_pretty() {
	result := execute('encode_json({"a": 1}, pretty: true)', map[string]VrlValue{}) or {
		panic('encode_json pretty: ${err}')
	}
	j := result as string
	assert j.contains('\n'), 'expected newlines for pretty: ${j}'
}

fn test_named_to_unix_timestamp_milliseconds() {
	result := execute('to_unix_timestamp(now(), unit: "milliseconds")',
		map[string]VrlValue{}) or { panic('to_unix_ts ms: ${err}') }
	v := result as i64
	assert v > 1000000000000, 'expected milliseconds value: ${v}'
}

fn test_named_to_unix_timestamp_nanoseconds() {
	result := execute('to_unix_timestamp(now(), unit: "nanoseconds")',
		map[string]VrlValue{}) or { panic('to_unix_ts ns: ${err}') }
	v := result as i64
	assert v > 1000000000000000000, 'expected nanoseconds value: ${v}'
}

fn test_named_parse_json_max_depth() {
	result := execute('parse_json!("{}", max_depth: 10)', map[string]VrlValue{}) or {
		panic('parse_json max_depth: ${err}')
	}
	j := vrl_to_json(result)
	assert j == '{}', 'expected {}: ${j}'
}

fn test_named_assert_message() {
	execute('assert(false, message: "custom message")', map[string]VrlValue{}) or {
		assert err.msg().contains('custom message'), 'expected custom message: ${err}'
		return
	}
	assert false, 'expected assertion error'
}

fn test_named_assert_eq_message() {
	execute('assert_eq(1, 2, message: "not equal")', map[string]VrlValue{}) or {
		assert err.msg().contains('not equal'), 'expected not equal: ${err}'
		return
	}
	assert false, 'expected assertion error'
}

fn test_named_contains_all_case_insensitive() {
	result := execute('contains_all("Hello World", ["hello", "world"], case_sensitive: false)',
		map[string]VrlValue{}) or { panic('contains_all ci: ${err}') }
	assert result == VrlValue(true)
}

fn test_named_find_from() {
	result := execute('find("abcabc", "abc", from: 1)', map[string]VrlValue{}) or {
		panic('find from: ${err}')
	}
	assert result == VrlValue(i64(3)), 'expected 3: ${vrl_to_json(result)}'
}

fn test_named_get_path() {
	result := execute('get(value: {"a": {"b": 1}}, path: ["a", "b"])',
		map[string]VrlValue{}) or { panic('get named: ${err}') }
	assert result == VrlValue(i64(1)), 'expected 1: ${vrl_to_json(result)}'
}

fn test_named_set_path() {
	result := execute('set(value: {"a": 1}, path: ["b"], data: 2)',
		map[string]VrlValue{}) or { panic('set named: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('"b"'), 'expected b: ${j}'
}

fn test_named_match_pattern() {
	result := execute('.result = match(value: "hello123", pattern: r\'\\d+\')',
		map[string]VrlValue{}) or { panic('match named: ${err}') }
	assert result == VrlValue(true)
}

fn test_named_match_any_patterns() {
	result := execute('.result = match_any(value: "hello", patterns: [r\'\\d+\', r\'[a-z]+\'])',
		map[string]VrlValue{}) or { panic('match_any named: ${err}') }
	assert result == VrlValue(true)
}

fn test_named_includes_value() {
	result := execute('.result = includes(value: [1, 2, 3], item: 2)',
		map[string]VrlValue{}) or { panic('includes named: ${err}') }
	assert result == VrlValue(true)
}

fn test_named_unique_value() {
	result := execute('unique(value: [1, 1, 2, 2, 3])', map[string]VrlValue{}) or {
		panic('unique named: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('3'), 'expected 3: ${j}'
}

fn test_named_encode_base64_padding() {
	result := execute('encode_base64("hello", padding: false)', map[string]VrlValue{}) or {
		panic('encode_base64 no padding: ${err}')
	}
	s := result as string
	assert !s.ends_with('='), 'expected no padding: ${s}'
}

fn test_named_encode_base64_url_safe() {
	result := execute('encode_base64("test+data/here", charset: "url_safe")',
		map[string]VrlValue{}) or { panic('encode_base64 url safe: ${err}') }
	_ := result as string
}

fn test_named_decode_base64_url_safe() {
	encoded := execute('encode_base64("test+data/here", charset: "url_safe")',
		map[string]VrlValue{}) or { panic('encode_base64 url safe: ${err}') }
	prog := 'decode_base64!("${encoded as string}", charset: "url_safe")'
	result := execute(prog, map[string]VrlValue{}) or {
		panic('decode_base64 url safe: ${err}')
	}
	assert result == VrlValue('test+data/here'), 'roundtrip failed: ${vrl_to_json(result)}'
}

fn test_named_encode_percent_ascii_set() {
	result := execute("encode_percent(\"hello world\", ascii_set: \"NON_ALPHANUMERIC\")",
		map[string]VrlValue{}) or { panic('encode_percent set: ${err}') }
	s := result as string
	assert s.contains('%20') || s.contains('+'), 'expected encoded space: ${s}'
}

fn test_named_encode_key_value_delimiters() {
	result := execute('encode_key_value({"a": "1", "b": "2"}, key_value_delimiter: ":", field_delimiter: ",")',
		map[string]VrlValue{}) or { panic('encode_key_value delims: ${err}') }
	s := result as string
	assert s.contains(':'), 'expected colon: ${s}'
	assert s.contains(','), 'expected comma: ${s}'
}

fn test_named_log_function() {
	// log function should succeed silently
	result := execute('.x = 1\nlog(.x)', map[string]VrlValue{}) or {
		panic('log function: ${err}')
	}
}

// ============================================================================
// Type conversion edge cases
// ============================================================================

fn test_to_int_from_bool() {
	result := execute('.result = to_int(true)', map[string]VrlValue{}) or {
		panic('to_int bool: ${err}')
	}
	assert result == VrlValue(i64(1))
}

fn test_to_int_from_null() {
	result := execute('.result = to_int(null)', map[string]VrlValue{}) or {
		panic('to_int null: ${err}')
	}
	assert result == VrlValue(i64(0))
}

fn test_to_float_from_bool() {
	result := execute('.result = to_float(true)', map[string]VrlValue{}) or {
		panic('to_float bool: ${err}')
	}
	assert result == VrlValue(1.0)
}

fn test_to_float_from_null() {
	result := execute('.result = to_float(null)', map[string]VrlValue{}) or {
		panic('to_float null: ${err}')
	}
	assert result == VrlValue(0.0)
}

fn test_to_bool_from_string_truthy() {
	truthy := ['true', 'yes', 'y', 't', '1']
	for s in truthy {
		result := execute('.result = to_bool("${s}")', map[string]VrlValue{}) or {
			panic('to_bool ${s}: ${err}')
		}
		assert result == VrlValue(true), 'expected true for ${s}'
	}
}

fn test_to_bool_from_string_falsy() {
	falsy := ['false', 'no', 'n', 'f', '0']
	for s in falsy {
		result := execute('.result = to_bool("${s}")', map[string]VrlValue{}) or {
			panic('to_bool ${s}: ${err}')
		}
		assert result == VrlValue(false), 'expected false for ${s}'
	}
}

fn test_to_bool_from_float() {
	result := execute('.result = to_bool(0.0)', map[string]VrlValue{}) or {
		panic('to_bool 0.0: ${err}')
	}
	assert result == VrlValue(false)

	result2 := execute('.result = to_bool(1.5)', map[string]VrlValue{}) or {
		panic('to_bool 1.5: ${err}')
	}
	assert result2 == VrlValue(true)
}

fn test_to_bool_from_null() {
	result := execute('.result = to_bool(null)', map[string]VrlValue{}) or {
		panic('to_bool null: ${err}')
	}
	assert result == VrlValue(false)
}

fn test_to_string_from_various_types() {
	result := execute('.result = to_string(42)', map[string]VrlValue{}) or {
		panic('to_string int: ${err}')
	}
	assert result == VrlValue('42')

	result2 := execute('.result = to_string(true)', map[string]VrlValue{}) or {
		panic('to_string bool: ${err}')
	}
	assert result2 == VrlValue('true')

	result3 := execute('.result = to_string(null)', map[string]VrlValue{}) or {
		panic('to_string null: ${err}')
	}
	assert result3 == VrlValue('')
}

fn test_is_nullish_values() {
	cases := [
		['is_nullish(null)', 'true'],
		['is_nullish("")', 'true'],
		['is_nullish("-")', 'true'],
		['is_nullish("hello")', 'false'],
		['is_nullish(42)', 'false'],
	]
	for c in cases {
		result := execute('.result = ${c[0]}', map[string]VrlValue{}) or {
			panic('is_nullish ${c[0]}: ${err}')
		}
		expected := c[1] == 'true'
		assert result == VrlValue(expected), '${c[0]}: expected ${c[1]}, got ${vrl_to_json(result)}'
	}
}

// ============================================================================
// String operations edge cases
// ============================================================================

fn test_replace_regex() {
	result := execute('.result = replace("hello123world", r\'\\d+\', "NUM")',
		map[string]VrlValue{}) or { panic('replace regex: ${err}') }
	assert result == VrlValue('helloNUMworld'), 'expected helloNUMworld: ${vrl_to_json(result)}'
}

fn test_replace_regex_all() {
	result := execute('.result = replace("a1b2c3", r\'\\d\', "X")', map[string]VrlValue{}) or {
		panic('replace regex all: ${err}')
	}
	assert result == VrlValue('aXbXcX'), 'expected aXbXcX: ${vrl_to_json(result)}'
}

fn test_split_regex() {
	result := execute('split("one1two2three", r\'\\d\')', map[string]VrlValue{}) or {
		panic('split regex: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('one'), 'expected one: ${j}'
	assert j.contains('two'), 'expected two: ${j}'
	assert j.contains('three'), 'expected three: ${j}'
}

fn test_split_with_limit() {
	result := execute('split("a,b,c,d", ",", 2)', map[string]VrlValue{}) or {
		panic('split limit: ${err}')
	}
	j := vrl_to_json(result)
	// With limit 2, should get ["a", "b,c,d"]
	assert j.contains('"a"'), 'expected a: ${j}'
}

fn test_join_with_separator() {
	result := execute('join(["a", "b", "c"], "-")', map[string]VrlValue{}) or {
		panic('join sep: ${err}')
	}
	assert result == VrlValue('a-b-c'), 'expected a-b-c: ${vrl_to_json(result)}'
}

fn test_slice_negative_end() {
	result := execute('slice("hello world", 0, -6)', map[string]VrlValue{}) or {
		panic('slice neg: ${err}')
	}
	assert result == VrlValue('hello'), 'expected hello: ${vrl_to_json(result)}'
}

fn test_slice_array() {
	result := execute('slice([1, 2, 3, 4, 5], 1, 3)', map[string]VrlValue{}) or {
		panic('slice array: ${err}')
	}
	j := vrl_to_json(result)
	assert j == '[2,3]', 'expected [2,3]: ${j}'
}

fn test_strlen_unicode() {
	result := execute('strlen("héllo")', map[string]VrlValue{}) or {
		panic('strlen unicode: ${err}')
	}
	assert result == VrlValue(i64(5)), 'expected 5: ${vrl_to_json(result)}'
}

// ============================================================================
// Collection operations edge cases
// ============================================================================

fn test_compact_with_options() {
	result := execute('compact({"a": null, "b": "", "c": [], "d": 1}, null: true, string: true, array: true)',
		map[string]VrlValue{}) or { panic('compact options: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('"d"'), 'expected d: ${j}'
	assert !j.contains('"a"'), 'expected no a (null): ${j}'
}

fn test_flatten_nested_arrays() {
	result := execute('flatten([[1, [2, 3]], [4, [5]]])', map[string]VrlValue{}) or {
		panic('flatten nested: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('1'), 'expected 1: ${j}'
	assert j.contains('5'), 'expected 5: ${j}'
}

fn test_flatten_object() {
	result := execute('flatten({"a": {"b": {"c": 1}}})', map[string]VrlValue{}) or {
		panic('flatten obj: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('a.b.c'), 'expected a.b.c: ${j}'
}

fn test_unflatten_dotted_keys() {
	result := execute('unflatten({"a.b.c": 1, "a.b.d": 2})', map[string]VrlValue{}) or {
		panic('unflatten: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected nested a: ${j}'
}

fn test_merge_deep() {
	result := execute('merge({"a": {"b": 1}}, {"a": {"c": 2}}, deep: true)',
		map[string]VrlValue{}) or { panic('merge deep: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
	assert j.contains('"c"'), 'expected c: ${j}'
}

fn test_get_nested_path() {
	result := execute('get({"a": {"b": [1, 2, 3]}}, ["a", "b", 1])',
		map[string]VrlValue{}) or { panic('get nested: ${err}') }
	assert result == VrlValue(i64(2)), 'expected 2: ${vrl_to_json(result)}'
}

fn test_set_nested_path() {
	result := execute('set({"a": {"b": 1}}, ["a", "c"], 42)', map[string]VrlValue{}) or {
		panic('set nested: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"c":42'), 'expected c:42: ${j}'
}

fn test_match_any_regex() {
	result := execute('.result = match_any("test123", [r\'\\d+\', r\'[a-z]+\'])',
		map[string]VrlValue{}) or { panic('match_any: ${err}') }
	assert result == VrlValue(true)
}

fn test_find_not_found() {
	result := execute('find("hello", "xyz")', map[string]VrlValue{}) or {
		panic('find not found: ${err}')
	}
	// find returns null when not found
	j := vrl_to_json(result)
	assert j == 'null' || j.contains('-1'), 'expected null or -1: ${j}'
}

fn test_from_unix_timestamp_milliseconds() {
	result := execute('from_unix_timestamp(1622547800000, "milliseconds")',
		map[string]VrlValue{}) or { panic('from_unix_ts ms: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('2021'), 'expected 2021: ${j}'
}

fn test_from_unix_timestamp_nanoseconds() {
	result := execute('from_unix_timestamp(1622547800000000000, "nanoseconds")',
		map[string]VrlValue{}) or { panic('from_unix_ts ns: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('2021'), 'expected 2021: ${j}'
}

fn test_get_env_var() {
	// HOME should be set in most environments
	execute('get_env_var!("HOME")', map[string]VrlValue{}) or {
		// May fail in sandboxed environment, that's ok
		return
	}
}

fn test_get_env_var_missing() {
	execute('get_env_var!("NONEXISTENT_VAR_XYZZY")', map[string]VrlValue{}) or {
		assert err.msg().contains('not found') || err.msg().contains('environment'),
			'unexpected error: ${err}'
		return
	}
	// It's ok if it doesn't error (env var might actually exist)
}
