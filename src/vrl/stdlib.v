module vrl

import regex
import time

// eval_fn_call dispatches built-in VRL functions.
fn (mut rt Runtime) eval_fn_call(expr FnCallExpr) !VrlValue {
	// Strip trailing '!' more efficiently using byte check
	mut name := expr.name
	if name.len > 0 && name[name.len - 1] == `!` {
		name = name[..name.len - 1]
	}

	// Special functions that need unevaluated args (PathExpr)
	if name == 'del' { return rt.fn_del(expr) }
	if name == 'exists' { return rt.fn_exists(expr) }
	if name == 'filter' { return rt.fn_filter(expr) }
	if name == 'for_each' { return rt.fn_for_each(expr) }

	// Fast path for common 1-arg functions: evaluate arg directly without []VrlValue alloc
	if expr.args.len == 1 {
		a0 := rt.eval(expr.args[0])!
		match name {
			'downcase' {
				v := a0
				match v {
					string { return VrlValue(v.to_lower()) }
					else { return error('downcase requires a string argument') }
				}
			}
			'upcase' {
				v := a0
				match v {
					string { return VrlValue(v.to_upper()) }
					else { return error('upcase requires a string argument') }
				}
			}
			'to_string' { return fn_to_string([a0]) }
		'format_number' { return VrlValue(vrl_to_string(a0)) }
			'to_int', 'int' { return fn_to_int([a0]) }
			'to_float', 'float' { return fn_to_float([a0]) }
			'to_bool', 'bool' { return fn_to_bool([a0]) }
			'string' { return fn_string([a0]) }
			'length', 'strlen' { return fn_length([a0]) }
			'strip_whitespace', 'trim' { return fn_strip_whitespace([a0]) }
			'is_string' { return VrlValue(a0 is string) }
			'is_integer' { return VrlValue(a0 is int) }
			'is_float' { return VrlValue(a0 is f64) }
			'is_boolean' { return VrlValue(a0 is bool) }
			'is_null' { return VrlValue(a0 is VrlNull) }
			'is_array' { return VrlValue(a0 is []VrlValue) }
			'is_object' { return VrlValue(a0 is ObjectMap) }
			'is_nullish' { return fn_is_nullish([a0]) }
			'encode_json' { return VrlValue(vrl_to_json(a0)) }
			'decode_json', 'parse_json' { return fn_decode_json([a0]) }
			'keys' { return fn_keys([a0]) }
			'values' { return fn_values([a0]) }
			'flatten' { return fn_flatten([a0]) }
			'unflatten' { return fn_unflatten([a0]) }
			'compact' { return fn_compact([a0]) }
			'abs' { return fn_abs([a0]) }
			'ceil' { return fn_ceil([a0]) }
			'floor' { return fn_floor([a0]) }
			'round' { return fn_round([a0]) }
			'type_def' { return fn_type_def([a0]) }
			'array' { return fn_ensure_array([a0]) }
			'object' { return fn_ensure_object([a0]) }
			'map_keys', 'map_values' { return a0 }
			else {}
		}
		// Fall through to 2-arg path or general path
	}

	// Fast path for common 2-arg functions
	if expr.args.len == 2 {
		a0 := if expr.args.len >= 1 { rt.eval(expr.args[0])! } else { VrlValue(VrlNull{}) }
		a1 := rt.eval(expr.args[1])!
		match name {
			'contains' { return fn_contains([a0, a1]) }
			'starts_with' { return fn_starts_with([a0, a1]) }
			'ends_with' { return fn_ends_with([a0, a1]) }
			'split' { return fn_split([a0, a1]) }
			'join' { return fn_join([a0, a1]) }
			'merge' { return fn_merge([a0, a1]) }
			'push' { return fn_push([a0, a1]) }
			'append' { return fn_append([a0, a1]) }
			'mod' { return fn_mod([a0, a1]) }
			'slice' { return fn_slice([a0, a1]) }
			'truncate' { return fn_truncate([a0, a1]) }
			else {}
		}
	}

	// General path: evaluate all args into array
	mut args := []VrlValue{}
	for arg in expr.args {
		val := rt.eval(arg)!
		args << val
	}

	match name {
		'to_string' { return fn_to_string(args) }
		'downcase' { return fn_downcase(args) }
		'upcase' { return fn_upcase(args) }
		'contains' { return fn_contains(args) }
		'starts_with' { return fn_starts_with(args) }
		'ends_with' { return fn_ends_with(args) }
		'length' { return fn_length(args) }
		'strip_whitespace', 'trim' { return fn_strip_whitespace(args) }
		'replace' { return fn_replace(args) }
		'slice' { return fn_slice(args) }
		'split' { return fn_split(args) }
		'join' { return fn_join(args) }
		'strlen' { return fn_strlen(args) }
		'truncate' { return fn_truncate(args) }
		'to_int', 'int' { return fn_to_int(args) }
		'to_float', 'float' { return fn_to_float(args) }
		'to_bool', 'bool' { return fn_to_bool(args) }
		'string' { return fn_string(args) }
		'is_string' { return fn_is_type(args, 'string') }
		'is_integer' { return fn_is_type(args, 'integer') }
		'is_float' { return fn_is_type(args, 'float') }
		'is_boolean' { return fn_is_type(args, 'boolean') }
		'is_null' { return fn_is_type(args, 'null') }
		'is_array' { return fn_is_type(args, 'array') }
		'is_object' { return fn_is_type(args, 'object') }
		'is_nullish' { return fn_is_nullish(args) }
		'type_def' { return fn_type_def(args) }
		'keys' { return fn_keys(args) }
		'values' { return fn_values(args) }
		'flatten' { return fn_flatten(args) }
		'unflatten' { return fn_unflatten(args) }
		'merge' { return fn_merge(args) }
		'compact' { return fn_compact(args) }
		'push' { return fn_push(args) }
		'append' { return fn_append(args) }
		'map_keys' { return fn_first_arg(args) }
		'map_values' { return fn_first_arg(args) }
		'encode_json' { return fn_encode_json(args) }
		'decode_json', 'parse_json' { return fn_decode_json(args) }
		'abs' { return fn_abs(args) }
		'ceil' { return fn_ceil(args) }
		'floor' { return fn_floor(args) }
		'round' { return fn_round(args) }
		'mod' { return fn_mod(args) }
		'assert' { return fn_assert(args) }
		'assert_eq' { return fn_assert_eq(args) }
		'now' { return VrlValue(Timestamp{}) }
		'format_number' { return fn_to_string(args) }
		'to_unix_timestamp' { return VrlValue(0) }
		'get_env_var' { return error('environment variable not found') }
		'uuid_v4' { return VrlValue('00000000-0000-4000-8000-000000000000') }
		'array' { return fn_ensure_array(args) }
		'object' { return fn_ensure_object(args) }
		'pop' { return fn_pop(args) }
		'match' { return fn_match(args) }
		'match_any' { return fn_match_any(args) }
		'includes' { return fn_includes(args) }
		'contains_all' { return fn_contains_all(args) }
		'find' { return fn_find(args) }
		'get' { return fn_get(args) }
		'set' { return fn_set(args) }
		'unique' { return fn_unique(args) }
		'to_regex' { return fn_to_regex(args) }
		'log' { return VrlValue(VrlNull{}) }  // log() is a no-op in our runtime
		'from_unix_timestamp' { return fn_from_unix_timestamp(args) }
		else { return error('unknown function: ${name}') }
	}
}

// String functions
fn fn_to_string(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_string requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a) }
		int { return VrlValue('${a}') }
		f64 { return VrlValue(format_float(a)) }
		bool {
			s := if a { 'true' } else { 'false' }
			return VrlValue(s)
		}
		VrlNull { return VrlValue('') }
		Timestamp {
			s := format_timestamp(a.t)
			return VrlValue(s)
		}
		else { return error('expected string, got ${vrl_type_name(a)}') }
	}
}

fn fn_downcase(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('downcase requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a.to_lower()) }
		else { return error('downcase requires a string argument') }
	}
}

fn fn_upcase(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('upcase requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a.to_upper()) }
		else { return error('upcase requires a string argument') }
	}
}

fn fn_contains(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('contains requires 2 arguments') }
	a := args[0]
	b := args[1]
	match a {
		string {
			match b {
				string { return VrlValue(a.contains(b)) }
				else { return error('contains second arg must be string') }
			}
		}
		else { return error('contains first arg must be string') }
	}
}

fn fn_starts_with(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('starts_with requires 2 arguments') }
	a := args[0]
	b := args[1]
	match a {
		string {
			match b {
				string { return VrlValue(a.starts_with(b)) }
				else { return error('starts_with second arg must be string') }
			}
		}
		else { return error('starts_with first arg must be string') }
	}
}

fn fn_ends_with(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('ends_with requires 2 arguments') }
	a := args[0]
	b := args[1]
	match a {
		string {
			match b {
				string { return VrlValue(a.ends_with(b)) }
				else { return error('ends_with second arg must be string') }
			}
		}
		else { return error('ends_with first arg must be string') }
	}
}

fn fn_length(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('length requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a.len) }
		[]VrlValue { return VrlValue(a.len) }
		ObjectMap { return VrlValue(a.len()) }
		else { return error('length requires string, array, or object') }
	}
}

fn fn_strip_whitespace(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('strip_whitespace requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a.trim_space()) }
		else { return error('strip_whitespace requires a string') }
	}
}

fn fn_replace(args []VrlValue) !VrlValue {
	if args.len < 3 { return error('replace requires 3 arguments') }
	a0 := args[0]
	a1 := args[1]
	a2 := args[2]
	s := match a0 {
		string { a0 }
		else { return error('replace first arg must be string') }
	}
	replacement := match a2 {
		string { a2 }
		else { return error('replace third arg must be string') }
	}
	// Pattern can be a string or regex
	p := a1
	match p {
		string { return VrlValue(s.replace(p, replacement)) }
		VrlRegex {
			mut re := regex.regex_opt(p.pattern) or { return VrlValue(s) }
			result := re.replace(s, replacement)
			return VrlValue(result)
		}
		else { return error('replace second arg must be string or regex') }
	}
}

fn fn_split(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('split requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('split first arg must be string') }
	}
	delim := match a1 {
		string { a1 }
		else { return error('split second arg must be string') }
	}
	parts := s.split(delim)
	mut result := []VrlValue{}
	for p in parts {
		result << VrlValue(p)
	}
	return VrlValue(result)
}

fn fn_join(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('join requires at least 1 argument') }
	a0 := args[0]
	arr := match a0 {
		[]VrlValue { a0 }
		else { return error('join first arg must be array') }
	}
	sep := if args.len > 1 {
		s1 := args[1]
		match s1 {
			string { s1 }
			else { '' }
		}
	} else {
		''
	}
	mut parts := []string{}
	for item in arr {
		parts << vrl_to_string(item)
	}
	return VrlValue(parts.join(sep))
}

fn fn_slice(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('slice requires at least 2 arguments') }
	a1 := args[1]
	start := match a1 {
		int { a1 }
		else { return error('slice start must be integer') }
	}
	a0 := args[0]
	match a0 {
		string {
			s := a0 as string
			mut st := start
			if st < 0 { st = s.len + st }
			mut end := s.len
			if args.len > 2 { end = get_int_arg(args[2], s.len) }
			if st >= 0 && st <= s.len && end >= st && end <= s.len {
				result := s[st..end]
				return VrlValue(result)
			}
			return VrlValue(s)
		}
		[]VrlValue {
			arr := a0
			mut st := start
			if st < 0 { st = arr.len + st }
			mut end := arr.len
			if args.len > 2 { end = get_int_arg(args[2], arr.len) }
			if st >= 0 && st <= arr.len && end >= st && end <= arr.len {
				result := arr[st..end]
				return VrlValue(result)
			}
			return VrlValue(arr)
		}
		else { return error('slice requires string or array') }
	}
}

fn get_int_arg(v VrlValue, default_val int) int {
	match v {
		int {
			if v < 0 { return default_val + v }
			return v
		}
		else { return default_val }
	}
}

fn fn_strlen(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('strlen requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a.len) }
		else { return error('strlen requires a string') }
	}
}

fn fn_truncate(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('truncate requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('truncate first arg must be string') }
	}
	max_len := match a1 {
		int { a1 }
		else { return error('truncate second arg must be integer') }
	}
	mut ellipsis := false
	if args.len > 2 {
		a2 := args[2]
		match a2 {
			bool { ellipsis = a2 }
			else {}
		}
	}
	if s.len <= max_len { return VrlValue(s) }
	truncated := s[..max_len]
	if ellipsis { return VrlValue(truncated + '...') }
	return VrlValue(truncated)
}

// Type functions
fn fn_to_int(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_int requires 1 argument') }
	a := args[0]
	match a {
		int { return VrlValue(a) }
		f64 { return VrlValue(int(a)) }
		bool {
			v := if a { 1 } else { 0 }
			return VrlValue(v)
		}
		string { return VrlValue(a.int()) }
		else { return error("can't convert to integer") }
	}
}

fn fn_to_float(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_float requires 1 argument') }
	a := args[0]
	match a {
		f64 { return VrlValue(a) }
		int { return VrlValue(f64(a)) }
		string { return VrlValue(a.f64()) }
		else { return error("can't convert to float") }
	}
}

fn fn_to_bool(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_bool requires 1 argument') }
	a := args[0]
	match a {
		bool { return VrlValue(a) }
		string { return VrlValue(a == 'true' || a == 'yes' || a == '1') }
		int { return VrlValue(a != 0) }
		VrlNull { return VrlValue(false) }
		else { return error("can't convert to boolean") }
	}
}

fn fn_string(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('string requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(a) }
		else { return error('expected string, got different type') }
	}
}

fn fn_is_type(args []VrlValue, type_name string) !VrlValue {
	if args.len < 1 { return VrlValue(false) }
	a := args[0]
	result := match type_name {
		'string' { a is string }
		'integer' { a is int }
		'float' { a is f64 }
		'boolean' { a is bool }
		'null' { a is VrlNull }
		'array' { a is []VrlValue }
		'object' { a is ObjectMap }
		else { false }
	}
	return VrlValue(result)
}

fn fn_is_nullish(args []VrlValue) !VrlValue {
	if args.len < 1 { return VrlValue(true) }
	a := args[0]
	match a {
		VrlNull { return VrlValue(true) }
		string { return VrlValue(a.trim_space().len == 0) }
		else { return VrlValue(false) }
	}
}

fn fn_type_def(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('type_def requires 1 argument') }
	return type_def_value(args[0])
}

fn type_def_value(v VrlValue) !VrlValue {
	a := v
	mut result := new_object_map()
	match a {
		string { result.set('bytes', VrlValue(true)) }
		int { result.set('integer', VrlValue(true)) }
		f64 { result.set('float', VrlValue(true)) }
		bool { result.set('boolean', VrlValue(true)) }
		VrlNull { result.set('null', VrlValue(true)) }
		[]VrlValue {
			// Build nested type info for array elements
			mut inner := new_object_map()
			for i, item in a {
				elem_type := type_def_value(item) or { VrlValue(new_object_map()) }
				inner.set('${i}', elem_type)
			}
			result.set('array', VrlValue(inner))
		}
		ObjectMap {
			// Build nested type info for object keys
			mut inner := new_object_map()
			all_keys := a.keys()
			for k in all_keys {
				val := a.get(k) or { VrlValue(VrlNull{}) }
				elem_type := type_def_value(val) or { VrlValue(new_object_map()) }
				inner.set(k, elem_type)
			}
			result.set('object', VrlValue(inner))
		}
		Timestamp { result.set('timestamp', VrlValue(true)) }
		VrlRegex { result.set('regex', VrlValue(true)) }
	}
	return VrlValue(result)
}

// Object/path functions
fn (mut rt Runtime) fn_del(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 { return error('del requires 1 argument') }
	path_expr := expr.args[0]
	match path_expr {
		PathExpr {
			if path_expr.path == '.' {
				old := VrlValue(rt.object.clone_map())
				rt.object.clear()
				return old
			}
			clean := if path_expr.path.starts_with('.') { path_expr.path[1..] } else { path_expr.path }
			parts := clean.split('.')
			if parts.len == 1 {
				val := rt.object.delete(parts[0])
				return val
			}
			if parts.len == 2 {
				if top_val := rt.object.get(parts[0]) {
					tv := top_val
					match tv {
						ObjectMap {
							val := tv.get(parts[1]) or { VrlValue(VrlNull{}) }
							mut m := tv.clone_map()
							m.delete(parts[1])
							rt.object.set(parts[0], VrlValue(m))
							return val
						}
						else {}
					}
				}
			}
			return VrlValue(VrlNull{})
		}
		else {
			return rt.eval(path_expr)
		}
	}
}

fn (mut rt Runtime) fn_exists(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 { return error('exists requires 1 argument') }
	path_expr := expr.args[0]
	match path_expr {
		PathExpr {
			if path_expr.path == '.' { return VrlValue(true) }
			clean := if path_expr.path.starts_with('.') { path_expr.path[1..] } else { path_expr.path }
			return VrlValue(rt.object.has(clean))
		}
		else { return VrlValue(false) }
	}
}

fn fn_keys(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('keys requires 1 argument') }
	a := args[0]
	match a {
		ObjectMap {
			all_keys := a.keys()
			mut result := []VrlValue{cap: all_keys.len}
			for k in all_keys {
				result << VrlValue(k)
			}
			return VrlValue(result)
		}
		else { return error('keys requires an object') }
	}
}

fn fn_values(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('values requires 1 argument') }
	a := args[0]
	match a {
		ObjectMap {
			if a.is_large {
				mut result := []VrlValue{}
				for _, v in a.hm {
					result << v
				}
				return VrlValue(result)
			}
			return VrlValue(a.vs.clone())
		}
		else { return error('values requires an object') }
	}
}

fn fn_flatten(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('flatten requires 1 argument') }
	a := args[0]
	match a {
		ObjectMap {
			mut result := new_object_map()
			flatten_object(a, '', mut result)
			return VrlValue(result)
		}
		[]VrlValue {
			mut result := []VrlValue{}
			flatten_array(a, mut result)
			return VrlValue(result)
		}
		else { return error('flatten requires object or array') }
	}
}

fn flatten_object(obj ObjectMap, prefix string, mut result ObjectMap) {
	if obj.is_large {
		for k, v in obj.hm {
			full_key := if prefix.len > 0 { '${prefix}.${k}' } else { k }
			val := v
			match val {
				ObjectMap {
					flatten_object(val, full_key, mut result)
				}
				else {
					result.set(full_key, v)
				}
			}
		}
	} else {
		for i in 0 .. obj.ks.len {
			full_key := if prefix.len > 0 { '${prefix}.${obj.ks[i]}' } else { obj.ks[i] }
			val := obj.vs[i]
			match val {
				ObjectMap {
					flatten_object(val, full_key, mut result)
				}
				else {
					result.set(full_key, obj.vs[i])
				}
			}
		}
	}
}

fn flatten_array(arr []VrlValue, mut result []VrlValue) {
	for item in arr {
		i := item
		match i {
			[]VrlValue {
				flatten_array(i, mut result)
			}
			else {
				result << item
			}
		}
	}
}

fn fn_unflatten(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('unflatten requires 1 argument') }
	a := args[0]
	match a {
		ObjectMap {
			mut result := new_object_map()
			all_keys := a.keys()
			for k in all_keys {
				v := a.get(k) or { VrlValue(VrlNull{}) }
				parts := k.split('.')
				if parts.len == 1 {
					result.set(k, v)
				} else {
					if !result.has(parts[0]) {
						result.set(parts[0], VrlValue(new_object_map()))
					}
					existing := result.get(parts[0]) or { VrlValue(new_object_map()) }
					e := existing
					match e {
						ObjectMap {
							mut m := e.clone_map()
							m.set(parts[1..].join('.'), v)
							result.set(parts[0], VrlValue(m))
						}
						else {}
					}
				}
			}
			return VrlValue(result)
		}
		else { return error('unflatten requires an object') }
	}
}

fn fn_merge(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('merge requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	match a0 {
		ObjectMap {
			match a1 {
				ObjectMap {
					mut result := a0.clone_map()
					if a1.is_large {
						for k, v in a1.hm {
							result.set(k, v)
						}
					} else {
						for i in 0 .. a1.ks.len {
							result.set(a1.ks[i], a1.vs[i])
						}
					}
					return VrlValue(result)
				}
				else { return error('only objects can be merged') }
			}
		}
		else { return error('only objects can be merged') }
	}
}

fn fn_compact(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('compact requires 1 argument') }
	a := args[0]
	match a {
		[]VrlValue {
			mut result := []VrlValue{}
			for item in a {
				i := item
				match i {
					VrlNull {}
					string { if i.len > 0 { result << item } }
					else { result << item }
				}
			}
			return VrlValue(result)
		}
		ObjectMap {
			mut result := new_object_map()
			if a.is_large {
				for k, v in a.hm {
					val := v
					match val {
						VrlNull {}
						string { if val.len > 0 { result.set(k, v) } }
						else { result.set(k, v) }
					}
				}
			} else {
				for i in 0 .. a.ks.len {
					val := a.vs[i]
					match val {
						VrlNull {}
						string { if val.len > 0 { result.set(a.ks[i], a.vs[i]) } }
						else { result.set(a.ks[i], a.vs[i]) }
					}
				}
			}
			return VrlValue(result)
		}
		else { return error('compact requires array or object') }
	}
}

fn fn_push(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('push requires 2 arguments') }
	a := args[0]
	match a {
		[]VrlValue {
			mut result := a.clone()
			result << args[1]
			return VrlValue(result)
		}
		else { return error('push first arg must be array') }
	}
}

fn fn_append(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('append requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	match a0 {
		[]VrlValue {
			match a1 {
				[]VrlValue {
					mut result := a0.clone()
					for item in a1 {
						result << item
					}
					return VrlValue(result)
				}
				else { return error('append second arg must be array') }
			}
		}
		else { return error('append first arg must be array') }
	}
}

fn fn_first_arg(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('requires 1 argument') }
	return args[0]
}

fn (mut rt Runtime) fn_filter(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 { return error('filter requires 1 argument') }
	container := rt.eval(expr.args[0])!
	if expr.closure.len == 0 { return container }
	closure_expr := expr.closure[0]
	if closure_expr is ClosureExpr {
		c := container
		match c {
			[]VrlValue {
				mut result := []VrlValue{}
				for i, item in c {
					if closure_expr.params.len > 0 {
						rt.vars.set(closure_expr.params[0].trim_left('_'), VrlValue(i))
					}
					if closure_expr.params.len > 1 {
						rt.vars.set(closure_expr.params[1], item)
					}
					cond := rt.eval(closure_expr.body[0])!
					if is_truthy(cond) { result << item }
				}
				return VrlValue(result)
			}
			else { return container }
		}
	}
	return container
}

fn (mut rt Runtime) fn_for_each(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 { return error('for_each requires 1 argument') }
	container := rt.eval(expr.args[0])!
	if expr.closure.len == 0 { return VrlValue(VrlNull{}) }
	closure_expr := expr.closure[0]
	if closure_expr is ClosureExpr {
		c := container
		match c {
			[]VrlValue {
				for i, item in c {
					if closure_expr.params.len > 0 {
						rt.vars.set(closure_expr.params[0].trim_left('_'), VrlValue(i))
					}
					if closure_expr.params.len > 1 {
						rt.vars.set(closure_expr.params[1], item)
					}
					rt.eval(closure_expr.body[0])!
				}
			}
			else {}
		}
	}
	return VrlValue(VrlNull{})
}

fn fn_encode_json(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('encode_json requires 1 argument') }
	return VrlValue(vrl_to_json(args[0]))
}

fn fn_decode_json(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('parse_json requires 1 argument') }
	a := args[0]
	match a {
		string { return parse_json_value(a) }
		else { return error('parse_json requires a string argument') }
	}
}

fn parse_json_value(s string) !VrlValue {
	return parse_json_recursive(s)
}

// Simple recursive JSON parser that produces VrlValues directly
fn parse_json_recursive(s string) !VrlValue {
	trimmed := s.trim_space()
	if trimmed.len == 0 { return VrlValue(VrlNull{}) }
	if trimmed == 'null' { return VrlValue(VrlNull{}) }
	if trimmed == 'true' { return VrlValue(true) }
	if trimmed == 'false' { return VrlValue(false) }
	if trimmed.starts_with('"') && trimmed.ends_with('"') {
		end := trimmed.len - 1
		inner := trimmed[1..end]
		return VrlValue(inner)
	}
	if trimmed[0].is_digit() || (trimmed[0] == `-` && trimmed.len > 1) {
		if trimmed.contains('.') {
			fv := trimmed.f64()
			return VrlValue(fv)
		}
		iv := trimmed.int()
		return VrlValue(iv)
	}
	if trimmed.starts_with('[') {
		return parse_json_array(trimmed)
	}
	if trimmed.starts_with('{') {
		return parse_json_object(trimmed)
	}
	return error('unable to parse JSON: ${trimmed}')
}

fn parse_json_array(s string) !VrlValue {
	end := s.len - 1
	inner := s[1..end].trim_space()
	if inner.len == 0 { return VrlValue([]VrlValue{}) }
	parts := split_json_top_level(inner)
	mut result := []VrlValue{}
	for part in parts {
		val := parse_json_recursive(part.trim_space())!
		result << val
	}
	return VrlValue(result)
}

fn parse_json_object(s string) !VrlValue {
	end := s.len - 1
	inner := s[1..end].trim_space()
	if inner.len == 0 { return VrlValue(new_object_map()) }
	parts := split_json_top_level(inner)
	mut result := new_object_map()
	for part in parts {
		colon_idx := find_colon(part)
		if colon_idx > 0 {
			key_str := part[..colon_idx].trim_space()
			val_str := part[colon_idx + 1..].trim_space()
			mut key := key_str
			if key_str.starts_with('"') && key_str.ends_with('"') {
				kend := key_str.len - 1
				key = key_str[1..kend]
			}
			val := parse_json_recursive(val_str)!
			result.set(key, val)
		}
	}
	return VrlValue(result)
}

fn find_colon(s string) int {
	mut depth := 0
	mut in_string := false
	for i := 0; i < s.len; i++ {
		ch := s[i]
		if ch == `"` && (i == 0 || s[i - 1] != `\\`) { in_string = !in_string }
		if !in_string {
			if ch == `[` || ch == `{` { depth++ }
			if ch == `]` || ch == `}` { depth-- }
			if ch == `:` && depth == 0 { return i }
		}
	}
	return -1
}

fn split_json_top_level(s string) []string {
	mut parts := []string{}
	mut depth := 0
	mut in_string := false
	mut start := 0
	for i := 0; i < s.len; i++ {
		ch := s[i]
		if ch == `"` && (i == 0 || s[i - 1] != `\\`) { in_string = !in_string }
		if !in_string {
			if ch == `[` || ch == `{` { depth++ }
			if ch == `]` || ch == `}` { depth-- }
			if ch == `,` && depth == 0 {
				parts << s[start..i]
				start = i + 1
			}
		}
	}
	if start < s.len {
		parts << s[start..]
	}
	return parts
}

// Math functions
fn fn_abs(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('abs requires 1 argument') }
	a := args[0]
	match a {
		int {
			v := if a < 0 { -a } else { a }
			return VrlValue(v)
		}
		f64 {
			v := if a < 0.0 { -a } else { a }
			return VrlValue(v)
		}
		else { return error('abs requires a number') }
	}
}

fn fn_ceil(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('ceil requires 1 argument') }
	a := args[0]
	match a {
		f64 {
			i := int(a)
			if a > f64(i) { return VrlValue(i + 1) }
			return VrlValue(i)
		}
		int { return VrlValue(a) }
		else { return error('ceil requires a number') }
	}
}

fn fn_floor(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('floor requires 1 argument') }
	a := args[0]
	match a {
		f64 { return VrlValue(int(a)) }
		int { return VrlValue(a) }
		else { return error('floor requires a number') }
	}
}

fn fn_round(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('round requires 1 argument') }
	precision := if args.len > 1 {
		p := args[1]
		match p {
			int { p }
			else { 0 }
		}
	} else { 0 }
	a := args[0]
	match a {
		f64 {
			if precision == 0 {
				return VrlValue(int(a + 0.5))
			}
			mut mult := 1.0
			for _ in 0 .. precision { mult *= 10.0 }
			return VrlValue(f64(int(a * mult + 0.5)) / mult)
		}
		int { return VrlValue(a) }
		else { return error('round requires a number') }
	}
}

fn fn_mod(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('mod requires 2 arguments') }
	return arith_mod(args[0], args[1])
}

fn fn_assert(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('assert requires 1 argument') }
	if !is_truthy(args[0]) {
		msg := if args.len > 1 { vrl_to_string(args[1]) } else { 'assertion failed' }
		return error(msg)
	}
	return VrlValue(true)
}

fn fn_assert_eq(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('assert_eq requires 2 arguments') }
	if !values_equal(args[0], args[1]) {
		msg := if args.len > 2 {
			vrl_to_string(args[2])
		} else {
			'assertion failed: ${vrl_to_json(args[0])} != ${vrl_to_json(args[1])}'
		}
		return error(msg)
	}
	return VrlValue(true)
}

fn fn_ensure_array(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('array requires 1 argument') }
	a := args[0]
	match a {
		[]VrlValue { return VrlValue(a) }
		else { return VrlValue([]VrlValue{}) }
	}
}

fn fn_ensure_object(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('object requires 1 argument') }
	a := args[0]
	match a {
		ObjectMap { return VrlValue(a) }
		else { return error('expected object, got ${vrl_type_name(a)}') }
	}
}

fn fn_pop(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('pop requires 1 argument') }
	a := args[0]
	match a {
		[]VrlValue {
			if a.len == 0 { return VrlValue([]VrlValue{}) }
			return VrlValue(a[..a.len - 1])
		}
		else { return error('pop requires an array') }
	}
}

fn fn_match(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('match requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('match first arg must be string') }
	}
	pattern := match a1 {
		VrlRegex { a1.pattern }
		string { a1 }
		else { return error('match second arg must be regex') }
	}
	// Use V's regex module for matching
mut re := regex.regex_opt(pattern) or { return error('invalid regex: ${pattern}') }
	start, _ := re.match_string(s)
	return VrlValue(start >= 0)
}

fn fn_match_any(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('match_any requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('match_any first arg must be string') }
	}
	patterns := match a1 {
		[]VrlValue { a1 }
		else { return error('match_any second arg must be array') }
	}
for p in patterns {
		pat := match p {
			VrlRegex { p.pattern }
			string { p }
			else { continue }
		}
		mut re := regex.regex_opt(pat) or { continue }
		start, _ := re.match_string(s)
		if start >= 0 { return VrlValue(true) }
	}
	return VrlValue(false)
}

fn fn_includes(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('includes requires 2 arguments') }
	a := args[0]
	match a {
		[]VrlValue {
			for item in a {
				if values_equal(item, args[1]) { return VrlValue(true) }
			}
			return VrlValue(false)
		}
		else { return error('includes first arg must be array') }
	}
}

fn fn_contains_all(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('contains_all requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('contains_all first arg must be string') }
	}
	needles := match a1 {
		[]VrlValue { a1 }
		else { return error('contains_all second arg must be array') }
	}
	for needle in needles {
		n := match needle {
			string { needle }
			else { continue }
		}
		if !s.contains(n) { return VrlValue(false) }
	}
	return VrlValue(true)
}

fn fn_find(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('find requires 2 arguments') }
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('find first arg must be string') }
	}
	pattern := match a1 {
		string { a1 }
		else { return error('find second arg must be string') }
	}
	idx := s.index(pattern) or { return VrlValue(-1) }
	return VrlValue(idx)
}

fn fn_get(args []VrlValue) !VrlValue {
	if args.len < 2 { return error('get requires 2 arguments') }
	container := args[0]
	path := args[1]
	c := container
	match c {
		ObjectMap {
			p := path
			match p {
				string {
					// Support dotted paths
					parts := (p as string).split('.')
					mut current := VrlValue(c)
					for part in parts {
						cur := current
						match cur {
							ObjectMap {
								current = cur.get(part) or { return VrlValue(VrlNull{}) }
							}
							else { return VrlValue(VrlNull{}) }
						}
					}
					return current
				}
				[]VrlValue {
					if p.len > 0 {
						first := p[0]
						match first {
							string { return c.get(first) or { VrlValue(VrlNull{}) } }
							else { return VrlValue(VrlNull{}) }
						}
					}
					return VrlValue(VrlNull{})
				}
				else { return VrlValue(VrlNull{}) }
			}
		}
		[]VrlValue {
			match path {
				int {
					idx := if path < 0 { c.len + path } else { path }
					if idx >= 0 && idx < c.len { return c[idx] }
					return VrlValue(VrlNull{})
				}
				else { return VrlValue(VrlNull{}) }
			}
		}
		else { return VrlValue(VrlNull{}) }
	}
}

fn fn_set(args []VrlValue) !VrlValue {
	if args.len < 3 { return error('set requires 3 arguments') }
	// set(object, path, value) - simplified implementation
	return args[0]
}

fn fn_unique(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('unique requires 1 argument') }
	a := args[0]
	match a {
		[]VrlValue {
			mut result := []VrlValue{}
			for item in a {
				mut found := false
				for existing in result {
					if values_equal(item, existing) { found = true; break }
				}
				if !found { result << item }
			}
			return VrlValue(result)
		}
		else { return error('unique requires an array') }
	}
}

fn fn_to_regex(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('to_regex requires 1 argument') }
	a := args[0]
	match a {
		string { return VrlValue(VrlRegex{pattern: a}) }
		VrlRegex { return VrlValue(a) }
		else { return error('to_regex requires a string') }
	}
}

fn fn_from_unix_timestamp(args []VrlValue) !VrlValue {
	if args.len < 1 { return error('from_unix_timestamp requires 1 argument') }
	a := args[0]
	match a {
		int {
		t := time.unix(a)
			return VrlValue(Timestamp{t: t})
		}
		else { return error('from_unix_timestamp requires an integer') }
	}
}
