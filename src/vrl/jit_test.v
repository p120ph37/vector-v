module vrl

// JIT tests - codegen tests always run, execution tests only with -d jit.

fn parse_vrl(source string) !Expr {
	mut lex := new_lexer(source)
	tokens := lex.tokenize()
	mut parser := new_parser(tokens)
	return parser.parse()
}

// --- Codegen tests (always run, no libtcc needed) ---

fn test_jit_codegen_literal_int() {
	ast := parse_vrl('42') or { panic(err) }
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('vi(42)')
	assert c_src.contains('jit_eval')
}

fn test_jit_codegen_literal_string() {
	ast := parse_vrl('"hello"') or { panic(err) }
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('vsl("hello")')
}

fn test_jit_codegen_arithmetic() {
	ast := parse_vrl('1 + 2') or { panic(err) }
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('val_add')
}

fn test_jit_codegen_path_assign() {
	ast := parse_vrl('.foo = "bar"') or { panic(err) }
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('path_set(&ctx, ".foo"')
}

fn test_jit_codegen_if_else() {
	ast := parse_vrl('if true { "yes" } else { "no" }') or { panic(err) }
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('if (truthy(')
}

fn test_jit_codegen_fn_downcase() {
	ast := parse_vrl('downcase("HELLO")') or { panic(err) }
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('fn_downcase')
}

fn test_jit_codegen_del() {
	ast := parse_vrl('del(.a)') or { panic(err) }
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('path_del(&ctx, ".a")')
}

fn test_jit_codegen_variable() {
	ast := parse_vrl('foo = 42\nfoo') or { panic(err) }
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('var_foo')
}

fn test_jit_codegen_not_operator() {
	ast := parse_vrl('!true') or { panic(err) }
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('!truthy(')
}

fn test_jit_codegen_coalesce() {
	ast := parse_vrl('.missing ?? "default"') or { panic(err) }
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('VT_NULL')
}

fn test_jit_can_compile_supported() {
	ast := parse_vrl('.message = downcase(.message)') or { panic(err) }
	assert jit_can_compile(ast) == true
}

fn test_jit_cannot_compile_unsupported_fn() {
	ast := parse_vrl('uuid_v4()') or { panic(err) }
	assert jit_can_compile(ast) == false
}

fn test_jit_codegen_complete_program() {
	src := '
.message = downcase(.message)
.host = upcase(.host)
.processed = true
if contains(.message, "error") {
  .severity = "high"
} else {
  .severity = "low"
}
del(.temp)
.
'
	ast := parse_vrl(src) or { panic(err) }
	assert jit_can_compile(ast) == true
	c_src := jit_generate_c(ast) or { panic(err) }
	assert c_src.contains('fn_downcase')
	assert c_src.contains('fn_upcase')
	assert c_src.contains('fn_contains')
	assert c_src.contains('path_del')
}

fn test_jit_available() {
	$if jit ? {
		assert jit_available() == true
	} $else {
		assert jit_available() == false
	}
}

// Helper to get a value from a map, returning VrlNull if missing.
fn get_val(m map[string]VrlValue, key string) VrlValue {
	return m[key] or { VrlValue(VrlNull{}) }
}

// --- Integration tests (only run with -d jit) ---

fn test_jit_compile_and_execute() {
	$if jit ? {
		ast := parse_vrl('.greeting = "hello"') or { panic(err) }
		mut prog := jit_compile(ast) or { panic(err) }
		result := jit_execute(&prog, map[string]VrlValue{}) or { panic(err) }
		assert 'greeting' in result
		assert get_val(result, 'greeting') == VrlValue('hello')
		jit_free(mut prog)
	}
}

fn test_jit_arithmetic_execution() {
	$if jit ? {
		ast := parse_vrl('.result = 10 + 20 * 2') or { panic(err) }
		mut prog := jit_compile(ast) or { panic(err) }
		result := jit_execute(&prog, map[string]VrlValue{}) or { panic(err) }
		assert get_val(result, 'result') == VrlValue(50)
		jit_free(mut prog)
	}
}

fn test_jit_path_transform() {
	$if jit ? {
		ast := parse_vrl('.output = downcase(.input)') or { panic(err) }
		mut prog := jit_compile(ast) or { panic(err) }
		mut obj := map[string]VrlValue{}
		obj['input'] = VrlValue('HELLO WORLD')
		result := jit_execute(&prog, obj) or { panic(err) }
		assert get_val(result, 'output') == VrlValue('hello world')
		jit_free(mut prog)
	}
}

fn test_jit_if_else_execution() {
	$if jit ? {
		src := 'if .level == "error" { .priority = "high" } else { .priority = "low" }'
		ast := parse_vrl(src) or { panic(err) }
		mut prog := jit_compile(ast) or { panic(err) }
		mut obj := map[string]VrlValue{}
		obj['level'] = VrlValue('error')
		r := jit_execute(&prog, obj) or { panic(err) }
		assert get_val(r, 'priority') == VrlValue('high')
		jit_free(mut prog)
	}
}

fn test_jit_del_execution() {
	$if jit ? {
		ast := parse_vrl('del(.temp)') or { panic(err) }
		mut prog := jit_compile(ast) or { panic(err) }
		mut obj := map[string]VrlValue{}
		obj['keep'] = VrlValue('yes')
		obj['temp'] = VrlValue('no')
		result := jit_execute(&prog, obj) or { panic(err) }
		assert 'keep' in result
		assert 'temp' !in result
		jit_free(mut prog)
	}
}

fn test_jit_complex_transform() {
	$if jit ? {
		src := '
.message = downcase(.message)
.processed = true
if contains(.message, "error") {
  .severity = "high"
} else {
  .severity = "low"
}
del(.raw)
'
		ast := parse_vrl(src) or { panic(err) }
		mut prog := jit_compile(ast) or { panic(err) }
		mut obj := map[string]VrlValue{}
		obj['message'] = VrlValue('ERROR: disk full')
		obj['raw'] = VrlValue('raw data')
		result := jit_execute(&prog, obj) or { panic(err) }
		assert get_val(result, 'message') == VrlValue('error: disk full')
		assert get_val(result, 'processed') == VrlValue(true)
		assert get_val(result, 'severity') == VrlValue('high')
		assert 'raw' !in result
		jit_free(mut prog)
	}
}

fn test_jit_reuse_compiled_program() {
	$if jit ? {
		ast := parse_vrl('.out = downcase(.input)') or { panic(err) }
		mut prog := jit_compile(ast) or { panic(err) }
		for word in ['HELLO', 'WORLD', 'FOO'] {
			mut obj := map[string]VrlValue{}
			obj['input'] = VrlValue(word)
			result := jit_execute(&prog, obj) or { panic(err) }
			assert get_val(result, 'out') == VrlValue(word.to_lower())
		}
		jit_free(mut prog)
	}
}
