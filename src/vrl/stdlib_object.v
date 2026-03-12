module vrl

// unnest(value) - expand array field into separate events
fn fn_unnest(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('unnest requires 1 argument')
	}
	a := args[0]
	match a {
		[]VrlValue {
			// Return the array elements as-is
			return VrlValue(a)
		}
		else { return error('unnest requires an array') }
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
	if args.len < 2 {
		return error('zip requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	keys := match a0 {
		[]VrlValue { a0 }
		else { return error('zip first arg must be array') }
	}
	vals := match a1 {
		[]VrlValue { a1 }
		else { return error('zip second arg must be array') }
	}
	mut result := []VrlValue{}
	max_len := if keys.len < vals.len { keys.len } else { vals.len }
	for i in 0 .. max_len {
		k := if i < keys.len { keys[i] } else { VrlValue(VrlNull{}) }
		v := if i < vals.len { vals[i] } else { VrlValue(VrlNull{}) }
		pair := [k, v]
		result << VrlValue(pair)
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
				int { '${s}' }
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
				int { if s < 0 { c.len + s } else { s } }
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
