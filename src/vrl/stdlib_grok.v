module vrl

import pcre2

// parse_grok implements the VRL parse_grok(value, pattern) function.
// It parses a string using a grok pattern and returns an object of named captures.
//
// Grok patterns use the syntax: %{PATTERNNAME:capturename}
// The pattern is expanded recursively using built-in pattern definitions,
// then compiled as a regex with named capture groups.

// grok_find_closing_brace finds the index of '}' starting from pos.
fn grok_find_closing_brace(s string, start int) int {
	for i := start; i < s.len; i++ {
		if s[i] == `}` {
			return i
		}
	}
	return -1
}

// grok_expand_pattern recursively expands %{NAME} and %{NAME:alias} references
// in a grok pattern into their regex equivalents.
fn grok_expand_pattern(pattern string, patterns map[string]string, depth int) !string {
	if depth > 100 {
		return error('grok pattern recursion limit exceeded')
	}
	mut result := []u8{}
	mut i := 0
	bytes := pattern.bytes()
	for i < bytes.len {
		if i + 1 < bytes.len && bytes[i] == `%` && bytes[i + 1] == `{` {
			end := grok_find_closing_brace(pattern, i + 2)
			if end < 0 {
				result << bytes[i]
				i++
				continue
			}
			inner := pattern[i + 2..end]
			parts := inner.split(':')
			pat_name := parts[0]
			alias := if parts.len > 1 { parts[1] } else { '' }
			if expanded_pat := patterns[pat_name] {
				sub := grok_expand_pattern(expanded_pat, patterns, depth + 1)!
				if alias.len > 0 {
					result << '(?P<${alias}>${sub})'.bytes()
				} else {
					result << '(?:${sub})'.bytes()
				}
			} else {
				return error('unknown grok pattern: ${pat_name}')
			}
			i = end + 1
		} else {
			result << bytes[i]
			i++
		}
	}
	return result.bytestr()
}

// fn_parse_grok implements parse_grok(value, pattern).
fn fn_parse_grok(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('parse_grok requires 2 arguments')
	}
	input := match args[0] {
		string { args[0] as string }
		else { return error('parse_grok requires a string value') }
	}
	pattern := match args[1] {
		string { args[1] as string }
		else { return error('parse_grok requires a string pattern') }
	}

	patterns := grok_builtin_patterns()
	expanded := grok_expand_pattern(pattern, patterns, 0)!

	full_pattern := '^${expanded}\$'

	re := pcre2.compile(full_pattern) or {
		return error('unable to compile grok pattern: ${err.msg()}')
	}

	m := re.find(input) or {
		return error('unable to parse input with grok pattern')
	}

	mut result := new_object_map()
	for i, grp in m.groups {
		if i < re.group_names.len && re.group_names[i].len > 0 {
			result.set(re.group_names[i], VrlValue(grp))
		}
	}

	return VrlValue(result)
}
