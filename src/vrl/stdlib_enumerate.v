module vrl

import regex.pcre

// tally(value)
fn fn_tally(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('tally requires 1 argument')
	}
	a := args[0]
	arr := match a {
		[]VrlValue { a }
		else { return error('tally requires an array') }
	}
	mut result := new_object_map()
	for item in arr {
		key := vrl_to_string(item)
		if existing := result.get(key) {
			e := existing
			match e {
				int {
					result.set(key, VrlValue(e + 1))
				}
				else {
					result.set(key, VrlValue(1))
				}
			}
		} else {
			result.set(key, VrlValue(1))
		}
	}
	return VrlValue(result)
}

// tally_value(array, value) - count occurrences of value in array
fn fn_tally_value(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('tally_value requires 2 arguments')
	}
	a := args[0]
	arr := match a {
		[]VrlValue { a }
		else { return error('tally_value requires an array') }
	}
	target := args[1]
	mut count := 0
	for item in arr {
		if values_equal(item, target) {
			count++
		}
	}
	return VrlValue(count)
}

// match_array(value, pattern)
fn fn_match_array(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('match_array requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	arr := match a0 {
		[]VrlValue { a0 }
		else { return error('match_array first arg must be array') }
	}
	all := if args.len > 2 { get_bool_arg(args[2], false) } else { false }

	for item in arr {
		i := item
		s := match i {
			string { i }
			else { continue }
		}
		matched := match a1 {
			VrlRegex {
				re := pcre.compile(normalize_regex_pattern(a1.pattern)) or { continue }
				if _ := re.find(s) { true } else { false }
			}
			else { false }
		}
		if all {
			if !matched {
				return VrlValue(false)
			}
		} else {
			if matched {
				return VrlValue(true)
			}
		}
	}
	return VrlValue(all)
}
