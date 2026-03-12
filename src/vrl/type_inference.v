module vrl

// Type inference for VRL type_def() function.
//
// type_def() returns static type information about expressions, tracking
// possible types across all execution paths (branches, short-circuits).
// This is compile-time analysis, not runtime type inspection.

// Helper constructors for common type ObjectMaps.
fn never_type() ObjectMap {
	mut m := new_object_map()
	m.set('never', VrlValue(true))
	return m
}

fn null_type() ObjectMap {
	mut m := new_object_map()
	m.set('null', VrlValue(true))
	return m
}

fn boolean_type() ObjectMap {
	mut m := new_object_map()
	m.set('boolean', VrlValue(true))
	return m
}

fn bytes_type() ObjectMap {
	mut m := new_object_map()
	m.set('bytes', VrlValue(true))
	return m
}

fn integer_type() ObjectMap {
	mut m := new_object_map()
	m.set('integer', VrlValue(true))
	return m
}

fn float_type() ObjectMap {
	mut m := new_object_map()
	m.set('float', VrlValue(true))
	return m
}

fn any_type() ObjectMap {
	mut m := new_object_map()
	m.set('any', VrlValue(true))
	return m
}

fn undefined_type() ObjectMap {
	mut m := new_object_map()
	m.set('undefined', VrlValue(true))
	return m
}

fn is_never(t ObjectMap) bool {
	return t.len() == 1 && (t.get('never') or { return false }) == VrlValue(true)
}

// type_from_value returns the type ObjectMap for a runtime value.
fn type_from_value(v VrlValue) ObjectMap {
	mut m := new_object_map()
	a := v
	match a {
		string { m.set('bytes', VrlValue(true)) }
		int { m.set('integer', VrlValue(true)) }
		f64 { m.set('float', VrlValue(true)) }
		bool { m.set('boolean', VrlValue(true)) }
		VrlNull { m.set('null', VrlValue(true)) }
		[]VrlValue {
			mut inner := new_object_map()
			for i, item in a {
				inner.set('${i}', VrlValue(type_from_value(item)))
			}
			m.set('array', VrlValue(inner))
		}
		ObjectMap {
			mut inner := new_object_map()
			for k in a.keys() {
				val := a.get(k) or { VrlValue(VrlNull{}) }
				inner.set(k, VrlValue(type_from_value(val)))
			}
			m.set('object', VrlValue(inner))
		}
		Timestamp { m.set('timestamp', VrlValue(true)) }
		VrlRegex { m.set('regex', VrlValue(true)) }
	}
	return m
}

// type_union merges two type ObjectMaps, combining all possible types.
fn type_union(a ObjectMap, b ObjectMap) ObjectMap {
	mut result := a.clone_map()
	for k in b.keys() {
		bval := b.get(k) or { continue }
		if existing := result.get(k) {
			// Both have this key - if both ObjectMaps, merge recursively
			e := existing
			bv := bval
			match e {
				ObjectMap {
					match bv {
						ObjectMap {
							result.set(k, VrlValue(type_union(e, bv)))
							continue
						}
						else {}
					}
				}
				else {}
			}
			// Otherwise keep existing (both are `true`)
		} else {
			result.set(k, bval)
		}
	}
	return result
}

// type_union_if is like type_union but treats object fields from different
// branches with "undefined" awareness (fields missing in one branch get "undefined").
fn type_union_if(a ObjectMap, b ObjectMap) ObjectMap {
	mut result := a.clone_map()
	for k in b.keys() {
		bval := b.get(k) or { continue }
		if existing := result.get(k) {
			e := existing
			bv := bval
			match e {
				ObjectMap {
					match bv {
						ObjectMap {
							if k == 'object' {
								result.set(k, VrlValue(type_union_object_fields(e, bv)))
							} else {
								result.set(k, VrlValue(type_union_if(e, bv)))
							}
							continue
						}
						else {}
					}
				}
				else {}
			}
		} else {
			result.set(k, bval)
		}
	}
	return result
}

// type_union_object_fields merges two object inner type maps.
// Fields missing in one side get "undefined" added to their type.
fn type_union_object_fields(a ObjectMap, b ObjectMap) ObjectMap {
	mut result := new_object_map()

	// Fields in a
	for k in a.keys() {
		aval := a.get(k) or { continue }
		if bval := b.get(k) {
			// In both: regular union of field types
			av := aval
			bv := bval
			match av {
				ObjectMap {
					match bv {
						ObjectMap {
							result.set(k, VrlValue(type_union(av, bv)))
							continue
						}
						else {}
					}
				}
				else {}
			}
			result.set(k, aval)
		} else {
			// Only in a: add undefined
			av := aval
			match av {
				ObjectMap {
					result.set(k, VrlValue(type_union(av, undefined_type())))
				}
				else {
					result.set(k, aval)
				}
			}
		}
	}

	// Fields only in b
	for k in b.keys() {
		if _ := a.get(k) {
			continue
		}
		bval := b.get(k) or { continue }
		bv := bval
		match bv {
			ObjectMap {
				result.set(k, VrlValue(type_union(bv, undefined_type())))
			}
			else {
				result.set(k, bval)
			}
		}
	}

	return result
}

// is_literal_bool checks if an expression is a literal boolean and returns its value.
fn is_literal_bool(expr Expr) (bool, bool) {
	match expr {
		LiteralExpr {
			v := expr.value
			match v {
				bool { return true, v }
				else { return false, false }
			}
		}
		else { return false, false }
	}
}

// is_literal_null checks if an expression is a literal null.
fn is_literal_null(expr Expr) bool {
	match expr {
		LiteralExpr {
			return expr.value is VrlNull
		}
		else { return false }
	}
}

// TypeEnv holds the type environment for static analysis.
struct TypeEnv {
mut:
	vars       map[string]ObjectMap // variable name -> possible types
	paths      map[string]ObjectMap // path (e.g. ".x") -> possible types
	meta_paths map[string]ObjectMap // metadata path (e.g. "foo") -> possible types
}

fn new_type_env() TypeEnv {
	return TypeEnv{
		vars:       map[string]ObjectMap{}
		paths:      map[string]ObjectMap{}
		meta_paths: map[string]ObjectMap{}
	}
}

fn (env &TypeEnv) clone() TypeEnv {
	return TypeEnv{
		vars:       env.vars.clone()
		paths:      env.paths.clone()
		meta_paths: env.meta_paths.clone()
	}
}

// infer_type performs static type inference on an expression.
// This is the main entry point called by type_def().
fn (rt &Runtime) infer_type(expr Expr) ObjectMap {
	mut env := TypeEnv{
		vars:  rt.type_vars.clone()
		paths: rt.type_paths.clone()
	}
	return infer_expr_type(expr, mut env)
}

// infer_expr_type infers the type of an expression, updating env with any assignments.
fn infer_expr_type(expr Expr, mut env TypeEnv) ObjectMap {
	match expr {
		LiteralExpr {
			return type_from_value(expr.value)
		}
		IdentExpr {
			if td := env.vars[expr.name] {
				return td
			}
			// Unknown variable - could be anything
			return any_type()
		}
		PathExpr {
			if expr.path == '.' {
				// Root object type
				if td := env.paths['.'] {
					return td
				}
				return any_type()
			}
			clean := if expr.path.starts_with('.') { expr.path[1..] } else { expr.path }
			if td := env.paths[clean] {
				return td
			}
			// Unknown path - could be anything
			return any_type()
		}
		MetaPathExpr {
			if expr.path == '%' {
				// Root metadata - build type from all tracked meta paths
				if td := env.meta_paths['%'] {
					return td
				}
				// Build object type from individual meta path entries
				mut has_keys := false
				mut inner := new_object_map()
				for k, v in env.meta_paths {
					if k != '%' {
						inner.set(k, VrlValue(v))
						has_keys = true
					}
				}
				if has_keys {
					mut m := new_object_map()
					m.set('object', VrlValue(inner))
					return m
				}
				return any_type()
			}
			clean := if expr.path.starts_with('%') { expr.path[1..] } else { expr.path }
			if td := env.meta_paths[clean] {
				return td
			}
			return any_type()
		}
		BlockExpr {
			return infer_block_type(expr, mut env)
		}
		IfExpr {
			return infer_if_type(expr, mut env)
		}
		BinaryExpr {
			return infer_binary_type(expr, mut env)
		}
		AbortExpr {
			return never_type()
		}
		ReturnExpr {
			return never_type()
		}
		FnCallExpr {
			return infer_fn_call_type(expr, mut env)
		}
		ArrayExpr {
			mut inner := new_object_map()
			for i, item in expr.items {
				inner.set('${i}', VrlValue(infer_expr_type(item, mut env)))
			}
			mut m := new_object_map()
			m.set('array', VrlValue(inner))
			return m
		}
		ObjectExpr {
			mut inner := new_object_map()
			for pair in expr.pairs {
				inner.set(pair.key, VrlValue(infer_expr_type(pair.value, mut env)))
			}
			mut m := new_object_map()
			m.set('object', VrlValue(inner))
			return m
		}
		AssignExpr {
			val_type := infer_expr_type(expr.value[0], mut env)
			apply_assign_type(expr.target[0], val_type, mut env)
			return val_type
		}
		IndexExpr {
			container_type := infer_expr_type(expr.expr[0], mut env)
			// Indexing into a known array: check if index is in bounds
			arr_inner := container_type.get('array') or {
				return undefined_type()
			}
			idx_expr := expr.index[0]
			match idx_expr {
				LiteralExpr {
					iv := idx_expr.value
					match iv {
						int {
							ai := arr_inner
							match ai {
								ObjectMap {
									elem := ai.get('${iv}') or {
										return undefined_type()
									}
									e := elem
									match e {
										ObjectMap { return e }
										else { return undefined_type() }
									}
								}
								else {}
							}
						}
						else {}
					}
				}
				else {}
			}
			return undefined_type()
		}
		CoalesceExpr {
			left := infer_expr_type(expr.expr[0], mut env)
			right := infer_expr_type(expr.default_[0], mut env)
			return type_union(left, right)
		}
		UnaryExpr {
			return infer_expr_type(expr.expr[0], mut env)
		}
		NotExpr {
			return boolean_type()
		}
		MergeAssignExpr {
			return infer_expr_type(expr.value[0], mut env)
		}
		OkErrAssignExpr {
			val_type := infer_expr_type(expr.value[0], mut env)
			// ok target gets the value type, err target gets string
			apply_assign_type(expr.ok_target[0], val_type, mut env)
			apply_assign_type(expr.err_target[0], bytes_type(), mut env)
			return val_type
		}
		ClosureExpr {
			return any_type()
		}
	}
}

// apply_assign_type updates the type environment for an assignment target.
fn apply_assign_type(target Expr, val_type ObjectMap, mut env TypeEnv) {
	match target {
		IdentExpr {
			env.vars[target.name] = val_type
		}
		PathExpr {
			if target.path == '.' {
				env.paths['.'] = val_type
			} else {
				clean := if target.path.starts_with('.') { target.path[1..] } else { target.path }
				env.paths[clean] = val_type
			}
		}
		MetaPathExpr {
			if target.path == '%' {
				env.meta_paths['%'] = val_type
			} else {
				clean := if target.path.starts_with('%') { target.path[1..] } else { target.path }
				env.meta_paths[clean] = val_type
			}
		}
		IndexExpr {
			// Nested assignment like err.foo.bar — ignore for type tracking
		}
		else {}
	}
}

// infer_block_type infers the type of a block expression.
// After abort/return, code is unreachable but still analyzed for type info.
fn infer_block_type(block BlockExpr, mut env TypeEnv) ObjectMap {
	if block.exprs.len == 0 {
		return null_type()
	}
	mut last := null_type()
	mut hit_never := false
	for e in block.exprs {
		t := infer_expr_type(e, mut env)
		if hit_never {
			// Code after abort/return: use this type instead of "never"
			last = t
			hit_never = is_never(t)
		} else if is_never(t) {
			last = t
			hit_never = true
		} else {
			last = t
		}
	}
	return last
}

// infer_if_type infers the type of an if expression, handling union types.
fn infer_if_type(expr IfExpr, mut env TypeEnv) ObjectMap {
	// Analyze condition (may have side effects on env)
	_ = infer_expr_type(expr.condition[0], mut env)

	// Clone env for each branch
	mut then_env := env.clone()
	mut else_env := env.clone()

	// Infer then-branch type
	mut then_type := null_type()
	if expr.then_block.len > 0 {
		then_type = infer_expr_type(expr.then_block[0], mut then_env)
	}

	// Infer else-branch type (null if no else)
	mut else_type := null_type()
	if expr.else_block.len > 0 {
		else_type = infer_expr_type(expr.else_block[0], mut else_env)
	}

	// Merge variable types from both branches
	merge_branch_envs(mut env, then_env, else_env)

	// Result type is union of both branches, handling never
	if is_never(then_type) && is_never(else_type) {
		return never_type()
	}
	if is_never(then_type) {
		return else_type
	}
	if is_never(else_type) {
		return then_type
	}
	return type_union_if(then_type, else_type)
}

// merge_branch_envs merges variable types from two branches into the parent env.
// Variables assigned in only one branch get their type unioned with the pre-branch type.
fn merge_branch_envs(mut env TypeEnv, then_env TypeEnv, else_env TypeEnv) {
	// Collect all variable names from both branches
	mut all_vars := map[string]bool{}
	for k, _ in then_env.vars {
		all_vars[k] = true
	}
	for k, _ in else_env.vars {
		all_vars[k] = true
	}

	for v, _ in all_vars {
		then_t := then_env.vars[v] or {
			// Not in then-branch, use pre-branch type
			env.vars[v] or { continue }
		}
		else_t := else_env.vars[v] or {
			// Not in else-branch, use pre-branch type
			env.vars[v] or { continue }
		}
		env.vars[v] = type_union(then_t, else_t)
	}

	// Same for paths
	mut all_paths := map[string]bool{}
	for k, _ in then_env.paths {
		all_paths[k] = true
	}
	for k, _ in else_env.paths {
		all_paths[k] = true
	}

	for p, _ in all_paths {
		in_then := then_env.paths[p] or { new_object_map() }
		in_else := else_env.paths[p] or { new_object_map() }
		had_before := p in env.paths

		then_t := if in_then.len() > 0 {
			in_then
		} else if had_before {
			env.paths[p] or { new_object_map() }
		} else {
			undefined_type()
		}
		else_t := if in_else.len() > 0 {
			in_else
		} else if had_before {
			env.paths[p] or { new_object_map() }
		} else {
			undefined_type()
		}
		env.paths[p] = type_union(then_t, else_t)
	}
}

// infer_binary_type infers the type of a binary expression.
fn infer_binary_type(expr BinaryExpr, mut env TypeEnv) ObjectMap {
	op0 := expr.op[0]

	// Logical AND: always returns boolean
	if op0 == `&` && expr.op.len == 2 {
		is_lit, lit_val := is_literal_bool(expr.left[0])
		if is_lit && !lit_val {
			// false && RHS: RHS never executes
			// Don't analyze RHS for env changes
		} else if is_lit && lit_val {
			// true && RHS: RHS always executes
			_ = infer_expr_type(expr.right[0], mut env)
		} else {
			// Unknown && RHS: RHS conditionally executes
			mut rhs_env := env.clone()
			_ = infer_expr_type(expr.right[0], mut rhs_env)
			// Union any variable changes from RHS
			for k, v in rhs_env.vars {
				if pre := env.vars[k] {
					env.vars[k] = type_union(pre, v)
				} else {
					env.vars[k] = v
				}
			}
		}
		return boolean_type()
	}

	// Logical OR: returns LHS if truthy, else RHS
	if op0 == `|` && expr.op.len == 2 {
		left_type := infer_expr_type(expr.left[0], mut env)
		right_type := infer_expr_type(expr.right[0], mut env)

		is_lit, lit_val := is_literal_bool(expr.left[0])
		is_null_lit := is_literal_null(expr.left[0])

		if is_lit && lit_val {
			// true || RHS: RHS never executes, returns LHS
			return left_type
		}
		if (is_lit && !lit_val) || is_null_lit {
			// false/null || RHS: RHS always executes, returns RHS
			// Also update env with RHS side effects
			_ = infer_expr_type(expr.right[0], mut env)
			return right_type
		}
		// Unknown || RHS: RHS conditionally executes
		mut rhs_env := env.clone()
		_ = infer_expr_type(expr.right[0], mut rhs_env)
		for k, v in rhs_env.vars {
			if pre := env.vars[k] {
				env.vars[k] = type_union(pre, v)
			} else {
				env.vars[k] = v
			}
		}
		return type_union(left_type, right_type)
	}

	// Object merge |
	if op0 == `|` && expr.op.len == 1 {
		left := infer_expr_type(expr.left[0], mut env)
		right := infer_expr_type(expr.right[0], mut env)
		// If one side is "never" (abort/return), use the other side's type
		if is_never(right) {
			return left
		}
		if is_never(left) {
			return right
		}
		return type_union(left, right)
	}

	// Error coalesce ??
	if expr.op == '??' {
		left := infer_expr_type(expr.left[0], mut env)
		right := infer_expr_type(expr.right[0], mut env)
		// Remove null from left, union with right
		mut result := new_object_map()
		for k in left.keys() {
			if k != 'null' {
				val := left.get(k) or { continue }
				result.set(k, val)
			}
		}
		return type_union(result, right)
	}

	// Comparison operators return boolean
	if op0 == `=` || op0 == `!` || op0 == `<` || op0 == `>` {
		return boolean_type()
	}

	// Arithmetic - infer from operands
	left := infer_expr_type(expr.left[0], mut env)
	right := infer_expr_type(expr.right[0], mut env)
	_ = right
	if op0 == `/` {
		return float_type()
	}
	return left
}

// infer_fn_call_type infers the return type of a function call.
fn infer_fn_call_type(expr FnCallExpr, mut env TypeEnv) ObjectMap {
	mut name := expr.name
	if name.len > 0 && name[name.len - 1] == `!` {
		name = name[..name.len - 1]
	}

	// Special: type_def itself - recursive type_def shouldn't happen normally
	if name == 'type_def' {
		if expr.args.len > 0 {
			return infer_expr_type(expr.args[0], mut env)
		}
		return any_type()
	}

	// Functions with known return types
	match name {
		'downcase', 'upcase', 'to_string', 'string', 'strip_whitespace',
		'truncate', 'trim', 'replace', 'join', 'encode_json', 'uuid_v4', 'now' {
			return bytes_type()
		}
		'contains', 'starts_with', 'ends_with' {
			return boolean_type()
		}
		'slice' {
			// slice returns the same type as its first argument
			if expr.args.len > 0 {
				return infer_expr_type(expr.args[0], mut env)
			}
			return any_type()
		}
		'to_int', 'int', 'strlen', 'length', 'to_unix_timestamp' {
			return integer_type()
		}
		'to_float', 'float' {
			return float_type()
		}
		'to_bool', 'bool', 'is_string', 'is_integer', 'is_float',
		'is_boolean', 'is_null', 'is_array', 'is_object',
		'is_nullish', 'match', 'assert', 'assert_eq' {
			return boolean_type()
		}
		'push', 'append', 'flatten', 'compact', 'unique', 'filter',
		'map_values', 'map_keys', 'keys', 'values', 'split' {
			// For push on unknown array, return special type
			if name == 'push' && expr.args.len > 0 {
				arg_type := infer_expr_type(expr.args[0], mut env)
				// If first arg is any_type (unknown path), return unknown array type
				if _ := arg_type.get('any') {
					mut m := new_object_map()
					m.set('array', VrlValue(new_object_map()))
					m.set('array_unknown_infinite', VrlValue(any_type()))
					return m
				}
			}
			mut m := new_object_map()
			m.set('array', VrlValue(new_object_map()))
			return m
		}
		'merge' {
			mut m := new_object_map()
			m.set('object', VrlValue(new_object_map()))
			return m
		}
		'del' {
			// del returns the deleted value - infer from path argument
			if expr.args.len > 0 {
				return infer_expr_type(expr.args[0], mut env)
			}
			return any_type()
		}
		'to_timestamp' {
			mut m := new_object_map()
			m.set('timestamp', VrlValue(true))
			return m
		}
		'type_of' {
			return bytes_type()
		}
		'parse_json' {
			return any_type()
		}
		else {
			// Unknown function, evaluate args for side effects
			for arg in expr.args {
				_ = infer_expr_type(arg, mut env)
			}
			return any_type()
		}
	}
}

// collect_path_assignments collects path assignments from an expression
// and returns them with "undefined" added to each type.
// Used for conditional_assignment where paths assigned in only one branch
// are marked as potentially undefined.
fn collect_path_assignments(expr Expr) map[string]ObjectMap {
	mut result := map[string]ObjectMap{}
	match expr {
		AssignExpr {
			target := expr.target[0]
			match target {
				PathExpr {
					clean := if target.path.starts_with('.') {
						target.path[1..]
					} else {
						target.path
					}
					if clean.len > 0 {
						result[clean] = new_object_map()
					}
				}
				else {}
			}
		}
		BlockExpr {
			for e in expr.exprs {
				sub := collect_path_assignments(e)
				for k, v in sub {
					result[k] = v
				}
			}
		}
		IfExpr {
			if expr.then_block.len > 0 {
				sub := collect_path_assignments(expr.then_block[0])
				for k, v in sub {
					result[k] = v
				}
			}
			if expr.else_block.len > 0 {
				sub := collect_path_assignments(expr.else_block[0])
				for k, v in sub {
					result[k] = v
				}
			}
		}
		else {}
	}
	return result
}

// update_type_vars_for_if_saved updates the runtime type tracking for an if-statement.
// Uses the saved pre-if type state as the base for analysis, so that branch execution's
// track_assign_type doesn't overwrite the union types.
fn (mut rt Runtime) update_type_vars_for_if_saved(expr IfExpr, saved_vars map[string]ObjectMap, saved_paths map[string]ObjectMap) {
	// Create environments for both branches starting from pre-if state
	mut then_env := TypeEnv{
		vars:  saved_vars.clone()
		paths: saved_paths.clone()
	}
	mut else_env := TypeEnv{
		vars:  saved_vars.clone()
		paths: saved_paths.clone()
	}

	// Analyze both branches
	if expr.then_block.len > 0 {
		_ = infer_expr_type(expr.then_block[0], mut then_env)
	}
	if expr.else_block.len > 0 {
		_ = infer_expr_type(expr.else_block[0], mut else_env)
	}

	// Merge variable types
	mut all_vars := map[string]bool{}
	for k, _ in then_env.vars {
		all_vars[k] = true
	}
	for k, _ in else_env.vars {
		all_vars[k] = true
	}

	for v, _ in all_vars {
		then_t := then_env.vars[v] or {
			saved_vars[v] or { continue }
		}
		else_t := else_env.vars[v] or {
			saved_vars[v] or { continue }
		}
		rt.type_vars[v] = type_union(then_t, else_t)
	}

	// Merge path types
	mut all_paths := map[string]bool{}
	for k, _ in then_env.paths {
		all_paths[k] = true
	}
	for k, _ in else_env.paths {
		all_paths[k] = true
	}

	for p, _ in all_paths {
		// Check if this path was newly assigned in only one branch
		in_then := then_env.paths[p] or { new_object_map() }
		in_else := else_env.paths[p] or { new_object_map() }
		had_before := p in saved_paths

		then_t := if in_then.len() > 0 {
			in_then
		} else if had_before {
			saved_paths[p] or { new_object_map() }
		} else {
			undefined_type()
		}
		else_t := if in_else.len() > 0 {
			in_else
		} else if had_before {
			saved_paths[p] or { new_object_map() }
		} else {
			undefined_type()
		}
		rt.type_paths[p] = type_union(then_t, else_t)
	}
}

// update_type_vars_for_binary_saved updates type tracking for && and || operators.
// Uses saved pre-eval type state as the base.
fn (mut rt Runtime) update_type_vars_for_binary_saved(expr BinaryExpr, saved_vars map[string]ObjectMap, saved_paths map[string]ObjectMap) {
	op0 := expr.op[0]

	if op0 == `&` && expr.op.len == 2 {
		// &&
		is_lit, lit_val := is_literal_bool(expr.left[0])
		if is_lit && !lit_val {
			// false && RHS: RHS never executes, no type changes
			return
		}
		if is_lit && lit_val {
			// true && RHS: RHS always executes
			mut rhs_env := TypeEnv{
				vars:  saved_vars.clone()
				paths: saved_paths.clone()
			}
			_ = infer_expr_type(expr.right[0], mut rhs_env)
			rt.type_vars = rhs_env.vars.clone()
			rt.type_paths = rhs_env.paths.clone()
			return
		}
		// Unknown && RHS: RHS conditionally executes
		mut rhs_env := TypeEnv{
			vars:  saved_vars.clone()
			paths: saved_paths.clone()
		}
		_ = infer_expr_type(expr.right[0], mut rhs_env)
		for k, v in rhs_env.vars {
			if pre := saved_vars[k] {
				rt.type_vars[k] = type_union(pre, v)
			} else {
				rt.type_vars[k] = v
			}
		}
	}

	if op0 == `|` && expr.op.len == 2 {
		// ||
		is_lit, lit_val := is_literal_bool(expr.left[0])
		if is_lit && lit_val {
			// true || RHS: RHS never executes, no type changes
			return
		}
		if is_lit && !lit_val {
			// false || RHS: RHS always executes
			mut rhs_env := TypeEnv{
				vars:  saved_vars.clone()
				paths: saved_paths.clone()
			}
			_ = infer_expr_type(expr.right[0], mut rhs_env)
			rt.type_vars = rhs_env.vars.clone()
			rt.type_paths = rhs_env.paths.clone()
			return
		}
		// Unknown || RHS: RHS conditionally executes
		mut rhs_env := TypeEnv{
			vars:  saved_vars.clone()
			paths: saved_paths.clone()
		}
		_ = infer_expr_type(expr.right[0], mut rhs_env)
		for k, v in rhs_env.vars {
			if pre := saved_vars[k] {
				rt.type_vars[k] = type_union(pre, v)
			} else {
				rt.type_vars[k] = v
			}
		}
	}
}
