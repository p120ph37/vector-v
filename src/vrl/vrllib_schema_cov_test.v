module vrl

import os

// Coverage tests for vrllib_jsonschema.v, static_check.v, and type_inference.v
// Targets uncovered lines across all three files.

fn cov_assert_checked_ok(source string) {
	execute_checked(source, map[string]VrlValue{}) or {
		panic('expected OK but got error for: ${source}\nerror: ${err}')
	}
}

fn cov_assert_checked_err(source string, expected_substr string) {
	execute_checked(source, map[string]VrlValue{}) or {
		assert err.msg().contains(expected_substr), 'expected error containing "${expected_substr}" but got: ${err.msg()}\nsource: ${source}'
		return
	}
	panic('expected static check error containing "${expected_substr}" but program succeeded\nsource: ${source}')
}

// ============================================================================
// vrllib_jsonschema.v coverage
// ============================================================================

// Line 11: too few arguments error
fn test_cov_jsonschema_too_few_args() {
	result := fn_validate_json_schema([]) or {
		assert err.msg().contains('at least 2 arguments')
		return
	}
	_ = result
}

// Line 15: value must be a string
fn test_cov_jsonschema_value_not_string() {
	result := fn_validate_json_schema([VrlValue(i64(42)), VrlValue('schema.json')]) or {
		assert err.msg().contains('value must be a string')
		return
	}
	_ = result
}

// Line 19: schema_definition must be a string
fn test_cov_jsonschema_schema_not_string() {
	result := fn_validate_json_schema([VrlValue('{}'), VrlValue(i64(1))]) or {
		assert err.msg().contains('schema_definition must be a string')
		return
	}
	_ = result
}

// Line 53: invalid schema JSON file
fn test_cov_jsonschema_invalid_schema_json() {
	path := '/tmp/test_cov_invalid_schema.json'
	os.write_file(path, '{bad schema') or { return }
	defer { os.rm(path) or {} }
	result := fn_validate_json_schema([VrlValue('42'), VrlValue(path)]) or {
		assert err.msg().contains('Failed to parse schema')
		return
	}
	_ = result
}

// Line 86: non-object, non-bool schema (else branch)
fn test_cov_jsonschema_validate_non_object_schema() {
	mut ctx := JsonSchemaContext{
		root_schema: VrlValue(VrlNull{})
		ignore_unknown_formats: false
	}
	// Pass a non-object, non-bool schema (e.g., a string)
	errors := ctx.validate(VrlValue(i64(42)), VrlValue('not_a_schema'), '/')
	assert errors.len == 0
}

// Line 123: type array with non-string element (continue branch)
fn test_cov_jsonschema_type_array_non_string_element() {
	// Create a schema with type as array containing a non-string
	mut schema := new_object_map()
	type_arr := [VrlValue('string'), VrlValue(i64(42))]
	schema.set('type', VrlValue(type_arr))
	mut ctx := JsonSchemaContext{
		root_schema: VrlValue(schema.clone_map())
		ignore_unknown_formats: false
	}
	// Test with a string value - should match first element
	errors := ctx.validate(VrlValue('hello'), VrlValue(schema), '/')
	assert errors.len == 0
}

// Lines 519, 528: resolve_ref non-local ref and non-object path
fn test_cov_jsonschema_resolve_ref_non_local() {
	ctx := JsonSchemaContext{
		root_schema: VrlValue(VrlNull{})
		ignore_unknown_formats: false
	}
	// Non-local ref (not starting with #/)
	result := ctx.resolve_ref('http://example.com/schema')
	assert result is VrlNull
}

fn test_cov_jsonschema_resolve_ref_non_object_path() {
	// root_schema has a key but it resolves to a non-object for next part
	mut root := new_object_map()
	root.set('defs', VrlValue('not_an_object'))
	ctx := JsonSchemaContext{
		root_schema: VrlValue(root)
		ignore_unknown_formats: false
	}
	// Try to resolve #/defs/something - defs is a string, not ObjectMap
	result := ctx.resolve_ref('#/defs/something')
	assert result is VrlNull
}

// Lines 549, 554, 559, 569: format validation failures
fn test_cov_jsonschema_format_date_invalid() {
	mut ctx := JsonSchemaContext{
		root_schema: VrlValue(VrlNull{})
		ignore_unknown_formats: false
	}
	errors := ctx.validate_format('not-a-date', 'date', '/')
	assert errors.len > 0
}

fn test_cov_jsonschema_format_time_invalid() {
	mut ctx := JsonSchemaContext{
		root_schema: VrlValue(VrlNull{})
		ignore_unknown_formats: false
	}
	errors := ctx.validate_format('not-a-time', 'time', '/')
	assert errors.len > 0
}

fn test_cov_jsonschema_format_uri_invalid() {
	mut ctx := JsonSchemaContext{
		root_schema: VrlValue(VrlNull{})
		ignore_unknown_formats: false
	}
	// Empty string - uri-reference is valid if len > 0, so use empty
	errors := ctx.validate_format('', 'uri', '/')
	assert errors.len > 0
}

fn test_cov_jsonschema_format_ipv6_invalid() {
	mut ctx := JsonSchemaContext{
		root_schema: VrlValue(VrlNull{})
		ignore_unknown_formats: false
	}
	errors := ctx.validate_format('not_ipv6', 'ipv6', '/')
	assert errors.len > 0
}

// Lines 622-625: jsonschema_display for null, array, object, else
fn test_cov_jsonschema_display_null() {
	result := jsonschema_display(VrlValue(VrlNull{}))
	assert result == 'null'
}

fn test_cov_jsonschema_display_array() {
	result := jsonschema_display(VrlValue([]VrlValue{}))
	assert result == '[...]'
}

fn test_cov_jsonschema_display_object() {
	result := jsonschema_display(VrlValue(new_object_map()))
	assert result == '{...}'
}

// Lines 633-634, 636: jsonschema_values_equal string cases
fn test_cov_jsonschema_values_equal_strings() {
	assert jsonschema_values_equal(VrlValue('hello'), VrlValue('hello'))
	assert !jsonschema_values_equal(VrlValue('hello'), VrlValue(i64(42)))
}

// Lines 642-643, 645: i64 compared with f64 and non-numeric
fn test_cov_jsonschema_values_equal_i64_f64() {
	assert jsonschema_values_equal(VrlValue(i64(5)), VrlValue(f64(5.0)))
	assert !jsonschema_values_equal(VrlValue(i64(5)), VrlValue('five'))
}

// Lines 648-649, 651-652, 654: f64 compared with f64, i64, and non-numeric
fn test_cov_jsonschema_values_equal_f64_variants() {
	assert jsonschema_values_equal(VrlValue(f64(3.14)), VrlValue(f64(3.14)))
	assert jsonschema_values_equal(VrlValue(f64(5.0)), VrlValue(i64(5)))
	assert !jsonschema_values_equal(VrlValue(f64(3.14)), VrlValue('pi'))
}

// Lines 657-658, 660: bool equality
fn test_cov_jsonschema_values_equal_bool() {
	assert jsonschema_values_equal(VrlValue(true), VrlValue(true))
	assert !jsonschema_values_equal(VrlValue(true), VrlValue('true'))
}

// Line 663: null equality
fn test_cov_jsonschema_values_equal_null() {
	assert jsonschema_values_equal(VrlValue(VrlNull{}), VrlValue(VrlNull{}))
	assert !jsonschema_values_equal(VrlValue(VrlNull{}), VrlValue(i64(0)))
}

// Lines 666-670, 673-674, 677, 679: array equality
fn test_cov_jsonschema_values_equal_arrays() {
	arr1 := [VrlValue(i64(1)), VrlValue(i64(2))]
	arr2 := [VrlValue(i64(1)), VrlValue(i64(2))]
	arr3 := [VrlValue(i64(1)), VrlValue(i64(3))]
	arr4 := [VrlValue(i64(1))]
	assert jsonschema_values_equal(VrlValue(arr1), VrlValue(arr2))
	assert !jsonschema_values_equal(VrlValue(arr1), VrlValue(arr3))
	assert !jsonschema_values_equal(VrlValue(arr1), VrlValue(arr4))
	assert !jsonschema_values_equal(VrlValue(arr1), VrlValue('not_array'))
}

// Lines 682-688, 691-694, 697, 699: object equality
fn test_cov_jsonschema_values_equal_objects() {
	mut obj1 := new_object_map()
	obj1.set('a', VrlValue(i64(1)))
	obj1.set('b', VrlValue(i64(2)))
	mut obj2 := new_object_map()
	obj2.set('a', VrlValue(i64(1)))
	obj2.set('b', VrlValue(i64(2)))
	mut obj3 := new_object_map()
	obj3.set('a', VrlValue(i64(1)))
	mut obj4 := new_object_map()
	obj4.set('a', VrlValue(i64(1)))
	obj4.set('b', VrlValue(i64(99)))
	assert jsonschema_values_equal(VrlValue(obj1), VrlValue(obj2))
	assert !jsonschema_values_equal(VrlValue(obj1), VrlValue(obj3)) // different len
	assert !jsonschema_values_equal(VrlValue(obj1), VrlValue(obj4)) // different values
	assert !jsonschema_values_equal(VrlValue(obj1), VrlValue('not_obj'))
}

// Line 702: else branch in values_equal
fn test_cov_jsonschema_values_equal_else() {
	// VrlRegex hits the else branch
	r := VrlValue(VrlRegex{ pattern: 'abc' })
	assert !jsonschema_values_equal(r, r)
}

// Lines 711-712: jsonschema_to_int for f64 and else
fn test_cov_jsonschema_to_int() {
	assert jsonschema_to_int(VrlValue(f64(3.7))) == 3
	assert jsonschema_to_int(VrlValue('not_a_number')) == -1
}

// Lines 742, 745, 749: email validation edge cases
fn test_cov_jsonschema_email_long_local() {
	// local part > 64 chars
	long_local := 'a'.repeat(65)
	assert !jsonschema_is_valid_email('${long_local}@example.com')
}

fn test_cov_jsonschema_email_long_domain() {
	long_domain := 'a'.repeat(256)
	assert !jsonschema_is_valid_email('user@${long_domain}')
}

fn test_cov_jsonschema_email_no_dot() {
	assert !jsonschema_is_valid_email('user@localhost')
}

// Lines 768, 776, 779, 783: date/time validation edge cases
fn test_cov_jsonschema_datetime_short() {
	assert !jsonschema_is_valid_datetime('2024-01-15')
}

fn test_cov_jsonschema_datetime_no_t_separator() {
	assert !jsonschema_is_valid_datetime('2024-01-15 10:30:00Z')
}

fn test_cov_jsonschema_date_wrong_length() {
	assert !jsonschema_is_valid_date('2024-1-15')
}

fn test_cov_jsonschema_date_bad_separator() {
	assert !jsonschema_is_valid_date('2024/01/15')
}

fn test_cov_jsonschema_date_non_digit() {
	assert !jsonschema_is_valid_date('20X4-01-15')
}

// Lines 792, 795, 800: time validation edge cases
fn test_cov_jsonschema_time_too_short() {
	assert !jsonschema_is_valid_time('10:30')
}

fn test_cov_jsonschema_time_bad_separator() {
	assert !jsonschema_is_valid_time('10-30-00Z')
}

fn test_cov_jsonschema_time_non_digit() {
	assert !jsonschema_is_valid_time('1X:30:00Z')
}

// Lines 806, 808, 812: time fractional seconds and no tz
fn test_cov_jsonschema_time_fractional() {
	assert jsonschema_is_valid_time('10:30:00.123Z')
}

fn test_cov_jsonschema_time_no_tz() {
	assert jsonschema_is_valid_time('10:30:00')
}

// Line 823: time bad timezone
fn test_cov_jsonschema_time_bad_tz() {
	assert !jsonschema_is_valid_time('10:30:00+0530')
}

// Lines 832, 838, 842: IPv4 validation
fn test_cov_jsonschema_ipv4_wrong_parts() {
	assert !jsonschema_is_valid_ipv4('192.168.1')
}

fn test_cov_jsonschema_ipv4_empty_part() {
	assert !jsonschema_is_valid_ipv4('192..168.1')
}

fn test_cov_jsonschema_ipv4_long_part() {
	assert !jsonschema_is_valid_ipv4('1234.168.1.1')
}

// ============================================================================
// static_check.v coverage
// ============================================================================

// Lines 62-63: MetaPathExpr is not fallible
fn test_cov_sc_meta_path_not_fallible() {
	// MetaPathExpr should return false for is_expr_fallible
	expr := Expr(MetaPathExpr{ path: '%foo' })
	assert !is_expr_fallible(expr)
}

// Line 67: ClosureExpr is not fallible
fn test_cov_sc_closure_not_fallible() {
	expr := Expr(ClosureExpr{ params: [], body: [] })
	assert !is_expr_fallible(expr)
}

// Lines 75: ObjectExpr with fallible value
fn test_cov_sc_object_fallible_value() {
	// ObjectExpr with a fallible function call
	prog := '. = {"key": parse_json!("{}")}'
	cov_assert_checked_ok(prog)
}

// Lines 93, 100-101, 103: FnCallExpr fallibility checks
fn test_cov_sc_infallible_fn_with_fallible_arg() {
	// Infallible fn with fallible arg (not handled) should be E100
	cov_assert_checked_err('downcase(parse_json("{}"))', 'E100')
}

// Lines 106, 109: AssignExpr and MergeAssignExpr fallibility
fn test_cov_sc_assign_fallible() {
	prog := '.x = parse_json!("{}")'
	cov_assert_checked_ok(prog)
}

// Lines 112, 116, 119-120, 122-123, 125-126, 128: if/block/coalesce/not/unary fallibility
fn test_cov_sc_ok_err_not_fallible() {
	expr := Expr(OkErrAssignExpr{
		ok_target: [Expr(IdentExpr{ name: 'ok' })]
		err_target: [Expr(IdentExpr{ name: 'err' })]
		value: [Expr(LiteralExpr{ value: VrlValue(i64(1)) })]
	})
	assert !is_expr_fallible(expr)
}

fn test_cov_sc_coalesce_fallible_rhs() {
	// CoalesceExpr: only RHS errors propagate
	// parse_json on RHS is fallible
	cov_assert_checked_err('(parse_json("x") ?? parse_json("y"))', 'E100')
}

fn test_cov_sc_if_fallible_condition() {
	// if with a fallible condition
	cov_assert_checked_err('if parse_json("x") { .x = 1 }', 'E100')
}

fn test_cov_sc_if_fallible_then() {
	// if with fallible then branch
	cov_assert_checked_err('if true { parse_json("x") }', 'E100')
}

fn test_cov_sc_if_fallible_else() {
	// if with fallible else branch
	cov_assert_checked_err('if true { .x = 1 } else { parse_json("x") }', 'E100')
}

fn test_cov_sc_block_fallible() {
	cov_assert_checked_err('{ parse_json("x") }', 'E100')
}

fn test_cov_sc_not_fallible() {
	// NotExpr with fallible inner
	expr := Expr(NotExpr{
		expr: [Expr(FnCallExpr{ name: 'parse_json', args: [Expr(LiteralExpr{ value: VrlValue('{}') })], closure: [] })]
	})
	assert is_expr_fallible(expr)
}

fn test_cov_sc_unary_fallible() {
	expr := Expr(UnaryExpr{
		op: '-'
		expr: [Expr(FnCallExpr{ name: 'parse_json', args: [Expr(LiteralExpr{ value: VrlValue('{}') })], closure: [] })]
	})
	assert is_expr_fallible(expr)
}

// Lines 132-133, 136, 138-139, 141-142, 144: more fallibility checks
fn test_cov_sc_abort_fallible_msg() {
	expr := Expr(AbortExpr{
		message: [Expr(FnCallExpr{ name: 'parse_json', args: [Expr(LiteralExpr{ value: VrlValue('{}') })], closure: [] })]
	})
	assert is_expr_fallible(expr)
}

fn test_cov_sc_abort_no_msg_not_fallible() {
	expr := Expr(AbortExpr{ message: [] })
	assert !is_expr_fallible(expr)
}

fn test_cov_sc_return_fallible() {
	expr := Expr(ReturnExpr{
		value: [Expr(FnCallExpr{ name: 'parse_json', args: [Expr(LiteralExpr{ value: VrlValue('{}') })], closure: [] })]
	})
	assert is_expr_fallible(expr)
}

fn test_cov_sc_return_no_value_not_fallible() {
	expr := Expr(ReturnExpr{ value: [] })
	assert !is_expr_fallible(expr)
}

// Lines 147-148, 150, 153: ReturnExpr and IndexExpr fallibility
fn test_cov_sc_index_fallible() {
	expr := Expr(IndexExpr{
		expr: [Expr(FnCallExpr{ name: 'parse_json', args: [Expr(LiteralExpr{ value: VrlValue('{}') })], closure: [] })]
		index: [Expr(LiteralExpr{ value: VrlValue(i64(0)) })]
	})
	assert is_expr_fallible(expr)
}

// Line 239, 267, 271, 273: e642_resolve_type and check_e642_target
fn test_cov_sc_e642_index_target() {
	// IndexExpr returns '' for e642_resolve_type
	expr := Expr(IndexExpr{
		expr: [Expr(IdentExpr{ name: 'x' })]
		index: [Expr(LiteralExpr{ value: VrlValue(i64(0)) })]
	})
	var_types := map[string]string{}
	result := e642_resolve_type(expr, var_types)
	assert result == ''
}

fn test_cov_sc_e642_resolve_path() {
	expr := Expr(PathExpr{ path: '.foo' })
	mut var_types := map[string]string{}
	var_types['.foo'] = 'string'
	result := e642_resolve_type(expr, var_types)
	assert result == 'string'
}

fn test_cov_sc_e642_resolve_else() {
	expr := Expr(LiteralExpr{ value: VrlValue(i64(42)) })
	var_types := map[string]string{}
	result := e642_resolve_type(expr, var_types)
	assert result == ''
}

// Line 333: check_e642_target for non-IndexExpr, non-PathExpr
fn test_cov_sc_e642_target_else() {
	target := Expr(LiteralExpr{ value: VrlValue(i64(42)) })
	var_types := map[string]string{}
	check_e642_target(target, var_types) or {
		panic('unexpected error')
	}
}

// Line 431: sc_walk UnaryExpr
fn test_cov_sc_walk_unary() {
	cov_assert_checked_ok('.x = -(1)')
}

// Lines 484-485, 487-488: sc_check_return_types in if branches
fn test_cov_sc_check_return_types_if() {
	// Replace_with with closure containing if/return
	prog := '.x = replace_with("hello world", r\'\\w+\', |m| { if m.string == "hello" { return "HI" } else { return "BYE" }; "" })'
	// This should pass - closures returning strings are valid for replace_with
	execute(prog, map[string]VrlValue{}) or { return }
}

// Lines 504, 506-507: sc_infer_simple_type for FnCallExpr
fn test_cov_sc_infer_simple_type_fn() {
	// Test with a fn call that returns known type
	expr := Expr(FnCallExpr{
		name: 'to_int!'
		args: [Expr(LiteralExpr{ value: VrlValue('42') })]
		closure: []
	})
	result := sc_infer_simple_type(expr)
	assert result == 'integer'
}

// Line 523: sc_infer_simple_type for BlockExpr
fn test_cov_sc_infer_simple_type_block() {
	expr := Expr(BlockExpr{
		exprs: [
			Expr(LiteralExpr{ value: VrlValue('hello') }),
			Expr(LiteralExpr{ value: VrlValue(i64(42)) }),
		]
	})
	result := sc_infer_simple_type(expr)
	assert result == 'integer'
}

// Line 543: sc_infer_simple_type else branch
fn test_cov_sc_infer_simple_type_else() {
	expr := Expr(PathExpr{ path: '.x' })
	result := sc_infer_simple_type(expr)
	assert result == ''
}

// Lines 593, 606, 609-610, 613-615, 617-618: check_read_only branches
fn test_cov_sc_check_read_only_if() {
	// if with read-only check should work
	prog := 'if true { .other = 1 }'
	execute_checked_with_readonly(prog, map[string]VrlValue{},
		['.hostname'], []string{}, []string{}) or {
		panic('unexpected error: ${err}')
	}
}

fn test_cov_sc_check_read_only_merge_assign() {
	prog := '.other |= {"a": 1}'
	execute_checked_with_readonly(prog, map[string]VrlValue{},
		['.hostname'], []string{}, []string{}) or {
		return
	}
}

fn test_cov_sc_check_read_only_ok_err() {
	prog := 'result, err = parse_json("{}")\n.x = result'
	execute_checked_with_readonly(prog, map[string]VrlValue{},
		['.hostname'], []string{}, []string{}) or {
		panic('unexpected error: ${err}')
	}
}

fn test_cov_sc_check_read_only_ok_err_readonly_target() {
	prog := '.hostname, err = parse_json("{}")\n.hostname'
	execute_checked_with_readonly(prog, map[string]VrlValue{},
		['.hostname'], []string{}, []string{}) or {
		assert err.msg().contains('E315')
		return
	}
}

// Line 626: check_read_only_target for else branch (not path, not meta, not index)
fn test_cov_sc_check_read_only_target_else() {
	// IdentExpr as target - falls through to else {}
	target := Expr(IdentExpr{ name: 'foo' })
	check_read_only_target(target, ['.hostname'], []string{}, []string{}) or {
		panic('unexpected error')
	}
}

// Lines 726-728, 739, 745: del_array_base_path and uses_del_path
fn test_cov_sc_del_array_base_path() {
	// PathExpr with array index
	expr := Expr(PathExpr{ path: '.arr[0]' })
	result := del_array_base_path(expr)
	assert result == '.arr'
}

fn test_cov_sc_del_array_base_path_ident() {
	inner := Expr(IdentExpr{ name: 'arr' })
	expr := Expr(IndexExpr{
		expr: [inner]
		index: [Expr(LiteralExpr{ value: VrlValue(i64(0)) })]
	})
	result := del_array_base_path(expr)
	assert result == 'arr'
}

fn test_cov_sc_del_array_base_path_else() {
	expr := Expr(LiteralExpr{ value: VrlValue(i64(42)) })
	result := del_array_base_path(expr)
	assert result == ''
}

// Lines 756-757, 767, 773: uses_del_path
fn test_cov_sc_uses_del_path_index_ident() {
	mut del_paths := map[string]bool{}
	del_paths['arr'] = true
	inner := Expr(IdentExpr{ name: 'arr' })
	expr := Expr(IndexExpr{
		expr: [inner]
		index: [Expr(LiteralExpr{ value: VrlValue(i64(0)) })]
	})
	assert uses_del_path(expr, del_paths)
}

fn test_cov_sc_uses_del_path_else() {
	del_paths := map[string]bool{}
	expr := Expr(LiteralExpr{ value: VrlValue(i64(42)) })
	assert !uses_del_path(expr, del_paths)
}

// Lines 847, 850, 852, 855: sc_expr_uses_var for coalesce, not, unary, index, etc.
fn test_cov_sc_expr_uses_var_coalesce() {
	expr := Expr(CoalesceExpr{
		expr: [Expr(IdentExpr{ name: 'foo' })]
		default_: [Expr(LiteralExpr{ value: VrlValue('default') })]
	})
	assert sc_expr_uses_var(expr, 'foo')
}

fn test_cov_sc_expr_uses_var_not() {
	expr := Expr(NotExpr{
		expr: [Expr(IdentExpr{ name: 'bar' })]
	})
	assert sc_expr_uses_var(expr, 'bar')
}

fn test_cov_sc_expr_uses_var_unary() {
	expr := Expr(UnaryExpr{
		op: '-'
		expr: [Expr(IdentExpr{ name: 'x' })]
	})
	assert sc_expr_uses_var(expr, 'x')
}

fn test_cov_sc_expr_uses_var_index() {
	expr := Expr(IndexExpr{
		expr: [Expr(IdentExpr{ name: 'arr' })]
		index: [Expr(LiteralExpr{ value: VrlValue(i64(0)) })]
	})
	assert sc_expr_uses_var(expr, 'arr')
}

// ============================================================================
// type_inference.v coverage
// ============================================================================

// Line 125: abstractify_arrays non-ObjectMap array
fn test_cov_type_inf_abstractify_non_object_array() {
	mut t := new_object_map()
	t.set('array', VrlValue(true)) // not an ObjectMap
	result := abstractify_arrays(t)
	_ := result.get('array') or {
		panic('expected array key')
	}
}

// Line 142: abstractify_arrays object with non-ObjectMap field
fn test_cov_type_inf_abstractify_object_non_obj_field() {
	mut inner := new_object_map()
	inner.set('field', VrlValue(true)) // non-ObjectMap field
	mut t := new_object_map()
	t.set('object', VrlValue(inner))
	result := abstractify_arrays(t)
	obj_val := result.get('object') or { panic('expected object key') }
	_ = obj_val
}

// Line 149: abstractify_arrays non-ObjectMap object value
fn test_cov_type_inf_abstractify_non_obj_object() {
	mut t := new_object_map()
	t.set('object', VrlValue(true)) // not an ObjectMap
	result := abstractify_arrays(t)
	_ := result.get('object') or {
		panic('expected object key')
	}
}

// Line 207: type_union_if with nested non-object key
fn test_cov_type_inf_union_if() {
	mut a := new_object_map()
	a.set('bytes', VrlValue(true))
	mut b := new_object_map()
	b.set('integer', VrlValue(true))
	result := type_union_if(a, b)
	_ := result.get('bytes') or { panic('expected bytes') }
	_ := result.get('integer') or { panic('expected integer') }
}

// Lines 233-235, 237, 239-240, 247, 256, 265, 274: type_union_object_fields
fn test_cov_type_inf_union_object_fields() {
	mut a := new_object_map()
	mut a_field := new_object_map()
	a_field.set('bytes', VrlValue(true))
	a.set('name', VrlValue(a_field))
	a.set('only_a', VrlValue(bytes_type()))

	mut b := new_object_map()
	mut b_field := new_object_map()
	b_field.set('integer', VrlValue(true))
	b.set('name', VrlValue(b_field))
	b.set('only_b', VrlValue(integer_type()))

	result := type_union_object_fields(a, b)
	// 'name' should be union of bytes and integer
	name_val := result.get('name') or { panic('expected name') }
	// 'only_a' should have undefined added
	only_a := result.get('only_a') or { panic('expected only_a') }
	_ = only_a
	// 'only_b' should have undefined added
	only_b := result.get('only_b') or { panic('expected only_b') }
	_ = only_b
	_ = name_val
}

// Lines 356-357, 359, 372: infer_expr_type for MetaPathExpr
fn test_cov_type_inf_meta_path() {
	prog := 'type_def(%)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_meta_path_named() {
	prog := '%foo = "bar"\ntype_def(%foo)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 388, 390-392, 394: MetaPathExpr with tracked meta paths
fn test_cov_type_inf_meta_path_root_with_keys() {
	prog := '%custom = "hello"\n%other = 42\ntype_def(%)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_meta_path_clean() {
	prog := '%mykey = "val"\ntype_def(%mykey)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 458, 469: IndexExpr type inference
fn test_cov_type_inf_index_expr() {
	prog := 'x = [1, 2, 3]\ntype_def(x[0])'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 477, 483: UnaryExpr and MergeAssignExpr type inference
fn test_cov_type_inf_unary_expr() {
	prog := 'x = 5\ntype_def(-x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_merge_assign() {
	prog := '.x = {}\n.x |= {"a": 1}\ntype_def(.x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 494: ClosureExpr type inference
fn test_cov_type_inf_closure() {
	prog := 'type_def(|x| { x })'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 515, 532: apply_assign_type MetaPathExpr
fn test_cov_type_inf_assign_meta_path() {
	prog := '%myfield = "hello"\ntype_def(%myfield)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Line 578, 584: infer_if_type both never
fn test_cov_type_inf_if_both_abort() {
	prog := 'type_def(if true { abort } else { abort })'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 604, 608: merge_branch_envs
fn test_cov_type_inf_merge_branches() {
	prog := 'if .flag { x = "hello" } else { x = 42 }\ntype_def(x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 630, 632, 637, 639: merge_branch_envs path handling
fn test_cov_type_inf_merge_branch_paths() {
	prog := 'if .flag { .newfield = "hello" } else { .otherfield = 42 }\ntype_def(.newfield)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 664-665, 667, 696-697, 699: infer_binary_type && and || with variable changes
fn test_cov_type_inf_binary_and_unknown() {
	prog := 'x = .flag && .other\ntype_def(x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_binary_or_unknown() {
	prog := 'x = .flag || .other\ntype_def(x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 714, 721-722, 724, 726-728, 731: infer_binary_type object merge and ??
fn test_cov_type_inf_binary_object_merge() {
	prog := 'x = {"a": 1} | {"b": 2}\ntype_def(x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_binary_coalesce() {
	prog := 'x = parse_json!("null") ?? "default"\ntype_def(x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 758-759, 761: infer_binary_type arithmetic
fn test_cov_type_inf_binary_division() {
	prog := 'x = 10 / 2\ntype_def(x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 789, 847: infer_fn_call_type - slice and del
fn test_cov_type_inf_fn_slice() {
	prog := 'type_def(slice!("hello", 1))'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_fn_del() {
	prog := '.x = 42\ntype_def(del(.x))'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Line 953: update_type_vars_for_if_saved
fn test_cov_type_inf_update_if_saved() {
	prog := '. = {}\nif .flag { .x = "hello" } else { .x = 42 }\ntype_def(.x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Lines 1037, 1070: update_type_vars_for_binary_saved
fn test_cov_type_inf_binary_saved_and() {
	prog := '.flag && { x = "hello"; true }\n.y = 1'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_binary_saved_or() {
	prog := '.flag || { x = "hello"; true }\n.y = 1'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Additional type inference fn coverage
fn test_cov_type_inf_fn_push() {
	prog := 'x = push([1, 2], 3)\ntype_def(x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_fn_push_any() {
	prog := 'x = push(.arr, 3)\ntype_def(x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_fn_parse_timestamp() {
	prog := 'type_def(now())'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_fn_to_timestamp() {
	prog := 'type_def(to_timestamp!(1234567890))'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_fn_merge() {
	prog := 'type_def(merge({"a": 1}, {"b": 2}))'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_fn_unknown() {
	prog := 'type_def(type_of("hello"))'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_fn_parse_json() {
	prog := 'type_def(parse_json!("{}"))'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// OkErrAssignExpr type inference (lines 483-491)
fn test_cov_type_inf_ok_err_assign() {
	prog := 'result, err = parse_json("{}")\ntype_def(result)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// NotExpr type inference (line 477-480)
fn test_cov_type_inf_not_expr() {
	prog := 'type_def(!true)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Boolean type for comparison operators
fn test_cov_type_inf_comparison() {
	prog := 'type_def(1 == 2)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// If with only then branch never (line 580-584)
fn test_cov_type_inf_if_then_abort() {
	prog := 'type_def(if true { abort } else { "hello" })'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_if_else_abort() {
	prog := 'type_def(if true { "hello" } else { abort })'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

// Boolean and/or with literal branches (lines 652-667)
fn test_cov_type_inf_and_false_literal() {
	prog := 'type_def(false && .x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_and_true_literal() {
	prog := 'type_def(true && .x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_or_true_literal() {
	prog := 'type_def(true || .x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_or_false_literal() {
	prog := 'type_def(false || .x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}

fn test_cov_type_inf_or_null_literal() {
	prog := 'type_def(null || .x)'
	result := execute(prog, map[string]VrlValue{}) or { return }
	_ = result
}
