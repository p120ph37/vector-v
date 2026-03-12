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
// The Runtime uses ObjectMap (flat-array map) instead of V's built-in hash map.
// For typical Vector events (1-16 fields), linear scan beats hashing due to
// no hash computation and better cache locality — similar to how Rust's BTreeMap
// uses a single sorted node for small collections.

// Runtime evaluates VRL AST nodes against an object context.
// Uses ObjectMap (flat-array map) instead of V's built-in hash map for the
// hot-path object/metadata/vars storage. For typical Vector events with 1-16
// fields, linear scan over contiguous memory is faster than hash lookup due
// to no hash computation and better cache locality. This is analogous to how
// Rust's BTreeMap stores small collections in a single sorted node.
pub struct Runtime {
mut:
	object     ObjectMap  // The root object (.) when it's an object
	root_array []VrlValue // The root value when . was assigned a non-object value
	has_root_array bool   // True if root was assigned a non-object value
	metadata   ObjectMap  // Metadata (%)
	vars       ObjectMap  // Local variables
	aborted    bool
	returned   bool
	abort_msg  string
}

pub fn new_runtime() Runtime {
	return Runtime{
		object: new_object_map()
		metadata: new_object_map()
		vars: new_object_map()
	}
}

pub fn new_runtime_with_object(obj map[string]VrlValue) Runtime {
	return Runtime{
		object: object_map_from_map(obj)
		metadata: new_object_map()
		vars: new_object_map()
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
			rt.merge_assign(expr.target[0], val)!
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
			return VrlValue(rt.object.clone_map())
		}
		ReturnExpr {
			rt.returned = true
			if expr.value.len > 0 {
				return rt.eval(expr.value[0])
			}
			return VrlValue(VrlNull{})
		}
		OkErrAssignExpr {
			return rt.eval_ok_err_assign(expr)
		}
		ClosureExpr {
			return VrlValue(VrlNull{})
		}
	}
}

fn (mut rt Runtime) eval_ok_err_assign(expr OkErrAssignExpr) !VrlValue {
	// Evaluate the expression; if it errors, assign default to ok and error string to err
	val := rt.eval(expr.value[0]) or {
		err_msg := err.msg()
		// Determine a type-appropriate default for ok value
		ok_default := ok_err_default_value(expr.value[0])
		rt.assign_to(expr.ok_target[0], ok_default)
		rt.assign_to(expr.err_target[0], VrlValue(err_msg))
		return VrlValue(err_msg)
	}
	// Success: assign value to ok, null to err
	rt.assign_to(expr.ok_target[0], val)
	rt.assign_to(expr.err_target[0], VrlValue(VrlNull{}))
	return val
}

// ok_err_default_value returns the type-appropriate default for an expression's ok value.
// Division always returns float, so default to 0.0. Function calls that return known types
// can be mapped here. Otherwise, return null.
fn ok_err_default_value(expr Expr) VrlValue {
	if expr is BinaryExpr {
		if expr.op == '/' {
			return VrlValue(f64(0))
		}
	}
	if expr is FnCallExpr {
		// Functions that return specific types
		match expr.name {
			'to_int', 'int' { return VrlValue(0) }
			'to_float', 'to_unix_timestamp' { return VrlValue(f64(0)) }
			'to_string', 'string' { return VrlValue('') }
			'to_bool', 'bool' { return VrlValue(false) }
			'push', 'append', 'flatten', 'compact', 'unique', 'filter',
			'map_values', 'map_keys', 'keys', 'values', 'split' {
				return VrlValue([]VrlValue{})
			}
			'merge' { return VrlValue(new_object_map()) }
			else {}
		}
	}
	return VrlValue(VrlNull{})
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
	mut obj := new_object_map()
	for pair in expr.pairs {
		val := rt.eval(pair.value)!
		obj.set(pair.key, val)
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
		if rt.aborted || rt.returned {
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
	if op0 == `|` && expr.op.len == 1 {
		// | — object merge
		left := rt.eval(expr.left[0])!
		right := rt.eval(expr.right[0])!
		return fn_merge([left, right])
	}
	if op0 == `&` && expr.op.len == 2 {
		// && — VRL returns boolean false when left is not truthy
		left := rt.eval(expr.left[0])!
		if !is_truthy(left) {
			return VrlValue(false)
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

// split_path_segments splits a cleaned path (no leading dot) into segments,
// handling quoted segments like foo."bar.baz"[0] properly.
fn split_path_segments(clean string) []string {
	if !clean.contains('"') && !clean.contains('[') {
		return clean.split('.')
	}
	mut segments := []string{}
	mut i := 0
	mut seg_start := 0
	for i < clean.len {
		if clean[i] == `"` {
			// Quoted segment: find closing quote
			i++
			start := i
			for i < clean.len && clean[i] != `"` {
				if clean[i] == `\\` && i + 1 < clean.len {
					i++
				}
				i++
			}
			segments << clean[start..i]
			if i < clean.len {
				i++ // skip closing "
			}
			seg_start = i
			// Skip dot after quoted segment
			if i < clean.len && clean[i] == `.` {
				i++
				seg_start = i
			}
		} else if clean[i] == `[` {
			// Array index: add preceding segment if any, then index
			if i > seg_start {
				segments << clean[seg_start..i]
			}
			i++ // skip [
			idx_start := i
			for i < clean.len && clean[i] != `]` {
				i++
			}
			segments << clean[idx_start..i]
			if i < clean.len {
				i++ // skip ]
			}
			seg_start = i
			if i < clean.len && clean[i] == `.` {
				i++
				seg_start = i
			}
		} else if clean[i] == `.` {
			if i > seg_start {
				segments << clean[seg_start..i]
			}
			i++
			seg_start = i
		} else {
			i++
		}
	}
	if seg_start < clean.len {
		segments << clean[seg_start..]
	}
	return segments
}

// Path access — avoids full object copy for simple lookups.
fn (rt &Runtime) get_path(path string) !VrlValue {
	if path == '.' {
		if rt.has_root_array {
			return VrlValue(rt.root_array.clone())
		}
		return VrlValue(rt.object.clone_map())
	}
	clean := if path.starts_with('.') { path[1..] } else { path }

	// Fast path for single-segment (no dots, no quotes) — most common case
	if !clean.contains('.') && !clean.contains('"') && !clean.contains('[') {
		if val := rt.object.get(clean) {
			return val
		}
		return VrlValue(VrlNull{})
	}

	// Multi-segment: first key from ObjectMap, then traverse nested
	parts := split_path_segments(clean)
	if val := rt.object.get(parts[0]) {
		if parts.len == 1 {
			return val
		}
		mut current := val
		for i in 1 .. parts.len {
			cur := current
			match cur {
				ObjectMap {
					if next := cur.get(parts[i]) {
						current = next
					} else {
						return VrlValue(VrlNull{})
					}
				}
				[]VrlValue {
					idx := parts[i].int()
					if idx >= 0 && idx < cur.len {
						current = cur[idx]
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
		return VrlValue(rt.metadata.clone_map())
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
					ObjectMap {
						rt.object = v.clone_map()
						rt.has_root_array = false
					}
					[]VrlValue {
						rt.root_array = v.clone()
						rt.has_root_array = true
					}
					else {}
				}
				return
			}
			clean := if target.path.starts_with('.') { target.path[1..] } else { target.path }
			// Fast path: single segment (no dot, no quotes) — most common case
			if !clean.contains('.') && !clean.contains('"') && !clean.contains('[') {
				rt.object.set(clean, val)
				return
			}
			parts := split_path_segments(clean)
			rt.set_nested_path(parts, val)
		}
		IdentExpr {
			rt.vars.set(target.name, val)
		}
		MetaPathExpr {
			if target.path == '%' {
				v := val
				match v {
					ObjectMap {
						rt.metadata = v.clone_map()
					}
					else {}
				}
				return
			}
			clean := if target.path.starts_with('%') { target.path[1..] } else { target.path }
			rt.metadata.set(clean, val)
		}
		IndexExpr {
			// Handle foo.bar = val, foo[0] = val, .path[idx] = val
			rt.assign_index(target, val)
		}
		else {}
	}
}

fn (mut rt Runtime) assign_index(target IndexExpr, val VrlValue) {
	// Resolve the chain of IndexExpr to find the root variable and path
	container_expr := target.expr[0]
	index_expr := target.index[0]
	// Get the index key
	idx_val := rt.eval(index_expr) or { return }

	// If container is an ident (local variable), get-or-create an object/array
	if container_expr is IdentExpr {
		name := container_expr.name
		existing := rt.vars.get(name) or { VrlValue(new_object_map()) }
		new_val := set_in_container(existing, idx_val, val)
		rt.vars.set(name, new_val)
		return
	}
	// If container is a path, similar logic
	if container_expr is PathExpr {
		existing := rt.get_path(container_expr.path) or { VrlValue(new_object_map()) }
		new_val := set_in_container(existing, idx_val, val)
		rt.assign_to(container_expr, new_val)
		return
	}
	// Nested IndexExpr — need recursive handling
	if container_expr is IndexExpr {
		// Get existing container value
		container_val := rt.eval(container_expr) or { VrlValue(new_object_map()) }
		new_val := set_in_container(container_val, idx_val, val)
		rt.assign_index(container_expr, new_val)
		return
	}
}

fn set_in_container(container VrlValue, key VrlValue, val VrlValue) VrlValue {
	k := key
	c := container
	match k {
		string {
			// Object key access
			match c {
				ObjectMap {
					mut m := c.clone_map()
					m.set(k, val)
					return VrlValue(m)
				}
				else {
					mut m := new_object_map()
					m.set(k, val)
					return VrlValue(m)
				}
			}
		}
		int {
			// Array index access
			match c {
				[]VrlValue {
					mut arr := c.clone()
					if k < 0 {
						mut idx := arr.len + k
						if idx < 0 {
							// Negative index beyond bounds: prepend nulls
							// e.g. arr=[1,2,3], k=-4: idx=-1, prepend 1 null → [null,1,2,3], then set [0]=val
							prepend_count := -idx
							mut new_arr := []VrlValue{len: prepend_count, init: VrlValue(VrlNull{})}
							for elem in arr {
								new_arr << elem
							}
							new_arr[0] = val
							return VrlValue(new_arr)
						}
						arr[idx] = val
						return VrlValue(arr)
					}
					// Positive index: extend if needed
					for k >= arr.len {
						arr << VrlValue(VrlNull{})
					}
					arr[k] = val
					return VrlValue(arr)
				}
				else {
					// Container is not an array — create one
					if k < 0 {
						target_len := if -k > 0 { -k } else { 1 }
						mut arr := []VrlValue{len: target_len, init: VrlValue(VrlNull{})}
						arr[0] = val
						return VrlValue(arr)
					}
					mut arr := []VrlValue{}
					for _ in 0 .. k {
						arr << VrlValue(VrlNull{})
					}
					arr << val
					return VrlValue(arr)
				}
			}
		}
		else { return container }
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
		// Check if second part is a numeric index
		is_numeric := parts[1].len > 0
			&& (parts[1][0].is_digit() || (parts[1][0] == `-` && parts[1].len > 1))
		if is_numeric {
			idx := parts[1].int()
			existing := rt.object.get(top) or { VrlValue([]VrlValue{}) }
			new_val := set_in_container(existing, VrlValue(idx), val)
			rt.object.set(top, new_val)
			return
		}
		if existing := rt.object.get(top) {
			e := existing
			match e {
				ObjectMap {
					mut m := e.clone_map()
					m.set(parts[1], val)
					rt.object.set(top, VrlValue(m))
					return
				}
				[]VrlValue {
					// Can't set string key on array — treat as object
				}
				else {}
			}
		}
		mut m := new_object_map()
		m.set(parts[1], val)
		rt.object.set(top, VrlValue(m))
		return
	}
	// 3+ levels: build nested maps
	rt.set_deep_path(parts, val)
}

fn is_numeric_segment(s string) bool {
	if s.len == 0 {
		return false
	}
	start := if s[0] == `-` { 1 } else { 0 }
	if start >= s.len {
		return false
	}
	for i in start .. s.len {
		if !s[i].is_digit() {
			return false
		}
	}
	return true
}

fn (mut rt Runtime) set_deep_path(parts []string, val VrlValue) {
	if parts.len == 0 {
		return
	}
	if parts.len == 1 {
		rt.object.set(parts[0], val)
		return
	}
	// Build from inside out, handling numeric segments as array indices
	mut current := val
	mut i := parts.len - 1
	for i >= 1 {
		if is_numeric_segment(parts[i]) {
			idx := parts[i].int()
			current = set_in_container(VrlValue([]VrlValue{}), VrlValue(idx), current)
		} else {
			mut m := new_object_map()
			m.set(parts[i], current)
			current = VrlValue(m)
		}
		i--
	}
	rt.object.set(parts[0], current)
}

fn (mut rt Runtime) merge_assign(target Expr, val VrlValue) ! {
	v := val
	if v !is ObjectMap {
		return error('only objects can be merged')
	}
	if target is PathExpr {
		if target.path == '.' {
			vo := val
			match vo {
				ObjectMap {
					if vo.is_large {
						for k, item in vo.hm {
							rt.object.set(k, item)
						}
					} else {
						for i in 0 .. vo.ks.len {
							rt.object.set(vo.ks[i], vo.vs[i])
						}
					}
				}
				else {}
			}
		} else {
			// Non-root path: merge val into existing object at path
			existing := rt.get_path(target.path) or { VrlValue(new_object_map()) }
			merged := fn_merge([existing, val])!
			rt.assign_to(target, merged)
		}
	} else if target is IdentExpr {
		existing := rt.vars.get(target.name) or { VrlValue(new_object_map()) }
		// Check that existing is also an object
		e := existing
		if e !is ObjectMap {
			return error('only objects can be merged')
		}
		merged := fn_merge([existing, val])!
		rt.vars.set(target.name, merged)
	}
}

// vrl_type_name returns the VRL type name for error messages.
fn vrl_type_name(v VrlValue) string {
	match v {
		string { return 'string' }
		int { return 'integer' }
		f64 { return 'float' }
		bool { return 'boolean' }
		VrlNull { return 'null' }
		[]VrlValue { return 'array' }
		ObjectMap { return 'object' }
		Timestamp { return 'timestamp' }
		VrlRegex { return 'regex' }
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
	// String + null = string, null + string = string (VRL coerces null to "")
	if l is string && r is VrlNull {
		return VrlValue(l as string)
	}
	if l is VrlNull && r is string {
		return VrlValue(r as string)
	}
	lt := vrl_type_name(left)
	rt_ := vrl_type_name(right)
	return error("can't add type ${rt_} to ${lt}")
}

fn is_nan(f f64) bool {
	return f != f
}

fn arith_sub(left VrlValue, right VrlValue) !VrlValue {
	l := left
	r := right
	match l {
		int {
			match r {
				int { return VrlValue(l - r) }
				f64 {
					result := f64(l) - r
					if is_nan(result) { return error("can't subtract type float from float") }
					return VrlValue(result)
				}
				else {}
			}
		}
		f64 {
			match r {
				int {
					result := l - f64(r)
					if is_nan(result) { return error("can't subtract type float from float") }
					return VrlValue(result)
				}
				f64 {
					result := l - r
					if is_nan(result) { return error("can't subtract type float from float") }
					return VrlValue(result)
				}
				else {}
			}
		}
		else {}
	}
	lt := vrl_type_name(left)
	rt_ := vrl_type_name(right)
	return error("can't subtract type ${rt_} from ${lt}")
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
	// String * int = repeat string
	if l is string && r is int {
		s := l as string
		n := r as int
		if n <= 0 { return VrlValue('') }
		mut result := ''
		for _ in 0 .. n { result += s }
		return VrlValue(result)
	}
	if l is int && r is string {
		s := r as string
		n := l as int
		if n <= 0 { return VrlValue('') }
		mut result := ''
		for _ in 0 .. n { result += s }
		return VrlValue(result)
	}
	return error("can't multiply these types")
}

fn arith_div(left VrlValue, right VrlValue) !VrlValue {
	if left is int {
		if right is int {
			divisor := right as int
			if divisor == 0 { return error("can't divide by zero") }
			dividend := left as int
			// VRL integer division produces float
			return VrlValue(f64(dividend) / f64(divisor))
		}
		if right is f64 {
			r := right as f64
			if r == 0.0 { return error("can't divide by zero") }
			return VrlValue(f64(left as int) / r)
		}
	}
	if left is f64 {
		if right is int {
			divisor := right as int
			if divisor == 0 { return error("can't divide by zero") }
			return VrlValue((left as f64) / f64(divisor))
		}
		if right is f64 {
			r := right as f64
			if r == 0.0 { return error("can't divide by zero") }
			return VrlValue((left as f64) / r)
		}
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
					ri := int(r)
					if ri == 0 { return error("can't calculate remainder with divisor of zero") }
					li := int(l)
					// INT_MIN % -1 is UB in C, guard against SIGFPE
					if ri == -1 { return VrlValue(0) }
					v := li % ri
					return VrlValue(v)
				}
				f64 {
					rf := f64(r)
					if rf == 0.0 { return error("can't calculate remainder with divisor of zero") }
					lf := f64(int(l))
					return VrlValue(lf - rf * f64(int(lf / rf)))
				}
				else {}
			}
		}
		f64 {
			match r {
				int {
					ri := int(r)
					if ri == 0 { return error("can't calculate remainder with divisor of zero") }
					lf := f64(l)
					rf := f64(ri)
					return VrlValue(lf - rf * f64(int(lf / rf)))
				}
				f64 {
					rf := f64(r)
					if rf == 0.0 { return error("can't calculate remainder with divisor of zero") }
					lf := f64(l)
					return VrlValue(lf - rf * f64(int(lf / rf)))
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
		Timestamp {
			match r {
				Timestamp { return VrlValue(l.t.unix() < r.t.unix()) }
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
		Timestamp {
			match r {
				Timestamp { return VrlValue(l.t.unix() > r.t.unix()) }
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
		Timestamp {
			match r {
				Timestamp { return VrlValue(l.t.unix() <= r.t.unix()) }
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
		Timestamp {
			match r {
				Timestamp { return VrlValue(l.t.unix() >= r.t.unix()) }
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
		ObjectMap {
			match i {
				string {
					if v := c.get(i) {
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

