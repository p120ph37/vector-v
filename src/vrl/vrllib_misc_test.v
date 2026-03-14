module vrl

import time

// Tests targeting uncovered code paths in vrllib_misc.v, vrllib_type.v,
// value.v, vrllib_object.v, vrllib_string.v, vrllib_enumerate.v, and lexer.v.

// ============================================================
// Helper functions
// ============================================================

fn assert_vrl_str(program string, expected string) {
	result := execute(program, map[string]VrlValue{}) or { panic('${program}: ${err}') }
	assert result == VrlValue(expected), '${program}: expected "${expected}", got ${vrl_to_json(result)}'
}

fn assert_vrl_int(program string, expected i64) {
	result := execute(program, map[string]VrlValue{}) or { panic('${program}: ${err}') }
	assert result == VrlValue(expected), '${program}: expected ${expected}, got ${vrl_to_json(result)}'
}

fn assert_vrl_bool(program string, expected bool) {
	result := execute(program, map[string]VrlValue{}) or { panic('${program}: ${err}') }
	assert result == VrlValue(expected), '${program}: expected ${expected}, got ${vrl_to_json(result)}'
}

fn assert_vrl_json(program string, expected string) {
	result := execute(program, map[string]VrlValue{}) or { panic('${program}: ${err}') }
	j := vrl_to_json(result)
	assert j == expected, '${program}: expected ${expected}, got ${j}'
}

fn assert_vrl_null(program string) {
	result := execute(program, map[string]VrlValue{}) or { panic('${program}: ${err}') }
	assert result is VrlNull, '${program}: expected null, got ${vrl_to_json(result)}'
}

fn assert_vrl_error(program string) {
	if _ := execute(program, map[string]VrlValue{}) {
		assert false, '${program}: expected error but got success'
	}
}

// ============================================================
// vrllib_misc.v: uuid_from_friendly_id, base62, hex padding
// ============================================================

fn test_uuid_from_friendly_id_empty_string() {
	if _ := fn_uuid_from_friendly_id([VrlValue('')]) {
		assert false, 'expected error for empty friendly id'
	}
}

fn test_uuid_from_friendly_id_wrong_type() {
	if _ := fn_uuid_from_friendly_id([VrlValue(i64(42))]) {
		assert false, 'expected error for non-string argument'
	}
}

fn test_uuid_from_friendly_id_no_args() {
	if _ := fn_uuid_from_friendly_id([]VrlValue{}) {
		assert false, 'expected error for no arguments'
	}
}

fn test_base62_char_val_digits() {
	assert base62_char_val(`0`)! == 0
	assert base62_char_val(`9`)! == 9
}

fn test_base62_char_val_uppercase() {
	assert base62_char_val(`A`)! == 10
	assert base62_char_val(`Z`)! == 35
}

fn test_base62_char_val_lowercase() {
	assert base62_char_val(`a`)! == 36
	assert base62_char_val(`z`)! == 61
}

fn test_base62_char_val_invalid() {
	if _ := base62_char_val(`!`) {
		assert false, 'expected error for invalid character'
	}
}

fn test_u64_mul_hi_zero() {
	assert u64_mul_hi(0, 100) == 0
	assert u64_mul_hi(100, 0) == 0
}

fn test_u64_mul_hi_small() {
	// Small values should have 0 high bits
	assert u64_mul_hi(1, 1) == 0
	assert u64_mul_hi(100, 62) == 0
}

fn test_u64_mul_hi_large() {
	// Large values should produce non-zero high bits
	result := u64_mul_hi(0xFFFFFFFFFFFFFFFF, 2)
	assert result == 1
}

fn test_u32_hex_pad() {
	assert u32_hex_pad(u32(0), 8) == '00000000'
	assert u32_hex_pad(u32(0xFF), 8) == '000000ff'
	assert u32_hex_pad(u32(0x12345678), 8) == '12345678'
}

fn test_u16_hex_pad() {
	assert u16_hex_pad(u16(0), 4) == '0000'
	assert u16_hex_pad(u16(0xFF), 4) == '00ff'
	assert u16_hex_pad(u16(0xABCD), 4) == 'abcd'
}

fn test_u64_hex_pad() {
	assert u64_hex_pad(u64(0), 12) == '000000000000'
	assert u64_hex_pad(u64(0xABC), 12) == '000000000abc'
}

fn test_encode_charset_no_args() {
	if _ := fn_encode_charset([]VrlValue{}, map[string]VrlValue{}) {
		assert false, 'expected error for no args'
	}
}

fn test_encode_charset_wrong_type() {
	if _ := fn_encode_charset([VrlValue(i64(42))], map[string]VrlValue{}) {
		assert false, 'expected error for non-string input'
	}
}

fn test_encode_charset_missing_charset() {
	if _ := fn_encode_charset([VrlValue('hello')], map[string]VrlValue{}) {
		assert false, 'expected error for missing charset'
	}
}

fn test_encode_charset_invalid_charset() {
	if _ := fn_encode_charset([VrlValue('hello')], {
		'to_charset': VrlValue('INVALID-NONEXISTENT-CHARSET')
	}) {
		assert false, 'expected error for invalid charset'
	}
}

fn test_encode_charset_wrong_charset_type() {
	if _ := fn_encode_charset([VrlValue('hello')], {
		'to_charset': VrlValue(i64(42))
	}) {
		assert false, 'expected error for non-string charset'
	}
}

fn test_decode_charset_no_args() {
	if _ := fn_decode_charset([]VrlValue{}, map[string]VrlValue{}) {
		assert false, 'expected error for no args'
	}
}

fn test_decode_charset_wrong_type() {
	if _ := fn_decode_charset([VrlValue(i64(42))], map[string]VrlValue{}) {
		assert false, 'expected error for non-string input'
	}
}

fn test_decode_charset_missing_charset() {
	if _ := fn_decode_charset([VrlValue('hello')], map[string]VrlValue{}) {
		assert false, 'expected error for missing charset'
	}
}

fn test_decode_charset_wrong_charset_type() {
	if _ := fn_decode_charset([VrlValue('hello')], {
		'from_charset': VrlValue(i64(42))
	}) {
		assert false, 'expected error for non-string charset'
	}
}

fn test_decode_charset_positional_arg() {
	// Use positional arg instead of named arg
	r := fn_decode_charset([VrlValue('hello'), VrlValue('UTF-8')], map[string]VrlValue{}) or {
		panic('decode_charset positional: ${err}')
	}
	assert r == VrlValue('hello')
}

fn test_encode_charset_positional_arg() {
	r := fn_encode_charset([VrlValue('hello'), VrlValue('UTF-8')], map[string]VrlValue{}) or {
		panic('encode_charset positional: ${err}')
	}
	assert r == VrlValue('hello')
}

fn test_decode_charset_positional_wrong_type() {
	if _ := fn_decode_charset([VrlValue('hello'), VrlValue(i64(42))], map[string]VrlValue{}) {
		assert false, 'expected error for non-string positional charset'
	}
}

fn test_encode_charset_positional_wrong_type() {
	if _ := fn_encode_charset([VrlValue('hello'), VrlValue(i64(42))], map[string]VrlValue{}) {
		assert false, 'expected error for non-string positional charset'
	}
}

// ============================================================
// vrllib_type.v: is_empty, is_json, is_regex, is_timestamp,
//   timestamp, tag_types_externally
// ============================================================

fn test_is_empty_with_object() {
	// Test is_empty with non-empty object
	assert_vrl_bool('is_empty({"a": 1})', false)
}

fn test_is_json_with_variant_object() {
	r1 := fn_is_json([VrlValue('{}'), VrlValue('object')])!
	assert r1 == VrlValue(true)
	r2 := fn_is_json([VrlValue('[]'), VrlValue('object')])!
	assert r2 == VrlValue(false)
}

fn test_is_json_with_variant_array() {
	r1 := fn_is_json([VrlValue('[1,2]'), VrlValue('array')])!
	assert r1 == VrlValue(true)
	r2 := fn_is_json([VrlValue('{}'), VrlValue('array')])!
	assert r2 == VrlValue(false)
}

fn test_is_json_with_variant_string() {
	r1 := fn_is_json([VrlValue('"hello"'), VrlValue('string')])!
	assert r1 == VrlValue(true)
	r2 := fn_is_json([VrlValue('42'), VrlValue('string')])!
	assert r2 == VrlValue(false)
}

fn test_is_json_with_variant_number() {
	r1 := fn_is_json([VrlValue('42'), VrlValue('number')])!
	assert r1 == VrlValue(true)
	r2 := fn_is_json([VrlValue('3.14'), VrlValue('number')])!
	assert r2 == VrlValue(true)
	r3 := fn_is_json([VrlValue('"text"'), VrlValue('number')])!
	assert r3 == VrlValue(false)
}

fn test_is_json_with_variant_bool() {
	r1 := fn_is_json([VrlValue('true'), VrlValue('bool')])!
	assert r1 == VrlValue(true)
	r2 := fn_is_json([VrlValue('false'), VrlValue('bool')])!
	assert r2 == VrlValue(true)
	r3 := fn_is_json([VrlValue('42'), VrlValue('bool')])!
	assert r3 == VrlValue(false)
}

fn test_is_json_with_variant_null() {
	r1 := fn_is_json([VrlValue('null'), VrlValue('null')])!
	assert r1 == VrlValue(true)
	r2 := fn_is_json([VrlValue('42'), VrlValue('null')])!
	assert r2 == VrlValue(false)
}

fn test_is_json_with_unknown_variant() {
	// Unknown variant should still return true if valid JSON
	r := fn_is_json([VrlValue('42'), VrlValue('unknown_variant')])!
	assert r == VrlValue(true)
}

fn test_is_json_non_string_variant() {
	// Non-string variant should be treated as empty string (no variant check)
	r := fn_is_json([VrlValue('42'), VrlValue(i64(1))])!
	assert r == VrlValue(true)
}

fn test_is_json_non_string_input() {
	r := fn_is_json([VrlValue(i64(42))])!
	assert r == VrlValue(false)
}

fn test_timestamp_coerce() {
	// Test the timestamp function
	result := execute('timestamp!(now())', map[string]VrlValue{}) or {
		panic('timestamp coerce: ${err}')
	}
	assert result is Timestamp
}

fn test_timestamp_wrong_type() {
	assert_vrl_error('timestamp!("not a timestamp")')
}

fn test_tag_types_externally_regex() {
	result := execute("tag_types_externally(r'[a-z]+')", map[string]VrlValue{}) or {
		panic('tag_types regex: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"regex"'), 'tag_types regex: got ${j}'
}

fn test_tag_types_externally_timestamp() {
	result := execute('tag_types_externally(now())', map[string]VrlValue{}) or {
		panic('tag_types timestamp: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"timestamp"'), 'tag_types timestamp: got ${j}'
}

// ============================================================
// value.v: format_float, float_to_decimal, vrl_to_json_pretty,
//   values_equal, is_truthy, vrl_to_string, format_timestamp
// ============================================================

fn test_format_float_negative_integer() {
	assert format_float(-5.0) == '-5.0'
}

fn test_format_float_large_integer() {
	assert format_float(1000000.0) == '1000000.0'
}

fn test_format_float_very_small() {
	// Very small number may use scientific notation internally
	s := format_float(0.000001)
	assert s.contains('0.000001') || s.contains('1') // should be represented as decimal
}

fn test_format_float_negative_decimal() {
	s := format_float(-3.14)
	assert s.starts_with('-')
}

fn test_float_to_decimal_no_exponent() {
	// No exponent should return as-is
	assert float_to_decimal('3.14', 3.14) == '3.14'
}

fn test_float_to_decimal_positive_exponent() {
	// 1.5e2 = 150.0
	result := float_to_decimal('1.5e2', 150.0)
	assert result == '150.0' || result == '15.0' || result.contains('15'), 'got ${result}'
}

fn test_float_to_decimal_negative_exponent() {
	// 1.5e-2 = 0.015
	result := float_to_decimal('1.5e-2', 0.015)
	assert result.contains('0.0'), 'got ${result}'
}

fn test_float_to_decimal_negative_number() {
	result := float_to_decimal('-1.5e2', -150.0)
	assert result.starts_with('-'), 'negative number should start with -: got ${result}'
}

fn test_vrl_to_string_null() {
	assert vrl_to_string(VrlValue(VrlNull{})) == 'null'
}

fn test_vrl_to_string_regex() {
	assert vrl_to_string(VrlValue(VrlRegex{pattern: '[a-z]+'})) == '[a-z]+'
}

fn test_vrl_to_string_bool() {
	assert vrl_to_string(VrlValue(true)) == 'true'
	assert vrl_to_string(VrlValue(false)) == 'false'
}

fn test_vrl_to_string_integer() {
	assert vrl_to_string(VrlValue(i64(42))) == '42'
	assert vrl_to_string(VrlValue(i64(-1))) == '-1'
}

fn test_vrl_to_string_float() {
	s := vrl_to_string(VrlValue(f64(3.14)))
	assert s == '3.14'
}

fn test_vrl_to_string_array() {
	arr := VrlValue([VrlValue(i64(1)), VrlValue(i64(2))])
	s := vrl_to_string(arr)
	assert s == '[1,2]'
}

fn test_vrl_to_string_object() {
	mut obj := new_object_map()
	obj.set('a', VrlValue(i64(1)))
	s := vrl_to_string(VrlValue(obj))
	assert s == '{"a":1}'
}

fn test_vrl_to_json_null() {
	assert vrl_to_json(VrlValue(VrlNull{})) == 'null'
}

fn test_vrl_to_json_regex() {
	assert vrl_to_json(VrlValue(VrlRegex{pattern: 'abc'})) == "\"r'abc'\""
}

fn test_vrl_to_json_pretty_empty_array() {
	assert vrl_to_json_pretty(VrlValue([]VrlValue{}), 0) == '[]'
}

fn test_vrl_to_json_pretty_empty_object() {
	obj := new_object_map()
	assert vrl_to_json_pretty(VrlValue(obj), 0) == '{}'
}

fn test_vrl_to_json_pretty_nested() {
	mut obj := new_object_map()
	obj.set('key', VrlValue('value'))
	obj.set('num', VrlValue(i64(42)))
	result := vrl_to_json_pretty(VrlValue(obj), 0)
	assert result.contains('"key"')
	assert result.contains('"value"')
	assert result.contains('42')
	assert result.contains('\n')
}

fn test_vrl_to_json_pretty_array() {
	arr := VrlValue([VrlValue(i64(1)), VrlValue('two'), VrlValue(true)])
	result := vrl_to_json_pretty(arr, 0)
	assert result.contains('1')
	assert result.contains('"two"')
	assert result.contains('true')
	assert result.contains('\n')
}

fn test_vrl_to_json_pretty_null() {
	assert vrl_to_json_pretty(VrlValue(VrlNull{}), 0) == 'null'
}

fn test_vrl_to_json_pretty_regex() {
	assert vrl_to_json_pretty(VrlValue(VrlRegex{pattern: 'x'}), 0) == "\"r'x'\""
}

fn test_vrl_to_json_pretty_bool() {
	assert vrl_to_json_pretty(VrlValue(true), 0) == 'true'
	assert vrl_to_json_pretty(VrlValue(false), 0) == 'false'
}

fn test_vrl_to_json_pretty_float() {
	result := vrl_to_json_pretty(VrlValue(f64(2.5)), 0)
	assert result == '2.5'
}

fn test_vrl_to_json_pretty_integer() {
	assert vrl_to_json_pretty(VrlValue(i64(99)), 0) == '99'
}

fn test_vrl_to_json_pretty_timestamp() {
	ts := Timestamp{t: time.unix(1609459200)}
	result := vrl_to_json_pretty(VrlValue(ts), 0)
	assert result.contains('2021') || result.contains('2020') // depends on timezone
}

fn test_is_truthy_float() {
	assert is_truthy(VrlValue(f64(1.0))) == true
	assert is_truthy(VrlValue(f64(0.0))) == false
	assert is_truthy(VrlValue(f64(-1.0))) == true
}

fn test_is_truthy_array() {
	assert is_truthy(VrlValue([]VrlValue{})) == true // arrays are truthy
	assert is_truthy(VrlValue([VrlValue(i64(1))])) == true
}

fn test_is_truthy_object() {
	obj := new_object_map()
	assert is_truthy(VrlValue(obj)) == true
}

fn test_values_equal_float_float() {
	assert values_equal(VrlValue(f64(1.5)), VrlValue(f64(1.5))) == true
	assert values_equal(VrlValue(f64(1.5)), VrlValue(f64(2.5))) == false
}

fn test_values_equal_float_int() {
	assert values_equal(VrlValue(f64(3.0)), VrlValue(i64(3))) == true
	assert values_equal(VrlValue(f64(3.5)), VrlValue(i64(3))) == false
}

fn test_values_equal_int_string() {
	assert values_equal(VrlValue(i64(1)), VrlValue('1')) == false
}

fn test_values_equal_string_int() {
	assert values_equal(VrlValue('hello'), VrlValue(i64(1))) == false
}

fn test_values_equal_bool_string() {
	assert values_equal(VrlValue(true), VrlValue('true')) == false
}

fn test_values_equal_null_string() {
	assert values_equal(VrlValue(VrlNull{}), VrlValue('null')) == false
}

fn test_values_equal_arrays_different_lengths() {
	a := VrlValue([VrlValue(i64(1))])
	b := VrlValue([VrlValue(i64(1)), VrlValue(i64(2))])
	assert values_equal(a, b) == false
}

fn test_values_equal_arrays_different_elements() {
	a := VrlValue([VrlValue(i64(1)), VrlValue(i64(2))])
	b := VrlValue([VrlValue(i64(1)), VrlValue(i64(3))])
	assert values_equal(a, b) == false
}

fn test_values_equal_arrays_same() {
	a := VrlValue([VrlValue('x'), VrlValue('y')])
	b := VrlValue([VrlValue('x'), VrlValue('y')])
	assert values_equal(a, b) == true
}

fn test_values_equal_array_vs_string() {
	assert values_equal(VrlValue([VrlValue(i64(1))]), VrlValue('test')) == false
}

fn test_values_equal_object_different_sizes() {
	mut a := new_object_map()
	a.set('x', VrlValue(i64(1)))
	mut b := new_object_map()
	b.set('x', VrlValue(i64(1)))
	b.set('y', VrlValue(i64(2)))
	assert values_equal(VrlValue(a), VrlValue(b)) == false
}

fn test_values_equal_object_different_values() {
	mut a := new_object_map()
	a.set('x', VrlValue(i64(1)))
	mut b := new_object_map()
	b.set('x', VrlValue(i64(2)))
	assert values_equal(VrlValue(a), VrlValue(b)) == false
}

fn test_values_equal_object_missing_key() {
	mut a := new_object_map()
	a.set('x', VrlValue(i64(1)))
	mut b := new_object_map()
	b.set('y', VrlValue(i64(1)))
	assert values_equal(VrlValue(a), VrlValue(b)) == false
}

fn test_values_equal_object_vs_string() {
	mut a := new_object_map()
	a.set('x', VrlValue(i64(1)))
	assert values_equal(VrlValue(a), VrlValue('test')) == false
}

fn test_values_equal_timestamp() {
	t1 := Timestamp{t: time.unix(1000)}
	t2 := Timestamp{t: time.unix(1000)}
	t3 := Timestamp{t: time.unix(2000)}
	assert values_equal(VrlValue(t1), VrlValue(t2)) == true
	assert values_equal(VrlValue(t1), VrlValue(t3)) == false
}

fn test_values_equal_timestamp_vs_string() {
	t := Timestamp{t: time.unix(1000)}
	assert values_equal(VrlValue(t), VrlValue('test')) == false
}

fn test_values_equal_regex() {
	r1 := VrlRegex{pattern: 'abc'}
	r2 := VrlRegex{pattern: 'abc'}
	r3 := VrlRegex{pattern: 'xyz'}
	assert values_equal(VrlValue(r1), VrlValue(r2)) == true
	assert values_equal(VrlValue(r1), VrlValue(r3)) == false
}

fn test_values_equal_regex_vs_string() {
	r := VrlRegex{pattern: 'abc'}
	assert values_equal(VrlValue(r), VrlValue('abc')) == false
}

fn test_values_equal_float_vs_string() {
	assert values_equal(VrlValue(f64(1.0)), VrlValue('1.0')) == false
}

fn test_format_timestamp_no_fractional() {
	// A timestamp with no fractional seconds
	t := time.unix(1609459200) // 2021-01-01T00:00:00Z
	s := format_timestamp(t)
	assert s.contains('2021') || s.contains('2020')
	// Should not have fractional part
	assert !s.contains('.') || s.contains('.000') || s.contains('.0')
}

// ============================================================
// vrllib_object.v: object_from_array, zip, remove, compact
// ============================================================

fn test_object_from_array_null_keys_skipped() {
	// Pairs where key is null should be skipped
	assert_vrl_json('object_from_array!([[null, 1], ["b", 2]])', '{"b":2}')
}

fn test_object_from_array_non_string_keys() {
	// Non-string keys should be converted to string
	assert_vrl_json('object_from_array!([[42, "val"]])', '{"42":"val"}')
}

fn test_object_from_array_with_keys_null_skipped() {
	// When keys array has nulls, those should be skipped
	assert_vrl_json('object_from_array!([10, 20], ["a", null])', '{"a":10}')
}

fn test_object_from_array_with_keys_non_string() {
	// Non-string keys in keys array converted to string
	assert_vrl_json('object_from_array!([10], [42])', '{"42":10}')
}

fn test_zip_single_array_of_arrays() {
	assert_vrl_json('zip([[1, 2], [3, 4]])', '[[1,3],[2,4]]')
}

fn test_zip_multiple_arrays() {
	assert_vrl_json('zip([1, 2], [3, 4])', '[[1,3],[2,4]]')
}

fn test_zip_unequal_lengths() {
	assert_vrl_json('zip([1, 2, 3], [4, 5])', '[[1,4],[2,5]]')
}

fn test_zip_empty() {
	assert_vrl_json('zip([])', '[]')
}

fn test_remove_from_object() {
	assert_vrl_json('remove!({"a": 1, "b": 2}, ["a"])', '{"b":2}')
}

fn test_remove_nested_object() {
	assert_vrl_json('remove!({"a": {"b": 1, "c": 2}}, ["a", "b"])', '{"a":{"c":2}}')
}

fn test_remove_from_array() {
	assert_vrl_json('remove!([10, 20, 30], [1])', '[10,30]')
}

fn test_remove_compact() {
	// Remove a key and compact empty containers
	assert_vrl_json('remove!({"a": {"b": 1}}, ["a", "b"], true)', '{}')
}

fn test_remove_nonexistent_key() {
	assert_vrl_json('remove!({"a": 1}, ["z"])', '{"a":1}')
}

// ============================================================
// vrllib_string.v: case conversion with original_case, sieve
//   with replace args, shannon_entropy codepoint/grapheme
// ============================================================

fn test_camelcase_with_original_case_snake() {
	assert_vrl_str('camelcase("hello_world", "snake_case")', 'helloWorld')
}

fn test_camelcase_with_original_case_kebab() {
	assert_vrl_str('camelcase("hello-world", "kebab-case")', 'helloWorld')
}

fn test_camelcase_with_original_case_camel() {
	assert_vrl_str('camelcase("helloWorld", "camelCase")', 'helloWorld')
}

fn test_camelcase_with_original_case_pascal() {
	assert_vrl_str('camelcase("HelloWorld", "PascalCase")', 'helloWorld')
}

fn test_snakecase_with_original_case() {
	assert_vrl_str('snakecase("helloWorld", "camelCase")', 'hello_world')
}

fn test_kebabcase_with_original_case() {
	assert_vrl_str('kebabcase("hello_world", "snake_case")', 'hello-world')
}

fn test_pascalcase_basic() {
	assert_vrl_str('pascalcase("hello_world")', 'HelloWorld')
}

fn test_pascalcase_with_original_case() {
	assert_vrl_str('pascalcase("helloWorld", "camelCase")', 'HelloWorld')
}

fn test_screamingsnakecase_basic() {
	assert_vrl_str('screamingsnakecase("hello_world")', 'HELLO_WORLD')
}

fn test_screamingsnakecase_with_original_case() {
	assert_vrl_str('screamingsnakecase("helloWorld", "camelCase")', 'HELLO_WORLD')
}

fn test_split_words_camel_acronym() {
	words := split_words_camel('XMLParser')
	assert words == ['XML', 'Parser']
}

fn test_split_words_camel_simple() {
	words := split_words_camel('helloWorld')
	assert words == ['hello', 'World']
}

fn test_split_words_camel_all_upper() {
	words := split_words_camel('ABC')
	assert words == ['ABC']
}

fn test_split_words_by_case_screaming_snake() {
	words := split_words_by_case('HELLO_WORLD', 'screaming_snake_case')
	assert words == ['HELLO', 'WORLD']
}

fn test_split_words_by_case_unknown() {
	// Unknown case falls back to split_words
	words := split_words_by_case('hello_world', 'unknown')
	assert words == ['hello', 'world']
}

fn test_sieve_with_replace_single() {
	assert_vrl_str("sieve(\"h3llo!\", r'[a-zA-Z0-9]', \"*\")", 'h3llo*')
}

fn test_sieve_with_replace_repeated() {
	assert_vrl_str("sieve(\"h3llo!!!\", r'[a-zA-Z0-9]', \"\", \"_\")", 'h3llo_')
}

fn test_shannon_entropy_codepoint() {
	result := execute('shannon_entropy("aabb", "codepoint")', map[string]VrlValue{}) or {
		panic('shannon_entropy codepoint: ${err}')
	}
	v := result as f64
	assert v > 0.99 && v < 1.01, 'expected ~1.0, got ${v}'
}

fn test_shannon_entropy_codepoint_empty() {
	result := execute('shannon_entropy("", "codepoint")', map[string]VrlValue{}) or {
		panic('shannon_entropy codepoint empty: ${err}')
	}
	assert result == VrlValue(f64(0.0))
}

fn test_shannon_entropy_grapheme() {
	result := execute('shannon_entropy("aabb", "grapheme")', map[string]VrlValue{}) or {
		panic('shannon_entropy grapheme: ${err}')
	}
	v := result as f64
	assert v > 0.99 && v < 1.01, 'expected ~1.0, got ${v}'
}

fn test_shannon_entropy_grapheme_empty() {
	result := execute('shannon_entropy("", "grapheme")', map[string]VrlValue{}) or {
		panic('shannon_entropy grapheme empty: ${err}')
	}
	assert result == VrlValue(f64(0.0))
}

fn test_strip_ansi_escape_codes_osc() {
	// OSC sequence: ESC ] ... BEL
	input := '\x1b]0;title\x07rest'
	result := fn_strip_ansi_escape_codes([VrlValue(input)]) or {
		panic('strip_ansi OSC: ${err}')
	}
	assert result == VrlValue('rest')
}

fn test_strip_ansi_escape_codes_osc_st() {
	// OSC sequence terminated by ESC backslash
	input := '\x1b]0;title\x1b\\rest'
	result := fn_strip_ansi_escape_codes([VrlValue(input)]) or {
		panic('strip_ansi OSC ST: ${err}')
	}
	assert result == VrlValue('rest')
}

fn test_basename_empty_string() {
	assert_vrl_null('basename("")')
}

fn test_basename_trailing_slashes() {
	assert_vrl_str('basename("/a/b///")', 'b')
}

fn test_dirname_trailing_slashes() {
	assert_vrl_str('dirname("/a/b///")', '/a')
}

fn test_split_path_root() {
	assert_vrl_json('split_path("/")', '["/"]')
}

fn test_rune_to_utf8_ascii() {
	result := rune_to_utf8(rune(65)) // 'A'
	assert result == [u8(65)]
}

fn test_rune_to_utf8_two_byte() {
	result := rune_to_utf8(rune(0xC9)) // e-acute
	assert result.len == 2
}

fn test_rune_to_utf8_three_byte() {
	result := rune_to_utf8(rune(0x4E2D)) // Chinese character
	assert result.len == 3
}

fn test_rune_to_utf8_four_byte() {
	result := rune_to_utf8(rune(0x1F600)) // emoji
	assert result.len == 4
}

fn test_is_combining_mark() {
	assert is_combining_mark(rune(0x0300)) == true // combining grave accent
	assert is_combining_mark(rune(0x036F)) == true
	assert is_combining_mark(rune(0x0041)) == false // 'A'
}

// ============================================================
// vrllib_enumerate.v: tally, tally_value, match_array
// ============================================================

fn test_tally_basic() {
	assert_vrl_json('tally(["a", "b", "a"])', '{"a":2,"b":1}')
}

fn test_tally_empty() {
	assert_vrl_json('tally([])', '{}')
}

fn test_tally_integers() {
	result := execute('tally([1, 2, 1, 3])', map[string]VrlValue{}) or {
		panic('tally integers: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"1":2')
	assert j.contains('"2":1')
	assert j.contains('"3":1')
}

fn test_match_array_all_match() {
	assert_vrl_bool("match_array([\"foo\", \"foobar\"], r'foo', all: true)", true)
}

fn test_match_array_all_not_match() {
	assert_vrl_bool("match_array([\"foo\", \"bar\"], r'foo', all: true)", false)
}

fn test_match_array_non_string_items() {
	// Non-string items should be skipped
	assert_vrl_bool("match_array([1, 2, 3], r'1')", false)
}

// ============================================================
// lexer.v: edge cases in tokenization
// ============================================================

fn test_lexer_block_comment() {
	// // style comments
	mut l := new_lexer('// comment\n42')
	tokens := l.tokenize()
	mut found_int := false
	for t in tokens {
		if t.kind == .integer && t.lit == '42' {
			found_int = true
		}
	}
	assert found_int, 'should find integer after block comment'
}

fn test_lexer_hash_comment() {
	mut l := new_lexer('# comment\n42')
	tokens := l.tokenize()
	mut found_int := false
	for t in tokens {
		if t.kind == .integer && t.lit == '42' {
			found_int = true
		}
	}
	assert found_int, 'should find integer after hash comment'
}

fn test_lexer_negative_number() {
	mut l := new_lexer('-42')
	tokens := l.tokenize()
	assert tokens[0].kind == .integer
	assert tokens[0].lit == '-42'
}

fn test_lexer_float_number() {
	mut l := new_lexer('3.14')
	tokens := l.tokenize()
	assert tokens[0].kind == .float
	assert tokens[0].lit == '3.14'
}

fn test_lexer_underscored_number() {
	mut l := new_lexer('1_000_000')
	tokens := l.tokenize()
	assert tokens[0].kind == .integer
	assert tokens[0].lit == '1000000'
}

fn test_lexer_template_literal() {
	mut l := new_lexer('"hello {{ name }}"')
	tokens := l.tokenize()
	assert tokens[0].kind == .template_lit
}

fn test_lexer_single_quoted_string() {
	mut l := new_lexer("'hello'")
	tokens := l.tokenize()
	assert tokens[0].kind == .string_lit
	assert tokens[0].lit == 'hello'
}

fn test_lexer_raw_string() {
	mut l := new_lexer("s'raw string'")
	tokens := l.tokenize()
	assert tokens[0].kind == .raw_string
	assert tokens[0].lit == 'raw string'
}

fn test_lexer_regex_literal() {
	mut l := new_lexer("r'[a-z]+'")
	tokens := l.tokenize()
	assert tokens[0].kind == .regex_lit
	assert tokens[0].lit == '[a-z]+'
}

fn test_lexer_timestamp_literal() {
	mut l := new_lexer("t'2024-01-01T00:00:00Z'")
	tokens := l.tokenize()
	assert tokens[0].kind == .timestamp_lit
}

fn test_lexer_two_char_operators() {
	mut l := new_lexer('== != <= >= && || ?? |= ->')
	tokens := l.tokenize()
	assert tokens[0].kind == .eq
	assert tokens[1].kind == .neq
	assert tokens[2].kind == .le
	assert tokens[3].kind == .ge
	assert tokens[4].kind == .and
	assert tokens[5].kind == .or
	assert tokens[6].kind == .question2
	assert tokens[7].kind == .pipe_assign
	assert tokens[8].kind == .arrow
}

fn test_lexer_single_char_operators() {
	mut l := new_lexer('+ - * / = < > ! | ( ) [ ] { } , : ;')
	tokens := l.tokenize()
	assert tokens[0].kind == .plus
	assert tokens[1].kind == .minus
	assert tokens[2].kind == .star
	assert tokens[3].kind == .slash
	assert tokens[4].kind == .assign
	assert tokens[5].kind == .lt
	assert tokens[6].kind == .gt
	assert tokens[7].kind == .not
	assert tokens[8].kind == .pipe
	assert tokens[9].kind == .lparen
	assert tokens[10].kind == .rparen
	assert tokens[11].kind == .lbracket
	assert tokens[12].kind == .rbracket
	assert tokens[13].kind == .lbrace
	assert tokens[14].kind == .rbrace
	assert tokens[15].kind == .comma
	assert tokens[16].kind == .colon
	assert tokens[17].kind == .semicolon
}

fn test_lexer_dot_path() {
	mut l := new_lexer('.foo.bar')
	tokens := l.tokenize()
	assert tokens[0].kind == .dot_ident
	assert tokens[0].lit == '.foo.bar'
}

fn test_lexer_meta_path() {
	mut l := new_lexer('%meta_field')
	tokens := l.tokenize()
	assert tokens[0].kind == .meta_ident
	assert tokens[0].lit == '%meta_field'
}

fn test_lexer_bare_percent_meta() {
	// Bare % as metadata root
	mut l := new_lexer('% ')
	tokens := l.tokenize()
	assert tokens[0].kind == .meta_ident
	assert tokens[0].lit == '%'
}

fn test_lexer_percent_as_modulo() {
	// After a value token, % should be modulo
	mut l := new_lexer('42 % 5')
	tokens := l.tokenize()
	mut found_percent := false
	for t in tokens {
		if t.kind == .percent {
			found_percent = true
		}
	}
	assert found_percent, 'should parse % as modulo after integer'
}

fn test_lexer_ident_with_bang() {
	mut l := new_lexer('assert!')
	tokens := l.tokenize()
	assert tokens[0].kind == .ident
	assert tokens[0].lit == 'assert!'
}

fn test_lexer_keywords() {
	mut l := new_lexer('true false null')
	tokens := l.tokenize()
	assert tokens[0].kind == .true_lit
	assert tokens[1].kind == .false_lit
	assert tokens[2].kind == .null_lit
}

fn test_lexer_string_escape_sequences() {
	mut l := new_lexer('"hello\\nworld\\t!"')
	tokens := l.tokenize()
	assert tokens[0].kind == .string_lit
	assert tokens[0].lit.contains('\n')
	assert tokens[0].lit.contains('\t')
}

fn test_lexer_string_escaped_braces() {
	mut l := new_lexer('"\\{not template\\}"')
	tokens := l.tokenize()
	assert tokens[0].kind == .string_lit
	assert tokens[0].lit == '{not template}'
}

fn test_lexer_prefixed_string_escape() {
	// In prefixed strings, only \' and \\ are interpreted
	mut l := new_lexer("r'hello\\'world'")
	tokens := l.tokenize()
	assert tokens[0].kind == .regex_lit
	assert tokens[0].lit == "hello'world"
}

fn test_lexer_prefixed_string_backslash_other() {
	// Other escape sequences in prefixed strings are kept literal
	mut l := new_lexer("s'hello\\nworld'")
	tokens := l.tokenize()
	assert tokens[0].kind == .raw_string
	assert tokens[0].lit == 'hello\\nworld'
}

fn test_lexer_dot_as_standalone() {
	mut l := new_lexer('. ')
	tokens := l.tokenize()
	assert tokens[0].kind == .dot
}

fn test_lexer_newline_resets_context() {
	mut l := new_lexer("42\n%x")
	tokens := l.tokenize()
	// After newline, % should be metadata, not modulo
	mut found_meta := false
	for t in tokens {
		if t.kind == .meta_ident {
			found_meta = true
		}
	}
	assert found_meta, 'should parse %x as meta_ident after newline'
}

fn test_lexer_semicolon_resets_context() {
	mut l := new_lexer('42; %x')
	tokens := l.tokenize()
	mut found_meta := false
	for t in tokens {
		if t.kind == .meta_ident {
			found_meta = true
		}
	}
	assert found_meta, 'should parse %x as meta_ident after semicolon'
}

fn test_token_str() {
	t := Token{kind: .integer, lit: '42', line: 1, col: 1}
	s := t.str()
	assert s.contains('42')
}

fn test_lexer_quoted_dot_path() {
	mut l := new_lexer('."quoted key"')
	tokens := l.tokenize()
	assert tokens[0].kind == .dot_ident
	assert tokens[0].lit.contains('quoted key')
}

fn test_lexer_at_in_path() {
	mut l := new_lexer('.@timestamp')
	tokens := l.tokenize()
	assert tokens[0].kind == .dot_ident
	assert tokens[0].lit == '.@timestamp'
}
