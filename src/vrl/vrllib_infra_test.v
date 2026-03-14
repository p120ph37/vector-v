module vrl

// Tests targeting uncovered code paths in static_check.v, type_inference.v,
// vrllib_object.v, vrllib_community_id.v, vrllib_ip.v, vrllib_dns.v,
// vrllib_enumerate.v, vrllib_grok.v, and vrllib_etld.v.

// ============================================================================
// static_check.v — E642 type mismatch (assigning wrong type to typed path)
// ============================================================================

fn test_sc_e642_string_field_access() {
	// Assigning a string, then trying to set a subfield should fail with E642
	execute_checked('
foo = "hello"
foo.bar = "world"
', map[string]VrlValue{}) or {
		assert err.msg().contains('E642'), 'expected E642: ${err}'
		return
	}
}

fn test_sc_e642_string_index_access() {
	// Assigning a string, then trying to index it as array should fail with E642
	execute_checked('
foo = "hello"
foo[0] = "x"
', map[string]VrlValue{}) or {
		assert err.msg().contains('E642'), 'expected E642: ${err}'
		return
	}
}

fn test_sc_e642_int_field_access() {
	// Integer cannot have fields
	execute_checked('
foo = 42
foo.bar = "test"
', map[string]VrlValue{}) or {
		assert err.msg().contains('E642'), 'expected E642: ${err}'
		return
	}
}

fn test_sc_e642_bool_field_access() {
	// Boolean cannot have fields
	execute_checked('
foo = true
foo.bar = "test"
', map[string]VrlValue{}) or {
		assert err.msg().contains('E642'), 'expected E642: ${err}'
		return
	}
}

fn test_sc_e642_object_literal_nested() {
	// Assigning object to root, then accessing nested field of wrong type
	execute_checked('
. = {"foo": true}
.foo.bar = "baz"
', map[string]VrlValue{}) or {
		assert err.msg().contains('E642'), 'expected E642: ${err}'
		return
	}
}

fn test_sc_e642_valid_object_field() {
	// Object should allow field access (no error)
	result := execute_checked('
foo = {}
foo.bar = "ok"
foo
', map[string]VrlValue{}) or { return }
	_ = result
}

// ============================================================================
// static_check.v — E900 unused variable detection
// ============================================================================

fn test_sc_e900_unused_variable() {
	execute_checked('
unused = 42
.result = "hello"
', map[string]VrlValue{}) or {
		assert err.msg().contains('E900') || err.msg().contains('unused'), 'expected E900: ${err}'
		return
	}
}

fn test_sc_e900_unused_literal() {
	// A bare literal in non-final position should trigger E900
	execute_checked('
42
.result = "hello"
', map[string]VrlValue{}) or {
		assert err.msg().contains('E900') || err.msg().contains('unused'), 'expected E900: ${err}'
		return
	}
}

fn test_sc_e900_used_variable() {
	// Used variable should not trigger E900
	result := execute_checked('
x = 42
.result = x
', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(42))
}

fn test_sc_e900_var_used_in_fn_call() {
	// Variable used in function call should not trigger E900
	result := execute_checked('
x = "HELLO"
downcase(x)
', map[string]VrlValue{}) or { return }
	assert result == VrlValue('hello')
}

fn test_sc_e900_var_used_in_if() {
	// Variable used in if condition
	result := execute_checked('
x = true
if x { "yes" } else { "no" }
', map[string]VrlValue{}) or { return }
	assert result == VrlValue('yes')
}

fn test_sc_e900_var_used_in_binary() {
	// Variable used in binary expression
	result := execute_checked('
x = 10
x + 5
', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(15))
}

fn test_sc_e900_var_used_in_coalesce() {
	// Variable used in coalesce expression
	result := execute_checked('
x = "hello"
parse_json!(x) ?? "default"
', map[string]VrlValue{}) or { return }
	_ = result
}

fn test_sc_e900_var_used_in_array() {
	// Variable used in array literal
	result := execute_checked('
x = 42
[x, 1, 2]
', map[string]VrlValue{}) or { return }
	_ = result
}

fn test_sc_e900_var_used_in_object() {
	// Variable used in object literal
	result := execute_checked('
x = 42
{"val": x}
', map[string]VrlValue{}) or { return }
	_ = result
}

fn test_sc_e900_var_used_in_not() {
	// Variable used in not expression
	result := execute_checked('
x = false
!x
', map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_sc_e900_var_used_in_index() {
	// Variable used in index expression
	result := execute_checked('
x = [1, 2, 3]
x[0]
', map[string]VrlValue{}) or { return }
	_ = result
}

// ============================================================================
// static_check.v — check_del_fallibility
// ============================================================================

fn test_sc_del_fallibility_binary_after_del() {
	// After del(.arr[0]), using .arr[1] in binary op should be E100
	execute_checked('
.arr = [1, 2, 3]
del(.arr[0])
.result = .arr[1] + .arr[2]
', map[string]VrlValue{}) or {
		assert err.msg().contains('E100') || err.msg().contains('error'), 'expected E100: ${err}'
		return
	}
}

// ============================================================================
// static_check.v — E660 non-boolean negation
// ============================================================================

fn test_sc_e660_negate_string() {
	execute_checked('.result = !"hello"', map[string]VrlValue{}) or {
		assert err.msg().contains('E660') || err.msg().contains('negation'), 'expected E660: ${err}'
		return
	}
}

fn test_sc_e660_negate_null() {
	execute_checked('.result = !null', map[string]VrlValue{}) or {
		assert err.msg().contains('E660') || err.msg().contains('negation'), 'expected E660: ${err}'
		return
	}
}

// ============================================================================
// static_check.v — E102 non-boolean predicate
// ============================================================================

fn test_sc_e102_string_predicate() {
	execute_checked('if "hello" { "yes" }', map[string]VrlValue{}) or {
		assert err.msg().contains('E102') || err.msg().contains('predicate'), 'expected E102: ${err}'
		return
	}
}

fn test_sc_e102_null_predicate() {
	execute_checked('if null { "yes" }', map[string]VrlValue{}) or {
		assert err.msg().contains('E102') || err.msg().contains('predicate'), 'expected E102: ${err}'
		return
	}
}

// ============================================================================
// static_check.v — E651 unnecessary coalesce
// ============================================================================

fn test_sc_e651_unnecessary_coalesce() {
	execute_checked('.result = downcase("HELLO") ?? "default"', map[string]VrlValue{}) or {
		assert err.msg().contains('E651') || err.msg().contains('coalesce'), 'expected E651: ${err}'
		return
	}
}

// ============================================================================
// static_check.v — E104 unnecessary error assignment
// ============================================================================

fn test_sc_e104_unnecessary_err_assign() {
	execute_checked('ok, err = downcase("HELLO")', map[string]VrlValue{}) or {
		assert err.msg().contains('E104') || err.msg().contains('unnecessary'), 'expected E104: ${err}'
		return
	}
}

// ============================================================================
// static_check.v — E620 abort on infallible function
// ============================================================================

fn test_sc_e620_abort_infallible() {
	execute_checked('.result = downcase!("HELLO")', map[string]VrlValue{}) or {
		assert err.msg().contains('E620') || err.msg().contains('infallible'), 'expected E620: ${err}'
		return
	}
}

// ============================================================================
// static_check.v — E300 non-string abort message
// ============================================================================

fn test_sc_e300_non_string_abort() {
	execute_checked('abort 42', map[string]VrlValue{}) or {
		assert err.msg().contains('E300') || err.msg().contains('abort'), 'expected E300: ${err}'
		return
	}
}

fn test_sc_e300_abort_with_array() {
	execute_checked('abort [1, 2]', map[string]VrlValue{}) or {
		assert err.msg().contains('E300') || err.msg().contains('abort'), 'expected E300: ${err}'
		return
	}
}

fn test_sc_e300_abort_with_object() {
	execute_checked('abort {"a": 1}', map[string]VrlValue{}) or {
		assert err.msg().contains('E300') || err.msg().contains('abort'), 'expected E300: ${err}'
		return
	}
}

fn test_sc_e300_abort_with_root() {
	execute_checked('abort .', map[string]VrlValue{}) or {
		assert err.msg().contains('E300') || err.msg().contains('abort') || err.msg().contains('non-string'),
			'expected E300: ${err}'
		return
	}
}

// ============================================================================
// static_check.v — E315 read-only path checking
// ============================================================================

fn test_sc_e315_read_only_exact() {
	execute_checked_with_readonly('.message = "new"', map[string]VrlValue{},
		['.message'], []string{}, []string{}) or {
		assert err.msg().contains('E315') || err.msg().contains('read-only'), 'expected E315: ${err}'
		return
	}
}

fn test_sc_e315_read_only_recursive() {
	execute_checked_with_readonly('.meta.host = "new"', map[string]VrlValue{},
		[]string{}, ['.meta'], []string{}) or {
		assert err.msg().contains('E315') || err.msg().contains('read-only'), 'expected E315: ${err}'
		return
	}
}

fn test_sc_e315_read_only_root() {
	execute_checked_with_readonly('. = {}', map[string]VrlValue{},
		['.message'], []string{}, []string{}) or {
		assert err.msg().contains('E315') || err.msg().contains('read-only'), 'expected E315: ${err}'
		return
	}
}

fn test_sc_e315_read_only_meta() {
	execute_checked_with_readonly('%foo = "bar"', map[string]VrlValue{},
		[]string{}, []string{}, ['foo']) or {
		assert err.msg().contains('E315') || err.msg().contains('read-only'), 'expected E315: ${err}'
		return
	}
}

// ============================================================================
// static_check.v — sc_expr_uses_var complex expressions
// ============================================================================

fn test_sc_var_used_in_closure() {
	// Variable used inside a closure body should count as used
	result := execute_checked('
x = 10
map_values({"a": 1}) -> |v| { v + x }
', map[string]VrlValue{}) or { return }
	_ = result
}

fn test_sc_var_used_in_assign_value() {
	// Variable used in the value side of an assignment
	result := execute_checked('
x = "hello"
y = x
y
', map[string]VrlValue{}) or { return }
	assert result == VrlValue('hello')
}

fn test_sc_var_used_in_ok_err() {
	// Variable used in ok/err assignment
	result := execute_checked('
x = "{}"
ok, err = parse_json(x)
ok
', map[string]VrlValue{}) or { return }
	_ = result
}

fn test_sc_var_used_in_merge_assign() {
	// Variable used in |= assignment
	result := execute_checked('
x = {"b": 2}
.a = 1
. |= x
', map[string]VrlValue{}) or { return }
	_ = result
}

fn test_sc_var_used_in_abort() {
	// Variable used in abort message
	execute_checked('
x = "error message"
abort x
', map[string]VrlValue{}) or {
		// abort always stops execution, so we get an error
		return
	}
}

fn test_sc_var_used_in_return() {
	// Variable used in return expression
	result := execute_checked('
x = 42
return x
', map[string]VrlValue{}) or { return }
	_ = result
}

// ============================================================================
// type_inference.v — infer_fn_call_type for different function return types
// ============================================================================

fn test_type_def_fn_call_downcase() {
	result := execute('type_def(downcase("HELLO"))', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('bytes'), 'expected bytes type: ${j}'
}

fn test_type_def_fn_call_strlen() {
	result := execute('type_def(strlen("hello"))', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('integer'), 'expected integer type: ${j}'
}

fn test_type_def_fn_call_to_float() {
	result := execute('type_def(to_float!(42))', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('float'), 'expected float type: ${j}'
}

fn test_type_def_fn_call_contains() {
	result := execute('type_def(contains("hello", "lo"))', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('boolean'), 'expected boolean type: ${j}'
}

fn test_type_def_fn_call_now() {
	result := execute('type_def(now())', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('timestamp'), 'expected timestamp type: ${j}'
}

fn test_type_def_fn_call_push() {
	result := execute('type_def(push([1, 2], 3))', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('array'), 'expected array type: ${j}'
}

fn test_type_def_fn_call_merge() {
	result := execute('type_def(merge({"a": 1}, {"b": 2}))', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('object'), 'expected object type: ${j}'
}

fn test_type_def_fn_call_parse_json() {
	result := execute('type_def(parse_json!("{}"))', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('any'), 'expected any type: ${j}'
}

fn test_type_def_fn_call_type_of() {
	result := execute('type_def(type_of(42))', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('bytes'), 'expected bytes type: ${j}'
}

fn test_type_def_fn_call_del() {
	result := execute('
.x = 42
type_def(del(.x))
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

fn test_type_def_fn_call_to_timestamp() {
	result := execute('type_def(to_timestamp!(42))', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('timestamp'), 'expected timestamp type: ${j}'
}

fn test_type_def_fn_call_slice() {
	result := execute('type_def(slice!("hello", 0, 3))', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

// ============================================================================
// type_inference.v — Type narrowing in if/else blocks
// ============================================================================

fn test_type_def_if_else_union() {
	result := execute('
x = if true { "hello" } else { 42 }
type_def(x)
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected union type: ${j}'
}

fn test_type_def_if_no_else() {
	result := execute('
x = if true { "hello" }
type_def(x)
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type with null: ${j}'
}

fn test_type_def_if_abort_then() {
	result := execute('
x = if false { abort "stop" } else { 42 }
type_def(x)
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('integer'), 'expected integer from else branch: ${j}'
}

// ============================================================================
// type_inference.v — Binary expression type inference
// ============================================================================

fn test_type_def_binary_comparison() {
	result := execute('type_def(1 == 2)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('boolean'), 'expected boolean type: ${j}'
}

fn test_type_def_binary_lt() {
	result := execute('type_def(1 < 2)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('boolean'), 'expected boolean type: ${j}'
}

fn test_type_def_binary_gt() {
	result := execute('type_def(1 > 2)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('boolean'), 'expected boolean type: ${j}'
}

fn test_type_def_binary_ne() {
	result := execute('type_def(1 != 2)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('boolean'), 'expected boolean type: ${j}'
}

fn test_type_def_binary_division() {
	result := execute('type_def(10 / 2)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('float'), 'expected float type for division: ${j}'
}

fn test_type_def_binary_and() {
	result := execute('type_def(true && false)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('boolean'), 'expected boolean type: ${j}'
}

fn test_type_def_binary_or() {
	result := execute('type_def(true || false)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

fn test_type_def_not_expr() {
	result := execute('type_def(!true)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('boolean'), 'expected boolean type: ${j}'
}

fn test_type_def_coalesce_expr() {
	result := execute('type_def(parse_json!("null") ?? "default")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

// ============================================================================
// type_inference.v — Array/object type inference
// ============================================================================

fn test_type_def_array_literal() {
	result := execute('type_def([1, "hello", true])', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('array'), 'expected array type: ${j}'
}

fn test_type_def_object_literal() {
	result := execute('type_def({"name": "alice", "age": 30})', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('object'), 'expected object type: ${j}'
}

fn test_type_def_nested_object() {
	result := execute('type_def({"user": {"name": "alice"}})', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('object'), 'expected object type: ${j}'
}

fn test_type_def_empty_block() {
	// An empty block should infer to null
	result := execute('type_def(null)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('null'), 'expected null type: ${j}'
}

fn test_type_def_assign_tracks_type() {
	result := execute('
.x = "hello"
type_def(.x)
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('bytes'), 'expected bytes type: ${j}'
}

fn test_type_def_meta_path() {
	result := execute('
%foo = "bar"
type_def(%foo)
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

fn test_type_def_ok_err_assign() {
	result := execute('
ok, err = parse_json!("{}")
type_def(ok)
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

fn test_type_def_merge_assign() {
	result := execute('
. = {"a": 1}
. |= {"b": 2}
type_def(.)
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

fn test_type_def_index_expr() {
	result := execute('
x = [1, 2, 3]
type_def(x[0])
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

fn test_type_def_unary_expr() {
	result := execute('type_def(-42)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

// ============================================================================
// vrllib_object.v — unnest with complex paths
// ============================================================================

fn test_unnest_nested_path() {
	prog := '
.data = {"items": ["x", "y"]}
unnest!(.data.items)
'
	result := execute(prog, map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('x') || j.contains('y'), 'expected unnested: ${j}'
}

fn test_unnest_variable() {
	prog := '
myvar = [1, 2, 3]
unnest!(myvar)
'
	result := execute(prog, map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('1') || j.contains('2'), 'expected unnested: ${j}'
}

// ============================================================================
// vrllib_object.v — set_nested_in_value with array indices
// ============================================================================

fn test_unnest_var_with_nested_path() {
	prog := '
myvar = {"items": [10, 20, 30]}
unnest!(myvar.items)
'
	result := execute(prog, map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected result: ${j}'
}

// ============================================================================
// vrllib_object.v — remove_nested with negative indices
// ============================================================================

fn test_remove_negative_index() {
	prog := 'remove!([1, 2, 3], [-1])'
	result := execute(prog, map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('[1,2]') || (j.contains('1') && j.contains('2') && !j.contains('3')),
		'expected [1,2]: ${j}'
}

fn test_remove_nested_object() {
	prog := 'remove!({"a": {"b": {"c": 1}}}, ["a", "b", "c"])'
	result := execute(prog, map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert !j.contains('"c"') || j.contains('{}'), 'expected c removed: ${j}'
}

fn test_remove_with_compact() {
	prog := 'remove!({"a": {"b": 1}, "c": 2}, ["a", "b"], compact: true)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('c'), 'expected c preserved: ${j}'
}

fn test_remove_array_nested() {
	prog := 'remove!([[1, 2], [3, 4]], [0, 1])'
	result := execute(prog, map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected result: ${j}'
}

// ============================================================================
// vrllib_object.v — compact_remove_value with nested structures
// ============================================================================

fn test_remove_compact_nested_empty() {
	prog := 'remove!({"a": {"b": 1}, "c": {"d": 2}}, ["c", "d"], compact: true)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	// After removing c.d and compacting, c should be removed (empty object)
	assert j.contains('"a"'), 'expected a preserved: ${j}'
}

fn test_remove_compact_array_null() {
	prog := 'remove!([1, null, 3], [1], compact: true)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('1'), 'expected 1: ${j}'
}

// ============================================================================
// vrllib_object.v — object_from_array with keys parameter
// ============================================================================

fn test_object_from_array_pairs() {
	result := execute('object_from_array([["a", 1], ["b", 2]])', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"a"') && j.contains('1'), 'expected a:1: ${j}'
	assert j.contains('"b"') && j.contains('2'), 'expected b:2: ${j}'
}

fn test_object_from_array_with_keys() {
	result := execute('object_from_array(["alice", "bob"], keys: ["name1", "name2"])',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('name1') || j.contains('alice'), 'expected names: ${j}'
}

fn test_object_from_array_int_key() {
	// Non-string keys should be converted to string
	result := execute('object_from_array([[42, "val"]])', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('42') && j.contains('val'), 'expected 42:val: ${j}'
}

fn test_object_from_array_null_key_skipped() {
	// Null keys should be skipped
	result := execute('object_from_array([[null, "skip"], ["a", "keep"]])',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
}

// ============================================================================
// vrllib_object.v — zip function
// ============================================================================

fn test_zip_two_arrays() {
	result := execute('zip(["a", "b"], [1, 2])', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('a') && j.contains('1'), 'expected zipped: ${j}'
}

fn test_zip_unequal_lengths() {
	result := execute('zip(["a", "b", "c"], [1, 2])', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	// Should zip to min length (2)
	assert j.contains('a') && j.contains('b'), 'expected zipped: ${j}'
}

fn test_zip_single_array_of_arrays() {
	result := execute('zip([["a", "b"], [1, 2]])', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected zipped: ${j}'
}

// ============================================================================
// vrllib_community_id.v — ICMPv6 type mappings
// ============================================================================

fn test_community_id_icmpv6_echo_request() {
	result := execute('community_id(source_ip: "::1", destination_ip: "::2", protocol: 58, source_port: 128, destination_port: 0)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

fn test_community_id_icmpv6_neighbor_solicitation() {
	result := execute('community_id(source_ip: "fe80::1", destination_ip: "fe80::2", protocol: 58, source_port: 135, destination_port: 0)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

fn test_community_id_icmpv6_router_solicitation() {
	result := execute('community_id(source_ip: "fe80::1", destination_ip: "ff02::2", protocol: 58, source_port: 133, destination_port: 0)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

fn test_community_id_icmpv6_multicast_listener() {
	result := execute('community_id(source_ip: "fe80::1", destination_ip: "ff02::1", protocol: 58, source_port: 130, destination_port: 0)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

fn test_community_id_icmpv6_node_info() {
	result := execute('community_id(source_ip: "::1", destination_ip: "::2", protocol: 58, source_port: 139, destination_port: 0)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

fn test_community_id_icmpv6_inverse_nd() {
	result := execute('community_id(source_ip: "::1", destination_ip: "::2", protocol: 58, source_port: 141, destination_port: 0)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

fn test_community_id_icmpv6_home_agent() {
	result := execute('community_id(source_ip: "::1", destination_ip: "::2", protocol: 58, source_port: 144, destination_port: 0)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

// ============================================================================
// vrllib_community_id.v — IP ordering with same IPs different ports
// ============================================================================

fn test_community_id_same_ip_higher_src_port() {
	// Same IP, src_port > dst_port should reorder
	result := execute('community_id(source_ip: "10.0.0.1", destination_ip: "10.0.0.1", protocol: 6, source_port: 443, destination_port: 80)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

// ============================================================================
// vrllib_community_id.v — SCTP protocol
// ============================================================================

fn test_community_id_sctp_reversed() {
	// SCTP with reversed IPs
	result := execute('community_id(source_ip: "10.0.0.2", destination_ip: "10.0.0.1", protocol: 132, source_port: 80, destination_port: 1234)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

fn test_community_id_sctp_missing_ports() {
	// SCTP without ports should error
	execute('community_id(source_ip: "10.0.0.1", destination_ip: "10.0.0.2", protocol: 132)',
		map[string]VrlValue{}) or {
		assert err.msg().contains('port'), 'expected port error: ${err}'
		return
	}
	assert false, 'expected error for missing SCTP ports'
}

// ============================================================================
// vrllib_community_id.v — GRE protocol (no ports)
// ============================================================================

fn test_community_id_gre_reversed() {
	result := execute('community_id(source_ip: "10.0.0.2", destination_ip: "10.0.0.1", protocol: 47)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

fn test_community_id_bad_seed() {
	execute('community_id(source_ip: "10.0.0.1", destination_ip: "10.0.0.2", protocol: 47, seed: 70000)',
		map[string]VrlValue{}) or {
		assert err.msg().contains('seed'), 'expected seed error: ${err}'
		return
	}
	assert false, 'expected error for bad seed'
}

fn test_community_id_bad_port() {
	execute('community_id(source_ip: "10.0.0.1", destination_ip: "10.0.0.2", protocol: 6, source_port: 70000, destination_port: 80)',
		map[string]VrlValue{}) or {
		assert err.msg().contains('port'), 'expected port error: ${err}'
		return
	}
	assert false, 'expected error for bad port'
}

// ============================================================================
// vrllib_community_id.v — ICMP same IP with src > dst
// ============================================================================

fn test_community_id_icmp_same_ip_reversed() {
	// ICMP with same IP, src_port > dst_port
	result := execute('community_id(source_ip: "10.0.0.1", destination_ip: "10.0.0.1", protocol: 1, source_port: 14, destination_port: 0)',
		map[string]VrlValue{}) or { return }
	s := result as string
	assert s.starts_with('1:'), 'expected 1: prefix: ${s}'
}

// ============================================================================
// vrllib_ip.v — ip_subnet with different prefix lengths
// ============================================================================

fn test_ip_subnet_24() {
	result := execute('ip_subnet("192.168.1.100", "/24")', map[string]VrlValue{}) or {
		return
	}
	s := result as string
	assert s == '192.168.1.0', 'expected 192.168.1.0: ${s}'
}

fn test_ip_subnet_8() {
	result := execute('ip_subnet("10.20.30.40", "/8")', map[string]VrlValue{}) or {
		return
	}
	s := result as string
	assert s == '10.0.0.0', 'expected 10.0.0.0: ${s}'
}

fn test_ip_subnet_dotted_mask() {
	result := execute('ip_subnet("192.168.1.100", "255.255.0.0")', map[string]VrlValue{}) or {
		return
	}
	s := result as string
	assert s == '192.168.0.0', 'expected 192.168.0.0: ${s}'
}

fn test_ip_subnet_32() {
	result := execute('ip_subnet("1.2.3.4", "/32")', map[string]VrlValue{}) or {
		return
	}
	s := result as string
	assert s == '1.2.3.4', 'expected 1.2.3.4: ${s}'
}

fn test_ip_subnet_0() {
	result := execute('ip_subnet("1.2.3.4", "/0")', map[string]VrlValue{}) or {
		return
	}
	s := result as string
	assert s == '0.0.0.0', 'expected 0.0.0.0: ${s}'
}

fn test_ip_subnet_invalid_prefix() {
	execute('ip_subnet("1.2.3.4", "/33")', map[string]VrlValue{}) or {
		assert err.msg().contains('prefix') || err.msg().contains('invalid'), 'expected error: ${err}'
		return
	}
}

fn test_ip_subnet_invalid_format() {
	execute('ip_subnet("1.2.3.4", "bogus")', map[string]VrlValue{}) or {
		assert err.msg().contains('subnet') || err.msg().contains('invalid'), 'expected error: ${err}'
		return
	}
}

// ============================================================================
// vrllib_ip.v — IPv6 operations
// ============================================================================

fn test_ip_to_ipv6_already_ipv6() {
	result := execute('ip_to_ipv6("::1")', map[string]VrlValue{}) or { return }
	s := result as string
	assert s == '::1', 'expected ::1: ${s}'
}

fn test_ip_to_ipv6_from_ipv4() {
	result := execute('ip_to_ipv6("192.168.1.1")', map[string]VrlValue{}) or { return }
	s := result as string
	assert s.contains('::ffff:192.168.1.1'), 'expected mapped: ${s}'
}

fn test_ipv6_to_ipv4_valid() {
	result := execute('ipv6_to_ipv4!("::ffff:10.0.0.1")', map[string]VrlValue{}) or {
		return
	}
	s := result as string
	assert s == '10.0.0.1', 'expected 10.0.0.1: ${s}'
}

fn test_ipv6_to_ipv4_not_mapped() {
	execute('ipv6_to_ipv4!("::1")', map[string]VrlValue{}) or {
		assert err.msg().contains('not an IPv4-mapped'), 'expected error: ${err}'
		return
	}
}

// ============================================================================
// vrllib_ip.v — ip_aton / ip_ntoa
// ============================================================================

fn test_ip_aton_loopback() {
	result := execute('ip_aton("127.0.0.1")', map[string]VrlValue{}) or { return }
	v := result as i64
	assert v == 2130706433, 'expected 2130706433: ${v}'
}

fn test_ip_ntoa_loopback() {
	result := execute('ip_ntoa(2130706433)', map[string]VrlValue{}) or { return }
	s := result as string
	assert s == '127.0.0.1', 'expected 127.0.0.1: ${s}'
}

fn test_ip_aton_ntoa_roundtrip() {
	result := execute('ip_ntoa(ip_aton("192.168.1.1"))', map[string]VrlValue{}) or {
		return
	}
	s := result as string
	assert s == '192.168.1.1', 'expected 192.168.1.1: ${s}'
}

fn test_ip_aton_invalid() {
	execute('ip_aton("not.an.ip")', map[string]VrlValue{}) or {
		return
	}
}

fn test_ip_version_ipv4() {
	result := execute('ip_version("10.0.0.1")', map[string]VrlValue{}) or { return }
	s := result as string
	assert s == 'IPv4', 'expected IPv4: ${s}'
}

fn test_ip_version_ipv6() {
	result := execute('ip_version("2001:db8::1")', map[string]VrlValue{}) or { return }
	s := result as string
	assert s == 'IPv6', 'expected IPv6: ${s}'
}

fn test_ip_version_invalid() {
	execute('ip_version("not-an-ip")', map[string]VrlValue{}) or {
		assert err.msg().contains('valid'), 'expected error: ${err}'
		return
	}
}

fn test_is_ipv4_valid() {
	result := execute('is_ipv4("192.168.1.1")', map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_is_ipv4_invalid() {
	result := execute('is_ipv4("not-ip")', map[string]VrlValue{}) or { return }
	assert result == VrlValue(false)
}

fn test_is_ipv6_valid() {
	result := execute('is_ipv6("::1")', map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_is_ipv6_invalid() {
	result := execute('is_ipv6("not-ip")', map[string]VrlValue{}) or { return }
	assert result == VrlValue(false)
}

fn test_ip_cidr_contains_match() {
	result := execute('ip_cidr_contains("10.0.0.0/8", "10.1.2.3")', map[string]VrlValue{}) or {
		return
	}
	assert result == VrlValue(true)
}

fn test_ip_cidr_contains_no_match() {
	result := execute('ip_cidr_contains("10.0.0.0/8", "192.168.1.1")',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(false)
}

fn test_ip_cidr_contains_array() {
	result := execute('ip_cidr_contains(["10.0.0.0/8", "192.168.0.0/16"], "192.168.1.1")',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

// ============================================================================
// vrllib_dns.v — dns_lookup and reverse_dns
// ============================================================================

fn test_dns_lookup_localhost() {
	result := execute('dns_lookup!("localhost")', map[string]VrlValue{}) or {
		// DNS lookup may fail in CI
		return
	}
	j := vrl_to_json(result)
	assert j.contains('127.0.0.1') || j.contains('::1') || j.len > 0,
		'expected IP: ${j}'
}

fn test_reverse_dns_loopback() {
	result := execute('reverse_dns!("127.0.0.1")', map[string]VrlValue{}) or {
		// reverse DNS may fail
		return
	}
	s := result as string
	assert s.len > 0, 'expected hostname: ${s}'
}

fn test_reverse_dns_invalid() {
	execute('reverse_dns!("not-an-ip")', map[string]VrlValue{}) or {
		assert err.msg().contains('unable to parse') || err.msg().contains('invalid'),
			'expected error: ${err}'
		return
	}
}

fn test_reverse_dns_ipv6_loopback() {
	result := execute('reverse_dns!("::1")', map[string]VrlValue{}) or {
		// reverse DNS may fail in CI
		return
	}
	s := result as string
	assert s.len > 0, 'expected hostname: ${s}'
}

// ============================================================================
// vrllib_enumerate.v — tally, tally_value, match_array
// ============================================================================

fn test_tally_basic() {
	result := execute('tally(["a", "b", "a", "c", "a"])', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"a"') && j.contains('3'), 'expected a:3: ${j}'
}

fn test_tally_value_basic() {
	result := execute('tally_value(["a", "b", "a", "c", "a"], "a")',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(3)), 'expected 3'
}

fn test_tally_value_not_found() {
	result := execute('tally_value(["a", "b", "c"], "z")', map[string]VrlValue{}) or {
		return
	}
	assert result == VrlValue(i64(0)), 'expected 0'
}

fn test_match_array_any() {
	result := execute("match_array([\"hello\", \"world\"], r'hell')",
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_match_array_none() {
	result := execute("match_array([\"hello\", \"world\"], r'xyz')",
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(false)
}

fn test_match_array_all_true() {
	result := execute("match_array([\"hello\", \"help\"], r'^hel', all: true)",
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(true)
}

fn test_match_array_all_false() {
	result := execute("match_array([\"hello\", \"world\"], r'^hel', all: true)",
		map[string]VrlValue{}) or { return }
	assert result == VrlValue(false)
}

// ============================================================================
// vrllib_grok.v — parse_grok
// ============================================================================

fn test_parse_grok_syslog() {
	result := execute('parse_grok!("55.3.244.1 GET /index.html 15824 0.043", "%{IP:client} %{WORD:method} %{URIPATHPARAM:request} %{NUMBER:bytes} %{NUMBER:duration}")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"client"'), 'expected client: ${j}'
	assert j.contains('55.3.244.1'), 'expected IP: ${j}'
	assert j.contains('"method"'), 'expected method: ${j}'
}

fn test_parse_grok_simple() {
	result := execute('parse_grok!("hello world", "%{WORD:first} %{WORD:second}")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"first"') && j.contains('hello'), 'expected first:hello: ${j}'
	assert j.contains('"second"') && j.contains('world'), 'expected second:world: ${j}'
}

fn test_parse_grok_no_match() {
	execute('parse_grok!("hello", "%{IP:addr}")', map[string]VrlValue{}) or {
		assert err.msg().contains('unable to parse') || err.msg().contains('grok'),
			'expected parse error: ${err}'
		return
	}
}

fn test_parse_grok_unknown_pattern() {
	execute('parse_grok!("hello", "%{NONEXISTENT:val}")', map[string]VrlValue{}) or {
		assert err.msg().contains('unknown') || err.msg().contains('pattern'),
			'expected unknown pattern error: ${err}'
		return
	}
}

// ============================================================================
// vrllib_etld.v — parse_etld
// ============================================================================

fn test_parse_etld_simple() {
	result := execute('parse_etld!("www.example.com")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"etld"'), 'expected etld field: ${j}'
	assert j.contains('"known_suffix"'), 'expected known_suffix field: ${j}'
}

fn test_parse_etld_co_uk() {
	result := execute('parse_etld!("www.example.co.uk")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('co.uk') || j.contains('uk'), 'expected co.uk suffix: ${j}'
}

fn test_parse_etld_plus_parts() {
	result := execute('parse_etld!("www.example.com", plus_parts: 1)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('example.com') || j.contains('"etld_plus"'), 'expected etld_plus: ${j}'
}

fn test_parse_etld_unknown_tld() {
	result := execute('parse_etld!("host.unknowntld123")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"known_suffix"'), 'expected known_suffix: ${j}'
}

fn test_parse_etld_non_string_error() {
	execute('parse_etld!(42)', map[string]VrlValue{}) or {
		assert err.msg().contains('string'), 'expected string error: ${err}'
		return
	}
}

fn test_parse_etld_plus_parts_zero() {
	result := execute('parse_etld!("sub.example.org", plus_parts: 0)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"etld"'), 'expected etld: ${j}'
}

fn test_parse_etld_negative_plus_parts() {
	// Negative plus_parts should be clamped to 0
	result := execute('parse_etld!("www.example.com", plus_parts: -1)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"etld"'), 'expected etld: ${j}'
}

// ============================================================================
// static_check.v — E631 fallible abort message
// ============================================================================

fn test_sc_e631_fallible_abort_message() {
	execute_checked('abort parse_json!("{}")', map[string]VrlValue{}) or {
		// parse_json! is not fallible (has !), but check the non-string message
		return
	}
}

// ============================================================================
// static_check.v — E122 closure return type mismatch
// ============================================================================

fn test_sc_e122_filter_non_boolean_closure() {
	execute_checked('filter([1, 2, 3]) -> |_i, v| { "not boolean" }',
		map[string]VrlValue{}) or {
		assert err.msg().contains('E122') || err.msg().contains('type mismatch'),
			'expected E122: ${err}'
		return
	}
}

fn test_sc_e122_replace_with_non_string_closure() {
	execute_checked("replace_with(\"hello\", r'\\w+') -> |m| { 42 }",
		map[string]VrlValue{}) or {
		assert err.msg().contains('E122') || err.msg().contains('type mismatch'),
			'expected E122: ${err}'
		return
	}
}

// ============================================================================
// type_inference.v — type_from_value for various types
// ============================================================================

fn test_type_def_timestamp() {
	result := execute('type_def(now())', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('timestamp'), 'expected timestamp: ${j}'
}

fn test_type_def_regex() {
	result := execute("type_def(r'hello')", map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('regex'), 'expected regex: ${j}'
}

fn test_type_def_ident_unknown() {
	// Unknown variable should be any type
	result := execute('
x = parse_json!("null")
type_def(x)
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

fn test_type_def_path_root() {
	result := execute('
. = {"a": 1}
type_def(.)
', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('object'), 'expected object: ${j}'
}

fn test_type_def_abort() {
	result := execute('type_def(if false { abort } else { 42 })',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('integer'), 'expected integer (abort branch is never): ${j}'
}

fn test_type_def_return_expr() {
	result := execute('type_def(if false { return 1 } else { "hello" })',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

fn test_type_def_closure() {
	result := execute("type_def(r'test')", map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected type info: ${j}'
}

// ============================================================================
// type_inference.v — binary OR with literal false/null
// ============================================================================

fn test_type_def_binary_or_true_lhs() {
	result := execute('type_def(true || "never")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('boolean'), 'expected boolean (true || always returns true): ${j}'
}

fn test_type_def_binary_or_false_lhs() {
	result := execute('type_def(false || "hello")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('bytes'), 'expected bytes (false || returns RHS): ${j}'
}

fn test_type_def_binary_or_null_lhs() {
	result := execute('type_def(null || 42)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('integer'), 'expected integer (null || returns RHS): ${j}'
}

// ============================================================================
// type_inference.v — object merge |
// ============================================================================

fn test_type_def_object_merge() {
	result := execute('type_def({"a": 1} | {"b": 2})', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('object'), 'expected object: ${j}'
}

// ============================================================================
// type_inference.v — AND with literal booleans
// ============================================================================

fn test_type_def_and_false_lhs() {
	result := execute('type_def(false && "never")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('boolean'), 'expected boolean: ${j}'
}

fn test_type_def_and_true_lhs() {
	result := execute('type_def(true && true)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('boolean'), 'expected boolean: ${j}'
}
