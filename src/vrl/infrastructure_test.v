module vrl

// Tests exercising VRL infrastructure: runtime, lexer, objectmap, operators, etc.

fn test_nested_if_else() {
	result := execute('
		x = 10
		if x > 5 {
			if x > 15 {
				"big"
			} else {
				"medium"
			}
		} else {
			"small"
		}
	', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('medium')
}

fn test_block_returns_last_value() {
	result := execute('
		x = 1
		y = 2
		x + y
	', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(3))
}

fn test_abort_stops_execution() {
	mut obj := map[string]VrlValue{}
	obj['message'] = VrlValue('test')
	mut lex := new_lexer('abort')
	tokens := lex.tokenize()
	mut parser := new_parser(tokens)
	ast := parser.parse() or { panic(err) }
	mut rt := new_runtime_with_object(obj)
	rt.eval(ast) or {}
	assert rt.aborted == true
}

fn test_objectmap_large_mode() {
	// Create an ObjectMap with >32 keys to trigger hash mode
	mut m := new_object_map()
	for i in 0 .. 40 {
		m.set('key_${i}', VrlValue(i64(i)))
	}
	assert m.is_large == true
	assert m.len() == 40

	// Verify all values are accessible
	for i in 0 .. 40 {
		val := m.get('key_${i}') or { panic('missing key_${i}') }
		assert val == VrlValue(i64(i))
	}

	// Delete a key
	m.delete('key_5')
	assert m.len() == 39
	if _ := m.get('key_5') {
		assert false, 'key_5 should have been deleted'
	}
}

fn test_objectmap_small_mode() {
	mut m := new_object_map()
	m.set('a', VrlValue('hello'))
	m.set('b', VrlValue(i64(42)))
	assert m.is_large == false
	assert m.len() == 2

	keys := m.keys()
	assert keys.len == 2

	val := m.get('a') or { panic('missing key') }
	assert val == VrlValue('hello')
}

fn test_objectmap_clone() {
	mut m := new_object_map()
	m.set('x', VrlValue(i64(1)))
	cloned := m.clone_map()
	assert cloned.len() == 1
	val := cloned.get('x') or { panic('missing') }
	assert val == VrlValue(i64(1))
}

fn test_objectmap_to_map() {
	mut m := new_object_map()
	m.set('foo', VrlValue('bar'))
	m.set('num', VrlValue(i64(99)))
	stdmap := m.to_map()
	assert stdmap.len == 2
	assert stdmap['foo'] == VrlValue('bar')
	assert stdmap['num'] == VrlValue(i64(99))
}

fn test_type_coercion_int_to_string() {
	result := execute('to_string(42)', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('42')
}

fn test_type_coercion_string_to_int() {
	result := execute('to_int!("123")', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(123))
}

fn test_type_coercion_int_to_float() {
	result := execute('to_float(42)', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(f64(42.0))
}

fn test_error_coalesce_operator() {
	result := execute('to_int("not_a_number") ?? 0', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(0))
}

fn test_error_coalesce_success() {
	result := execute('to_int("42") ?? 0', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(42))
}

fn test_lexer_raw_string() {
	mut lex := new_lexer("s'hello world'")
	tokens := lex.tokenize()
	assert tokens[0].kind == .raw_string
	assert tokens[0].lit == 'hello world'
}

fn test_lexer_regex() {
	mut lex := new_lexer("r'[a-z]+'")
	tokens := lex.tokenize()
	assert tokens[0].kind == .regex_lit
	assert tokens[0].lit == '[a-z]+'
}

fn test_lexer_comments() {
	mut lex := new_lexer('1 + 2 # this is a comment\n3')
	tokens := lex.tokenize()
	// Should skip the comment
	mut found_3 := false
	for t in tokens {
		if t.kind == .integer && t.lit == '3' {
			found_3 = true
		}
	}
	assert found_3
}

fn test_lexer_quoted_path() {
	mut lex := new_lexer('."quoted key"')
	tokens := lex.tokenize()
	assert tokens[0].kind == .dot_ident
}

fn test_binary_operators_eq() {
	result := execute('1 == 1', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)
}

fn test_binary_operators_neq() {
	result := execute('1 != 2', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)
}

fn test_binary_operators_gt() {
	result := execute('5 > 3', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)
}

fn test_binary_operators_lt() {
	result := execute('3 < 5', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)
}

fn test_binary_operators_ge() {
	result := execute('5 >= 5', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)
}

fn test_binary_operators_le() {
	result := execute('5 <= 5', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)
}

fn test_binary_operators_and() {
	result := execute('true && true', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)

	result2 := execute('true && false', map[string]VrlValue{}) or { panic(err) }
	assert result2 == VrlValue(false)
}

fn test_binary_operators_or() {
	result := execute('false || true', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)

	result2 := execute('false || false', map[string]VrlValue{}) or { panic(err) }
	assert result2 == VrlValue(false)
}

fn test_array_indexing() {
	result := execute('
		arr = [10, 20, 30]
		arr[1]
	', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(20))
}

fn test_array_negative_indexing() {
	result := execute('
		arr = [10, 20, 30]
		arr[-1]
	', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(30))
}

fn test_nested_object_access() {
	mut obj := map[string]VrlValue{}
	mut inner := new_object_map()
	inner.set('name', VrlValue('test'))
	obj['info'] = VrlValue(inner)

	result := execute('.info.name', obj) or { panic(err) }
	assert result == VrlValue('test')
}

fn test_nested_object_assignment() {
	result := execute('
		.a.b = "deep"
		.a.b
	', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('deep')
}

fn test_string_comparison() {
	result := execute('"abc" == "abc"', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(true)

	result2 := execute('"abc" != "def"', map[string]VrlValue{}) or { panic(err) }
	assert result2 == VrlValue(true)
}

fn test_negation() {
	result := execute('-(5)', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(-5))
}

fn test_not_operator() {
	result := execute('!true', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(false)

	result2 := execute('!false', map[string]VrlValue{}) or { panic(err) }
	assert result2 == VrlValue(true)
}

fn test_null_value() {
	result := execute('null', map[string]VrlValue{}) or { panic(err) }
	assert result is VrlNull
}

fn test_is_truthy_values() {
	assert is_truthy(VrlValue(true)) == true
	assert is_truthy(VrlValue(false)) == false
	assert is_truthy(VrlValue(VrlNull{})) == false
	assert is_truthy(VrlValue('hello')) == true
	assert is_truthy(VrlValue('')) == false
	assert is_truthy(VrlValue(i64(1))) == true
	assert is_truthy(VrlValue(i64(0))) == false
}

fn test_values_equal() {
	assert values_equal(VrlValue(i64(1)), VrlValue(i64(1))) == true
	assert values_equal(VrlValue(i64(1)), VrlValue(i64(2))) == false
	assert values_equal(VrlValue('a'), VrlValue('a')) == true
	assert values_equal(VrlValue('a'), VrlValue('b')) == false
	assert values_equal(VrlValue(true), VrlValue(true)) == true
	assert values_equal(VrlValue(true), VrlValue(false)) == false
	assert values_equal(VrlValue(VrlNull{}), VrlValue(VrlNull{})) == true
	assert values_equal(VrlValue(i64(1)), VrlValue(f64(1.0))) == true
}

fn test_vrl_to_string_types() {
	assert vrl_to_string(VrlValue(i64(42))) == '42'
	assert vrl_to_string(VrlValue('hello')) == 'hello'
	assert vrl_to_string(VrlValue(true)) == 'true'
	assert vrl_to_string(VrlValue(false)) == 'false'
	assert vrl_to_string(VrlValue(VrlNull{})) == 'null'
}

fn test_vrl_to_json_basic() {
	assert vrl_to_json(VrlValue(i64(42))) == '42'
	assert vrl_to_json(VrlValue(true)) == 'true'
	assert vrl_to_json(VrlValue(false)) == 'false'
	assert vrl_to_json(VrlValue(VrlNull{})) == 'null'
}

fn test_arithmetic_operations() {
	r1 := execute('2 + 3', map[string]VrlValue{}) or { panic(err) }
	assert r1 == VrlValue(i64(5))

	r2 := execute('10 - 4', map[string]VrlValue{}) or { panic(err) }
	assert r2 == VrlValue(i64(6))

	r3 := execute('3 * 4', map[string]VrlValue{}) or { panic(err) }
	assert r3 == VrlValue(i64(12))

	r4 := execute('10 / 2', map[string]VrlValue{}) or { panic(err) }
	assert r4 == VrlValue(f64(5.0))

	r5 := execute('10 % 3', map[string]VrlValue{}) or { panic(err) }
	assert r5 == VrlValue(i64(1))
}

fn test_string_concatenation() {
	result := execute('"hello" + " " + "world"', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue('hello world')
}

fn test_variable_assignment_and_use() {
	result := execute('
		x = 10
		y = 20
		x + y
	', map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(30))
}

fn test_object_construction() {
	result := execute('{"key": "value", "num": 42}', map[string]VrlValue{}) or { panic(err) }
	r := result
	match r {
		ObjectMap {
			val := r.get('key') or { panic('missing key') }
			assert val == VrlValue('value')
			num := r.get('num') or { panic('missing num') }
			assert num == VrlValue(i64(42))
		}
		else {
			assert false, 'expected ObjectMap'
		}
	}
}

fn test_array_construction() {
	result := execute('[1, 2, 3]', map[string]VrlValue{}) or { panic(err) }
	r := result
	match r {
		[]VrlValue {
			assert r.len == 3
			assert r[0] == VrlValue(i64(1))
			assert r[2] == VrlValue(i64(3))
		}
		else {
			assert false, 'expected array'
		}
	}
}

fn test_objectmap_large_via_vrl() {
	// Build a VRL program that creates >32 fields
	mut lines := []string{}
	for i in 0 .. 35 {
		lines << '.field_${i} = ${i}'
	}
	lines << '.field_0'
	source := lines.join('\n')
	result := execute(source, map[string]VrlValue{}) or { panic(err) }
	assert result == VrlValue(i64(0))
}

fn test_format_float_integer() {
	assert format_float(42.0) == '42.0'
}

fn test_format_float_decimal() {
	s := format_float(3.14)
	assert s.contains('3.14')
}

fn test_lexer_multiline() {
	source := '.a = 1\n.b = 2\n.c = 3'
	mut lex := new_lexer(source)
	tokens := lex.tokenize()
	mut dot_ident_count := 0
	for t in tokens {
		if t.kind == .dot_ident {
			dot_ident_count++
		}
	}
	assert dot_ident_count == 3
}

fn test_lexer_all_operators() {
	mut lex := new_lexer('+ - * / < > = !')
	tokens := lex.tokenize()
	assert tokens[0].kind == .plus
	assert tokens[1].kind == .minus
	assert tokens[2].kind == .star
	assert tokens[3].kind == .slash
	assert tokens[4].kind == .lt
	assert tokens[5].kind == .gt
}

fn test_runtime_get_object() {
	mut obj := map[string]VrlValue{}
	obj['message'] = VrlValue('hello')
	mut rt := new_runtime_with_object(obj)
	result := rt.get_object()
	assert result['message'] == VrlValue('hello')
}

fn test_runtime_new_empty() {
	rt := new_runtime()
	obj := rt.get_object()
	assert obj.len == 0
}
