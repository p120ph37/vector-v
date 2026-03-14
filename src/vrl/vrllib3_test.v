module vrl

// Comprehensive data-driven tests for VRL vrllib functions with low coverage.
// Tests math, array, object, string, type, match, JSON, timestamp,
// format, assert, misc, and path functions.

fn assert_vrl3(prog string, expected VrlValue) {
	result := execute(prog, map[string]VrlValue{}) or { panic('${prog}: ${err}') }
	assert vrl_to_json(result) == vrl_to_json(expected), '${prog}: expected ${vrl_to_json(expected)}, got ${vrl_to_json(result)}'
}

fn assert_vrl3_json(prog string, expected_json string) {
	result := execute(prog, map[string]VrlValue{}) or { panic('${prog}: ${err}') }
	assert vrl_to_json(result) == expected_json, '${prog}: expected ${expected_json}, got ${vrl_to_json(result)}'
}

fn assert_vrl3_err(prog string, expected_substr string) {
	execute(prog, map[string]VrlValue{}) or {
		assert err.msg().contains(expected_substr), '${prog}: expected error containing "${expected_substr}", got "${err.msg()}"'
		return
	}
	panic('${prog}: expected error but got success')
}

// ============================================================
// Math functions: abs, ceil, floor, round, mod
// ============================================================

fn test_abs() {
	cases := [
		['abs(5)', '5'],
		['abs(-5)', '5'],
		['abs(0)', '0'],
		['abs(-3.14)', '3.14'],
		['abs(3.14)', '3.14'],
		['abs(-0.0)', '0.0'],
		['abs(100)', '100'],
		['abs(-100)', '100'],
	]
	for c in cases {
		result := execute(c[0], map[string]VrlValue{}) or { panic('${c[0]}: ${err}') }
		got := vrl_to_json(result)
		assert got == c[1], '${c[0]}: expected ${c[1]}, got ${got}'
	}
}

fn test_abs_error() {
	assert_vrl3_err('abs("hello")', 'abs requires a number')
}

fn test_ceil() {
	// ceil with no precision returns integer
	assert_vrl3('ceil(3.1)', VrlValue(i64(4)))
	assert_vrl3('ceil(3.9)', VrlValue(i64(4)))
	assert_vrl3('ceil(3.0)', VrlValue(i64(3)))
	assert_vrl3('ceil(-2.1)', VrlValue(i64(-2)))
	assert_vrl3('ceil(-2.9)', VrlValue(i64(-2)))
	// ceil with integer input
	assert_vrl3('ceil(5)', VrlValue(i64(5)))
}

fn test_ceil_precision() {
	// ceil with precision returns float
	result := execute('ceil(3.14159, precision: 2)', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j == '3.15', 'ceil precision 2: got ${j}'

	result2 := execute('ceil(3.141, precision: 1)', map[string]VrlValue{}) or { panic(err) }
	j2 := vrl_to_json(result2)
	assert j2 == '3.2', 'ceil precision 1: got ${j2}'

	// Integer with precision returns float
	result3 := execute('ceil(5, precision: 2)', map[string]VrlValue{}) or { panic(err) }
	j3 := vrl_to_json(result3)
	assert j3 == '5.0' || j3 == '5', 'ceil int precision: got ${j3}'
}

fn test_ceil_error() {
	assert_vrl3_err('ceil("hello")', 'ceil requires a number')
}

fn test_floor() {
	assert_vrl3('floor(3.9)', VrlValue(i64(3)))
	assert_vrl3('floor(3.1)', VrlValue(i64(3)))
	assert_vrl3('floor(3.0)', VrlValue(i64(3)))
	assert_vrl3('floor(-2.1)', VrlValue(i64(-3)))
	assert_vrl3('floor(-2.9)', VrlValue(i64(-3)))
	assert_vrl3('floor(5)', VrlValue(i64(5)))
}

fn test_floor_precision() {
	result := execute('floor(3.14159, precision: 2)', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j == '3.14', 'floor precision 2: got ${j}'

	result2 := execute('floor(3.19, precision: 1)', map[string]VrlValue{}) or { panic(err) }
	j2 := vrl_to_json(result2)
	assert j2 == '3.1', 'floor precision 1: got ${j2}'

	// Integer with precision returns float
	result3 := execute('floor(7, precision: 1)', map[string]VrlValue{}) or { panic(err) }
	j3 := vrl_to_json(result3)
	assert j3 == '7.0' || j3 == '7', 'floor int precision: got ${j3}'
}

fn test_floor_error() {
	assert_vrl3_err('floor("x")', 'floor requires a number')
}

fn test_round() {
	assert_vrl3('round(3.5)', VrlValue(i64(4)))
	assert_vrl3('round(3.4)', VrlValue(i64(3)))
	assert_vrl3('round(3.0)', VrlValue(i64(3)))
	assert_vrl3('round(-2.5)', VrlValue(i64(-2)))
	assert_vrl3('round(7)', VrlValue(i64(7)))
}

fn test_round_precision() {
	result := execute('round(3.14159, precision: 2)', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j == '3.14', 'round precision 2: got ${j}'

	result2 := execute('round(3.145, precision: 2)', map[string]VrlValue{}) or { panic(err) }
	j2 := vrl_to_json(result2)
	assert j2 == '3.15', 'round precision 2 up: got ${j2}'
}

fn test_round_error() {
	assert_vrl3_err('round("x")', 'round requires a number')
}

fn test_mod_fn() {
	assert_vrl3('mod(10, 3)', VrlValue(i64(1)))
	assert_vrl3('mod(10, 5)', VrlValue(i64(0)))
	assert_vrl3('mod(7, 2)', VrlValue(i64(1)))
}

// ============================================================
// Array functions: flatten, unflatten, push, append, pop, unique, ensure_array, ensure_object
// ============================================================

fn test_flatten_array() {
	assert_vrl3_json('flatten([1, [2, 3], [4, [5, 6]]])', '[1,2,3,4,5,6]')
	assert_vrl3_json('flatten([1, 2, 3])', '[1,2,3]')
	assert_vrl3_json('flatten([])', '[]')
	assert_vrl3_json('flatten([[1], [2], [3]])', '[1,2,3]')
	assert_vrl3_json('flatten([[[1]], [[2]]])', '[1,2]')
}

fn test_flatten_object() {
	result := execute('flatten({"a": {"b": 1, "c": 2}})', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"a.b":1'), 'flatten object a.b: got ${j}'
	assert j.contains('"a.c":2'), 'flatten object a.c: got ${j}'
}

fn test_flatten_object_separator() {
	result := execute('flatten({"a": {"b": 1}}, separator: "_")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"a_b":1'), 'flatten object sep _: got ${j}'
}

fn test_flatten_error() {
	assert_vrl3_err('flatten("hello")', 'flatten requires object or array')
}

fn test_unflatten() {
	result := execute('unflatten({"a.b": 1, "a.c": 2})', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"a":{'), 'unflatten structure: got ${j}'
	assert j.contains('"b":1'), 'unflatten b: got ${j}'
	assert j.contains('"c":2'), 'unflatten c: got ${j}'
}

fn test_unflatten_separator() {
	result := execute('unflatten({"a_b": 1}, separator: "_")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"a":{'), 'unflatten sep _: got ${j}'
	assert j.contains('"b":1'), 'unflatten sep _ value: got ${j}'
}

fn test_unflatten_error() {
	assert_vrl3_err('unflatten("hello")', 'unflatten requires an object')
}

fn test_push() {
	assert_vrl3_json('push([1, 2], 3)', '[1,2,3]')
	assert_vrl3_json('push([], "hello")', '["hello"]')
	assert_vrl3_json('push([1], [2, 3])', '[1,[2,3]]')
}

fn test_push_error() {
	assert_vrl3_err('push("hello", 1)', 'push first arg must be array')
}

fn test_append() {
	assert_vrl3_json('append([1, 2], [3, 4])', '[1,2,3,4]')
	assert_vrl3_json('append([], [1])', '[1]')
	assert_vrl3_json('append([1], [])', '[1]')
}

fn test_append_error() {
	assert_vrl3_err('append("hello", [1])', 'append first arg must be array')
	assert_vrl3_err('append([1], "hello")', 'append second arg must be array')
}

fn test_pop() {
	assert_vrl3_json('pop([1, 2, 3])', '[1,2]')
	assert_vrl3_json('pop([1])', '[]')
	assert_vrl3_json('pop([])', '[]')
}

fn test_pop_error() {
	assert_vrl3_err('pop("hello")', 'pop requires an array')
}

fn test_unique() {
	assert_vrl3_json('unique([1, 2, 2, 3, 3, 3])', '[1,2,3]')
	assert_vrl3_json('unique(["a", "b", "a"])', '["a","b"]')
	assert_vrl3_json('unique([])', '[]')
	assert_vrl3_json('unique([1])', '[1]')
}

fn test_unique_error() {
	assert_vrl3_err('unique("hello")', 'unique requires an array')
}

fn test_ensure_array() {
	assert_vrl3_json('array!([1, 2, 3])', '[1,2,3]')
	assert_vrl3_err('array!("hello")', 'expected array')
}

fn test_ensure_object() {
	result := execute('object!({"a": 1})', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"a":1'), 'ensure_object: got ${j}'

	assert_vrl3_err('object!("hello")', 'expected object')
}

// ============================================================
// Object functions: keys, values, merge, compact, get, set
// ============================================================

fn test_keys() {
	result := execute('keys({"b": 2, "a": 1})', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'keys contains a: got ${j}'
	assert j.contains('"b"'), 'keys contains b: got ${j}'
}

fn test_keys_error() {
	assert_vrl3_err('keys("hello")', 'keys requires an object')
}

fn test_values() {
	result := execute('values({"a": 1, "b": 2})', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('1'), 'values contains 1: got ${j}'
	assert j.contains('2'), 'values contains 2: got ${j}'
}

fn test_values_error() {
	assert_vrl3_err('values("hello")', 'values requires an object')
}

fn test_merge_shallow() {
	result := execute('merge({"a": 1}, {"b": 2})', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"a":1'), 'merge a: got ${j}'
	assert j.contains('"b":2'), 'merge b: got ${j}'
}

fn test_merge_overwrite() {
	result := execute('merge({"a": 1}, {"a": 2})', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"a":2'), 'merge overwrite: got ${j}'
}

fn test_merge_error() {
	assert_vrl3_err('merge("a", {"b": 1})', 'only objects can be merged')
	assert_vrl3_err('merge({"a": 1}, "b")', 'only objects can be merged')
}

fn test_compact_default() {
	// Default compact removes nulls, empty strings, empty arrays, empty objects
	result := execute('compact({"a": null, "b": "", "c": 1, "d": [], "e": {}})', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"c":1'), 'compact keeps c: got ${j}'
	assert !j.contains('"a"'), 'compact removes null: got ${j}'
	assert !j.contains('"b"'), 'compact removes empty string: got ${j}'
	assert !j.contains('"d"'), 'compact removes empty array: got ${j}'
	assert !j.contains('"e"'), 'compact removes empty object: got ${j}'
}

fn test_compact_array() {
	assert_vrl3_json('compact([1, null, "", 2, [], 3])', '[1,2,3]')
}

fn test_compact_named_args() {
	// Keep nulls but remove empty strings
	result := execute('compact({"a": null, "b": "", "c": 1}, null: false, string: true)', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"a":null'), 'compact null:false keeps null: got ${j}'
	assert j.contains('"c":1'), 'compact keeps c: got ${j}'
	assert !j.contains('"b"'), 'compact string:true removes empty str: got ${j}'
}

fn test_compact_nullish() {
	result := execute('compact([null, " ", "-", "hello", ""], nullish: true)', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"hello"'), 'compact nullish keeps hello: got ${j}'
	assert !j.contains('null'), 'compact nullish removes null: got ${j}'
}

fn test_compact_non_recursive() {
	result := execute('compact({"a": {"b": null, "c": 1}}, recursive: false)', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	// non-recursive should keep the nested null
	assert j.contains('"b":null'), 'compact non-recursive keeps nested null: got ${j}'
}

// ============================================================
// String functions
// ============================================================

fn test_contains_fn() {
	cases := [
		['contains("hello world", "world")', 'true'],
		['contains("hello world", "xyz")', 'false'],
		['contains("HELLO", "hello")', 'false'],
		['contains("HELLO", "hello", case_sensitive: false)', 'true'],
	]
	for c in cases {
		result := execute(c[0], map[string]VrlValue{}) or { panic('${c[0]}: ${err}') }
		got := vrl_to_json(result)
		assert got == c[1], '${c[0]}: expected ${c[1]}, got ${got}'
	}
}

fn test_contains_error() {
	assert_vrl3_err('contains(123, "x")', 'invalid argument type')
}

fn test_starts_with_fn() {
	assert_vrl3('starts_with("hello world", "hello")', VrlValue(true))
	assert_vrl3('starts_with("hello world", "world")', VrlValue(false))
	assert_vrl3('starts_with("HELLO", "hello", case_sensitive: false)', VrlValue(true))
}

fn test_starts_with_error() {
	assert_vrl3_err('starts_with(123, "x")', 'first arg must be string')
}

fn test_ends_with_fn() {
	assert_vrl3('ends_with("hello world", "world")', VrlValue(true))
	assert_vrl3('ends_with("hello world", "hello")', VrlValue(false))
	assert_vrl3('ends_with("WORLD", "world", case_sensitive: false)', VrlValue(true))
}

fn test_ends_with_error() {
	assert_vrl3_err('ends_with(123, "x")', 'first arg must be string')
}

fn test_replace_fn() {
	assert_vrl3('replace("hello world", "world", "earth")', VrlValue('hello earth'))
	assert_vrl3('replace("aaa", "a", "b")', VrlValue('bbb'))
	// Replace with count=1 (first occurrence only)
	assert_vrl3('replace("aaa", "a", "b", count: 1)', VrlValue('baa'))
}

fn test_replace_error() {
	assert_vrl3_err('replace(123, "a", "b")', 'replace first arg must be string')
}

fn test_split_fn() {
	assert_vrl3_json('split("a,b,c", ",")', '["a","b","c"]')
	assert_vrl3_json('split("hello", ",")', '["hello"]')
	assert_vrl3_json('split("a,b,c", ",", limit: 2)', '["a","b,c"]')
}

fn test_split_error() {
	assert_vrl3_err('split(123, ",")', 'split first arg must be string')
}

fn test_join_fn() {
	assert_vrl3('join(["a", "b", "c"], ",")', VrlValue('a,b,c'))
	assert_vrl3('join(["hello"])', VrlValue('hello'))
	assert_vrl3('join([], ",")', VrlValue(''))
	assert_vrl3('join(["a", "b"], " ")', VrlValue('a b'))
}

fn test_join_error() {
	assert_vrl3_err('join("hello")', 'join first arg must be array')
}

fn test_slice_string() {
	assert_vrl3('slice("hello", 1)', VrlValue('ello'))
	assert_vrl3('slice("hello", 1, 3)', VrlValue('el'))
	assert_vrl3('slice("hello", -3)', VrlValue('llo'))
	assert_vrl3('slice("hello", 0, 5)', VrlValue('hello'))
}

fn test_slice_array() {
	assert_vrl3_json('slice([1, 2, 3, 4, 5], 1)', '[2,3,4,5]')
	assert_vrl3_json('slice([1, 2, 3, 4, 5], 1, 3)', '[2,3]')
	assert_vrl3_json('slice([1, 2, 3], -2)', '[2,3]')
}

fn test_slice_error() {
	assert_vrl3_err('slice(123, 0)', 'slice requires string or array')
}

fn test_truncate() {
	assert_vrl3('truncate("hello world", 5)', VrlValue('hello'))
	assert_vrl3('truncate("hi", 10)', VrlValue('hi'))
	assert_vrl3('truncate("hello world", 5, suffix: "...")', VrlValue('hello...'))
	assert_vrl3('truncate("hello world", 5, ellipsis: true)', VrlValue('hello...'))
}

fn test_truncate_error() {
	assert_vrl3_err('truncate(123, 5)', 'truncate first arg must be string')
}

fn test_strlen() {
	assert_vrl3('strlen("hello")', VrlValue(i64(5)))
	assert_vrl3('strlen("")', VrlValue(i64(0)))
	assert_vrl3('strlen("abc")', VrlValue(i64(3)))
}

fn test_strlen_error() {
	assert_vrl3_err('strlen(123)', 'strlen requires a string')
}

fn test_strip_whitespace() {
	assert_vrl3('strip_whitespace("  hello  ")', VrlValue('hello'))
	assert_vrl3('strip_whitespace("hello")', VrlValue('hello'))
	assert_vrl3('strip_whitespace("")', VrlValue(''))
}

fn test_strip_whitespace_error() {
	assert_vrl3_err('strip_whitespace(123)', 'strip_whitespace requires a string')
}

fn test_downcase() {
	assert_vrl3('downcase("HELLO")', VrlValue('hello'))
	assert_vrl3('downcase("Hello World")', VrlValue('hello world'))
	assert_vrl3('downcase("already")', VrlValue('already'))
}

fn test_downcase_error() {
	assert_vrl3_err('downcase(123)', 'expected string')
}

fn test_upcase() {
	assert_vrl3('upcase("hello")', VrlValue('HELLO'))
	assert_vrl3('upcase("Hello World")', VrlValue('HELLO WORLD'))
	assert_vrl3('upcase("ALREADY")', VrlValue('ALREADY'))
}

fn test_upcase_error() {
	assert_vrl3_err('upcase(123)', 'expected string')
}

fn test_to_string_fn() {
	assert_vrl3('to_string("hello")', VrlValue('hello'))
	assert_vrl3('to_string(42)', VrlValue('42'))
	assert_vrl3('to_string(3.14)', VrlValue('3.14'))
	assert_vrl3('to_string(true)', VrlValue('true'))
	assert_vrl3('to_string(false)', VrlValue('false'))
	assert_vrl3('to_string(null)', VrlValue(''))
}

fn test_length() {
	assert_vrl3('length("hello")', VrlValue(i64(5)))
	assert_vrl3('length("")', VrlValue(i64(0)))
	assert_vrl3('length([1, 2, 3])', VrlValue(i64(3)))
	assert_vrl3('length([])', VrlValue(i64(0)))
}

fn test_length_object() {
	result := execute('length({"a": 1, "b": 2})', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j == '2', 'length object: got ${j}'
}

fn test_length_error() {
	assert_vrl3_err('length(123)', 'length requires string, array, or object')
}

// ============================================================
// Type functions
// ============================================================

fn test_is_string_fn() {
	assert_vrl3('is_string("hello")', VrlValue(true))
	assert_vrl3('is_string(42)', VrlValue(false))
	assert_vrl3('is_string(null)', VrlValue(false))
}

fn test_is_integer_fn() {
	assert_vrl3('is_integer(42)', VrlValue(true))
	assert_vrl3('is_integer("hello")', VrlValue(false))
	assert_vrl3('is_integer(3.14)', VrlValue(false))
}

fn test_is_float_fn() {
	assert_vrl3('is_float(3.14)', VrlValue(true))
	assert_vrl3('is_float(42)', VrlValue(false))
	assert_vrl3('is_float("hello")', VrlValue(false))
}

fn test_is_boolean_fn() {
	assert_vrl3('is_boolean(true)', VrlValue(true))
	assert_vrl3('is_boolean(false)', VrlValue(true))
	assert_vrl3('is_boolean(42)', VrlValue(false))
}

fn test_is_null_fn() {
	assert_vrl3('is_null(null)', VrlValue(true))
	assert_vrl3('is_null("")', VrlValue(false))
	assert_vrl3('is_null(0)', VrlValue(false))
}

fn test_is_array_fn() {
	assert_vrl3('is_array([1, 2])', VrlValue(true))
	assert_vrl3('is_array([])', VrlValue(true))
	assert_vrl3('is_array("hello")', VrlValue(false))
}

fn test_is_object_fn() {
	assert_vrl3('is_object({"a": 1})', VrlValue(true))
	assert_vrl3('is_object("hello")', VrlValue(false))
	assert_vrl3('is_object([1])', VrlValue(false))
}

fn test_is_nullish_fn() {
	assert_vrl3('is_nullish(null)', VrlValue(true))
	assert_vrl3('is_nullish("")', VrlValue(true))
	assert_vrl3('is_nullish("  ")', VrlValue(true))
	assert_vrl3('is_nullish("-")', VrlValue(true))
	assert_vrl3('is_nullish("hello")', VrlValue(false))
	assert_vrl3('is_nullish(0)', VrlValue(false))
	assert_vrl3('is_nullish(false)', VrlValue(false))
}

fn test_to_int_fn() {
	assert_vrl3('to_int!(42)', VrlValue(i64(42)))
	assert_vrl3('to_int!(3.9)', VrlValue(i64(3)))
	assert_vrl3('to_int!(true)', VrlValue(i64(1)))
	assert_vrl3('to_int!(false)', VrlValue(i64(0)))
	assert_vrl3('to_int!("123")', VrlValue(i64(123)))
	assert_vrl3('to_int!(null)', VrlValue(i64(0)))
}

fn test_to_float_fn() {
	result := execute('to_float!(42)', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j == '42' || j == '42.0', 'to_float int: got ${j}'

	result2 := execute('to_float!(3.14)', map[string]VrlValue{}) or { panic(err) }
	j2 := vrl_to_json(result2)
	assert j2 == '3.14', 'to_float float: got ${j2}'

	assert_vrl3('to_float!(true)', VrlValue(f64(1.0)))
	assert_vrl3('to_float!(false)', VrlValue(f64(0.0)))
	assert_vrl3('to_float!(null)', VrlValue(f64(0.0)))
}

fn test_to_bool_fn() {
	assert_vrl3('to_bool!(true)', VrlValue(true))
	assert_vrl3('to_bool!(false)', VrlValue(false))
	assert_vrl3('to_bool!("true")', VrlValue(true))
	assert_vrl3('to_bool!("false")', VrlValue(false))
	assert_vrl3('to_bool!("yes")', VrlValue(true))
	assert_vrl3('to_bool!("no")', VrlValue(false))
	assert_vrl3('to_bool!("y")', VrlValue(true))
	assert_vrl3('to_bool!("n")', VrlValue(false))
	assert_vrl3('to_bool!("t")', VrlValue(true))
	assert_vrl3('to_bool!("f")', VrlValue(false))
	assert_vrl3('to_bool!("1")', VrlValue(true))
	assert_vrl3('to_bool!("0")', VrlValue(false))
	assert_vrl3('to_bool!(1)', VrlValue(true))
	assert_vrl3('to_bool!(0)', VrlValue(false))
	assert_vrl3('to_bool!(null)', VrlValue(false))
}

fn test_to_bool_error() {
	assert_vrl3_err('to_bool!("maybe")', "can't convert to boolean")
}

// ============================================================
// Match functions
// ============================================================

fn test_match_fn() {
	assert_vrl3('match("hello123", r\'\\d+\')', VrlValue(true))
	assert_vrl3('match("hello", r\'\\d+\')', VrlValue(false))
	assert_vrl3('match("HELLO", r\'(?i)hello\')', VrlValue(true))
}

fn test_match_error() {
	assert_vrl3_err('match(123, r\'\\d+\')', 'match first arg must be string')
}

fn test_match_any_fn() {
	assert_vrl3('match_any("hello", [r\'\\d+\', r\'hello\'])', VrlValue(true))
	assert_vrl3('match_any("test", [r\'\\d+\', r\'xyz\'])', VrlValue(false))
	assert_vrl3('match_any("abc123", [r\'\\d+\'])', VrlValue(true))
}

fn test_match_any_error() {
	assert_vrl3_err('match_any(123, [r\'\\d+\'])', 'match_any first arg must be string')
}

fn test_includes_fn() {
	assert_vrl3('includes([1, 2, 3], 2)', VrlValue(true))
	assert_vrl3('includes([1, 2, 3], 4)', VrlValue(false))
	assert_vrl3('includes(["a", "b"], "a")', VrlValue(true))
	assert_vrl3('includes(["a", "b"], "c")', VrlValue(false))
	assert_vrl3('includes([], 1)', VrlValue(false))
}

fn test_includes_error() {
	assert_vrl3_err('includes("hello", "h")', 'includes first arg must be array')
}

fn test_contains_all_fn() {
	assert_vrl3('contains_all("hello world", ["hello", "world"])', VrlValue(true))
	assert_vrl3('contains_all("hello world", ["hello", "xyz"])', VrlValue(false))
	assert_vrl3('contains_all("HELLO WORLD", ["hello", "world"], case_sensitive: false)', VrlValue(true))
}

fn test_contains_all_error() {
	assert_vrl3_err('contains_all(123, ["a"])', 'contains_all first arg must be string')
}

fn test_find_fn() {
	assert_vrl3('find("hello world", "world")', VrlValue(i64(6)))
	assert_vrl3('find("hello", "xyz")', VrlValue(VrlNull{}))
	assert_vrl3('find("hello hello", "hello", from: 1)', VrlValue(i64(6)))
}

fn test_find_regex() {
	assert_vrl3('find("abc123def", r\'\\d+\')', VrlValue(i64(3)))
	assert_vrl3('find("abcdef", r\'\\d+\')', VrlValue(VrlNull{}))
}

fn test_find_error() {
	assert_vrl3_err('find(123, "x")', 'find first arg must be string')
}

// ============================================================
// JSON functions
// ============================================================

fn test_encode_json_fn() {
	assert_vrl3('encode_json("hello")', VrlValue('"hello"'))
	assert_vrl3('encode_json(42)', VrlValue('42'))
	assert_vrl3('encode_json(true)', VrlValue('true'))
	assert_vrl3('encode_json(null)', VrlValue('null'))
}

fn test_encode_json_array() {
	result := execute('encode_json([1, 2, 3])', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s == '[1,2,3]', 'encode_json array: got ${s}'
}

fn test_encode_json_object() {
	result := execute('encode_json({"a": 1})', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s.contains('"a":1') || s.contains('"a": 1'), 'encode_json object: got ${s}'
}

fn test_decode_json_fn() {
	assert_vrl3('decode_json!("42")', VrlValue(i64(42)))
	assert_vrl3('decode_json!("3.14")', VrlValue(f64(3.14)))
	assert_vrl3('decode_json!("true")', VrlValue(true))
	assert_vrl3('decode_json!("false")', VrlValue(false))
	assert_vrl3('decode_json!("null")', VrlValue(VrlNull{}))
	assert_vrl3('decode_json!("\\"hello\\"")', VrlValue('hello'))
}

fn test_decode_json_array() {
	assert_vrl3_json('decode_json!("[1, 2, 3]")', '[1,2,3]')
}

fn test_decode_json_object() {
	result := execute('decode_json!("{\\"a\\": 1, \\"b\\": \\"hello\\"}")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"a":1'), 'decode_json object a: got ${j}'
	assert j.contains('"b":"hello"'), 'decode_json object b: got ${j}'
}

fn test_decode_json_nested() {
	result := execute('decode_json!("{\\"a\\": {\\"b\\": [1, 2]}}")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"a":{"b":[1,2]}'), 'decode_json nested: got ${j}'
}

fn test_decode_json_escaped() {
	result := execute('decode_json!("{\\"msg\\": \\"hello\\\\nworld\\"}")', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"msg"'), 'decode_json escaped key: got ${j}'
}

fn test_decode_json_error() {
	assert_vrl3_err('decode_json!(123)', 'parse_json requires a string')
}

// ============================================================
// Timestamp functions
// ============================================================

fn test_from_unix_timestamp_seconds() {
	result := execute('from_unix_timestamp(0, unit: "seconds")', map[string]VrlValue{}) or {
		panic(err)
	}
	// Should return a timestamp
	ts := result as Timestamp
	assert ts.t.unix() == 0, 'from_unix_timestamp seconds: got ${ts.t.unix()}'
}

fn test_from_unix_timestamp_default() {
	result := execute('from_unix_timestamp(1000)', map[string]VrlValue{}) or { panic(err) }
	ts := result as Timestamp
	assert ts.t.unix() == 1000, 'from_unix_timestamp default: got ${ts.t.unix()}'
}

fn test_from_unix_timestamp_milliseconds() {
	result := execute('from_unix_timestamp(1000000, unit: "milliseconds")', map[string]VrlValue{}) or {
		panic(err)
	}
	ts := result as Timestamp
	assert ts.t.unix() == 1000, 'from_unix_timestamp ms: got ${ts.t.unix()}'
}

fn test_from_unix_timestamp_nanoseconds() {
	result := execute('from_unix_timestamp(1000000000, unit: "nanoseconds")', map[string]VrlValue{}) or {
		panic(err)
	}
	ts := result as Timestamp
	assert ts.t.unix() == 1, 'from_unix_timestamp ns: got ${ts.t.unix()}'
}

fn test_from_unix_timestamp_microseconds() {
	result := execute('from_unix_timestamp(1000000, unit: "microseconds")', map[string]VrlValue{}) or {
		panic(err)
	}
	ts := result as Timestamp
	assert ts.t.unix() == 1, 'from_unix_timestamp us: got ${ts.t.unix()}'
}

fn test_from_unix_timestamp_error() {
	assert_vrl3_err('from_unix_timestamp("hello")', 'from_unix_timestamp requires an integer')
}

fn test_from_unix_timestamp_unknown_unit() {
	assert_vrl3_err('from_unix_timestamp(0, unit: "years")', 'unknown unit')
}

fn test_to_unix_timestamp() {
	// Create a timestamp from seconds, then convert back
	result := execute('to_unix_timestamp(from_unix_timestamp(12345))', map[string]VrlValue{}) or {
		panic(err)
	}
	assert result == VrlValue(i64(12345)), 'to_unix_timestamp roundtrip: got ${vrl_to_json(result)}'
}

fn test_to_unix_timestamp_milliseconds() {
	result := execute('to_unix_timestamp(from_unix_timestamp(1), unit: "milliseconds")', map[string]VrlValue{}) or {
		panic(err)
	}
	assert result == VrlValue(i64(1000)), 'to_unix_timestamp ms: got ${vrl_to_json(result)}'
}

fn test_to_unix_timestamp_nanoseconds() {
	result := execute('to_unix_timestamp(from_unix_timestamp(1), unit: "nanoseconds")', map[string]VrlValue{}) or {
		panic(err)
	}
	assert result == VrlValue(i64(1000000000)), 'to_unix_timestamp ns: got ${vrl_to_json(result)}'
}

fn test_to_unix_timestamp_microseconds() {
	result := execute('to_unix_timestamp(from_unix_timestamp(1), unit: "microseconds")', map[string]VrlValue{}) or {
		panic(err)
	}
	assert result == VrlValue(i64(1000000)), 'to_unix_timestamp us: got ${vrl_to_json(result)}'
}

fn test_to_unix_timestamp_error() {
	assert_vrl3_err('to_unix_timestamp("hello")', 'to_unix_timestamp requires a timestamp')
}

fn test_to_unix_timestamp_unknown_unit() {
	assert_vrl3_err('to_unix_timestamp(from_unix_timestamp(0), unit: "years")', 'unknown unit')
}

// ============================================================
// Format functions
// ============================================================

fn test_format_number_basic() {
	result := execute('format_number(1234.567)', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s == '1234.567', 'format_number basic: got ${s}'
}

fn test_format_number_scale() {
	result := execute('format_number(1234.567, 2)', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s == '1234.57', 'format_number scale 2: got ${s}'
}

fn test_format_number_scale_zero() {
	result := execute('format_number(1234.567, 0)', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s == '1234', 'format_number scale 0: got ${s}'
}

fn test_format_number_separators() {
	result := execute('format_number(1234567.89, 2, decimal_separator: ",", grouping_separator: ".")', map[string]VrlValue{}) or {
		panic(err)
	}
	s := result as string
	assert s == '1.234.567,89', 'format_number separators: got ${s}'
}

fn test_format_number_grouping() {
	result := execute('format_number(1234567, grouping_separator: ",")', map[string]VrlValue{}) or {
		panic(err)
	}
	s := result as string
	assert s == '1,234,567.0', 'format_number grouping: got ${s}'
}

fn test_format_number_integer() {
	result := execute('format_number(42)', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s == '42.0', 'format_number integer: got ${s}'
}

fn test_format_number_integer_scale() {
	result := execute('format_number(42, 2)', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s == '42.00', 'format_number integer scale: got ${s}'
}

fn test_format_number_error() {
	assert_vrl3_err('format_number("hello")', 'format_number requires a number')
}

// ============================================================
// Assert functions
// ============================================================

fn test_assert_true() {
	assert_vrl3('assert(true)', VrlValue(true))
	assert_vrl3('assert!(true)', VrlValue(true))
}

fn test_assert_false() {
	assert_vrl3_err('assert!(false)', 'assertion failed')
}

fn test_assert_with_message() {
	assert_vrl3_err('assert!(false, message: "custom error")', 'custom error')
}

fn test_assert_eq_fn() {
	assert_vrl3('assert_eq!(1, 1)', VrlValue(true))
	assert_vrl3('assert_eq!("hello", "hello")', VrlValue(true))
	assert_vrl3('assert_eq!(true, true)', VrlValue(true))
}

fn test_assert_eq_fail() {
	assert_vrl3_err('assert_eq!(1, 2)', 'assertion failed')
}

fn test_assert_eq_with_message() {
	assert_vrl3_err('assert_eq!(1, 2, message: "not equal")', 'not equal')
}

// ============================================================
// Misc functions
// ============================================================

fn test_uuid_v4() {
	result := execute('uuid_v4()', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s.len == 36, 'uuid_v4 length: got ${s.len}'
	assert s[8] == `-`, 'uuid_v4 dash at 8'
	assert s[13] == `-`, 'uuid_v4 dash at 13'
	assert s[18] == `-`, 'uuid_v4 dash at 18'
	assert s[23] == `-`, 'uuid_v4 dash at 23'
	assert s[14] == `4`, 'uuid_v4 version char: got ${s[14]}'
}

fn test_uuid_v4_uniqueness() {
	r1 := execute('uuid_v4()', map[string]VrlValue{}) or { panic(err) }
	r2 := execute('uuid_v4()', map[string]VrlValue{}) or { panic(err) }
	assert r1 != r2, 'uuid_v4 should produce unique values'
}

fn test_get_env_var() {
	// PATH should always exist
	result := execute('get_env_var!("PATH")', map[string]VrlValue{}) or { panic(err) }
	s := result as string
	assert s.len > 0, 'get_env_var PATH should not be empty'
}

fn test_get_env_var_not_found() {
	assert_vrl3_err('get_env_var!("VERY_UNLIKELY_ENV_VAR_NAME_XYZ_12345")', 'environment variable not found')
}

fn test_get_env_var_error() {
	assert_vrl3_err('get_env_var!(123)', 'get_env_var requires a string')
}

fn test_to_regex_fn() {
	// to_regex creates a regex from a string
	result := execute('to_regex!("\\\\d+")', map[string]VrlValue{}) or { panic(err) }
	r := result as VrlRegex
	assert r.pattern == '\\d+', 'to_regex pattern: got ${r.pattern}'
}

fn test_to_regex_error() {
	assert_vrl3_err('to_regex!(123)', 'to_regex requires a string')
}

fn test_exists_fn() {
	mut obj := map[string]VrlValue{}
	obj['name'] = VrlValue('test')
	result := execute('exists(.name)', obj) or { panic(err) }
	assert result == VrlValue(true), 'exists .name: got ${vrl_to_json(result)}'

	result2 := execute('exists(.missing)', obj) or { panic(err) }
	assert result2 == VrlValue(false), 'exists .missing: got ${vrl_to_json(result2)}'
}

// ============================================================
// Path functions: get (nested), set (nested)
// ============================================================

fn test_get_nested_path() {
	result := execute('get!({"a": {"b": {"c": 42}}}, ["a", "b", "c"])', map[string]VrlValue{}) or {
		panic(err)
	}
	assert result == VrlValue(i64(42)), 'get nested: got ${vrl_to_json(result)}'
}

fn test_get_missing_path() {
	result := execute('get!({"a": 1}, ["b"])', map[string]VrlValue{}) or { panic(err) }
	assert result is VrlNull, 'get missing should return null'
}

fn test_get_array_index() {
	result := execute('get!([10, 20, 30], [1])', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(20)), 'get array index: got ${vrl_to_json(result)}'
}

fn test_set_nested_path() {
	result := execute('set!({"a": {}}, ["a", "b"], 42)', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"b":42'), 'set nested: got ${j}'
}

fn test_set_create_path() {
	result := execute('set!({"a": 1}, ["b"], 2)', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"a":1'), 'set keeps a: got ${j}'
	assert j.contains('"b":2'), 'set creates b: got ${j}'
}

fn test_set_auto_create_nested() {
	result := execute('set!(null, ["a", "b"], 42)', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'set auto-create a: got ${j}'
	assert j.contains('"b":42'), 'set auto-create b: got ${j}'
}

fn test_get_with_named_args() {
	result := execute('get!(value: {"x": 10}, path: ["x"])', map[string]VrlValue{}) or {
		panic(err)
	}
	assert result == VrlValue(i64(10)), 'get named args: got ${vrl_to_json(result)}'
}

fn test_set_with_named_args() {
	result := execute('set!(value: {"x": 1}, path: ["y"], data: 2)', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"y":2'), 'set named args: got ${j}'
}

// ============================================================
// Edge cases for coverage
// ============================================================

fn test_string_fn() {
	// string() is like ensure_string - passes through strings, errors on others
	assert_vrl3('string!("hello")', VrlValue('hello'))
	assert_vrl3_err('string!(123)', 'expected string')
}

fn test_compact_object_flags() {
	// Test with object:false - empty objects should be kept
	result := execute('compact({"a": null, "b": {}, "c": 1}, object: false)', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"b":{}'), 'compact object:false keeps empty obj: got ${j}'
	assert j.contains('"c":1'), 'compact object:false keeps c: got ${j}'
	assert !j.contains('"a"'), 'compact object:false removes null: got ${j}'
}

fn test_compact_array_flag() {
	// Test with array:false - empty arrays should be kept
	result := execute('compact({"a": null, "b": [], "c": 1}, array: false)', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	assert j.contains('"b":[]'), 'compact array:false keeps empty arr: got ${j}'
	assert j.contains('"c":1'), 'compact array:false keeps c: got ${j}'
}

fn test_replace_with_regex() {
	result := execute('replace("hello 123 world", r\'\\d+\', "NUM")', map[string]VrlValue{}) or {
		panic(err)
	}
	s := result as string
	assert s == 'hello NUM world', 'replace regex: got ${s}'
}

fn test_replace_regex_count1() {
	result := execute('replace("a1b2c3", r\'\\d\', "X", count: 1)', map[string]VrlValue{}) or {
		panic(err)
	}
	s := result as string
	assert s == 'aXb2c3', 'replace regex count 1: got ${s}'
}

fn test_split_with_limit() {
	assert_vrl3_json('split("a,b,c,d", ",", limit: 3)', '["a","b","c,d"]')
}

fn test_find_with_from() {
	// Find "o" starting from position 5
	result := execute('find("hello world", "o", from: 5)', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(7)), 'find with from: got ${vrl_to_json(result)}'
}

fn test_encode_json_pretty() {
	result := execute('encode_json({"a": 1}, pretty: true)', map[string]VrlValue{}) or {
		panic(err)
	}
	s := result as string
	assert s.contains('\n'), 'encode_json pretty should have newlines: got ${s}'
}

fn test_decode_json_max_depth() {
	result := execute('decode_json!("{\\"a\\": {\\"b\\": 1}}", max_depth: 1)', map[string]VrlValue{}) or {
		panic(err)
	}
	j := vrl_to_json(result)
	// At depth 1, the inner object should be kept as string
	assert j.contains('"a"'), 'decode_json max_depth: got ${j}'
}

fn test_ceil_floor_round_integer_passthrough() {
	// Integers should pass through unchanged
	assert_vrl3('ceil(10)', VrlValue(i64(10)))
	assert_vrl3('floor(10)', VrlValue(i64(10)))
	assert_vrl3('round(10)', VrlValue(i64(10)))
}

fn test_abs_zero() {
	assert_vrl3('abs(0)', VrlValue(i64(0)))
}

fn test_unique_with_mixed_types() {
	assert_vrl3_json('unique([1, "a", 1, "a", true, true])', '[1,"a",true]')
}

fn test_flatten_deeply_nested() {
	assert_vrl3_json('flatten([1, [2, [3, [4]]]])', '[1,2,3,4]')
}

fn test_get_empty_segments() {
	result := execute('get!({"a": 1}, [])', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	// Empty path returns the container itself
	assert j.contains('"a":1'), 'get empty path: got ${j}'
}

fn test_set_overwrite_value() {
	result := execute('set!({"a": 1}, ["a"], 99)', map[string]VrlValue{}) or { panic(err) }
	j := vrl_to_json(result)
	assert j.contains('"a":99'), 'set overwrite: got ${j}'
}
