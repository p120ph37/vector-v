module vrl

// unnest(value) - expand array field into separate events (fallback for pre-evaluated args)
fn fn_unnest(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('unnest requires 1 argument')
	}
	a := args[0]
	match a {
		[]VrlValue {
			return VrlValue(a)
		}
		else { return error('unnest requires an array') }
	}
}

// fn_unnest_special is the path-aware version of unnest.
// For each element in the nested array, creates a copy of the root object/variable
// with the nested path set to just that element.
fn (mut rt Runtime) fn_unnest_special(expr FnCallExpr) !VrlValue {
	if expr.args.len < 1 {
		return error('unnest requires 1 argument')
	}
	arg := expr.args[0]

	// Determine if it's a path expression or an ident-based path
	match arg {
		PathExpr {
			return rt.unnest_path(arg.path)
		}
		IndexExpr {
			// Could be ident.path[idx].path — need to extract the path segments
			// and the root source (. or variable)
			mut segments := []string{}
			root_name := extract_index_path(arg, mut segments)
			if root_name.starts_with('.') || root_name == '.' {
				// Path rooted at .
				full_path := if root_name == '.' {
					'.${segments.join(".")}'
				} else {
					'${root_name}.${segments.join(".")}'
				}
				return rt.unnest_path(full_path)
			}
			// Variable-rooted
			return rt.unnest_var(root_name, segments)
		}
		IdentExpr {
			// Simple variable unnest
			val := rt.vars.get(arg.name) or { return error('unnest requires an array') }
			v := val
			match v {
				[]VrlValue { return VrlValue(v) }
				else { return error('unnest requires an array') }
			}
		}
		else {
			// Fall back to evaluating and returning
			val := rt.eval(arg)!
			v := val
			match v {
				[]VrlValue { return VrlValue(v) }
				else { return error('unnest requires an array') }
			}
		}
	}
}

// extract_index_path walks an IndexExpr chain and builds path segments.
// Returns the root name (e.g., "." or variable name).
fn extract_index_path(expr IndexExpr, mut segments []string) string {
	// Get index key
	idx := expr.index[0]
	match idx {
		LiteralExpr {
			v := idx.value
			match v {
				string { segments.insert(0, v) }
				i64 { segments.insert(0, '${v}') }
				else {}
			}
		}
		else {}
	}
	// Recurse into container
	container := expr.expr[0]
	match container {
		IndexExpr {
			return extract_index_path(container, mut segments)
		}
		IdentExpr {
			return container.name
		}
		PathExpr {
			return container.path
		}
		else {
			return '.'
		}
	}
}

// unnest_path handles unnest for path expressions (rooted at .)
fn (mut rt Runtime) unnest_path(path string) !VrlValue {
	// Get the array value at the path
	arr_val := rt.get_path(path)!
	a := arr_val
	arr := match a {
		[]VrlValue { a }
		else { return error('unnest requires an array') }
	}

	// For each element, create a copy of root with the path set to that element
	mut result := []VrlValue{}
	for item in arr {
		mut new_rt := Runtime{
			object: rt.object.clone_map()
			metadata: rt.metadata.clone_map()
			vars: rt.vars.clone_map()
		}
		clean := if path.starts_with('.') { path[1..] } else { path }
		parts := split_path_segments(clean)
		new_rt.set_nested_path(parts, item)
		result << VrlValue(new_rt.object.clone_map())
	}
	return VrlValue(result)
}

// unnest_var handles unnest for variable-rooted paths
fn (mut rt Runtime) unnest_var(var_name string, segments []string) !VrlValue {
	// Build the full value from variable
	var_val := rt.vars.get(var_name) or { return error('unnest requires an array') }

	// Navigate to the nested array
	mut current := var_val
	for seg in segments {
		c := current
		match c {
			ObjectMap {
				current = c.get(seg) or { return error('unnest requires an array') }
			}
			[]VrlValue {
				idx := seg.int()
				if idx >= 0 && idx < c.len {
					current = c[idx]
				} else {
					return error('unnest requires an array')
				}
			}
			else {
				return error('unnest requires an array')
			}
		}
	}

	cv := current
	arr := match cv {
		[]VrlValue { cv }
		else { return error('unnest requires an array') }
	}

	// For each element, create a copy of the variable with the nested path set
	mut result := []VrlValue{}
	for item in arr {
		new_val := set_nested_in_value(var_val, segments, item)
		mut obj := new_object_map()
		// The result should be objects with the variable path included
		obj.set(var_name, new_val)
		// Actually in VRL, unnest on a variable returns objects structured
		// with the variable name as root (without the variable name prefix in the path)
		result << new_val
	}
	return VrlValue(result)
}

// set_nested_in_value sets a value at a nested path within a VrlValue
fn set_nested_in_value(root VrlValue, segments []string, val VrlValue) VrlValue {
	if segments.len == 0 {
		return val
	}
	seg := segments[0]
	rest := segments[1..]

	r := root
	match r {
		ObjectMap {
			mut m := r.clone_map()
			if rest.len == 0 {
				m.set(seg, val)
			} else {
				existing := m.get(seg) or { VrlValue(VrlNull{}) }
				m.set(seg, set_nested_in_value(existing, rest, val))
			}
			return VrlValue(m)
		}
		[]VrlValue {
			idx := seg.int()
			if idx >= 0 && idx < r.len {
				mut arr := r.clone()
				if rest.len == 0 {
					arr[idx] = val
				} else {
					arr[idx] = set_nested_in_value(r[idx], rest, val)
				}
				return VrlValue(arr)
			}
			return root
		}
		else {
			// Try to create the appropriate container
			if is_numeric_segment(seg) {
				idx := seg.int()
				mut arr := []VrlValue{len: idx + 1, init: VrlValue(VrlNull{})}
				arr[idx] = if rest.len == 0 { val } else { set_nested_in_value(VrlValue(VrlNull{}), rest, val) }
				return VrlValue(arr)
			}
			mut m := new_object_map()
			m.set(seg, if rest.len == 0 { val } else { set_nested_in_value(VrlValue(VrlNull{}), rest, val) })
			return VrlValue(m)
		}
	}
}

// object_from_array(values, [keys]) - convert to object
fn fn_object_from_array(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('object_from_array requires 1 argument')
	}
	a := args[0]
	arr := match a {
		[]VrlValue { a }
		else { return error('object_from_array requires an array') }
	}

	// If keys array provided, zip keys with values
	if args.len > 1 {
		keys_val := args[1]
		keys := match keys_val {
			[]VrlValue { keys_val }
			else { return error('keys must be an array') }
		}
		mut result := new_object_map()
		max_len := if arr.len > keys.len { keys.len } else { arr.len }
		for i in 0 .. max_len {
			k := keys[i]
			match k {
				string { result.set(k, arr[i]) }
				VrlNull {} // skip null keys
				else { result.set(vrl_to_string(k), arr[i]) }
			}
		}
		return VrlValue(result)
	}

	// Single array of [key, value] pairs
	mut result := new_object_map()
	for item in arr {
		i := item
		match i {
			[]VrlValue {
				if i.len >= 2 {
					key := i[0]
					match key {
						VrlNull {} // skip null keys
						string { result.set(key, i[1]) }
						else { result.set(vrl_to_string(key), i[1]) }
					}
				}
			}
			else {}
		}
	}
	return VrlValue(result)
}

// zip(keys, values)
fn fn_zip(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('zip requires at least 1 argument')
	}
	mut arrays := [][]VrlValue{}
	if args.len == 1 {
		// Single arg: must be an array of arrays
		a := args[0]
		match a {
			[]VrlValue {
				for item in a {
					inner := item
					match inner {
						[]VrlValue { arrays << inner }
						else { return error('zip requires an array of arrays') }
					}
				}
			}
			else { return error('zip requires an array argument') }
		}
	} else {
		// Multiple args: each is an array
		for i, a in args {
			arr := a
			match arr {
				[]VrlValue { arrays << arr }
				else { return error('zip argument ${i + 1} must be array') }
			}
		}
	}
	if arrays.len == 0 {
		return VrlValue([]VrlValue{})
	}
	// Find min length across all arrays
	mut min_len := arrays[0].len
	for arr in arrays {
		if arr.len < min_len {
			min_len = arr.len
		}
	}
	mut result := []VrlValue{}
	for i in 0 .. min_len {
		mut tuple := []VrlValue{}
		for arr in arrays {
			tuple << arr[i]
		}
		result << VrlValue(tuple)
	}
	return VrlValue(result)
}

// remove(value, path, [compact])
fn fn_remove(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('remove requires 2 arguments')
	}
	container := args[0]
	path := args[1]
	compact := if args.len > 2 { get_bool_arg(args[2], false) } else { false }
	segments := get_path_segments(path)
	result := remove_nested(container, segments)!
	if compact {
		return compact_remove_value(result)
	}
	return result
}

fn remove_nested(container VrlValue, segments []VrlValue) !VrlValue {
	if segments.len == 0 {
		return VrlValue(VrlNull{})
	}
	c := container
	seg := segments[0]
	rest := segments[1..]
	match c {
		ObjectMap {
			s := seg
			key := match s {
				string { s }
				i64 { '${s}' }
				else { return VrlValue(container) }
			}
			if rest.len == 0 {
				mut result := c.clone_map()
				result.delete(key)
				return VrlValue(result)
			}
			existing := c.get(key) or { return VrlValue(container) }
			new_val := remove_nested(existing, rest)!
			mut result := c.clone_map()
			result.set(key, new_val)
			return VrlValue(result)
		}
		[]VrlValue {
			s := seg
			idx := match s {
				i64 { if s < 0 { c.len + int(s) } else { int(s) } }
				string { s.int() }
				else { return VrlValue(container) }
			}
			if rest.len == 0 {
				if idx >= 0 && idx < c.len {
					mut result := []VrlValue{}
					for i, item in c {
						if i != idx {
							result << item
						}
					}
					return VrlValue(result)
				}
				return VrlValue(container)
			}
			if idx >= 0 && idx < c.len {
				new_val := remove_nested(c[idx], rest)!
				mut result := c.clone()
				result[idx] = new_val
				return VrlValue(result)
			}
			return VrlValue(container)
		}
		else {
			return VrlValue(container)
		}
	}
}

// compact_remove_value recursively removes empty objects and arrays
fn compact_remove_value(v VrlValue) VrlValue {
	val := v
	match val {
		ObjectMap {
			mut result := new_object_map()
			all_keys := val.keys()
			for k in all_keys {
				item := val.get(k) or { VrlValue(VrlNull{}) }
				compacted := compact_remove_value(item)
				c := compacted
				match c {
					ObjectMap {
						if c.len() > 0 {
							result.set(k, compacted)
						}
					}
					[]VrlValue {
						if c.len > 0 {
							result.set(k, compacted)
						}
					}
					VrlNull {}
					else {
						result.set(k, compacted)
					}
				}
			}
			return VrlValue(result)
		}
		[]VrlValue {
			mut result := []VrlValue{}
			for item in val {
				compacted := compact_remove_value(item)
				c := compacted
				match c {
					ObjectMap {
						if c.len() > 0 {
							result << compacted
						}
					}
					[]VrlValue {
						if c.len > 0 {
							result << compacted
						}
					}
					VrlNull {}
					else {
						result << compacted
					}
				}
			}
			return VrlValue(result)
		}
		else {
			return v
		}
	}
}
