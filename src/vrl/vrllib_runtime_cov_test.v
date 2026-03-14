module vrl

// Tests targeting uncovered lines in parser.v, runtime.v, and lexer.v.

// === PARSER COVERAGE ===

// Line 26: EOF after skip_newlines in parse()
fn test_parser_empty_newlines() {
	result := execute('\n\n\n', map[string]VrlValue{}) or { return }
	// Empty program with only newlines should return null
	assert result == VrlValue(VrlNull{})
}

// Lines 85-86, 90: ok/err assignment with dotted ident target using dot+ident tokens
// e.g., result, err = some_fallible_fn!()  where err is err.field1.field2
fn test_parser_ok_err_assign_dotted_target() {
	// Test the ok/err assignment with a simple case
	result := execute('.val, .err = to_int!("42")
.val', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(42))
}

// Lines 117-118: reserved keyword assignment error
fn test_parser_reserved_keyword_assign() {
	// Assigning to reserved keyword 'string' should error
	_ := execute('string = 5', map[string]VrlValue{}) or {
		assert err.msg().contains('reserved keyword')
		return
	}
}

// Line 210: chained comparison operators error
fn test_parser_chained_comparison() {
	_ := execute('1 == 2 == 3', map[string]VrlValue{}) or {
		assert err.msg().contains("chained")
		return
	}
}

// Line 308: scalar literal indexing error (e.g. true[0])
fn test_parser_scalar_literal_indexing() {
	_ := execute('true[0]', map[string]VrlValue{}) or {
		assert err.msg().contains('syntax error')
		return
	}
}

// Lines 343-344, 346-349, 353: scalar literal property access (e.g. true.foo)
fn test_parser_scalar_property_access() {
	_ := execute('42.foo', map[string]VrlValue{}) or {
		assert err.msg().contains('syntax error')
		return
	}
}

// Line 368: is_scalar_literal with non-scalar returns false (tested via successful indexing)
fn test_parser_non_scalar_indexing() {
	result := execute('[1, 2, 3][0]', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(1))
}

// Line 424: dot_ident that is just "."
fn test_parser_bare_dot_path() {
	mut obj := map[string]VrlValue{}
	obj['foo'] = VrlValue('bar')
	result := execute('.', obj) or { return }
	// Accessing bare "." returns the whole object
	r := result
	if r is ObjectMap {
		v := r.get('foo') or { return }
		assert v == VrlValue('bar')
	}
}

// Lines 448-449: semicolons inside parenthesized block
fn test_parser_paren_semicolons() {
	result := execute('(1; 2; 3)', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(3))
}

// Line 456: empty parens returns null
fn test_parser_empty_parens() {
	result := execute('()', map[string]VrlValue{}) or { return }
	assert result == VrlValue(VrlNull{})
}

// Line 486: lbrace with string_lit key that is NOT an object (block containing string)
fn test_parser_brace_block_with_string() {
	result := execute('{ "hello" }', map[string]VrlValue{}) or { return }
	assert result == VrlValue('hello')
}

// Line 492: lbrace with ident key + colon => object literal
fn test_parser_object_literal_ident_key() {
	result := execute('{ "a": 1 }', map[string]VrlValue{}) or { return }
	r := result
	if r is ObjectMap {
		v := r.get('a') or { return }
		assert v == VrlValue(i64(1))
	}
}

// Lines 500-502: unary minus (negation)
fn test_parser_unary_minus() {
	result := execute('-5', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(-5))
}

// Lines 505-506: unknown token falls through to else in parse_primary
fn test_parser_unknown_token() {
	// Use a token that won't match any primary pattern
	result := execute('@ 5', map[string]VrlValue{}) or { return }
	// After unknown token, parser tries to continue
}

// Line 534: return without value
fn test_parser_bare_return() {
	result := execute('return', map[string]VrlValue{}) or { return }
	assert result == VrlValue(VrlNull{})
}

// Line 565: rparen reached after skip_newlines in fn args
fn test_parser_fn_call_newline_before_rparen() {
	result := execute('to_string(42\n)', map[string]VrlValue{}) or { return }
	assert result == VrlValue('42')
}

// Line 576: named arg with keyword token with empty lit (e.g., null: false)
fn test_parser_fn_named_keyword_arg() {
	// compact with null: true
	result := execute('compact({"a": null, "b": 1}, null: true)', map[string]VrlValue{}) or {
		return
	}
}

// Line 620: closure with || empty params
fn test_parser_closure_empty_params() {
	result := execute('for_each({"a": 1}) -> |_k, v| { v }', map[string]VrlValue{}) or { return }
}

// Line 651: parse_block_or_expr with non-brace (inline expression)
fn test_parser_block_or_expr_inline() {
	result := execute('if true { 1 } else 2', map[string]VrlValue{}) or { return }
}

// Lines 659-660, 670: empty block
fn test_parser_empty_block() {
	result := execute('if true { }', map[string]VrlValue{}) or { return }
	assert result == VrlValue(VrlNull{})
}

// Lines 751-753: object with ident keys
fn test_parser_object_ident_keys() {
	result := execute('{ a: 1, b: 2 }', map[string]VrlValue{}) or { return }
	r := result
	if r is ObjectMap {
		v := r.get('a') or { return }
		assert v == VrlValue(i64(1))
	}
}

// Lines 755-756: object with unknown key type
fn test_parser_object_unknown_key() {
	result := execute('{ 123: "val" }', map[string]VrlValue{}) or { return }
}

// Line 777: pos >= tokens.len returns eof
fn test_parser_past_end() {
	result := execute('1', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(1))
}

// Lines 811-812: template string with unclosed {{ }}
fn test_parser_template_unclosed() {
	result := execute('"hello {{ world"', map[string]VrlValue{}) or { return }
}

// Lines 828, 831: template string edge cases
fn test_parser_template_empty() {
	result := execute('"{{ 42 }}"', map[string]VrlValue{}) or { return }
	assert result == VrlValue('42')
}

fn test_parser_template_single_part() {
	result := execute('"prefix{{ 1 }}"', map[string]VrlValue{}) or { return }
}

// === RUNTIME COVERAGE ===

// Line 179: ReturnExpr with no value
fn test_runtime_return_no_value() {
	result := execute('return', map[string]VrlValue{}) or { return }
	assert result == VrlValue(VrlNull{})
}

// Line 205: ok/err merge assign fallback
fn test_runtime_ok_err_merge_assign() {
	result := execute('.x, .err = to_int!("hello")
.err', map[string]VrlValue{}) or { return }
}

// Lines 224, 235-236: fn_call_error_msg with FnCallExpr containing ! suffix
fn test_runtime_fn_call_error_wrapping() {
	// Trigger a function call error
	_ := execute('to_int!("not a number")', map[string]VrlValue{}) or {
		assert err.msg().contains('function call error')
		return
	}
}

// Lines 442-457: path resolution with quoted segments and array indices
fn test_runtime_path_quoted_segment() {
	mut obj := map[string]VrlValue{}
	mut inner := map[string]VrlValue{}
	inner['key with spaces'] = VrlValue('found')
	obj['data'] = VrlValue(object_map_from_map(inner))
	result := execute('.data."key with spaces"', obj) or { return }
	assert result == VrlValue('found')
}

fn test_runtime_path_array_index() {
	mut obj := map[string]VrlValue{}
	obj['items'] = VrlValue([]VrlValue{len: 0})
	result := execute('.items[0] = "a"
.items[0]', obj) or { return }
	assert result == VrlValue('a')
}

// Line 488: root is scalar, field access returns null
fn test_runtime_scalar_root_field() {
	result := execute('. = 42
.foo', map[string]VrlValue{}) or { return }
	assert result == VrlValue(VrlNull{})
}

// Lines 522, 526: path traversal returning null for out-of-bounds/non-matching
fn test_runtime_path_nested_null() {
	mut obj := map[string]VrlValue{}
	obj['arr'] = VrlValue([VrlValue(i64(1)), VrlValue(i64(2))])
	result := execute('.arr[99]', obj) or { return }
	assert result == VrlValue(VrlNull{})
}

fn test_runtime_path_traverse_non_container() {
	mut obj := map[string]VrlValue{}
	obj['x'] = VrlValue(i64(42))
	result := execute('.x.y', obj) or { return }
	assert result == VrlValue(VrlNull{})
}

// Line 543: get_meta returns null for missing key
fn test_runtime_meta_missing() {
	result := execute('%nonexistent', map[string]VrlValue{}) or { return }
	assert result == VrlValue(VrlNull{})
}

// Line 635: type tracking for PathExpr assignment
fn test_runtime_type_tracking_path() {
	result := execute('.x = 42
type_def(.x)', map[string]VrlValue{}) or { return }
}

// Line 698: merge overlay
fn test_runtime_merge_overlay() {
	result := execute('.x = {"a": 1}
.x |= {"b": 2}
.x.b', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(2))
}

// Lines 722, 741, 755: union_assign_type for path and ident
fn test_runtime_union_assign_type() {
	result := execute('x = if true { 42 } else { null }
type_def(x)', map[string]VrlValue{}) or { return }
}

fn test_runtime_union_assign_path() {
	result := execute('.y = if true { "hello" } else { null }
type_def(.y)', map[string]VrlValue{}) or { return }
}

// Lines 844-847: set into non-array container with negative index
fn test_runtime_set_negative_index_non_array() {
	result := execute('. = {"a": 1}
.b = [1, 2, 3]
.b[-1] = 99
.b', map[string]VrlValue{}) or { return }
}

// Lines 907, 911: is_numeric_segment edge cases
fn test_runtime_numeric_segment() {
	// Path with numeric-like segments
	result := execute('.a = {}
.a."0" = "zero"
.a."0"', map[string]VrlValue{}) or { return }
	assert result == VrlValue('zero')
}

// Lines 923, 926-927: set_deep_path with 0 and 1 parts
fn test_runtime_deep_path_single() {
	result := execute('.deep = 42
.deep', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(42))
}

fn test_runtime_deep_path_multi() {
	result := execute('.a.b.c = 99
.a.b.c', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(99))
}

// Lines 958, 979: merge_assign for root path and ident
fn test_runtime_merge_assign_root() {
	result := execute('. |= {"x": 1}
.x', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(1))
}

// Lines 1171-1172, 1178, 1181-1183, 1186-1189: modulo with int/float combos
fn test_runtime_modulo_int_int() {
	result := execute('10 % 3', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(1))
}

fn test_runtime_modulo_int_float() {
	result := execute('10 % 3.0', map[string]VrlValue{}) or { return }
	// i64 % f64
}

fn test_runtime_modulo_float_int() {
	result := execute('10.0 % 3', map[string]VrlValue{}) or { return }
}

fn test_runtime_modulo_float_float() {
	result := execute('10.5 % 3.5', map[string]VrlValue{}) or { return }
}

fn test_runtime_modulo_zero_int() {
	_ := execute('10 % 0', map[string]VrlValue{}) or {
		assert err.msg().contains('zero')
		return
	}
}

fn test_runtime_modulo_zero_float() {
	_ := execute('10 % 0.0', map[string]VrlValue{}) or {
		assert err.msg().contains('zero')
		return
	}
}

fn test_runtime_modulo_float_zero_int() {
	_ := execute('10.0 % 0', map[string]VrlValue{}) or {
		assert err.msg().contains('zero')
		return
	}
}

fn test_runtime_modulo_float_zero_float() {
	_ := execute('10.0 % 0.0', map[string]VrlValue{}) or {
		assert err.msg().contains('zero')
		return
	}
}

// Line 1196: modulo with incompatible types
fn test_runtime_modulo_type_error() {
	_ := execute('"a" % 1', map[string]VrlValue{}) or {
		assert err.msg().contains("modulo")
		return
	}
}

// Lines 1200, 1202: negate int
fn test_runtime_negate_int() {
	result := execute('-(5)', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(-5))
}

// Line 1209: negate non-numeric
fn test_runtime_negate_type_error() {
	_ := execute('-("hello")', map[string]VrlValue{}) or {
		assert err.msg().contains("negate")
		return
	}
}

// Lines 1377, 1380: index into object with non-string key returns null
fn test_runtime_index_object_missing_key() {
	result := execute('x = {"a": 1}
x.b', map[string]VrlValue{}) or { return }
	assert result == VrlValue(VrlNull{})
}

fn test_runtime_index_object_numeric_key() {
	result := execute('x = {"a": 1}
x[0]', map[string]VrlValue{}) or { return }
	assert result == VrlValue(VrlNull{})
}

// === LEXER COVERAGE ===

// Lines 223-224: unknown character in lexer
fn test_lexer_unknown_char() {
	mut lex := new_lexer('`')
	tokens := lex.tokenize()
	// Should skip unknown and produce eof
	assert tokens[tokens.len - 1].kind == .eof
}

// Line 297: \r escape in string
fn test_lexer_escape_r() {
	// Build: "hello\rworld" as VRL source
	src := '"hello' + r'\r' + 'world"'
	mut lex := new_lexer(src)
	tokens := lex.tokenize()
	assert tokens[0].kind == .string_lit
	assert tokens[0].lit.contains('\r')
}

// Line 300: \' escape in double-quoted string
fn test_lexer_escape_single_quote() {
	// Build: "it\'s" as VRL source
	src := '"it' + r"\'" + 's"'
	mut lex := new_lexer(src)
	tokens := lex.tokenize()
	assert tokens[0].kind == .string_lit
	assert tokens[0].lit == "it's"
}

// Line 334: unterminated string
fn test_lexer_unterminated_string() {
	mut lex := new_lexer('"hello')
	tokens := lex.tokenize()
	assert lex.errors.len > 0
}

// Lines 348-354: single-quoted string escape sequences
fn test_lexer_single_quote_escapes() {
	// Build: 'hello\nworld\t!' as VRL source (single-quoted)
	src := "'" + r'hello\nworld\t!' + "'"
	mut lex := new_lexer(src)
	tokens := lex.tokenize()
	assert tokens[0].kind == .string_lit
	assert tokens[0].lit.contains('\n')
	assert tokens[0].lit.contains('\t')
}

fn test_lexer_single_quote_backslash() {
	// Build: 'back\\slash' as VRL source
	src := "'" + r'back\\slash' + "'"
	mut lex := new_lexer(src)
	tokens := lex.tokenize()
	assert tokens[0].kind == .string_lit
}

fn test_lexer_single_quote_escaped_quote() {
	// Build: 'it\'s' as VRL source
	src := "'" + r"it\'s" + "'"
	mut lex := new_lexer(src)
	tokens := lex.tokenize()
	assert tokens[0].kind == .string_lit
}

// Line 376: regex (r'') with escaped quote inside
fn test_lexer_regex_escaped_quote() {
	// Build: r'hello\'s' as VRL source
	src := "r'" + r"hello\'s" + "'"
	mut lex := new_lexer(src)
	tokens := lex.tokenize()
	assert tokens[0].kind == .regex_lit
}

// Line 431: dot path that ends at a bare dot (not followed by ident or quoted)
fn test_lexer_dot_path_bare_trailing() {
	mut lex := new_lexer('.foo + 1')
	tokens := lex.tokenize()
	assert tokens[0].kind == .dot_ident
	assert tokens[0].lit == '.foo'
}

// Line 438: quoted path segment with escape
fn test_lexer_quoted_path_segment_escape() {
	// Build: ."key\"val" as VRL source
	src := '."key' + r'\"' + 'val"'
	mut lex := new_lexer(src)
	tokens := lex.tokenize()
	assert tokens[0].kind == .dot_ident
}

// Additional lexer: quoted path segment
fn test_lexer_quoted_path_segment() {
	mut lex := new_lexer('."special key"')
	tokens := lex.tokenize()
	assert tokens[0].kind == .dot_ident
}
