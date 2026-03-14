module vrl

import math
import pcre2

enum CaseMode {
	camel
	pascal
	snake
	kebab
	screaming_snake
}

fn extract_words(args []VrlValue, func_name string) !(string, []string) {
	if args.len < 1 {
		return error('${func_name} requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('${func_name} requires a string') }
	}
	mut words := split_words(s)
	if args.len >= 2 {
		oc := args[1]
		match oc {
			string { words = split_words_by_case(s, oc) }
			else {}
		}
	}
	return s, words
}

fn capitalize_word(w string) string {
	mut result := []u8{}
	mut first := true
	for c in w.to_lower() {
		if first {
			if c >= `a` && c <= `z` {
				result << c - 32
			} else {
				result << c
			}
			first = false
		} else {
			result << c
		}
	}
	return result.bytestr()
}

fn convert_case(args []VrlValue, mode CaseMode) !VrlValue {
	func_name := match mode {
		.camel { 'camelcase' }
		.pascal { 'pascalcase' }
		.snake { 'snakecase' }
		.kebab { 'kebabcase' }
		.screaming_snake { 'screamingsnakecase' }
	}
	_, words := extract_words(args, func_name)!
	mut parts := []string{}
	sep := match mode {
		.snake, .screaming_snake { '_' }
		.kebab { '-' }
		else { '' }
	}
	for i, w in words {
		match mode {
			.camel {
				if i == 0 {
					parts << w.to_lower()
				} else {
					parts << capitalize_word(w)
				}
			}
			.pascal { parts << capitalize_word(w) }
			.snake, .kebab { parts << w.to_lower() }
			.screaming_snake { parts << w.to_upper() }
		}
	}
	return VrlValue(parts.join(sep))
}

fn fn_camelcase(args []VrlValue) !VrlValue { return convert_case(args, .camel) }
fn fn_pascalcase(args []VrlValue) !VrlValue { return convert_case(args, .pascal) }
fn fn_snakecase(args []VrlValue) !VrlValue { return convert_case(args, .snake) }
fn fn_kebabcase(args []VrlValue) !VrlValue { return convert_case(args, .kebab) }
fn fn_screamingsnakecase(args []VrlValue) !VrlValue { return convert_case(args, .screaming_snake) }

// split_words_by_case splits a string into words based on the specified original case.
// This matches the Rust convert_case crate's from_case() behavior:
// only use the boundaries appropriate for the declared case.
fn split_words_by_case(s string, original_case string) []string {
	normalized := original_case.to_lower().replace('-', '').replace('_', '').replace(' ', '')
	return match normalized {
		'snakecase', 'snake', 'screamingsnakecase', 'screamingsnake', 'screaming' {
			// Split on underscores only
			s.split('_')
		}
		'kebabcase', 'kebab' {
			// Split on hyphens only
			s.split('-')
		}
		'camelcase', 'camel', 'pascalcase', 'pascal' {
			// Split on uppercase letter boundaries only (no separator splitting)
			split_words_camel(s)
		}
		else {
			split_words(s)
		}
	}
}

// split_words_camel splits only on uppercase letter boundaries.
// Does NOT split on underscores, hyphens, or spaces.
fn split_words_camel(s string) []string {
	mut words := []string{}
	mut current := []u8{}
	bytes := s.bytes()
	for i := 0; i < bytes.len; i++ {
		c := bytes[i]
		if c >= `A` && c <= `Z` {
			// Check for transitions
			if current.len > 0 {
				// Check if this is part of an acronym (consecutive uppercase)
				prev_upper := i > 0 && bytes[i - 1] >= `A` && bytes[i - 1] <= `Z`
				next_lower := i + 1 < bytes.len && bytes[i + 1] >= `a` && bytes[i + 1] <= `z`
				if prev_upper && next_lower {
					// End of acronym: "XMLParser" → ["XML", "Parser"]
					words << current.bytestr()
					current = [c]
				} else if !prev_upper {
					// New word starts
					words << current.bytestr()
					current = [c]
				} else {
					current << c
				}
			} else {
				current << c
			}
		} else {
			current << c
		}
	}
	if current.len > 0 {
		words << current.bytestr()
	}
	return words
}

// split_words splits a string into words for case conversion.
// Handles camelCase, PascalCase, snake_case, kebab-case, spaces, etc.
fn split_words(s string) []string {
	mut words := []string{}
	mut current := []u8{}
	bytes := s.bytes()
	for i := 0; i < bytes.len; i++ {
		c := bytes[i]
		if c == `_` || c == `-` || c == ` ` || c == `\t` {
			if current.len > 0 {
				words << current.bytestr()
				current = []u8{}
			}
			continue
		}
		if c >= `A` && c <= `Z` {
			// Check for camelCase boundary
			if current.len > 0 {
				// Check if previous char was lowercase
				last := current[current.len - 1]
				if last >= `a` && last <= `z` {
					words << current.bytestr()
					current = []u8{}
				} else if last >= `A` && last <= `Z` && i + 1 < bytes.len {
					// Handle sequences like "XMLParser" -> "XML", "Parser"
					next := bytes[i + 1]
					if next >= `a` && next <= `z` && current.len > 1 {
						words << current.bytestr()
						current = []u8{}
					}
				}
			}
		}
		current << c
	}
	if current.len > 0 {
		words << current.bytestr()
	}
	return words
}

// basename(value, [extension])
fn fn_basename(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('basename requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('basename requires a string') }
	}
	if s == '/' || s.len == 0 {
		return VrlValue(VrlNull{})
	}
	// Remove trailing slashes
	mut path := s.trim_right('/')
	if path.len == 0 {
		return VrlValue(VrlNull{})
	}
	// Find last /
	idx := path.last_index('/') or { return VrlValue(path) }
	mut base := path[idx + 1..]
	// Remove extension if provided
	if args.len > 1 {
		ext := args[1]
		match ext {
			string {
				if base.ends_with(ext) {
					base = base[..base.len - ext.len]
				}
			}
			else {}
		}
	}
	return VrlValue(base)
}

// dirname(value)
fn fn_dirname(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('dirname requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('dirname requires a string') }
	}
	mut path := s.trim_right('/')
	if path.len == 0 {
		return VrlValue('/')
	}
	idx := path.last_index('/') or { return VrlValue('.') }
	if idx == 0 {
		return VrlValue('/')
	}
	return VrlValue(path[..idx])
}

// split_path(value)
fn fn_split_path(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('split_path requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('split_path requires a string') }
	}
	parts := s.split('/')
	mut result := []VrlValue{}
	if s.starts_with('/') {
		result << VrlValue('/')
	}
	for p in parts {
		if p.len > 0 {
			result << VrlValue(p)
		}
	}
	return VrlValue(result)
}

// strip_ansi_escape_codes(value)
fn fn_strip_ansi_escape_codes(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('strip_ansi_escape_codes requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('strip_ansi_escape_codes requires a string') }
	}
	// Remove ANSI escape sequences: ESC[ ... m and other CSI sequences
	mut result := []u8{cap: s.len}
	mut i := 0
	bytes := s.bytes()
	for i < bytes.len {
		if bytes[i] == 0x1B && i + 1 < bytes.len && bytes[i + 1] == `[` {
			// Skip CSI sequence until we find a letter
			i += 2
			for i < bytes.len {
				c := bytes[i]
				i++
				if (c >= `A` && c <= `Z`) || (c >= `a` && c <= `z`) {
					break
				}
			}
			continue
		}
		if bytes[i] == 0x1B && i + 1 < bytes.len && bytes[i + 1] == `]` {
			// OSC sequence - skip until ST (ESC \ or BEL)
			i += 2
			for i < bytes.len {
				if bytes[i] == 0x07 {
					i++
					break
				}
				if bytes[i] == 0x1B && i + 1 < bytes.len && bytes[i + 1] == `\\` {
					i += 2
					break
				}
				i++
			}
			continue
		}
		result << bytes[i]
		i++
	}
	return VrlValue(result.bytestr())
}

// shannon_entropy(value, [segmentation])
fn fn_shannon_entropy(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('shannon_entropy requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('shannon_entropy requires a string') }
	}
	segmentation := if args.len > 1 {
		v := args[1]
		match v {
			string { v }
			else { 'byte' }
		}
	} else {
		'byte'
	}
	if s.len == 0 {
		return VrlValue(f64(0.0))
	}
	match segmentation {
		'codepoint' {
			runes := s.runes()
			if runes.len == 0 {
				return VrlValue(f64(0.0))
			}
			mut freq := map[rune]int{}
			for r in runes {
				freq[r]++
			}
			total := f64(runes.len)
			mut entropy := f64(0.0)
			for _, count in freq {
				p := f64(count) / total
				if p > 0 {
					entropy -= p * math.log2(p)
				}
			}
			return VrlValue(entropy)
		}
		'grapheme' {
			// Simplified grapheme segmentation - use runes as approximation
			// True grapheme clusters would need Unicode tables
			runes := s.runes()
			if runes.len == 0 {
				return VrlValue(f64(0.0))
			}
			// Group combining characters with their base
			mut graphemes := []string{}
			mut current := []rune{}
			for r in runes {
				if is_combining_mark(r) && current.len > 0 {
					current << r
				} else {
					if current.len > 0 {
						mut buf := []u8{}
						for cr in current {
							buf << rune_to_utf8(cr)
						}
						graphemes << buf.bytestr()
					}
					current = [r]
				}
			}
			if current.len > 0 {
				mut buf := []u8{}
				for cr in current {
					buf << rune_to_utf8(cr)
				}
				graphemes << buf.bytestr()
			}
			if graphemes.len == 0 {
				return VrlValue(f64(0.0))
			}
			mut freq := map[string]int{}
			for g in graphemes {
				freq[g]++
			}
			total := f64(graphemes.len)
			mut entropy := f64(0.0)
			for _, count in freq {
				p := f64(count) / total
				if p > 0 {
					entropy -= p * math.log2(p)
				}
			}
			return VrlValue(entropy)
		}
		else {
			// byte mode (default)
			mut freq := [256]int{}
			bytes := s.bytes()
			for b in bytes {
				freq[b]++
			}
			total := f64(bytes.len)
			mut entropy := f64(0.0)
			for count in freq {
				if count > 0 {
					p := f64(count) / total
					entropy -= p * math.log2(p)
				}
			}
			return VrlValue(entropy)
		}
	}
}

fn is_combining_mark(r rune) bool {
	v := int(r)
	return (v >= 0x0300 && v <= 0x036F) || // Combining Diacritical Marks
		(v >= 0x1AB0 && v <= 0x1AFF) || // Combining Diacritical Marks Extended
		(v >= 0x1DC0 && v <= 0x1DFF) || // Combining Diacritical Marks Supplement
		(v >= 0x20D0 && v <= 0x20FF) || // Combining Diacritical Marks for Symbols
		(v >= 0xFE00 && v <= 0xFE0F) || // Variation Selectors
		(v >= 0xE0100 && v <= 0xE01EF) || // Variation Selectors Supplement
		(v >= 0x1F3FB && v <= 0x1F3FF) // Emoji skin tone modifiers
}

fn rune_to_utf8(r rune) []u8 {
	v := int(r)
	if v < 0x80 {
		return [u8(v)]
	}
	if v < 0x800 {
		return [u8(0xC0 | (v >> 6)), u8(0x80 | (v & 0x3F))]
	}
	if v < 0x10000 {
		return [u8(0xE0 | (v >> 12)), u8(0x80 | ((v >> 6) & 0x3F)), u8(0x80 | (v & 0x3F))]
	}
	return [u8(0xF0 | (v >> 18)), u8(0x80 | ((v >> 12) & 0x3F)), u8(0x80 | ((v >> 6) & 0x3F)),
		u8(0x80 | (v & 0x3F))]
}

// sieve(value, pattern, [replace_single, replace_repeated])
fn fn_sieve(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('sieve requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('sieve first arg must be string') }
	}
	pattern := match a1 {
		VrlRegex { a1.pattern }
		string { a1 }
		else { return error('sieve second arg must be regex') }
	}
	replace_single := if args.len > 2 {
		v := args[2]
		match v {
			string { v }
			else { '' }
		}
	} else {
		''
	}
	replace_repeated := if args.len > 3 {
		v := args[3]
		match v {
			string { v }
			else { '' }
		}
	} else {
		''
	}
	re := pcre2.compile(pattern) or {
		return error('invalid regex: ${pattern}')
	}

	// Build a list of matching/non-matching segments
	runes := s.runes()
	mut matches := []bool{len: runes.len}
	for i, r in runes {
		char_bytes := rune_to_utf8(r)
		char_str := char_bytes.bytestr()
		if m := re.find(char_str) {
			matches[i] = m.start == 0 && m.end == char_str.len
		}
	}

	mut result := []u8{}
	mut i2 := 0
	for i2 < runes.len {
		if matches[i2] {
			result << rune_to_utf8(runes[i2])
			i2++
		} else {
			// Count consecutive non-matching chars
			mut run_len := 0
			for i2 + run_len < runes.len && !matches[i2 + run_len] {
				run_len++
			}
			if run_len > 1 && replace_repeated.len > 0 {
				// Replace entire run with replace_repeated
				for c in replace_repeated {
					result << c
				}
			} else if replace_single.len > 0 {
				// Replace each char individually with replace_single
				for _ in 0 .. run_len {
					for c in replace_single {
						result << c
					}
				}
			} else if replace_repeated.len > 0 {
				// Single char but only replace_repeated is set
				for c in replace_repeated {
					result << c
				}
			}
			// else: no replacement, chars are just dropped
			i2 += run_len
		}
	}
	return VrlValue(result.bytestr())
}

// replace_with(value, pattern, closure) - handled as special function in eval
fn (mut rt Runtime) fn_replace_with(expr FnCallExpr) !VrlValue {
	if expr.args.len < 2 {
		return error('replace_with requires 2 arguments')
	}
	value := rt.eval(expr.args[0])!
	s := match value {
		string { value as string }
		else { return error('replace_with first arg must be string') }
	}
	pattern_val := rt.eval(expr.args[1])!
	pattern := match pattern_val {
		VrlRegex { (pattern_val as VrlRegex).pattern }
		string { pattern_val as string }
		else { return error('replace_with second arg must be regex') }
	}

	// Get count named arg if present
	mut count := -1
	if expr.arg_names.len > 0 {
		for i, an in expr.arg_names {
			if an == 'count' {
				cv := rt.eval(expr.args[i])!
				c := cv
				match c {
					i64 { count = int(c) }
					else {}
				}
			}
		}
	}

	if count == 0 {
		return VrlValue(s)
	}

	if expr.closure.len == 0 {
		return error('replace_with requires a closure')
	}
	closure_expr := expr.closure[0]
	if closure_expr is ClosureExpr {
		// Validate capture group names - "string" and "captures" are reserved
		if pattern.contains('(?P<string>') || pattern.contains('(?P<captures>') {
			return error('function call error for "replace_with": Capture group cannot be named "string" or "captures"')
		}

		re := pcre2.compile(pattern) or {
			return error('invalid regex: ${pattern}')
		}

		saved := rt.save_closure_params(closure_expr.params)

		// Find all matches
		matches := re.find_all(s)
		if matches.len == 0 {
			rt.restore_closure_params(saved, closure_expr.params)
			return VrlValue(s)
		}

		mut result := []u8{}
		mut pos := 0
		mut replacements := 0

		for m in matches {
			if count > 0 && replacements >= count {
				break
			}
			// Add text before match
			for i in pos .. m.start {
				result << s[i]
			}

			// Build match object
			matched_str := s[m.start..m.end]
			mut match_obj := new_object_map()
			match_obj.set('string', VrlValue(matched_str))

			// Get capture groups
			mut captures := []VrlValue{}
			for grp in m.groups {
				if grp.len > 0 {
					captures << VrlValue(grp)
				} else {
					captures << VrlValue(VrlNull{})
				}
			}
			match_obj.set('captures', VrlValue(captures))

			// Set closure param
			if closure_expr.params.len > 0 {
				rt.vars.set(closure_expr.params[0].trim_left('_'), VrlValue(match_obj))
			}

			// Evaluate closure
			replacement := rt.eval(closure_expr.body[0]) or {
				rt.restore_closure_params(saved, closure_expr.params)
				return error('function call error for "replace_with" at (1:1): ${err}')
			}
			if rt.returned {
				rt.returned = false
			}
			rep_str := match replacement {
				string { replacement as string }
				else { return error('replace_with closure must return a string') }
			}
			for c in rep_str {
				result << c
			}
			pos = m.end
			replacements++
		}

		// Add remaining text
		for i in pos .. s.len {
			result << s[i]
		}

		rt.restore_closure_params(saved, closure_expr.params)
		return VrlValue(result.bytestr())
	}
	return error('replace_with requires a closure')
}
