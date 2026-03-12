module vrl

// Static analysis for VRL programs — compile-time error detection.
//
// Implements a subset of the Rust VRL compiler's static checks:
//   E100 — unhandled fallible expression (fallible fn call without !)
//   E102 — non-boolean if predicate (literal non-boolean condition)
//   E104 — unnecessary error assignment (ok, err = infallible)
//   E300 — non-string abort message
//   E631 — fallible abort message expression
//   E651 — unnecessary error coalesce (infallible ?? default)
//   E660 — non-boolean negation (! on non-boolean literal)

// is_fn_infallible returns true if a function is guaranteed to never fail,
// regardless of input types. Functions NOT in this list are considered fallible.
fn is_fn_infallible(name string) bool {
	return name in [
		// Type checking — always return bool
		'is_string', 'is_integer', 'is_float', 'is_boolean', 'is_null',
		'is_array', 'is_object', 'is_nullish', 'is_empty', 'is_json',
		'is_regex', 'is_timestamp', 'is_ipv4', 'is_ipv6',
		// String manipulation — accept string, always succeed
		'downcase', 'upcase', 'contains', 'starts_with', 'ends_with',
		'strip_whitespace', 'trim', 'truncate', 'replace', 'sieve',
		'camelcase', 'pascalcase', 'snakecase', 'kebabcase', 'screamingsnakecase',
		'strip_ansi_escape_codes',
		// Info / coercion that always succeeds
		'length', 'strlen', 'type_of', 'to_string', 'string',
		// Math — accept numeric, always succeed
		'ceil', 'floor', 'round', 'abs',
		// Collections — always succeed
		'push', 'append', 'flatten', 'compact', 'unique', 'keys', 'values',
		'merge', 'join', 'split', 'del', 'exists',
		'tag_types_externally', 'tally', 'tally_value', 'object_from_array',
		// Encoding (non-parsing) — always succeed
		'encode_json', 'encode_base64', 'encode_base16', 'encode_percent',
		'encode_key_value', 'encode_logfmt', 'encode_csv',
		'encode_gzip', 'encode_zlib', 'encode_zstd',
		// Hashing — accept bytes, always succeed
		'sha1', 'sha2', 'md5', 'hmac',
		// Random — no args or numeric, always succeed
		'random_bool', 'random_float', 'random_int',
		// Misc infallible
		'get_hostname', 'now', 'uuid_v4', 'uuid_v7',
		'basename', 'dirname', 'log', 'match', 'match_array',
		'format_int', 'format_number',
		'split_path', 'unflatten', 'shannon_entropy', 'find',
		'map_values', 'map_keys', 'filter', 'for_each',
		'replace_with', 'type_def', 'set',
		// Zip is infallible
		'zip',
	]
}

// is_expr_fallible returns true if an expression can produce an unhandled error.
// This is a pure analysis function — it does not produce errors.
fn is_expr_fallible(expr Expr) bool {
	match expr {
		LiteralExpr { return false }
		IdentExpr { return false }
		PathExpr { return false }
		MetaPathExpr { return false }
		ClosureExpr { return false }
		ArrayExpr {
			for item in expr.items {
				if is_expr_fallible(item) {
					return true
				}
			}
			return false
		}
		ObjectExpr {
			for pair in expr.pairs {
				if is_expr_fallible(pair.value) {
					return true
				}
			}
			return false
		}
		FnCallExpr {
			name := expr.name
			// If the function call has !, all errors (including arg errors) are handled
			if name.len > 0 && name[name.len - 1] == `!` {
				return false
			}
			// Check if the function itself is fallible
			if !is_fn_infallible(name) {
				return true
			}
			// Even infallible functions: check if args are fallible
			for arg in expr.args {
				if is_expr_fallible(arg) {
					return true
				}
			}
			return false
		}
		BinaryExpr {
			// Division and modulo are always fallible (potential divide-by-zero)
			if expr.op == '/' || expr.op == '%' {
				return true
			}
			return is_expr_fallible(expr.left[0]) || is_expr_fallible(expr.right[0])
		}
		AssignExpr {
			return is_expr_fallible(expr.value[0])
		}
		MergeAssignExpr {
			return is_expr_fallible(expr.value[0])
		}
		OkErrAssignExpr {
			return false // ok/err handles errors
		}
		CoalesceExpr {
			// ?? handles errors from LHS; only RHS errors propagate
			return is_expr_fallible(expr.default_[0])
		}
		IfExpr {
			if is_expr_fallible(expr.condition[0]) {
				return true
			}
			if expr.then_block.len > 0 && is_expr_fallible(expr.then_block[0]) {
				return true
			}
			if expr.else_block.len > 0 && is_expr_fallible(expr.else_block[0]) {
				return true
			}
			return false
		}
		BlockExpr {
			for e in expr.exprs {
				if is_expr_fallible(e) {
					return true
				}
			}
			return false
		}
		NotExpr { return is_expr_fallible(expr.expr[0]) }
		UnaryExpr { return is_expr_fallible(expr.expr[0]) }
		AbortExpr {
			if expr.message.len > 0 {
				return is_expr_fallible(expr.message[0])
			}
			return false
		}
		ReturnExpr {
			if expr.value.len > 0 {
				return is_expr_fallible(expr.value[0])
			}
			return false
		}
		IndexExpr {
			return is_expr_fallible(expr.expr[0]) || is_expr_fallible(expr.index[0])
		}
	}
}

// static_check performs compile-time analysis on a VRL AST.
// Returns an error if any static violation is found.
fn static_check(expr Expr) ! {
	sc_walk(expr, false)!
}

// sc_walk recursively walks the AST checking for static errors.
// `handled` is true when the current expression's errors are being caught
// (inside ?? LHS, ok/err value, or fn! args).
fn sc_walk(expr Expr, handled bool) ! {
	match expr {
		LiteralExpr {}
		IdentExpr {}
		PathExpr {}
		MetaPathExpr {}
		ClosureExpr {}
		BlockExpr {
			for e in expr.exprs {
				sc_walk(e, handled)!
			}
		}
		FnCallExpr {
			mut name := expr.name
			if name.len > 0 && name[name.len - 1] == `!` {
				// ! handles all errors from this call and its args
				name = name[..name.len - 1]
				for arg in expr.args {
					sc_walk(arg, true)!
				}
				// E122: check closure return type for replace_with
				if name == 'replace_with' && expr.closure.len > 0 {
					sc_check_closure_return_type(expr.closure[0], 'string')!
				}
				return
			}
			// E100: fallible function call without error handling
			if !handled && !is_fn_infallible(name) {
				return error('error[E100]: unhandled error')
			}
			// E122: check closure return type for replace_with
			if name == 'replace_with' && expr.closure.len > 0 {
				sc_check_closure_return_type(expr.closure[0], 'string')!
			}
			// Recurse into args
			for arg in expr.args {
				sc_walk(arg, handled)!
			}
		}
		BinaryExpr {
			sc_walk(expr.left[0], handled)!
			sc_walk(expr.right[0], handled)!
		}
		AssignExpr {
			// Assignment doesn't handle errors — value must be checked independently
			sc_walk(expr.value[0], false)!
		}
		MergeAssignExpr {
			sc_walk(expr.value[0], false)!
		}
		CoalesceExpr {
			// E651: unnecessary coalesce on infallible LHS
			if !is_expr_fallible(expr.expr[0]) {
				return error('error[E651]: unnecessary error coalescing operation')
			}
			// LHS errors are handled by ??
			sc_walk(expr.expr[0], true)!
			// RHS errors inherit parent context
			sc_walk(expr.default_[0], handled)!
		}
		OkErrAssignExpr {
			// E104: unnecessary error assignment on infallible value
			if !is_expr_fallible(expr.value[0]) {
				return error('error[E104]: unnecessary error assignment')
			}
			// Value errors are handled by ok/err
			sc_walk(expr.value[0], true)!
		}
		IfExpr {
			// E102: non-boolean literal as if condition
			cond := expr.condition[0]
			if cond is LiteralExpr {
				v := cond.value
				if v !is bool {
					return error('error[E102]: non-boolean predicate')
				}
			}
			sc_walk(expr.condition[0], handled)!
			if expr.then_block.len > 0 {
				sc_walk(expr.then_block[0], handled)!
			}
			if expr.else_block.len > 0 {
				sc_walk(expr.else_block[0], handled)!
			}
		}
		NotExpr {
			// E660: negation of non-boolean literal
			inner := expr.expr[0]
			if inner is LiteralExpr {
				v := inner.value
				if v !is bool {
					return error('error[E660]: non-boolean negation')
				}
			}
			sc_walk(inner, handled)!
		}
		AbortExpr {
			if expr.message.len > 0 {
				msg := expr.message[0]
				// E631: fallible abort message
				if is_expr_fallible(msg) {
					return error('error[E631]: unhandled fallible expression')
				}
				// E300: non-string abort message
				if sc_is_known_non_string(msg) {
					return error('error[E300]: non-string abort message')
				}
				sc_walk(msg, handled)!
			}
		}
		ReturnExpr {
			if expr.value.len > 0 {
				sc_walk(expr.value[0], handled)!
			}
		}
		UnaryExpr {
			sc_walk(expr.expr[0], handled)!
		}
		ArrayExpr {
			for item in expr.items {
				sc_walk(item, handled)!
			}
		}
		ObjectExpr {
			for pair in expr.pairs {
				sc_walk(pair.value, handled)!
			}
		}
		IndexExpr {
			sc_walk(expr.expr[0], handled)!
			sc_walk(expr.index[0], handled)!
		}
	}
}

// sc_check_closure_return_type checks if a closure's body returns the expected type.
// Used for replace_with (expects string return) and similar functions.
fn sc_check_closure_return_type(closure_expr Expr, expected_type string) ! {
	if closure_expr is ClosureExpr {
		if closure_expr.body.len > 0 {
			body := closure_expr.body[0]
			ret_type := sc_infer_simple_type(body)
			if ret_type.len > 0 && ret_type != expected_type {
				return error('error[E122]: type mismatch in closure return type, received: ${ret_type}, expected: ${expected_type}')
			}
		}
	}
}

// sc_infer_simple_type returns a simple type name for an expression if statically known.
// Returns empty string if the type cannot be determined.
fn sc_infer_simple_type(expr Expr) string {
	match expr {
		LiteralExpr {
			v := expr.value
			match v {
				string { return 'string' }
				i64 { return 'integer' }
				f64 { return 'float' }
				bool { return 'boolean' }
				VrlNull { return 'null' }
				else { return '' }
			}
		}
		FnCallExpr {
			mut name := expr.name
			if name.len > 0 && name[name.len - 1] == `!` {
				name = name[..name.len - 1]
			}
			// Functions with known return types
			match name {
				'to_int', 'int', 'strlen', 'length', 'to_unix_timestamp',
				'ip_aton', 'parse_int', 'random_int', 'parse_bytes' {
					return 'integer'
				}
				'to_float', 'float', 'parse_float', 'random_float',
				'shannon_entropy', 'parse_duration' {
					return 'float'
				}
				'to_bool', 'bool', 'is_string', 'is_integer', 'is_float',
				'is_boolean', 'is_null', 'is_array', 'is_object',
				'is_nullish', 'match', 'assert', 'assert_eq',
				'contains', 'starts_with', 'ends_with', 'is_empty' {
					return 'boolean'
				}
				'downcase', 'upcase', 'to_string', 'string',
				'strip_whitespace', 'trim', 'truncate', 'replace',
				'encode_json', 'join', 'encode_base64', 'decode_base64' {
					return 'string'
				}
				else { return '' }
			}
		}
		BlockExpr {
			if expr.exprs.len > 0 {
				return sc_infer_simple_type(expr.exprs[expr.exprs.len - 1])
			}
			return ''
		}
		else { return '' }
	}
}

// sc_is_known_non_string returns true if an expression is statically known
// to NOT resolve to a string type.
fn sc_is_known_non_string(expr Expr) bool {
	if expr is LiteralExpr {
		v := expr.value
		return v !is string
	}
	// Root path . is always an object
	if expr is PathExpr && expr.path == '.' {
		return true
	}
	// Array and object literals are non-string
	if expr is ArrayExpr || expr is ObjectExpr {
		return true
	}
	return false
}

// execute_checked compiles and runs a VRL program with static analysis.
// Returns compile-time errors before execution if any violations are found.
pub fn execute_checked(source string, obj map[string]VrlValue) !VrlValue {
	mut lex := new_lexer(source)
	tokens := lex.tokenize()
	if lex.errors.len > 0 {
		return error(lex.errors[0])
	}
	mut parser := new_parser(tokens)
	ast := parser.parse()!
	static_check(ast)!
	mut rt := new_runtime_with_object(obj)
	return rt.eval(ast)
}
