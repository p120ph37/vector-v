module vrl

// NOTE: JIT compilation via libtcc was explored and removed.
//
// A TCC-based JIT compiled VRL ASTs to C, then to native code at runtime.
// While the generated native code itself executed very fast, the overhead of
// translating between V data structures (maps, sum-type values) and C structs
// on every call dominated execution time. Even after eliminating JSON
// serialization and using a direct memory interface with typed setter/getter
// functions, the V↔C marshaling cost made JIT consistently slower than the
// tree-walking interpreter for typical workloads.
//
// The interpreter (with optimizations like fast single-segment path access,
// direct structural equality, byte-level operator dispatch, and inlined
// stdlib fast paths) already matches or beats the upstream Rust VRL
// implementation on most benchmarks when compiled with -prod -cc clang.
//
// Benchmark results (100K iterations, -prod -cc clang vs Rust --release):
//   field_assign:  V 255ns  vs Rust 197ns  (1.29x)
//   downcase:      V 259ns  vs Rust 319ns  (V wins 1.23x)
//   conditional:   V 423ns  vs Rust 561ns  (V wins 1.33x)
//   multi_ops:     V 633ns  vs Rust 932ns  (V wins 1.47x)
//   arithmetic:    V 714ns  vs Rust 943ns  (V wins 1.32x)
//
// The Runtime uses SmallMap (flat-array map) instead of V's built-in hash map.
// For typical Vector events (1-16 fields), linear scan beats hashing due to
// no hash computation and better cache locality — similar to how Rust's BTreeMap
// uses a single sorted node for small collections.

// Runtime evaluates VRL AST nodes against an object context.
// Uses SmallMap (flat-array map) instead of V's built-in hash map for the
// hot-path object/metadata/vars storage. For typical Vector events with 1-16
// fields, linear scan over contiguous memory is faster than hash lookup due
// to no hash computation and better cache locality. This is analogous to how
// Rust's BTreeMap stores small collections in a single sorted node.
pub struct Runtime {
mut:
	object   SmallMap // The root object (.)
	metadata SmallMap // Metadata (%)
	vars     SmallMap // Local variables
	aborted  bool
	abort_msg string
}

pub fn new_runtime() Runtime {
	return Runtime{
		object: new_small_map()
		metadata: new_small_map()
		vars: new_small_map()
	}
}

pub fn new_runtime_with_object(obj map[string]VrlValue) Runtime {
	return Runtime{
		object: small_map_from_map(obj)
		metadata: new_small_map()
		vars: new_small_map()
	}
}

// get_object returns the current root object as a standard map.
pub fn (rt &Runtime) get_object() map[string]VrlValue {
	return rt.object.to_map()
}

// execute compiles and runs a VRL program, returning the result.
pub fn execute(source string, obj map[string]VrlValue) !VrlValue {
	mut lex := new_lexer(source)
	tokens := lex.tokenize()
	mut parser := new_parser(tokens)
	ast := parser.parse()!
	mut rt := new_runtime_with_object(obj)
	return rt.eval(ast)
}

// eval evaluates an AST expression.
pub fn (mut rt Runtime) eval(expr Expr) !VrlValue {
	match expr {
		LiteralExpr {
			return expr.value
		}
		PathExpr {
			return rt.get_path(expr.path)
		}
		AssignExpr {
			val := rt.eval(expr.value[0])!
			rt.assign_to(expr.target[0], val)
			return val
		}
		BlockExpr {
			return rt.eval_block(expr)
		}
		FnCallExpr {
			return rt.eval_fn_call(expr)
		}
		BinaryExpr {
			return rt.eval_binary(expr)
		}
		IdentExpr {
			if val := rt.vars.get(expr.name) {
				return val
			}
			return VrlValue(VrlNull{})
		}
		IfExpr {
			return rt.eval_if(expr)
		}
		UnaryExpr {
			val := rt.eval(expr.expr[0])!
			if expr.op == '-' {
				return negate_value(val)
			}
			return val
		}
		NotExpr {
			val := rt.eval(expr.expr[0])!
			b := !is_truthy(val)
			return VrlValue(b)
		}
		ArrayExpr {
			return rt.eval_array(expr)
		}
		ObjectExpr {
			return rt.eval_object(expr)
		}
		MetaPathExpr {
			return rt.get_meta(expr.path)
		}
		MergeAssignExpr {
			val := rt.eval(expr.value[0])!
			rt.merge_assign(expr.target[0], val)
			return rt.eval(expr.target[0])
		}
		IndexExpr {
			container := rt.eval(expr.expr[0])!
			index := rt.eval(expr.index[0])!
			return index_into(container, index)
		}
		CoalesceExpr {
			return rt.eval_coalesce(expr)
		}
		AbortExpr {
			rt.aborted = true
			if expr.message.len > 0 {
				msg_val := rt.eval(expr.message[0])!
				rt.abort_msg = vrl_to_string(msg_val)
			}
			return VrlValue(VrlNull{})
		}
		ClosureExpr {
			return VrlValue(VrlNull{})
		}
	}
}

fn (mut rt Runtime) eval_array(expr ArrayExpr) !VrlValue {
	mut items := []VrlValue{}
	for item in expr.items {
		val := rt.eval(item)!
		items << val
	}
	return VrlValue(items)
}

fn (mut rt Runtime) eval_object(expr ObjectExpr) !VrlValue {
	mut obj := map[string]VrlValue{}
	for pair in expr.pairs {
		val := rt.eval(pair.value)!
		obj[pair.key] = val
	}
	return VrlValue(obj)
}

fn (mut rt Runtime) eval_if(expr IfExpr) !VrlValue {
	cond := rt.eval(expr.condition[0])!
	if is_truthy(cond) {
		return rt.eval(expr.then_block[0])
	}
	if expr.else_block.len > 0 {
		return rt.eval(expr.else_block[0])
	}
	return VrlValue(VrlNull{})
}

fn (mut rt Runtime) eval_block(expr BlockExpr) !VrlValue {
	mut result := VrlValue(VrlNull{})
	for e in expr.exprs {
		result = rt.eval(e)!
		if rt.aborted {
			return result
		}
	}
	return result
}

fn (mut rt Runtime) eval_coalesce(expr CoalesceExpr) !VrlValue {
	result := rt.eval(expr.expr[0]) or {
		return rt.eval(expr.default_[0])
	}
	if result is VrlNull {
		return rt.eval(expr.default_[0])
	}
	return result
}

fn (mut rt Runtime) eval_binary(expr BinaryExpr) !VrlValue {
	// Use first byte for fast operator dispatch
	op0 := expr.op[0]
	if op0 == `|` && expr.op.len == 2 {
		// ||
		left := rt.eval(expr.left[0])!
		if is_truthy(left) {
			return left
		}
		return rt.eval(expr.right[0])
	}
	if op0 == `&` && expr.op.len == 2 {
		// &&
		left := rt.eval(expr.left[0])!
		if !is_truthy(left) {
			return left
		}
		return rt.eval(expr.right[0])
	}

	left := rt.eval(expr.left[0])!
	right := rt.eval(expr.right[0])!

	match op0 {
		`+` { return arith_add(left, right) }
		`-` { return arith_sub(left, right) }
		`*` { return arith_mul(left, right) }
		`/` { return arith_div(left, right) }
		`%` { return arith_mod(left, right) }
		`=` {
			// ==
			return VrlValue(values_equal(left, right))
		}
		`!` {
			// !=
			return VrlValue(!values_equal(left, right))
		}
		`<` {
			if expr.op.len == 1 {
				return compare_values_lt(left, right)
			}
			// <=
			return compare_values_le(left, right)
		}
		`>` {
			if expr.op.len == 1 {
				return compare_values_gt(left, right)
			}
			// >=
			return compare_values_ge(left, right)
		}
		else {
			return error('unknown operator: ${expr.op}')
		}
	}
}

// Path access — avoids full object copy for simple lookups.
fn (rt &Runtime) get_path(path string) !VrlValue {
	if path == '.' {
		return VrlValue(rt.object.to_map())
	}
	clean := if path.starts_with('.') { path[1..] } else { path }

	// Fast path for single-segment (no dots) — most common case
	if !clean.contains('.') {
		if val := rt.object.get(clean) {
			return val
		}
		return VrlValue(VrlNull{})
	}

	// Multi-segment: first key from SmallMap, then traverse nested map[string]VrlValue
	parts := clean.split('.')
	if val := rt.object.get(parts[0]) {
		if parts.len == 1 {
			return val
		}
		mut current := val
		for i in 1 .. parts.len {
			cur := current
			match cur {
				map[string]VrlValue {
					if next := cur[parts[i]] {
						current = next
					} else {
						return VrlValue(VrlNull{})
					}
				}
				else {
					return VrlValue(VrlNull{})
				}
			}
		}
		return current
	}
	return VrlValue(VrlNull{})
}

fn (rt &Runtime) get_meta(path string) !VrlValue {
	if path == '%' {
		return VrlValue(rt.metadata.to_map())
	}
	clean := if path.starts_with('%') { path[1..] } else { path }
	if val := rt.metadata.get(clean) {
		return val
	}
	return VrlValue(VrlNull{})
}

// Assignment
fn (mut rt Runtime) assign_to(target Expr, val VrlValue) {
	match target {
		PathExpr {
			if target.path == '.' {
				v := val
				match v {
					map[string]VrlValue {
						rt.object = small_map_from_map(v)
					}
					else {}
				}
				return
			}
			clean := if target.path.starts_with('.') { target.path[1..] } else { target.path }
			// Fast path: single segment (no dot) — most common case
			if !clean.contains('.') {
				rt.object.set(clean, val)
				return
			}
			parts := clean.split('.')
			rt.set_nested_path(parts, val)
		}
		IdentExpr {
			rt.vars.set(target.name, val)
		}
		MetaPathExpr {
			if target.path == '%' {
				v := val
				match v {
					map[string]VrlValue {
						rt.metadata = small_map_from_map(v)
					}
					else {}
				}
				return
			}
			clean := if target.path.starts_with('%') { target.path[1..] } else { target.path }
			rt.metadata.set(clean, val)
		}
		else {}
	}
}

fn (mut rt Runtime) set_nested_path(parts []string, val VrlValue) {
	if parts.len <= 1 {
		if parts.len == 1 {
			rt.object.set(parts[0], val)
		}
		return
	}
	if parts.len == 2 {
		top := parts[0]
		if existing := rt.object.get(top) {
			e := existing
			match e {
				map[string]VrlValue {
					mut m := copy_map(e)
					m[parts[1]] = val
					rt.object.set(top, VrlValue(m))
					return
				}
				else {}
			}
		}
		mut m := map[string]VrlValue{}
		m[parts[1]] = val
		rt.object.set(top, VrlValue(m))
		return
	}
	// 3+ levels: build nested maps
	rt.set_deep_path(parts, val)
}

fn (mut rt Runtime) set_deep_path(parts []string, val VrlValue) {
	if parts.len == 0 {
		return
	}
	if parts.len == 1 {
		rt.object.set(parts[0], val)
		return
	}
	// Build from inside out
	mut current := val
	mut i := parts.len - 1
	for i >= 1 {
		mut m := map[string]VrlValue{}
		m[parts[i]] = current
		current = VrlValue(m)
		i--
	}
	rt.object.set(parts[0], current)
}

fn (mut rt Runtime) merge_assign(target Expr, val VrlValue) {
	if target is PathExpr {
		if target.path == '.' {
			v := val
			match v {
				map[string]VrlValue {
					for k, item in v {
						rt.object.set(k, item)
					}
				}
				else {}
			}
		}
	}
}

// Pure functions for arithmetic and comparison
fn arith_add(left VrlValue, right VrlValue) !VrlValue {
	l := left
	r := right
	match l {
		int {
			match r {
				int { return VrlValue(l + r) }
				f64 { return VrlValue(f64(l) + r) }
				else {}
			}
		}
		f64 {
			match r {
				int { return VrlValue(l + f64(r)) }
				f64 { return VrlValue(l + r) }
				else {}
			}
		}
		string {
			match r {
				string { return VrlValue(l + r) }
				else {}
			}
		}
		else {}
	}
	return error("can't add these types")
}

fn arith_sub(left VrlValue, right VrlValue) !VrlValue {
	l := left
	r := right
	match l {
		int {
			match r {
				int { return VrlValue(l - r) }
				f64 { return VrlValue(f64(l) - r) }
				else {}
			}
		}
		f64 {
			match r {
				int { return VrlValue(l - f64(r)) }
				f64 { return VrlValue(l - r) }
				else {}
			}
		}
		else {}
	}
	return error("can't subtract these types")
}

fn arith_mul(left VrlValue, right VrlValue) !VrlValue {
	l := left
	r := right
	match l {
		int {
			match r {
				int { return VrlValue(l * r) }
				f64 { return VrlValue(f64(l) * r) }
				else {}
			}
		}
		f64 {
			match r {
				int { return VrlValue(l * f64(r)) }
				f64 { return VrlValue(l * r) }
				else {}
			}
		}
		else {}
	}
	return error("can't multiply these types")
}

fn arith_div(left VrlValue, right VrlValue) !VrlValue {
	l := left
	r := right
	match l {
		int {
			match r {
				int {
					if r == 0 { return error('division by zero') }
					return VrlValue(l / r)
				}
				f64 {
					if r == 0.0 { return error('division by zero') }
					return VrlValue(f64(l) / r)
				}
				else {}
			}
		}
		f64 {
			match r {
				int {
					if r == 0 { return error('division by zero') }
					return VrlValue(l / f64(r))
				}
				f64 {
					if r == 0.0 { return error('division by zero') }
					return VrlValue(l / r)
				}
				else {}
			}
		}
		else {}
	}
	return error("can't divide these types")
}

fn arith_mod(left VrlValue, right VrlValue) !VrlValue {
	l := left
	r := right
	match l {
		int {
			match r {
				int {
					if r == 0 { return error('modulo by zero') }
					return VrlValue(l % r)
				}
				else {}
			}
		}
		else {}
	}
	return error("can't modulo these types")
}

fn negate_value(v VrlValue) !VrlValue {
	match v {
		int {
			neg := 0 - v
			return VrlValue(neg)
		}
		f64 {
			neg := 0.0 - v
			return VrlValue(neg)
		}
		else { return error("can't negate this type") }
	}
}

fn compare_values_lt(left VrlValue, right VrlValue) !VrlValue {
	l := left
	r := right
	match l {
		int {
			match r {
				int { return VrlValue(l < r) }
				f64 { return VrlValue(f64(l) < r) }
				else {}
			}
		}
		f64 {
			match r {
				int { return VrlValue(l < f64(r)) }
				f64 { return VrlValue(l < r) }
				else {}
			}
		}
		string {
			match r {
				string { return VrlValue(l < r) }
				else {}
			}
		}
		else {}
	}
	return error("can't compare these types")
}

fn compare_values_gt(left VrlValue, right VrlValue) !VrlValue {
	l := left
	r := right
	match l {
		int {
			match r {
				int { return VrlValue(l > r) }
				f64 { return VrlValue(f64(l) > r) }
				else {}
			}
		}
		f64 {
			match r {
				int { return VrlValue(l > f64(r)) }
				f64 { return VrlValue(l > r) }
				else {}
			}
		}
		string {
			match r {
				string { return VrlValue(l > r) }
				else {}
			}
		}
		else {}
	}
	return error("can't compare these types")
}

fn compare_values_le(left VrlValue, right VrlValue) !VrlValue {
	l := left
	r := right
	match l {
		int {
			match r {
				int { return VrlValue(l <= r) }
				f64 { return VrlValue(f64(l) <= r) }
				else {}
			}
		}
		f64 {
			match r {
				int { return VrlValue(l <= f64(r)) }
				f64 { return VrlValue(l <= r) }
				else {}
			}
		}
		string {
			match r {
				string { return VrlValue(l <= r) }
				else {}
			}
		}
		else {}
	}
	return error("can't compare these types")
}

fn compare_values_ge(left VrlValue, right VrlValue) !VrlValue {
	l := left
	r := right
	match l {
		int {
			match r {
				int { return VrlValue(l >= r) }
				f64 { return VrlValue(f64(l) >= r) }
				else {}
			}
		}
		f64 {
			match r {
				int { return VrlValue(l >= f64(r)) }
				f64 { return VrlValue(l >= r) }
				else {}
			}
		}
		string {
			match r {
				string { return VrlValue(l >= r) }
				else {}
			}
		}
		else {}
	}
	return error("can't compare these types")
}

fn index_into(container VrlValue, index VrlValue) !VrlValue {
	c := container
	i := index
	match c {
		[]VrlValue {
			match i {
				int {
					idx := if i < 0 { c.len + i } else { i }
					if idx >= 0 && idx < c.len {
						return c[idx]
					}
					return VrlValue(VrlNull{})
				}
				else {
					return VrlValue(VrlNull{})
				}
			}
		}
		map[string]VrlValue {
			match i {
				string {
					if v := c[i] {
						return v
					}
					return VrlValue(VrlNull{})
				}
				else {
					return VrlValue(VrlNull{})
				}
			}
		}
		else {
			return VrlValue(VrlNull{})
		}
	}
}

// copy_map manually copies a map to avoid issues with sum type maps.
fn copy_map(src map[string]VrlValue) map[string]VrlValue {
	mut dst := map[string]VrlValue{}
	for k, v in src {
		dst[k] = v
	}
	return dst
}
