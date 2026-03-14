module vrl

// Tests for static_check.v — compile-time VRL program analysis.
// Exercises error detection codes: E100, E102, E104, E300, E315,
// E620, E631, E642, E651, E660, E900.

// ============================================================================
// Helper: expect static check to pass (program compiles and runs)
// ============================================================================

fn assert_checked_ok(source string) {
	execute_checked(source, map[string]VrlValue{}) or {
		panic('expected OK but got error for: ${source}\nerror: ${err}')
	}
}

// Helper: expect static check to fail with a specific error substring
fn assert_checked_err(source string, expected_substr string) {
	execute_checked(source, map[string]VrlValue{}) or {
		assert err.msg().contains(expected_substr), 'expected error containing "${expected_substr}" but got: ${err.msg()}\nsource: ${source}'
		return
	}
	panic('expected static check error containing "${expected_substr}" but program succeeded\nsource: ${source}')
}

// ============================================================================
// E100: unhandled fallible expression
// ============================================================================

fn test_sc_e100_unhandled_fallible_fn() {
	// parse_json is fallible; calling without ! should be E100
	assert_checked_err('parse_json("test")', 'E100')
}

fn test_sc_e100_handled_with_bang() {
	// Using ! handles the error
	assert_checked_ok('parse_json!("{}")')
}

fn test_sc_e100_handled_with_coalesce() {
	// Using ?? handles the error
	assert_checked_ok('parse_json("{}") ?? {}')
}

fn test_sc_e100_handled_with_ok_err() {
	// ok/err assignment handles the error
	assert_checked_ok('result, err = parse_json("{}")\nresult')
}

fn test_sc_e100_division_is_fallible() {
	// Division on null types triggers type error
	assert_checked_err('.x = .a / .b', 'divide')
}

fn test_sc_e100_modulo_is_fallible() {
	assert_checked_err('.x = .a % .b', 'modulo')
}

// ============================================================================
// E102: non-boolean if predicate
// ============================================================================

fn test_sc_e102_non_boolean_if_string() {
	assert_checked_err('if "hello" { .x = 1 }', 'E102')
}

fn test_sc_e102_non_boolean_if_integer() {
	assert_checked_err('if 42 { .x = 1 }', 'E102')
}

fn test_sc_e102_boolean_if_ok() {
	assert_checked_ok('if true { .x = 1 }')
}

fn test_sc_e102_variable_if_ok() {
	// Variable as condition is allowed (type unknown at static time)
	assert_checked_ok('.y = true\nif .y { .x = 1 }')
}

// ============================================================================
// E104: unnecessary error assignment (ok/err on infallible)
// ============================================================================

fn test_sc_e104_infallible_ok_err() {
	// downcase is infallible, so ok/err is unnecessary
	assert_checked_err('result, err = downcase("HELLO")\nresult', 'E104')
}

fn test_sc_e104_fallible_ok_err_ok() {
	// parse_json is fallible, so ok/err is fine
	assert_checked_ok('result, err = parse_json("{}")\nresult')
}

// ============================================================================
// E300: non-string abort message
// ============================================================================

fn test_sc_e300_abort_integer_message() {
	assert_checked_err('abort 42', 'E300')
}

fn test_sc_e300_abort_boolean_message() {
	assert_checked_err('abort true', 'E300')
}

fn test_sc_e300_abort_string_ok() {
	assert_checked_ok('abort "something went wrong"')
}

fn test_sc_e300_abort_no_message_ok() {
	assert_checked_ok('abort')
}

// ============================================================================
// E620: abort (!) on infallible function
// ============================================================================

fn test_sc_e620_bang_on_infallible() {
	// downcase is infallible, using ! is unnecessary
	assert_checked_err('downcase!("HELLO")', 'E620')
}

fn test_sc_e620_bang_on_fallible_ok() {
	assert_checked_ok('parse_json!("{}")')
}

// ============================================================================
// E642: parent path type mismatch
// ============================================================================

fn test_sc_e642_string_then_field_access() {
	// Assign a string to a var, then try to set a field on it
	assert_checked_err('foo = "hello"\nfoo.bar = "world"', 'E642')
}

fn test_sc_e642_object_field_ok() {
	assert_checked_ok('. = {"foo": true}\n.bar = "test"')
}

fn test_sc_e642_nested_type_mismatch() {
	// . = {"foo": true} means .foo is boolean, so .foo.bar should fail
	assert_checked_err('. = {"foo": true}\n.foo.bar = "test"', 'E642')
}

// ============================================================================
// E651: unnecessary error coalescing
// ============================================================================

fn test_sc_e651_infallible_coalesce() {
	// downcase is infallible, so ?? is unnecessary
	assert_checked_err('downcase("x") ?? "default"', 'E651')
}

fn test_sc_e651_fallible_coalesce_ok() {
	assert_checked_ok('parse_json("{}") ?? {}')
}

// ============================================================================
// E660: non-boolean negation
// ============================================================================

fn test_sc_e660_negate_integer() {
	assert_checked_err('!42', 'E660')
}

fn test_sc_e660_negate_string() {
	assert_checked_err('!"hello"', 'E660')
}

fn test_sc_e660_negate_boolean_ok() {
	assert_checked_ok('.x = !true')
}

// ============================================================================
// E900: unused expression / unused variable
// ============================================================================

fn test_sc_e900_unused_literal() {
	assert_checked_err('"unused string"\n.x = 1', 'E900')
}

fn test_sc_e900_unused_variable() {
	assert_checked_err('foo = "bar"\n.x = 1', 'E900')
}

fn test_sc_e900_used_variable_ok() {
	assert_checked_ok('foo = "bar"\n.x = foo')
}

// ============================================================================
// E315: read-only path mutation
// ============================================================================

fn test_sc_e315_read_only_path() {
	execute_checked_with_readonly('.hostname = "new"', map[string]VrlValue{},
		['.hostname'], []string{}, []string{}) or {
		assert err.msg().contains('E315'), 'expected E315, got ${err.msg()}'
		return
	}
	panic('expected E315 error for read-only path mutation')
}

fn test_sc_e315_read_only_recursive() {
	execute_checked_with_readonly('.meta.host = "new"', map[string]VrlValue{},
		[]string{}, ['.meta'], []string{}) or {
		assert err.msg().contains('E315'), 'expected E315, got ${err.msg()}'
		return
	}
	panic('expected E315 error for read-only recursive path mutation')
}

fn test_sc_e315_read_only_meta_path() {
	execute_checked_with_readonly('%custom = "val"', map[string]VrlValue{},
		[]string{}, []string{}, ['custom']) or {
		assert err.msg().contains('E315'), 'expected E315, got ${err.msg()}'
		return
	}
	panic('expected E315 error for read-only meta path mutation')
}

fn test_sc_e315_non_readonly_ok() {
	execute_checked_with_readonly('.other = "val"', map[string]VrlValue{},
		['.hostname'], []string{}, []string{}) or {
		panic('expected non-readonly path to succeed, got ${err.msg()}')
	}
}

fn test_sc_e315_root_mutation_blocked() {
	execute_checked_with_readonly('. = {}', map[string]VrlValue{},
		['.hostname'], []string{}, []string{}) or {
		assert err.msg().contains('E315'), 'expected E315, got ${err.msg()}'
		return
	}
	panic('expected E315 error for root mutation with read-only paths')
}

// ============================================================================
// Valid programs that should pass static checking
// ============================================================================

fn test_sc_valid_simple_assignment() {
	assert_checked_ok('.message = "hello"')
}

fn test_sc_valid_if_else() {
	assert_checked_ok('if .level == "error" { .critical = true } else { .critical = false }')
}

fn test_sc_valid_infallible_functions() {
	assert_checked_ok('.msg = downcase("HELLO")')
}

fn test_sc_valid_array_operations() {
	assert_checked_ok('.tags = push(["a", "b"], "c")')
}

fn test_sc_valid_nested_function_calls() {
	assert_checked_ok('.x = length(split("a,b,c", ","))')
}

fn test_sc_valid_string_operations() {
	assert_checked_ok('.y = contains("hello world", "hello")')
}

fn test_sc_valid_encode_json() {
	assert_checked_ok('.out = encode_json({"key": "value"})')
}

// ============================================================================
// Complex programs combining multiple features
// ============================================================================

fn test_sc_complex_parse_and_transform() {
	prog := '
parsed, err = parse_json("{}")
if err == null {
  .parsed = parsed
} else {
  .parse_error = true
}
'
	assert_checked_ok(prog)
}

fn test_sc_complex_multiple_assignments() {
	prog := '
.host = downcase("HELLO")
.severity = upcase("info")
.processed = true
'
	assert_checked_ok(prog)
}

// ============================================================================
// is_fn_infallible tests (via static check behavior)
// ============================================================================

fn test_sc_infallible_type_check_functions() {
	// All type-check functions should be infallible
	fns := ['is_string(.x)', 'is_integer(.x)', 'is_float(.x)', 'is_boolean(.x)',
		'is_null(.x)', 'is_array(.x)', 'is_object(.x)']
	for f in fns {
		assert_checked_ok('.result = ${f}')
	}
}

fn test_sc_infallible_string_functions() {
	fns := ['downcase("X")', 'upcase("x")', 'contains("abc", "a")',
		'starts_with("abc", "a")', 'ends_with("abc", "c")',
		'strip_whitespace("  x  ")', 'truncate("hello", 3)']
	for f in fns {
		assert_checked_ok('.result = ${f}')
	}
}

fn test_sc_infallible_collection_functions() {
	fns := ['length([1,2,3])', 'keys({"a": 1})', 'values({"a": 1})',
		'flatten([[1,2],[3]])', 'compact([1, null, 2])',
		'unique([1,1,2])']
	for f in fns {
		assert_checked_ok('.result = ${f}')
	}
}

fn test_sc_infallible_encoding_functions() {
	fns := ['encode_json({"a": 1})', 'encode_base64("hello")']
	for f in fns {
		assert_checked_ok('.result = ${f}')
	}
}

fn test_sc_infallible_hash_functions() {
	fns := ['sha1("hello")', 'md5("hello")']
	for f in fns {
		assert_checked_ok('.result = ${f}')
	}
}
