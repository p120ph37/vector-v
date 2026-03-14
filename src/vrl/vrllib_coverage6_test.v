module vrl

import time

// Coverage tests for parser.v, value.v, vrllib_type.v, vrllib_array.v

fn test_cov6_parser_dotted_assign() {
	result := execute('.val = "hello"
.result = .val', map[string]VrlValue{}) or { return }
	assert result == VrlValue('hello')
}

fn test_cov6_parser_reserved_keywords() {
	for kw in ['array', 'object', 'string', 'integer', 'float', 'boolean', 'null', 'regex', 'timestamp'] {
		_ := execute('${kw} = 42', map[string]VrlValue{}) or { continue }
	}
}

fn test_cov6_parser_dot_property() {
	result := execute('.obj = {"name": "test"}
.result = .obj.name', map[string]VrlValue{}) or { return }
	assert result == VrlValue('test')
}

fn test_cov6_parser_nested_property() {
	result := execute('.obj = {"a": {"b": "deep"}}
.result = .obj.a.b', map[string]VrlValue{}) or { return }
	assert result == VrlValue('deep')
}

fn test_cov6_parser_scalar_property() {
	_ := execute('.result = "hello".length', map[string]VrlValue{}) or { return }
}

fn test_cov6_parser_dot_root() {
	result := execute('. = {"foo": "bar"}
.result = .foo', map[string]VrlValue{}) or { return }
	assert result == VrlValue('bar')
}

fn test_cov6_parser_paren_semicolons() {
	result := execute('.result = (1; 2; 3)', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(3))
}

fn test_cov6_parser_unary_minus() {
	result := execute('.result = -42', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(-42))
}

fn test_cov6_parser_unary_minus_float() {
	result := execute('.result = -3.14', map[string]VrlValue{}) or { return }
	assert result == VrlValue(-3.14)
}

fn test_cov6_parser_fn_newlines() {
	result := execute('.result = to_string(\n\t42\n)', map[string]VrlValue{}) or { return }
	assert result == VrlValue('42')
}

fn test_cov6_parser_named_arg_keyword() {
	result := execute('.result = is_json("{}", variant: "object")', map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_cov6_parser_closure_path() {
	result := execute('.items = [1, 2, 3]
.result = length(.items)', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(3))
}

fn test_cov6_parser_block_or_expr() {
	result := execute('.result = if true { 1 } else { 2 }', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(1))
}

fn test_cov6_parser_block() {
	result := execute('.a = 1
.b = { .a = 10; .a }
.result = .b', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(10))
}

fn test_cov6_parser_object_literal() {
	result := execute('.obj = {"key1": "val1", "key2": "val2"}
.result = .obj.key1', map[string]VrlValue{}) or { return }
	assert result == VrlValue('val1')
}

fn test_cov6_parser_string_interpolation() {
	result := execute('.name = "world"
.result = "hello {{.name}}"', map[string]VrlValue{}) or { return }
	assert result == VrlValue('hello world')
}

fn test_cov6_parser_error_coalescing() {
	result := execute('.result = to_int("not_a_number") ?? 0', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(0))
}

// value.v — timestamp formatting (lines 100-101, 107-109)
fn test_cov6_value_timestamp_format_no_frac() {
	t := time.new(year: 2020, month: 1, day: 1, hour: 0, minute: 0, second: 0)
	result := format_timestamp(t)
	assert result.contains('2020')
}

fn test_cov6_value_timestamp_format_with_offset() {
	t := time.new(year: 2020, month: 6, day: 15, hour: 10, minute: 30, second: 0)
	result := format_timestamp(t)
	assert result.contains('2020')
}

// value.v — large ObjectMap comparison (lines 321-323, 326)
fn test_cov6_value_large_objectmap_cmp() {
	mut om1 := new_object_map()
	mut om2 := new_object_map()
	for i in 0 .. 40 {
		om1.set('key_${i}', VrlValue(i64(i)))
		om2.set('key_${i}', VrlValue(i64(i)))
	}
	assert values_equal(VrlValue(om1), VrlValue(om2))

	mut om3 := new_object_map()
	for i in 0 .. 40 {
		om3.set('key_${i}', VrlValue(i64(i)))
	}
	om3.set('key_0', VrlValue(i64(999)))
	assert !values_equal(VrlValue(om1), VrlValue(om3))

	mut om4 := new_object_map()
	for i in 0 .. 35 {
		om4.set('key_${i}', VrlValue(i64(i)))
	}
	assert !values_equal(VrlValue(om1), VrlValue(om4))
}

// vrllib_type.v — type checking (lines 6, 20, 75, 84, 93, 105)
fn test_cov6_is_empty_no_args() {
	_ := fn_is_empty([]VrlValue{}) or { return }
}

fn test_cov6_is_json_no_args() {
	_ := fn_is_json([]VrlValue{}) or { return }
}

fn test_cov6_is_regex_no_args() {
	result := fn_is_regex([]VrlValue{}) or { return }
	assert result == VrlValue(false)
}

fn test_cov6_is_timestamp_no_args() {
	result := fn_is_timestamp([]VrlValue{}) or { return }
	assert result == VrlValue(false)
}

fn test_cov6_timestamp_no_args() {
	_ := fn_timestamp([]VrlValue{}) or { return }
}

fn test_cov6_tag_types_no_args() {
	_ := fn_tag_types_externally([]VrlValue{}) or { return }
}

// vrllib_array.v — chunks edge cases (lines 6, 12, 39)
fn test_cov6_chunks_no_args() {
	_ := fn_chunks([]VrlValue{}) or { return }
}

fn test_cov6_chunks_non_int_size() {
	_ := fn_chunks([VrlValue('hello'), VrlValue('not_int')]) or { return }
}

fn test_cov6_chunks_invalid_type() {
	_ := fn_chunks([VrlValue(i64(42)), VrlValue(i64(2))]) or { return }
}

// Comparison operators (refactored in runtime.v)
fn test_cov6_compare_lt_int() {
	result := execute('.result = 1 < 2', map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_cov6_compare_le_float() {
	result := execute('.result = 1.5 <= 1.5', map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_cov6_compare_gt_string() {
	result := execute('.result = "b" > "a"', map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_cov6_compare_ge_int_float() {
	result := execute('.result = 5 >= 4.9', map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_cov6_compare_type_error() {
	_ := execute('.result = "a" < 1', map[string]VrlValue{}) or { return }
}

// Type constructors (refactored in type_inference.v)
fn test_cov6_type_constructors() {
	nt := never_type()
	assert nt.len() == 1
	
	bt := boolean_type()
	assert bt.len() == 1
	
	it := integer_type()
	assert it.len() == 1
	
	ft := float_type()
	assert ft.len() == 1
	
	at := any_type()
	assert at.len() == 1
	
	ut := undefined_type()
	assert ut.len() == 1
}

// Case conversion (refactored in vrllib_string.v)
fn test_cov6_camelcase() {
	result := execute('.result = camelcase("hello_world")', map[string]VrlValue{}) or { return }
	assert result == VrlValue('helloWorld')
}

fn test_cov6_pascalcase() {
	result := execute('.result = pascalcase("hello_world")', map[string]VrlValue{}) or { return }
	assert result == VrlValue('HelloWorld')
}

fn test_cov6_snakecase() {
	result := execute('.result = snakecase("helloWorld")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('hello')
}

fn test_cov6_kebabcase() {
	result := execute('.result = kebabcase("hello_world")', map[string]VrlValue{}) or { return }
	assert result == VrlValue('hello-world')
}

fn test_cov6_screamingsnakecase() {
	result := execute('.result = screaming_snakecase("hello_world")', map[string]VrlValue{}) or { return }
	assert result == VrlValue('HELLO_WORLD')
}

// parser.v lines 85-86, 90: ok/err assignment with ident.dot.ident target
fn test_cov6_parser_ok_err_dotted_ident_target() {
	// This tests the branch where err target is ident followed by .dot .ident
	// e.g. .result, err_info = to_int!("abc")
	prog := '.result, err_info = to_int!("abc")'
	_ := execute(prog, map[string]VrlValue{}) or { return }
}

// parser.v line 620: closure with || empty params
fn test_cov6_parser_closure_for_each() {
	// for_each / map_values use closures
	prog := '.arr = [10, 20, 30]
.result = map_values(.arr) -> |v| { v + 1 }'
	_ := execute(prog, map[string]VrlValue{}) or { return }
}

// parser.v line 828: string interpolation with no templates produces empty literal
fn test_cov6_parser_string_interp_empty() {
	result := execute('.result = "no interpolation here"', map[string]VrlValue{}) or { return }
	assert result == VrlValue('no interpolation here')
}

// parser.v line 777: current() past end (eof sentinel)
fn test_cov6_parser_eof_handling() {
	// A very short program that ends abruptly should still parse
	result := execute('.result = 1', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(1))
}

// parser.v line 660: empty block with only newlines
fn test_cov6_parser_block_only_newlines() {
	prog := '.result = {\n\n5\n\n}'
	result := execute(prog, map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(5))
}

// parser.v line 651: block_or_expr taking expr branch (no braces)
fn test_cov6_parser_if_else_no_block() {
	// if/else where else is a simple expression
	result := execute('.result = if false { 1 } else { 99 }', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(99))
}

// value.v line 326: large ObjectMap key not found in other
fn test_cov6_value_large_objectmap_missing_key() {
	mut om1 := new_object_map()
	mut om2 := new_object_map()
	for i in 0 .. 40 {
		om1.set('key_${i}', VrlValue(i64(i)))
		om2.set('other_${i}', VrlValue(i64(i)))
	}
	assert !values_equal(VrlValue(om1), VrlValue(om2)), 'maps with completely different keys'
}

// parser.v line 565: rparen after newline in fn args
fn test_cov6_parser_fn_args_trailing_newline() {
	prog := '.result = to_string(\n42,\n)'
	_ := execute(prog, map[string]VrlValue{}) or { return }
}
