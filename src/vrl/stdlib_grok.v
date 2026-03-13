module vrl

import regex.pcre

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

// grok_strip_unsupported removes regex features unsupported by V's regex engine:
// - Lookahead/lookbehind assertions: (?=...) (?!...) (?<=...) (?<!...) → removed
// - Atomic groups: (?>...) → converted to regular groups (...)
fn grok_strip_unsupported(pattern string) string {
	mut result := []u8{}
	mut i := 0
	bytes := pattern.bytes()
	for i < bytes.len {
		// Skip escaped characters
		if bytes[i] == `\\` && i + 1 < bytes.len {
			result << bytes[i]
			result << bytes[i + 1]
			i += 2
			continue
		}
		// Check for special group syntax starting with (?
		if bytes[i] == `(` && i + 1 < bytes.len && bytes[i + 1] == `?` {
			// Lookaround: (?= (?! (?<= (?<!
			is_lookaround := if i + 2 < bytes.len {
				if bytes[i + 2] == `=` || bytes[i + 2] == `!` {
					true
				} else if bytes[i + 2] == `<` && i + 3 < bytes.len
					&& (bytes[i + 3] == `=` || bytes[i + 3] == `!`) {
					true
				} else {
					false
				}
			} else {
				false
			}
			if is_lookaround {
				// Skip the entire lookaround group by counting parens
				mut depth := 1
				mut j := i + 2
				for j < bytes.len && depth > 0 {
					if bytes[j] == `\\` {
						j += 2
						continue
					}
					if bytes[j] == `(` {
						depth++
					} else if bytes[j] == `)` {
						depth--
					}
					j++
				}
				i = j
				continue
			}
			// Atomic group: (?> → convert to regular group (
			if i + 2 < bytes.len && bytes[i + 2] == `>` {
				result << `(`
				i += 3 // skip (?>
				continue
			}
		}
		result << bytes[i]
		i++
	}
	return result.bytestr()
}

// grok_extract_group_names extracts the ordered list of named capture groups
// from the expanded regex pattern (after lookaround stripping).
fn grok_extract_group_names(pattern string) []string {
	mut names := []string{}
	mut i := 0
	bytes := pattern.bytes()
	for i < bytes.len {
		if bytes[i] == `\\` {
			i += 2
			continue
		}
		if bytes[i] == `(` {
			if i + 3 < bytes.len && bytes[i + 1] == `?` && bytes[i + 2] == `P`
				&& bytes[i + 3] == `<` {
				name_start := i + 4
				mut name_end := name_start
				for name_end < bytes.len && bytes[name_end] != `>` {
					name_end++
				}
				if name_end > name_start {
					names << pattern[name_start..name_end]
				}
				i = name_end + 1
			} else if i + 1 < bytes.len && bytes[i + 1] == `?` {
				i += 2
			} else {
				names << ''
				i++
			}
		} else {
			i++
		}
	}
	return names
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

	// Strip lookaround assertions since V's regex engine doesn't support them.
	// For grok patterns with full-string anchoring, these are unnecessary.
	cleaned := grok_strip_unsupported(expanded)

	full_pattern := '^${cleaned}\$'

	re := pcre.compile(full_pattern) or {
		return error('unable to compile grok pattern: ${err.msg()}')
	}

	m := re.find(input) or {
		return error('unable to parse input with grok pattern')
	}

	names := grok_extract_group_names(cleaned)
	mut result := new_object_map()
	for i, grp in m.groups {
		if i < names.len && names[i].len > 0 {
			result.set(names[i], VrlValue(grp))
		}
	}

	return VrlValue(result)
}
