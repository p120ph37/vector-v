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
	// E642: check parent path type mismatches (variable type tracking)
	mut var_types := map[string]string{} // var name -> simple type
	check_e642(expr, mut var_types)!
	// Check for unhandled fallible expressions after del() on array elements
	mut del_paths := map[string]bool{}
	check_del_fallibility(expr, mut del_paths)!
	// E900: unused variables and literals (warnings treated as errors)
	check_e900(expr)!
}

// check_e642 walks the AST tracking variable types and checking for
// assignments where the parent path resolves to an incompatible type.
// e.g., foo = "string"; foo.bar = {} → E642 (string has no fields)
// e.g., foo = "string"; foo[0] = [] → E642 (string is not an array)
fn check_e642(expr Expr, mut var_types map[string]string) ! {
	match expr {
		BlockExpr {
			for e in expr.exprs {
				check_e642(e, mut var_types)!
			}
		}
		AssignExpr {
			target := expr.target[0]
			value := expr.value[0]
			// Check if target is a compound path into a typed variable
			check_e642_target(target, var_types)!
			// Track the type of the assignment target
			e642_track_assign(target, value, mut var_types)
		}
		IfExpr {
			if expr.then_block.len > 0 {
				check_e642(expr.then_block[0], mut var_types)!
			}
			if expr.else_block.len > 0 {
				check_e642(expr.else_block[0], mut var_types)!
			}
		}
		else {}
	}
}

// check_e642_target checks if an assignment target's parent path has an incompatible type.
fn check_e642_target(target Expr, var_types map[string]string) ! {
	match target {
		IndexExpr {
			// Assignment like foo[0] = val or foo.bar = val
			// The parent is target.expr[0], the segment is target.index[0]
			parent := target.expr[0]
			idx := target.index[0]
			// Get the parent's type
			parent_type := e642_resolve_type(parent, var_types)
			if parent_type.len > 0 {
				// Check: indexing with integer into non-array
				if idx is LiteralExpr {
					iv := idx.value
					if iv is i64 {
						if parent_type != 'array' && parent_type != 'object' && parent_type != 'any' && parent_type != '' {
							return error('error[E642]: parent path segment rejects this mutation')
						}
					} else if iv is string {
						// Field access like foo.bar (parsed as IndexExpr with string literal)
						if parent_type != 'object' && parent_type != 'any' && parent_type != '' {
							return error('error[E642]: parent path segment rejects this mutation')
						}
					}
				}
			}
			// Also check nested: foo.bar.baz — recurse on parent
			check_e642_target(parent, var_types)!
		}
		PathExpr {
			path := target.path
			// Compound paths like .bar where . is known to be non-object
			if path != '.' && path.starts_with('.') {
				// Parent is root "."
				if root_type := var_types['.'] {
					if root_type != 'object' && root_type != 'any' && root_type != '' {
						return error('error[E642]: parent path segment rejects this mutation')
					}
					// If root IS an object, check nested fields
					// e.g., . = {"foo": true}; .foo.bar = "bar"
					// .foo is boolean, so .foo.bar should fail
					parts := path[1..].split('.')
					if parts.len > 1 {
						parent_path := '.${parts[0]}'
						if pt := var_types[parent_path] {
							if pt != 'object' && pt != 'any' && pt != '' {
								return error('error[E642]: parent path segment rejects this mutation')
							}
						}
					}
				}
			}
		}
		else {}
	}
}

// e642_resolve_type returns the known type of an expression from the variable tracking.
fn e642_resolve_type(expr Expr, var_types map[string]string) string {
	match expr {
		IdentExpr {
			return var_types[expr.name] or { '' }
		}
		PathExpr {
			return var_types[expr.path] or { '' }
		}
		IndexExpr {
			// Nested — the type is unknown unless we track deeply
			return ''
		}
		else { return '' }
	}
}

// e642_track_assign records the type of a variable after an assignment.
fn e642_track_assign(target Expr, value Expr, mut var_types map[string]string) {
	match target {
		IdentExpr {
			var_types[target.name] = sc_infer_simple_type(value)
		}
		PathExpr {
			t := sc_infer_simple_type(value)
			var_types[target.path] = t
			// If assigning to root and value is an object literal, track fields
			if target.path == '.' {
				if value is ObjectExpr {
					var_types['.'] = 'object'
					for pair in value.pairs {
						ft := sc_infer_simple_type(pair.value)
						if ft.len > 0 {
							var_types['.${pair.key}'] = ft
						}
					}
				}
			}
		}
		else {}
	}
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
				// E620: abort (!) on infallible function
				if is_fn_infallible(name) {
					return error("warning[E620]: can't abort infallible function")
				}
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
			// E122: check closure return type
			if expr.closure.len > 0 {
				if name == 'replace_with' {
					sc_check_closure_return_type(expr.closure[0], 'string')!
				} else if name == 'filter' {
					sc_check_closure_return_type(expr.closure[0], 'boolean')!
				}
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
// Used for replace_with (expects string return), filter (expects boolean), etc.
fn sc_check_closure_return_type(closure_expr Expr, expected_type string) ! {
	if closure_expr is ClosureExpr {
		if closure_expr.body.len > 0 {
			body := closure_expr.body[0]
			// Check the final expression type
			ret_type := sc_infer_simple_type(body)
			if ret_type.len > 0 && ret_type != expected_type {
				return error('error[E122]: type mismatch in closure return type, received: ${ret_type}, expected: ${expected_type}')
			}
			// Also check any return statements inside the body
			sc_check_return_types(body, expected_type)!
		}
	}
}

// sc_check_return_types walks a body looking for return statements with wrong types.
fn sc_check_return_types(expr Expr, expected_type string) ! {
	match expr {
		BlockExpr {
			for e in expr.exprs {
				sc_check_return_types(e, expected_type)!
			}
		}
		ReturnExpr {
			if expr.value.len > 0 {
				ret_type := sc_infer_simple_type(expr.value[0])
				if ret_type.len > 0 && ret_type != expected_type {
					return error('error[E122]: type mismatch in closure return type, received: ${ret_type}, expected: ${expected_type}')
				}
			}
		}
		IfExpr {
			if expr.then_block.len > 0 {
				sc_check_return_types(expr.then_block[0], expected_type)!
			}
			if expr.else_block.len > 0 {
				sc_check_return_types(expr.else_block[0], expected_type)!
			}
		}
		else {}
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
	return execute_checked_with_readonly(source, obj, []string{}, []string{}, []string{})
}

// execute_checked_with_readonly compiles and runs a VRL program with static analysis
// and read-only path enforcement.
pub fn execute_checked_with_readonly(source string, obj map[string]VrlValue, ro_paths []string, ro_rec_paths []string, ro_meta_paths []string) !VrlValue {
	mut lex := new_lexer(source)
	tokens := lex.tokenize()
	if lex.errors.len > 0 {
		return error(lex.errors[0])
	}
	mut parser := new_parser(tokens)
	ast := parser.parse()!
	static_check(ast)!
	if ro_paths.len > 0 || ro_rec_paths.len > 0 || ro_meta_paths.len > 0 {
		check_read_only(ast, ro_paths, ro_rec_paths, ro_meta_paths)!
	}
	mut rt := new_runtime_with_object(obj)
	return rt.eval(ast)
}

// check_read_only walks the AST and checks for assignments to read-only paths.
// Returns E315 if any read-only path is mutated.
fn check_read_only(expr Expr, ro_paths []string, ro_rec_paths []string, ro_meta_paths []string) ! {
	match expr {
		BlockExpr {
			for e in expr.exprs {
				check_read_only(e, ro_paths, ro_rec_paths, ro_meta_paths)!
			}
		}
		AssignExpr {
			check_read_only_target(expr.target[0], ro_paths, ro_rec_paths, ro_meta_paths)!
			check_read_only(expr.value[0], ro_paths, ro_rec_paths, ro_meta_paths)!
		}
		MergeAssignExpr {
			check_read_only_target(expr.target[0], ro_paths, ro_rec_paths, ro_meta_paths)!
			check_read_only(expr.value[0], ro_paths, ro_rec_paths, ro_meta_paths)!
		}
		OkErrAssignExpr {
			check_read_only_target(expr.ok_target[0], ro_paths, ro_rec_paths, ro_meta_paths)!
			check_read_only(expr.value[0], ro_paths, ro_rec_paths, ro_meta_paths)!
		}
		IfExpr {
			check_read_only(expr.condition[0], ro_paths, ro_rec_paths, ro_meta_paths)!
			if expr.then_block.len > 0 {
				check_read_only(expr.then_block[0], ro_paths, ro_rec_paths, ro_meta_paths)!
			}
			if expr.else_block.len > 0 {
				check_read_only(expr.else_block[0], ro_paths, ro_rec_paths, ro_meta_paths)!
			}
		}
		else {}
	}
}

// check_read_only_target checks if an assignment target is a read-only path.
fn check_read_only_target(target Expr, ro_paths []string, ro_rec_paths []string, ro_meta_paths []string) ! {
	match target {
		PathExpr {
			path := target.path
			// Root path "." — if any read-only path exists, root mutation is forbidden
			if path == '.' {
				if ro_paths.len > 0 || ro_rec_paths.len > 0 {
					return error('error[E315]: mutation of read-only value')
				}
			}
			// Check exact match against read_only paths
			for ro in ro_paths {
				if path == ro {
					return error('error[E315]: mutation of read-only value')
				}
			}
			// Check prefix match against read_only_recursive paths
			for ro in ro_rec_paths {
				if path == ro || path.starts_with('${ro}.') || path.starts_with('${ro}[') {
					return error('error[E315]: mutation of read-only value')
				}
			}
		}
		MetaPathExpr {
			// Normalize: strip leading % from path
			raw_path := target.path
			clean_path := if raw_path.starts_with('%') { raw_path[1..] } else { raw_path }
			for ro in ro_meta_paths {
				// Normalize: strip leading . or % from the read_only spec
				clean_ro := if ro.starts_with('.') { ro[1..] } else if ro.starts_with('%') { ro[1..] } else { ro }
				if clean_path == clean_ro {
					return error('error[E315]: mutation of read-only value')
				}
			}
		}
		IndexExpr {
			// For indexed assignments like foo[0], check the base
			check_read_only_target(target.expr[0], ro_paths, ro_rec_paths, ro_meta_paths)!
		}
		else {}
	}
}

// check_del_fallibility tracks del() calls on array-indexed paths and flags
// subsequent unhandled binary operations that use those paths as E100.
// After del(.arr[N]), .arr[M] could be out of bounds, making .arr[M] + X fallible.
fn check_del_fallibility(expr Expr, mut del_paths map[string]bool) ! {
	match expr {
		BlockExpr {
			for e in expr.exprs {
				check_del_fallibility(e, mut del_paths)!
			}
		}
		FnCallExpr {
			mut name := expr.name
			if name.len > 0 && name[name.len - 1] == `!` {
				name = name[..name.len - 1]
			}
			if name == 'del' && expr.args.len > 0 {
				// Track the base path of del'd array elements
				base := del_array_base_path(expr.args[0])
				if base.len > 0 {
					del_paths[base] = true
				}
			}
		}
		BinaryExpr {
			// Check if either operand accesses a del'd array path
			if expr.op == '+' || expr.op == '-' || expr.op == '*' {
				if uses_del_path(expr.left[0], del_paths) || uses_del_path(expr.right[0], del_paths) {
					return error('error[E100]: unhandled error')
				}
			}
			check_del_fallibility(expr.left[0], mut del_paths)!
			check_del_fallibility(expr.right[0], mut del_paths)!
		}
		AssignExpr {
			// Check the value side for del-affected expressions
			check_del_fallibility(expr.value[0], mut del_paths)!
		}
		IfExpr {
			if expr.then_block.len > 0 {
				check_del_fallibility(expr.then_block[0], mut del_paths)!
			}
			if expr.else_block.len > 0 {
				check_del_fallibility(expr.else_block[0], mut del_paths)!
			}
		}
		else {}
	}
}

// del_array_base_path extracts the base path from a del() argument like .onk[0].
// Returns the base path (e.g., ".onk") if the argument is an array-indexed path,
// or empty string otherwise.
fn del_array_base_path(expr Expr) string {
	match expr {
		PathExpr {
			// Path like .onk[0] — check if it contains array indexing
			p := expr.path
			bracket := p.index('[') or { return '' }
			if bracket > 0 {
				return p[..bracket]
			}
		}
		IndexExpr {
			// IndexExpr where index is numeric — base is expr.expr[0]
			if expr.expr.len > 0 {
				base_expr := expr.expr[0]
				if base_expr is PathExpr {
					return base_expr.path
				}
				if base_expr is IdentExpr {
					return base_expr.name
				}
			}
		}
		else {}
	}
	return ''
}

// uses_del_path checks if an expression accesses a path that was targeted by del().
fn uses_del_path(expr Expr, del_paths map[string]bool) bool {
	match expr {
		PathExpr {
			// Check if this path accesses a del'd array (e.g., .onk[1] when .onk was del'd)
			p := expr.path
			bracket := p.index('[') or { return false }
			if bracket > 0 {
				base := p[..bracket]
				return base in del_paths
			}
		}
		IndexExpr {
			if expr.expr.len > 0 {
				base_expr := expr.expr[0]
				if base_expr is PathExpr {
					return base_expr.path in del_paths
				}
				if base_expr is IdentExpr {
					return base_expr.name in del_paths
				}
			}
		}
		else {}
	}
	return false
}

// check_e900 detects unused literals and unused variable assignments in non-final
// position of a block. E900 is a warning in upstream, but we treat it as error
// for conformance.
fn check_e900(expr Expr) ! {
	match expr {
		BlockExpr {
			for i, e in expr.exprs {
				if i < expr.exprs.len - 1 {
					// Non-final expression: check if it's a pure literal (no side effects)
					if e is LiteralExpr {
						return error('warning[E900]: unused expression')
					}
					// Check if it's a variable-only assignment (not path assignment)
					if e is AssignExpr {
						target := e.target[0]
						if target is IdentExpr {
							// Local variable assignment — check if var is used later
							vname := target.name
							mut used := false
							for j in (i + 1) .. expr.exprs.len {
								if sc_expr_uses_var(expr.exprs[j], vname) {
									used = true
									break
								}
							}
							if !used {
								return error('warning[E900]: unused variable')
							}
						}
					}
				}
				// Recurse into sub-expressions
				check_e900(e)!
			}
		}
		IfExpr {
			if expr.then_block.len > 0 {
				check_e900(expr.then_block[0])!
			}
			if expr.else_block.len > 0 {
				check_e900(expr.else_block[0])!
			}
		}
		else {}
	}
}

// sc_expr_uses_var checks if an expression references a given variable name.
fn sc_expr_uses_var(expr Expr, name string) bool {
	match expr {
		IdentExpr { return expr.name == name }
		BlockExpr {
			for e in expr.exprs {
				if sc_expr_uses_var(e, name) { return true }
			}
		}
		FnCallExpr {
			for arg in expr.args {
				if sc_expr_uses_var(arg, name) { return true }
			}
			if expr.closure.len > 0 && sc_expr_uses_var(expr.closure[0], name) { return true }
		}
		BinaryExpr {
			return sc_expr_uses_var(expr.left[0], name) || sc_expr_uses_var(expr.right[0], name)
		}
		AssignExpr {
			return sc_expr_uses_var(expr.value[0], name)
		}
		IfExpr {
			if sc_expr_uses_var(expr.condition[0], name) { return true }
			if expr.then_block.len > 0 && sc_expr_uses_var(expr.then_block[0], name) { return true }
			if expr.else_block.len > 0 && sc_expr_uses_var(expr.else_block[0], name) { return true }
		}
		CoalesceExpr {
			return sc_expr_uses_var(expr.expr[0], name) || sc_expr_uses_var(expr.default_[0], name)
		}
		NotExpr { return sc_expr_uses_var(expr.expr[0], name) }
		UnaryExpr { return sc_expr_uses_var(expr.expr[0], name) }
		IndexExpr {
			return sc_expr_uses_var(expr.expr[0], name) || sc_expr_uses_var(expr.index[0], name)
		}
		ArrayExpr {
			for item in expr.items {
				if sc_expr_uses_var(item, name) { return true }
			}
		}
		ObjectExpr {
			for pair in expr.pairs {
				if sc_expr_uses_var(pair.value, name) { return true }
			}
		}
		ClosureExpr {
			if expr.body.len > 0 { return sc_expr_uses_var(expr.body[0], name) }
		}
		ReturnExpr {
			if expr.value.len > 0 { return sc_expr_uses_var(expr.value[0], name) }
		}
		AbortExpr {
			if expr.message.len > 0 { return sc_expr_uses_var(expr.message[0], name) }
		}
		OkErrAssignExpr {
			return sc_expr_uses_var(expr.value[0], name)
		}
		MergeAssignExpr {
			return sc_expr_uses_var(expr.value[0], name)
		}
		else { return false }
	}
	return false
}
