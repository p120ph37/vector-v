module vrl

// Unit tests for VRL lexer, parser, and runtime.

fn test_lexer_basic_tokens() {
	mut lex := new_lexer('1 + 2')
	tokens := lex.tokenize()
	assert tokens[0].kind == .integer
	assert tokens[0].lit == '1'
	assert tokens[1].kind == .plus
	assert tokens[2].kind == .integer
	assert tokens[2].lit == '2'
}

fn test_lexer_string() {
	mut lex := new_lexer('"hello world"')
	tokens := lex.tokenize()
	assert tokens[0].kind == .string_lit
	assert tokens[0].lit == 'hello world'
}

fn test_lexer_dot_path() {
	mut lex := new_lexer('.foo.bar')
	tokens := lex.tokenize()
	assert tokens[0].kind == .dot_ident
	assert tokens[0].lit == '.foo.bar'
}

fn test_lexer_keywords() {
	mut lex := new_lexer('true false null')
	tokens := lex.tokenize()
	assert tokens[0].kind == .true_lit
	assert tokens[1].kind == .false_lit
	assert tokens[2].kind == .null_lit
}

fn test_lexer_operators() {
	mut lex := new_lexer('== != <= >= && || ??')
	tokens := lex.tokenize()
	assert tokens[0].kind == .eq
	assert tokens[1].kind == .neq
	assert tokens[2].kind == .le
	assert tokens[3].kind == .ge
	assert tokens[4].kind == .and
	assert tokens[5].kind == .or
	assert tokens[6].kind == .question2
}

fn test_integer_arithmetic() {
	result := execute('1 + 1', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(2))
}

fn test_float_arithmetic() {
	result := execute('1.5 + 2.5', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(4.0)
}

fn test_string_literal() {
	result := execute('"hello"', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('hello')
}

fn test_boolean_literal() {
	result := execute('true', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)
}

fn test_null_literal() {
	result := execute('null', map[string]VrlValue{}) or { panic(err) }
	assert result is VrlNull
}

fn test_variable_assignment() {
	result := execute('foo = 5\nfoo', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(5))
}

fn test_path_access() {
	mut obj := map[string]VrlValue{}
	obj['message'] = VrlValue('hello')
	result := execute('.message', obj) or { panic(err) }
	assert result == VrlValue('hello')
}

fn test_path_assignment() {
	mut obj := map[string]VrlValue{}
	result := execute('.foo = "bar"\n.', obj) or { panic(err) }
	json_str := vrl_to_json(result)
	assert json_str.contains('"foo"')
	assert json_str.contains('"bar"')
}

fn test_del_function() {
	mut obj := map[string]VrlValue{}
	obj['a'] = VrlValue(i64(1))
	obj['b'] = VrlValue(i64(2))
	result := execute('del(.a)\n.', obj) or { panic(err) }
	json_str := vrl_to_json(result)
	assert !json_str.contains('"a"')
	assert json_str.contains('"b"')
}

fn test_equality() {
	result := execute('1 == 1', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)

	result2 := execute('1 == 2', map[string]VrlValue{}) or { panic(err) }
	assert result2 == VrlValue(false)
}

fn test_comparison() {
	result := execute('1 < 2', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)
}

fn test_logical_and() {
	result := execute('true && true', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)

	result2 := execute('true && false', map[string]VrlValue{}) or { panic(err) }
	assert result2 == VrlValue(false)
}

fn test_logical_or() {
	result := execute('false || true', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)
}

fn test_if_expression() {
	result := execute('if true { "yes" } else { "no" }', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('yes')

	result2 := execute('if false { "yes" } else { "no" }', map[string]VrlValue{}) or { panic(err) }
	assert result2 == VrlValue('no')
}

fn test_array_literal() {
	result := execute('[1, 2, 3]', map[string]VrlValue{}) or { panic(err) }
	json_str := vrl_to_json(result)
	assert json_str == '[1,2,3]'
}

fn test_object_literal() {
	result := execute('{ "foo": 1, "bar": 2 }', map[string]VrlValue{}) or { panic(err) }
	json_str := vrl_to_json(result)
	assert json_str.contains('"foo":1')
	assert json_str.contains('"bar":2')
}

fn test_downcase() {
	result := execute('downcase("HELLO")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('hello')
}

fn test_upcase() {
	result := execute('upcase("hello")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('HELLO')
}

fn test_contains() {
	result := execute('contains("hello world", "world")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)
}

fn test_to_int() {
	result := execute('to_int!(true)', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(1))
}

fn test_to_string() {
	result := execute('to_string!(42)', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('42')
}

fn test_encode_json() {
	result := execute('encode_json({"foo": "bar"})', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('{"foo":"bar"}')
}

fn test_is_type_functions() {
	result := execute('is_string("hello")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)

	result2 := execute('is_integer(42)', map[string]VrlValue{}) or { panic(err) }
	assert result2 == VrlValue(true)

	result3 := execute('is_boolean(true)', map[string]VrlValue{}) or { panic(err) }
	assert result3 == VrlValue(true)

	result4 := execute('is_null(null)', map[string]VrlValue{}) or { panic(err) }
	assert result4 == VrlValue(true)
}

fn test_length() {
	result := execute('length("hello")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(5))
}

fn test_error_coalescing() {
	// ?? should catch errors and return default
	result := execute('"hello" ?? "default"', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('hello')
}

fn test_abs() {
	result := execute('abs(-5)', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(5))
}

fn test_merge_objects() {
	result := execute('merge({"a": 1}, {"b": 2})', map[string]VrlValue{}) or { panic(err) }
	json_str := vrl_to_json(result)
	assert json_str.contains('"a":1')
	assert json_str.contains('"b":2')
}

fn test_flatten_object() {
	mut obj := map[string]VrlValue{}
	mut inner := new_object_map()
	inner.set('b', VrlValue(i64(1)))
	obj['a'] = VrlValue(inner)
	result := execute('flatten(.)', obj) or { panic(err) }
	json_str := vrl_to_json(result)
	assert json_str.contains('"a.b":1')
}

fn test_split() {
	result := execute('split("a,b,c", ",")', map[string]VrlValue{}) or { panic(err) }
	json_str := vrl_to_json(result)
	assert json_str == '["a","b","c"]'
}

fn test_join() {
	result := execute('join(["a", "b", "c"], "-")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('a-b-c')
}

fn test_compact_array() {
	result := execute('compact(["a", null, "b"])', map[string]VrlValue{}) or { panic(err) }
	json_str := vrl_to_json(result)
	assert json_str == '["a","b"]'
}

fn test_multiplication() {
	result := execute('3 * 4', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(12))
}

fn test_division() {
	result := execute('10 / 2', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(5.0)
}

fn test_subtraction() {
	result := execute('10 - 3', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(7))
}

fn test_modulo() {
	result := execute('10 % 3', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(1))
}

fn test_nested_path_set_get() {
	mut obj := map[string]VrlValue{}
	mut inner := new_object_map()
	inner.set('b', VrlValue(i64(42)))
	obj['a'] = VrlValue(inner)
	result := execute('.a.b', obj) or { panic(err) }
	assert result == VrlValue(i64(42))
}

fn test_not_operator() {
	result := execute('!true', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(false)

	result2 := execute('!false', map[string]VrlValue{}) or { panic(err) }
	assert result2 == VrlValue(true)
}

fn test_merge_assign() {
	result := execute('. = {"foo": 1}\n. |= {"bar": 2}\n.', map[string]VrlValue{}) or {
		panic(err)
	}
	json_str := vrl_to_json(result)
	assert json_str.contains('"foo":1')
	assert json_str.contains('"bar":2')
}

fn test_multiline_program() {
	src := '
.foo = "test"
.bar = "hello"
.baz = 42
.
'
	result := execute(src, map[string]VrlValue{}) or { panic(err) }
	json_str := vrl_to_json(result)
	assert json_str.contains('"foo":"test"')
	assert json_str.contains('"bar":"hello"')
	assert json_str.contains('"baz":42')
}

fn test_integer_with_underscores() {
	mut lex := new_lexer('123_000_123')
	tokens := lex.tokenize()
	assert tokens[0].kind == .integer
	assert tokens[0].lit == '123000123'
}

fn test_push() {
	result := execute('push([1, 2], 3)', map[string]VrlValue{}) or { panic(err) }
	json_str := vrl_to_json(result)
	assert json_str == '[1,2,3]'
}

fn test_replace() {
	result := execute('replace("hello world", "world", "vlang")', map[string]VrlValue{}) or {
		panic(err)
	}
	assert result == VrlValue('hello vlang')
}

fn test_starts_ends_with() {
	result := execute('starts_with("hello", "he")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)

	result2 := execute('ends_with("hello", "lo")', map[string]VrlValue{}) or { panic(err) }
	assert result2 == VrlValue(true)
}

fn test_ok_err_assignment() {
	// Success case: .ok gets value, err gets null
	r1 := execute('.x = 1\n.ok, err = 1 / .x\ndel(.x)\n[., err]', map[string]VrlValue{}) or {
		panic(err)
	}
	j1 := vrl_to_json(r1)
	assert j1 == '[{"ok":1.0},null]', 'ok_err success: got ${j1}'

	// Error case: ok gets default, err gets error string
	r2 := execute('.ok, .err = 1 / 0\n.', map[string]VrlValue{}) or { panic(err) }
	j2 := vrl_to_json(r2)
	assert j2.contains('"err"'), 'ok_err error: got ${j2}'
	assert j2.contains('divide by zero'), 'ok_err error msg: got ${j2}'
}
