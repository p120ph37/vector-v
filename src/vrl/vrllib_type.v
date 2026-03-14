module vrl

// is_empty(value)
fn fn_is_empty(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('is_empty requires 1 argument')
	}
	a := args[0]
	match a {
		string { return VrlValue(a.len == 0) }
		[]VrlValue { return VrlValue(a.len == 0) }
		ObjectMap { return VrlValue(a.len() == 0) }
		else { return VrlValue(true) }
	}
}

// is_json(value, [variant])
fn fn_is_json(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('is_json requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return VrlValue(false) }
	}
	variant := if args.len > 1 {
		v := args[1]
		match v {
			string { v }
			else { '' }
		}
	} else {
		''
	}
	trimmed := s.trim_space()
	if trimmed.len == 0 {
		return VrlValue(false)
	}
	// Try to parse as JSON
	result := parse_json_recursive(trimmed) or { return VrlValue(false) }
	if variant.len == 0 {
		return VrlValue(true)
	}
	// Check variant
	r := result
	match variant {
		'object' {
			return VrlValue(r is ObjectMap)
		}
		'array' {
			return VrlValue(r is []VrlValue)
		}
		'string' {
			return VrlValue(r is string)
		}
		'number' {
			return VrlValue(r is i64 || r is f64)
		}
		'bool' {
			return VrlValue(r is bool)
		}
		'null' {
			return VrlValue(r is VrlNull)
		}
		else {
			return VrlValue(true)
		}
	}
}

// is_regex(value)
fn fn_is_regex(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return VrlValue(false)
	}
	a := args[0]
	return VrlValue(a is VrlRegex)
}

// is_timestamp(value)
fn fn_is_timestamp(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return VrlValue(false)
	}
	a := args[0]
	return VrlValue(a is Timestamp)
}

// timestamp(value) - coerce to timestamp
fn fn_timestamp(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('timestamp requires 1 argument')
	}
	a := args[0]
	match a {
		Timestamp { return VrlValue(a) }
		else { return error('expected timestamp, got ${vrl_type_name(a)}') }
	}
}

// tag_types_externally(value)
fn fn_tag_types_externally(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('tag_types_externally requires 1 argument')
	}
	return tag_types_ext(args[0])
}

fn tag_types_ext(v VrlValue) !VrlValue {
	val := v
	match val {
		string {
			mut obj := new_object_map()
			obj.set(vrl_type_name(v), v)
			return VrlValue(obj)
		}
		i64 {
			mut obj := new_object_map()
			obj.set('integer', v)
			return VrlValue(obj)
		}
		f64 {
			mut obj := new_object_map()
			obj.set('float', v)
			return VrlValue(obj)
		}
		bool {
			mut obj := new_object_map()
			obj.set('boolean', v)
			return VrlValue(obj)
		}
		VrlNull {
			return VrlValue(VrlNull{})
		}
		Timestamp {
			mut obj := new_object_map()
			obj.set('timestamp', VrlValue(format_timestamp(val.t)))
			return VrlValue(obj)
		}
		[]VrlValue {
			mut result := []VrlValue{}
			for item in val {
				result << tag_types_ext(item)!
			}
			return VrlValue(result)
		}
		ObjectMap {
			mut inner := new_object_map()
			all_keys := val.keys()
			for k in all_keys {
				item := val.get(k) or { VrlValue(VrlNull{}) }
				inner.set(k, tag_types_ext(item)!)
			}
			mut obj := new_object_map()
			obj.set('object', VrlValue(inner))
			return VrlValue(obj)
		}
		VrlRegex {
			mut obj := new_object_map()
			obj.set('regex', VrlValue(val.pattern))
			return VrlValue(obj)
		}
	}
}
