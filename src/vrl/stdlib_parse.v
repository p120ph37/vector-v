module vrl

import regex.pcre
import time

// extract_named_groups parses (?P<name>...) from a regex pattern
fn extract_named_groups(pattern string) []string {
	mut names := []string{}
	mut i := 0
	mut group_idx := 0
	for i < pattern.len {
		if pattern[i] == `\\` {
			i += 2
			continue
		}
		if pattern[i] == `(` {
			if i + 3 < pattern.len && pattern[i + 1] == `?` {
				if pattern[i + 2] == `P` && pattern[i + 3] == `<` {
					// Named group (?P<name>...)
					name_start := i + 4
					mut name_end := name_start
					for name_end < pattern.len && pattern[name_end] != `>` {
						name_end++
					}
					names << pattern[name_start..name_end]
					group_idx++
					i = name_end + 1
					continue
				}
				// Non-capturing group (?:...) or other
				if pattern[i + 2] != `:` && pattern[i + 2] != `=` && pattern[i + 2] != `!`
					&& pattern[i + 2] != `<` {
					// Could be flags like (?i)
				}
				i++
				continue
			}
			// Regular capturing group
			names << ''
			group_idx++
		}
		i++
	}
	return names
}

// parse_regex(value, pattern)
fn fn_parse_regex(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('parse_regex requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('parse_regex first arg must be string') }
	}
	pattern := match a1 {
		VrlRegex { a1.pattern }
		string { a1 }
		else { return error('parse_regex second arg must be regex') }
	}
	re := pcre.compile(normalize_regex_pattern(pattern)) or {
		return error('invalid regex: ${pattern}')
	}
	m := re.find(s) or {
		return error('no match')
	}
	names := extract_named_groups(pattern)
	mut result := new_object_map()
	// Index 0 is the full match
	result.set('0', VrlValue(s[m.start..m.end]))
	// Numbered and named capture groups
	for i, grp in m.groups {
		result.set('${i + 1}', VrlValue(grp))
		if i < names.len && names[i].len > 0 {
			result.set(names[i], VrlValue(grp))
		}
	}
	return VrlValue(result)
}

// parse_regex_all(value, pattern)
fn fn_parse_regex_all(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('parse_regex_all requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('parse_regex_all first arg must be string') }
	}
	pattern := match a1 {
		VrlRegex { a1.pattern }
		string { a1 }
		else { return error('parse_regex_all second arg must be regex') }
	}
	re := pcre.compile(normalize_regex_pattern(pattern)) or {
		return error('invalid regex: ${pattern}')
	}
	names := extract_named_groups(pattern)
	mut results := []VrlValue{}
	mut pos := 0
	for pos <= s.len {
		m := re.find(s[pos..]) or { break }
		if m.start == m.end && m.start == 0 && pos > 0 {
			pos++
			continue
		}
		mut obj := new_object_map()
		obj.set('0', VrlValue(s[pos + m.start..pos + m.end]))
		for i, grp in m.groups {
			obj.set('${i + 1}', VrlValue(grp))
			if i < names.len && names[i].len > 0 {
				obj.set(names[i], VrlValue(grp))
			}
		}
		results << VrlValue(obj)
		pos += m.end
		if m.start == m.end {
			pos++
		}
	}
	return VrlValue(results)
}

// parse_key_value(value, [key_value_delimiter, field_delimiter, whitespace, accept_standalone_key])
fn fn_parse_key_value(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_key_value requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_key_value first arg must be string') }
	}
	kv_delim := if args.len > 1 {
		v := args[1]
		match v {
			string { v }
			else { '=' }
		}
	} else {
		'='
	}
	field_delim := if args.len > 2 {
		v := args[2]
		match v {
			string { v }
			else { ' ' }
		}
	} else {
		' '
	}
	accept_standalone := if args.len > 4 { get_bool_arg(args[4], true) } else { true }

	mut result := new_object_map()
	fields := if field_delim == ' ' {
		split_kv_fields_whitespace(s)
	} else {
		s.split(field_delim)
	}
	for field in fields {
		trimmed := field.trim_space()
		if trimmed.len == 0 {
			continue
		}
		idx := trimmed.index(kv_delim) or {
			if accept_standalone {
				result.set(trimmed, VrlValue(true))
			}
			continue
		}
		key := trimmed[..idx].trim_space()
		mut value := trimmed[idx + kv_delim.len..].trim_space()
		// Remove surrounding quotes
		if value.len >= 2 {
			if (value[0] == `"` && value[value.len - 1] == `"`)
				|| (value[0] == `'` && value[value.len - 1] == `'`) {
				value = value[1..value.len - 1]
			}
		}
		if key.len > 0 {
			result.set(key, VrlValue(value))
		}
	}
	return VrlValue(result)
}

fn split_kv_fields_whitespace(s string) []string {
	mut fields := []string{}
	mut current := []u8{}
	mut in_quote := u8(0)
	for c in s.bytes() {
		if in_quote != 0 {
			current << c
			if c == in_quote {
				in_quote = 0
			}
			continue
		}
		if c == `"` || c == `'` {
			in_quote = c
			current << c
			continue
		}
		if c == ` ` || c == `\t` {
			if current.len > 0 {
				fields << current.bytestr()
				current = []u8{}
			}
			continue
		}
		current << c
	}
	if current.len > 0 {
		fields << current.bytestr()
	}
	return fields
}

// parse_csv(value, [delimiter])
fn fn_parse_csv(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_csv requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_csv requires a string') }
	}
	delimiter := if args.len > 1 {
		v := args[1]
		match v {
			string {
				if v.len > 0 { v[0] } else { `,` }
			}
			else { `,` }
		}
	} else {
		`,`
	}
	rows := parse_csv_string(s, delimiter)
	if rows.len == 1 {
		return VrlValue(rows[0])
	}
	mut result := []VrlValue{}
	for row in rows {
		result << VrlValue(row)
	}
	return VrlValue(result)
}

fn parse_csv_string(s string, delimiter u8) [][]VrlValue {
	mut rows := [][]VrlValue{}
	mut current_row := []VrlValue{}
	mut field := []u8{}
	mut in_quotes := false
	mut i := 0
	bytes := s.bytes()
	for i < bytes.len {
		c := bytes[i]
		if in_quotes {
			if c == `"` {
				if i + 1 < bytes.len && bytes[i + 1] == `"` {
					field << `"`
					i += 2
					continue
				}
				in_quotes = false
				i++
				continue
			}
			field << c
			i++
			continue
		}
		if c == `"` {
			in_quotes = true
			i++
			continue
		}
		if c == delimiter {
			current_row << VrlValue(field.bytestr())
			field = []u8{}
			i++
			continue
		}
		if c == `\n` || (c == `\r` && i + 1 < bytes.len && bytes[i + 1] == `\n`) {
			current_row << VrlValue(field.bytestr())
			field = []u8{}
			rows << current_row
			current_row = []VrlValue{}
			if c == `\r` {
				i += 2
			} else {
				i++
			}
			continue
		}
		field << c
		i++
	}
	current_row << VrlValue(field.bytestr())
	rows << current_row
	return rows
}

// parse_url(value)
fn fn_parse_url(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_url requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_url requires a string') }
	}
	return parse_url_string(s)
}

fn parse_url_string(s string) !VrlValue {
	mut result := new_object_map()
	mut remaining := s

	// Extract fragment
	mut fragment := ''
	if frag_idx := remaining.index('#') {
		fragment = remaining[frag_idx + 1..]
		remaining = remaining[..frag_idx]
	}
	result.set('fragment', if fragment.len > 0 { VrlValue(fragment) } else { VrlValue(VrlNull{}) })

	// Extract query
	mut query_str := ''
	if q_idx := remaining.index('?') {
		query_str = remaining[q_idx + 1..]
		remaining = remaining[..q_idx]
	}

	// Extract scheme
	mut scheme := ''
	if scheme_idx := remaining.index('://') {
		scheme = remaining[..scheme_idx]
		remaining = remaining[scheme_idx + 3..]
	}
	result.set('scheme', VrlValue(scheme))

	// Extract path
	mut path := '/'
	if path_idx := remaining.index('/') {
		path = remaining[path_idx..]
		remaining = remaining[..path_idx]
	}
	result.set('path', VrlValue(path))

	// Extract userinfo
	mut username := ''
	mut password := ''
	if at_idx := remaining.index('@') {
		userinfo := remaining[..at_idx]
		remaining = remaining[at_idx + 1..]
		if colon_idx := userinfo.index(':') {
			username = userinfo[..colon_idx]
			password = userinfo[colon_idx + 1..]
		} else {
			username = userinfo
		}
	}

	// Extract host and port
	mut host := remaining
	mut port := VrlValue(VrlNull{})
	if colon_idx := remaining.last_index(':') {
		possible_port := remaining[colon_idx + 1..]
		if possible_port.len > 0 && possible_port.bytes().all(it.is_digit()) {
			host = remaining[..colon_idx]
			port = VrlValue(possible_port.int())
		}
	}
	result.set('host', VrlValue(host))
	result.set('port', port)
	result.set('username', VrlValue(username))
	result.set('password', VrlValue(password))

	// Parse query string
	result.set('query', parse_qs_to_object(query_str))
	return VrlValue(result)
}

// parse_query_string(value)
fn fn_parse_query_string(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_query_string requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_query_string requires a string') }
	}
	// Remove leading ? if present
	qs := if s.starts_with('?') { s[1..] } else { s }
	return parse_qs_to_object(qs)
}

fn parse_qs_to_object(qs string) VrlValue {
	mut result := new_object_map()
	if qs.len == 0 {
		return VrlValue(result)
	}
	pairs := qs.split('&')
	for pair in pairs {
		if pair.len == 0 {
			continue
		}
		eq_idx := pair.index('=') or {
			result.set(percent_decode(pair), VrlValue(''))
			continue
		}
		key := percent_decode(pair[..eq_idx])
		value := percent_decode(pair[eq_idx + 1..])
		// If key already exists, convert to array
		if existing := result.get(key) {
			e := existing
			match e {
				[]VrlValue {
					mut arr := e.clone()
					arr << VrlValue(value)
					result.set(key, VrlValue(arr))
				}
				else {
					result.set(key, VrlValue([existing, VrlValue(value)]))
				}
			}
		} else {
			result.set(key, VrlValue(value))
		}
	}
	return VrlValue(result)
}

// parse_tokens(value, [pattern])
fn fn_parse_tokens(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_tokens requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_tokens requires a string') }
	}
	// Extract quoted strings and non-whitespace tokens
	mut tokens := []VrlValue{}
	mut i := 0
	bytes := s.bytes()
	for i < bytes.len {
		// Skip whitespace
		if bytes[i] == ` ` || bytes[i] == `\t` {
			i++
			continue
		}
		// Check for quoted string
		if bytes[i] == `"` || bytes[i] == `'` || bytes[i] == `[` {
			close := if bytes[i] == `[` { `]` } else { bytes[i] }
			i++
			mut token := []u8{}
			for i < bytes.len && bytes[i] != close {
				if bytes[i] == `\\` && i + 1 < bytes.len {
					i++
				}
				token << bytes[i]
				i++
			}
			if i < bytes.len {
				i++
			}
			tokens << VrlValue(token.bytestr())
			continue
		}
		// Skip special delimiters
		if bytes[i] == `-` {
			i++
			continue
		}
		// Read non-whitespace token
		mut token := []u8{}
		for i < bytes.len && bytes[i] != ` ` && bytes[i] != `\t` {
			token << bytes[i]
			i++
		}
		tokens << VrlValue(token.bytestr())
	}
	return VrlValue(tokens)
}

// parse_duration(value, output_unit)
fn fn_parse_duration(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('parse_duration requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('parse_duration first arg must be string') }
	}
	unit := match a1 {
		string { a1 }
		else { return error('parse_duration second arg must be string') }
	}
	// Parse number and unit from string
	mut num_end := 0
	for num_end < s.len && (s[num_end].is_digit() || s[num_end] == `.`) {
		num_end++
	}
	if num_end == 0 {
		return error('unable to parse duration: ${s}')
	}
	value := s[..num_end].f64()
	src_unit := s[num_end..].trim_space()

	// Convert to nanoseconds first
	ns := match src_unit {
		'ns' { value }
		'us', 'µs' { value * 1000.0 }
		'ms' { value * 1_000_000.0 }
		's' { value * 1_000_000_000.0 }
		'm' { value * 60_000_000_000.0 }
		'h' { value * 3_600_000_000_000.0 }
		'd' { value * 86_400_000_000_000.0 }
		else { return error('unknown duration unit: ${src_unit}') }
	}

	// Convert to output unit
	result := match unit {
		'ns' { ns }
		'us', 'µs' { ns / 1000.0 }
		'ms' { ns / 1_000_000.0 }
		's' { ns / 1_000_000_000.0 }
		'm' { ns / 60_000_000_000.0 }
		'h' { ns / 3_600_000_000_000.0 }
		'd' { ns / 86_400_000_000_000.0 }
		else { return error('unknown output unit: ${unit}') }
	}
	return VrlValue(result)
}

// parse_bytes(value)
fn fn_parse_bytes(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_bytes requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_bytes requires a string') }
	}
	// Get output unit (required)
	output_unit := if args.len > 1 {
		u := args[1]
		match u {
			string { u.to_lower() }
			else { 'b' }
		}
	} else {
		'b'
	}
	// Get base: "2" (binary, default) or "10" (SI/decimal)
	base_str := if args.len > 2 {
		b := args[2]
		match b {
			string { b }
			else { '2' }
		}
	} else {
		'2'
	}
	is_binary := base_str != '10'

	// Parse number and unit from input string
	mut num_end := 0
	for num_end < s.len && (s[num_end].is_digit() || s[num_end] == `.`) {
		num_end++
	}
	if num_end == 0 {
		return error('unable to parse bytes: ${s}')
	}
	value := s[..num_end].f64()
	input_unit := s[num_end..].trim_space().to_lower()

	// Convert input to bytes
	input_mult := bytes_multiplier(input_unit, is_binary)!
	// Convert output unit
	output_mult := bytes_multiplier(output_unit, is_binary)!

	result := (value * input_mult) / output_mult
	return VrlValue(result)
}

fn bytes_multiplier(unit string, is_binary bool) !f64 {
	k := if is_binary { 1024.0 } else { 1000.0 }
	return match unit {
		'b' { 1.0 }
		'kb', 'kib' { k }
		'mb', 'mib' { k * k }
		'gb', 'gib' { k * k * k }
		'tb', 'tib' { k * k * k * k }
		'pb', 'pib' { k * k * k * k * k }
		else { error('unknown byte unit: ${unit}') }
	}
}

// parse_int(value, base)
fn fn_parse_int(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_int requires at least 1 argument')
	}
	a0 := args[0]
	s := match a0 {
		string { a0 }
		else { return error('parse_int first arg must be string') }
	}
	base_val := if args.len > 1 {
		a1 := args[1]
		match a1 {
			int { a1 }
			else { 10 }
		}
	} else {
		10
	}
	// Parse integer with given base
	mut negative := false
	mut str := s
	if str.starts_with('-') {
		negative = true
		str = str[1..]
	} else if str.starts_with('+') {
		str = str[1..]
	}
	// Auto-detect base from prefix when using default base 10
	mut base := base_val
	if base == 10 {
		if str.starts_with('0x') || str.starts_with('0X') {
			base = 16
			str = str[2..]
		} else if str.starts_with('0o') || str.starts_with('0O') {
			base = 8
			str = str[2..]
		} else if str.starts_with('0b') || str.starts_with('0B') {
			base = 2
			str = str[2..]
		}
	} else if base == 16 && (str.starts_with('0x') || str.starts_with('0X')) {
		str = str[2..]
	} else if base == 8 && (str.starts_with('0o') || str.starts_with('0O')) {
		str = str[2..]
	} else if base == 2 && (str.starts_with('0b') || str.starts_with('0B')) {
		str = str[2..]
	}
	mut result := i64(0)
	for c in str.bytes() {
		digit := char_to_digit(c, base) or { return error('invalid digit in base ${base}: ${s}') }
		result = result * base + digit
	}
	if negative {
		result = -result
	}
	return VrlValue(int(result))
}

fn char_to_digit(c u8, base int) !i64 {
	val := if c >= `0` && c <= `9` {
		i64(c - `0`)
	} else if c >= `a` && c <= `z` {
		i64(c - `a` + 10)
	} else if c >= `A` && c <= `Z` {
		i64(c - `A` + 10)
	} else {
		return error('invalid digit')
	}
	if val >= base {
		return error('digit out of range for base')
	}
	return val
}

// parse_float(value) - already exists as to_float but this is for string parsing
fn fn_parse_float(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_float requires 1 argument')
	}
	a := args[0]
	match a {
		string { return VrlValue(a.f64()) }
		f64 { return VrlValue(a) }
		int { return VrlValue(f64(a)) }
		else { return error('parse_float requires a string') }
	}
}

// format_int(value, [base])
fn fn_format_int(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('format_int requires 1 argument')
	}
	a := args[0]
	val := match a {
		int { a }
		else { return error('format_int requires an integer') }
	}
	base := if args.len > 1 {
		b := args[1]
		match b {
			int { b }
			else { 10 }
		}
	} else {
		10
	}
	if base < 2 || base > 36 {
		return error('base must be between 2 and 36')
	}
	return VrlValue(int_to_base(val, base))
}

fn int_to_base(val int, base int) string {
	if val == 0 {
		return '0'
	}
	mut negative := false
	mut n := i64(val)
	if n < 0 {
		negative = true
		n = -n
	}
	digits := '0123456789abcdefghijklmnopqrstuvwxyz'
	mut result := []u8{}
	for n > 0 {
		result << digits[int(n % base)]
		n /= base
	}
	if negative {
		result << `-`
	}
	// Reverse
	mut reversed := []u8{cap: result.len}
	for i := result.len - 1; i >= 0; i-- {
		reversed << result[i]
	}
	return reversed.bytestr()
}

// parse_timestamp(value, format)
fn fn_parse_timestamp(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('parse_timestamp requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	s := match a0 {
		string { a0 }
		else { return error('parse_timestamp first arg must be string') }
	}
	fmt := match a1 {
		string { a1 }
		else { return error('parse_timestamp second arg must be string') }
	}
	// Special case: %+ means RFC3339/ISO8601
	if fmt == '%+' || fmt == '%Y-%m-%dT%H:%M:%S%z' || fmt == '%Y-%m-%dT%H:%M:%S%.f%z' {
		t := time.parse_rfc3339(s) or { return error('unable to parse timestamp: ${s}') }
		return VrlValue(Timestamp{t: t})
	}
	// Try V's built-in parsing for common formats
	if fmt == '%Y-%m-%dT%H:%M:%SZ' || fmt == '%Y-%m-%dT%H:%M:%S' {
		t := time.parse_rfc3339(s) or {
			t2 := time.parse_iso8601(s) or { return error('unable to parse timestamp: ${s}') }
			t2
		}
		return VrlValue(Timestamp{t: t})
	}
	// Convert strftime format to V time format
	v_fmt := strftime_to_v_format(fmt)
	t := time.parse_format(s, v_fmt) or { return error('unable to parse timestamp: ${s}') }
	return VrlValue(Timestamp{t: t})
}

fn strftime_to_v_format(fmt string) string {
	mut result := []u8{}
	mut i := 0
	for i < fmt.len {
		if fmt[i] == `%` && i + 1 < fmt.len {
			i++
			match fmt[i] {
				`Y` {
					for c in 'YYYY' {
						result << c
					}
				}
				`m` {
					for c in 'MM' {
						result << c
					}
				}
				`d` {
					for c in 'DD' {
						result << c
					}
				}
				`H` {
					for c in 'HH' {
						result << c
					}
				}
				`M` {
					for c in 'mm' {
						result << c
					}
				}
				`S` {
					for c in 'ss' {
						result << c
					}
				}
				`f` {
					for c in 'NNNNNN' {
						result << c
					}
				}
				`z` {
					for c in 'Z' {
						result << c
					}
				}
				`+` {
					for c in 'YYYY-MM-DDTHH:mm:ssZ' {
						result << c
					}
				}
				else {
					result << `%`
					result << fmt[i]
				}
			}
		} else {
			result << fmt[i]
		}
		i++
	}
	return result.bytestr()
}

// format_timestamp(value, format, [timezone])
fn fn_format_timestamp(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('format_timestamp requires 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	ts := match a0 {
		Timestamp { a0 }
		else { return error('format_timestamp first arg must be timestamp') }
	}
	fmt := match a1 {
		string { a1 }
		else { return error('format_timestamp second arg must be string') }
	}
	// Optional timezone argument (3rd positional or named 'timezone')
	tz_str := if args.len > 2 {
		a2 := args[2]
		match a2 {
			string { a2 }
			else { 'UTC' }
		}
	} else {
		'UTC'
	}
	offset_seconds := parse_tz_offset(tz_str) or { return error('unknown timezone: ${tz_str}') }
	adjusted := ts.t.add(offset_seconds * time.second)
	return VrlValue(strftime_format_with_offset(adjusted, fmt, offset_seconds))
}

// parse_tz_offset returns the UTC offset in seconds for a timezone string.
fn parse_tz_offset(tz string) !int {
	if tz == 'UTC' || tz == 'utc' || tz == 'GMT' || tz == 'gmt' {
		return 0
	}
	// Try fixed offset formats: +HH:MM, -HH:MM, +HHMM, -HHMM
	if tz.len >= 5 && (tz[0] == `+` || tz[0] == `-`) {
		sign := if tz[0] == `-` { -1 } else { 1 }
		rest := tz[1..]
		hours, minutes := if rest.contains(':') {
			parts := rest.split(':')
			if parts.len == 2 { parts[0].int(), parts[1].int() } else { return error('invalid tz') }
		} else if rest.len == 4 {
			rest[..2].int(), rest[2..].int()
		} else {
			return error('invalid tz')
		}
		return sign * (hours * 3600 + minutes * 60)
	}
	// Common IANA timezone abbreviations
	return match tz {
		'EST' { -5 * 3600 }
		'EDT' { -4 * 3600 }
		'CST' { -6 * 3600 }
		'CDT' { -5 * 3600 }
		'MST' { -7 * 3600 }
		'MDT' { -6 * 3600 }
		'PST' { -8 * 3600 }
		'PDT' { -7 * 3600 }
		'CET' { 1 * 3600 }
		'CEST' { 2 * 3600 }
		'JST' { 9 * 3600 }
		'IST' { 5 * 3600 + 1800 }
		'AEST' { 10 * 3600 }
		'AEDT' { 11 * 3600 }
		'NZST' { 12 * 3600 }
		'NZDT' { 13 * 3600 }
		'America/New_York' { -5 * 3600 }
		'America/Chicago' { -6 * 3600 }
		'America/Denver' { -7 * 3600 }
		'America/Los_Angeles' { -8 * 3600 }
		'Europe/London' { 0 }
		'Europe/Paris' { 1 * 3600 }
		'Europe/Berlin' { 1 * 3600 }
		'Asia/Tokyo' { 9 * 3600 }
		'Asia/Shanghai' { 8 * 3600 }
		'Asia/Kolkata' { 5 * 3600 + 1800 }
		'Australia/Sydney' { 10 * 3600 }
		'Pacific/Auckland' { 12 * 3600 }
		else { return error('unknown timezone: ${tz}') }
	}
}

fn strftime_format(t time.Time, fmt string) string {
	return strftime_format_with_offset(t, fmt, 0)
}

fn strftime_format_with_offset(t time.Time, fmt string, offset_seconds int) string {
	mut result := []u8{}
	mut i := 0
	for i < fmt.len {
		if fmt[i] == `%` && i + 1 < fmt.len {
			i++
			match fmt[i] {
				`Y` {
					for c in '${t.year:04d}' {
						result << c
					}
				}
				`m` {
					for c in '${t.month:02d}' {
						result << c
					}
				}
				`d` {
					for c in '${t.day:02d}' {
						result << c
					}
				}
				`H` {
					for c in '${t.hour:02d}' {
						result << c
					}
				}
				`M` {
					for c in '${t.minute:02d}' {
						result << c
					}
				}
				`S` {
					for c in '${t.second:02d}' {
						result << c
					}
				}
				`f` {
					us := int(t.unix_micro() % 1_000_000)
					for c in '${us:06d}' {
						result << c
					}
				}
				`3` {
					// %3f - milliseconds (3 digits)
					if i + 1 < fmt.len && fmt[i + 1] == `f` {
						ms := int((t.unix_micro() % 1_000_000) / 1000)
						for c in '${ms:03d}' {
							result << c
						}
						i++
					} else {
						result << `%`
						result << `3`
					}
				}
				`z` {
					oz := format_offset_hhmm(offset_seconds)
					for c in oz {
						result << c
					}
				}
				`Z` {
					for c in 'UTC' {
						result << c
					}
				}
				`v` {
					// %v: short date "day-Mon-year" e.g. "21-Oct-2020"
					months_v := ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
						'Oct', 'Nov', 'Dec']
					sv := '${t.day:2d}-${months_v[t.month - 1]}-${t.year:04d}'
					for c in sv {
						result << c
					}
				}
				`R` {
					// %R: 24-hour time without seconds "HH:MM"
					sr := '${t.hour:02d}:${t.minute:02d}'
					for c in sr {
						result << c
					}
				}
				`+` {
					// %+: RFC3339 with timezone offset
					off := format_offset_colon(offset_seconds)
					sp := '${t.year:04d}-${t.month:02d}-${t.day:02d}T${t.hour:02d}:${t.minute:02d}:${t.second:02d}${off}'
					for c in sp {
						result << c
					}
				}
				`a` {
					days := ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
					dow := int(t.day_of_week())
					for c in days[dow] {
						result << c
					}
				}
				`A` {
					days := ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
						'Saturday']
					dow := int(t.day_of_week())
					for c in days[dow] {
						result << c
					}
				}
				`b`, `h` {
					months := ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
						'Oct', 'Nov', 'Dec']
					for c in months[t.month - 1] {
						result << c
					}
				}
				`B` {
					months := ['January', 'February', 'March', 'April', 'May', 'June', 'July',
						'August', 'September', 'October', 'November', 'December']
					for c in months[t.month - 1] {
						result << c
					}
				}
				`p` {
					ampm := if t.hour < 12 { 'AM' } else { 'PM' }
					for c in ampm {
						result << c
					}
				}
				`P` {
					ampm := if t.hour < 12 { 'am' } else { 'pm' }
					for c in ampm {
						result << c
					}
				}
				`I` {
					h := if t.hour == 0 { 12 } else if t.hour > 12 { t.hour - 12 } else { t.hour }
					for c in '${h:02d}' {
						result << c
					}
				}
				`j` {
					for c in '${t.day:03d}' {
						result << c
					}
				}
				`e` {
					for c in '${t.day:2d}' {
						result << c
					}
				}
				`n` {
					result << `\n`
				}
				`t` {
					result << `\t`
				}
				`%` {
					result << `%`
				}
				else {
					result << `%`
					result << fmt[i]
				}
			}
		} else {
			result << fmt[i]
		}
		i++
	}
	return result.bytestr()
}

// format_offset_hhmm formats a UTC offset in seconds as "+HHMM" or "-HHMM".
fn format_offset_hhmm(offset_seconds int) string {
	sign := if offset_seconds < 0 { '-' } else { '+' }
	abs_off := if offset_seconds < 0 { -offset_seconds } else { offset_seconds }
	hours := abs_off / 3600
	minutes := (abs_off % 3600) / 60
	return '${sign}${hours:02d}${minutes:02d}'
}

// format_offset_colon formats a UTC offset in seconds as "+HH:MM" or "-HH:MM".
fn format_offset_colon(offset_seconds int) string {
	sign := if offset_seconds < 0 { '-' } else { '+' }
	abs_off := if offset_seconds < 0 { -offset_seconds } else { offset_seconds }
	hours := abs_off / 3600
	minutes := (abs_off % 3600) / 60
	return '${sign}${hours:02d}:${minutes:02d}'
}
