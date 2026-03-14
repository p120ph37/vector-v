module vrl

import os
import math
import pcre2
import time

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
	// Optional numeric_groups parameter (default: false)
	mut numeric_groups := false
	if args.len >= 3 {
		ng := args[2]
		match ng {
			bool { numeric_groups = ng }
			else {}
		}
	}
	re := pcre2.compile(pattern) or {
		return error('invalid regex: ${pattern}')
	}
	m := re.find(s) or {
		return error('no match')
	}
	mut result := new_object_map()
	if numeric_groups {
		// Include all numeric groups
		result.set('0', VrlValue(s[m.start..m.end]))
		for i, grp in m.groups {
			result.set('${i + 1}', VrlValue(grp))
		}
	}
	// Always include named groups
	for i, grp in m.groups {
		if i < re.group_names.len && re.group_names[i].len > 0 {
			result.set(re.group_names[i], VrlValue(grp))
		}
	}
	return VrlValue(result)
}

// parse_regex_all(value, pattern, numeric_groups)
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
	mut numeric_groups := false
	if args.len >= 3 {
		ng := args[2]
		match ng {
			bool { numeric_groups = ng }
			else {}
		}
	}
	re := pcre2.compile(pattern) or {
		return error('invalid regex: ${pattern}')
	}
	mut results := []VrlValue{}
	mut pos := 0
	for pos <= s.len {
		m := re.find(s[pos..]) or { break }
		if m.start == m.end && m.start == 0 && pos > 0 {
			pos++
			continue
		}
		mut obj := new_object_map()
		if numeric_groups {
			obj.set('0', VrlValue(s[pos + m.start..pos + m.end]))
			for i, grp in m.groups {
				obj.set('${i + 1}', VrlValue(grp))
			}
		}
		for i, grp in m.groups {
			if i < re.group_names.len && re.group_names[i].len > 0 {
				obj.set(re.group_names[i], VrlValue(grp))
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
			port = VrlValue(possible_port.i64())
		}
	}
	// Punycode-encode international domain names (like the url crate does)
	encoded_host := punycode_encode_domain(host)
	result.set('host', VrlValue(encoded_host))
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
// duration_unit_to_ns converts a value in the given unit to nanoseconds.
fn duration_unit_to_ns(value f64, unit string) !f64 {
	return match unit {
		'ns' { value }
		'us', 'µs' { value * 1000.0 }
		'ms' { value * 1_000_000.0 }
		's' { value * 1_000_000_000.0 }
		'm' { value * 60_000_000_000.0 }
		'h' { value * 3_600_000_000_000.0 }
		'd' { value * 86_400_000_000_000.0 }
		else { error('unknown duration unit: ${unit}') }
	}
}

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
	out_unit := match a1 {
		string { a1 }
		else { return error('parse_duration second arg must be string') }
	}

	// Parse one or more number+unit pairs (e.g., "1s", "1s 1ms", "2h 30m 15s")
	mut total_ns := f64(0)
	mut pos := 0
	mut parsed_any := false
	for pos < s.len {
		// Skip whitespace
		for pos < s.len && s[pos] == ` ` {
			pos++
		}
		if pos >= s.len { break }

		// Parse number
		mut num_end := pos
		for num_end < s.len && (s[num_end].is_digit() || s[num_end] == `.` || s[num_end] == `-`) {
			num_end++
		}
		if num_end == pos {
			return error('unable to parse duration: ${s}')
		}
		value := s[pos..num_end].f64()

		// Parse unit
		mut unit_end := num_end
		for unit_end < s.len && s[unit_end] != ` ` && !s[unit_end].is_digit() && s[unit_end] != `-` {
			unit_end++
		}
		src_unit := s[num_end..unit_end].trim_space()
		if src_unit.len == 0 {
			return error('unable to parse duration: ${s}')
		}

		total_ns += duration_unit_to_ns(value, src_unit)!
		parsed_any = true
		pos = unit_end
	}

	if !parsed_any {
		return error('unable to parse duration: ${s}')
	}

	// Convert to output unit
	result := match out_unit {
		'ns' { total_ns }
		'us', 'µs' { total_ns / 1000.0 }
		'ms' { total_ns / 1_000_000.0 }
		's' { total_ns / 1_000_000_000.0 }
		'm' { total_ns / 60_000_000_000.0 }
		'h' { total_ns / 3_600_000_000_000.0 }
		'd' { total_ns / 86_400_000_000_000.0 }
		else { return error('unknown output unit: ${out_unit}') }
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
			i64 { a1 }
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
		digit := char_to_digit(c, int(base)) or { return error('invalid digit in base ${base}: ${s}') }
		result = result * base + digit
	}
	if negative {
		result = -result
	}
	return VrlValue(i64(result))
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
		i64 { return VrlValue(f64(a)) }
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
		i64 { a }
		else { return error('format_int requires an integer') }
	}
	base := if args.len > 1 {
		b := args[1]
		match b {
			i64 { b }
			else { 10 }
		}
	} else {
		10
	}
	if base < 2 || base > 36 {
		return error('base must be between 2 and 36')
	}
	return VrlValue(int_to_base(int(val), int(base)))
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
	// Check if format contains %z (timezone offset) — V's parse_format doesn't support it,
	// so we strip the timezone from the input and format, parse the rest, then apply the offset.
	if fmt.contains('%z') {
		return parse_timestamp_with_tz(s, fmt)
	}
	// Expand shortcuts like %T -> %H:%M:%S and handle %b (month names)
	expanded := expand_strftime_shortcuts(fmt)
	processed_s2, processed_fmt2 := replace_month_name_in_input(s, expanded) or {
		return error('unable to parse timestamp: ${s}')
	}
	// Convert strftime format to V time format
	v_fmt := strftime_to_v_format(processed_fmt2)
	t := time.parse_format(processed_s2, v_fmt) or {
		return error('unable to parse timestamp: ${s}')
	}
	return VrlValue(Timestamp{t: t})
}

// parse_timestamp_with_tz handles formats containing %z by stripping the timezone offset
// from the input string, parsing the datetime portion, and then applying the offset.
fn parse_timestamp_with_tz(s string, fmt string) !VrlValue {
	// First expand shortcuts like %T -> %H:%M:%S
	expanded_fmt := expand_strftime_shortcuts(fmt)
	// Replace month names (%b) with numeric months in both input and format
	processed_s, processed_fmt := replace_month_name_in_input(s, expanded_fmt)!
	// Find where %z appears in the format to locate the timezone in the input string.
	// Build the format without %z and figure out what separates the tz from the rest.
	fmt_no_tz := processed_fmt.replace('%z', '').trim_right(' ')
	v_fmt := strftime_to_v_format(fmt_no_tz)

	// Find the timezone offset in the input string: look for +HHMM, -HHMM, +HH:MM, -HH:MM, or Z at the end
	mut tz_offset_seconds := 0
	mut datetime_str := processed_s
	trimmed := processed_s.trim_space()
	if trimmed.len >= 5 {
		// Try to find a timezone offset pattern at the end: +0600, -0530, +06:00, etc.
		mut tz_start := -1
		for idx := trimmed.len - 1; idx >= 0; idx-- {
			ch := trimmed[idx]
			if ch == `+` || ch == `-` {
				rest := trimmed[idx..]
				// Validate it looks like a tz offset: +HHMM or +HH:MM
				stripped := rest.replace(':', '')
				if stripped.len >= 5 && stripped[1..].bytes().all(it.is_digit()) {
					tz_start = idx
				}
				break
			}
			// Only digits and colons are valid in the tz portion
			if !ch.is_digit() && ch != `:` {
				break
			}
		}
		if tz_start >= 0 {
			tz_part := trimmed[tz_start..].trim_space()
			tz_offset_seconds = parse_tz_offset(tz_part) or { 0 }
			datetime_str = trimmed[..tz_start].trim_space()
		}
	}

	t := time.parse_format(datetime_str, v_fmt) or {
		return error('unable to parse timestamp: ${s}')
	}
	// Subtract the offset to convert local time to UTC
	utc_t := t.add(-tz_offset_seconds * time.second)
	return VrlValue(Timestamp{t: utc_t})
}

// expand_strftime_shortcuts expands strftime shortcut specifiers like %T -> %H:%M:%S
// before further processing. This must be called before strftime_to_v_format.
fn expand_strftime_shortcuts(fmt string) string {
	mut result := []u8{}
	mut i := 0
	for i < fmt.len {
		if fmt[i] == `%` && i + 1 < fmt.len {
			i++
			match fmt[i] {
				`T` {
					// %T is equivalent to %H:%M:%S
					for c in '%H:%M:%S' {
						result << c
					}
				}
				`R` {
					// %R is equivalent to %H:%M
					for c in '%H:%M' {
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

// month_abbrev_to_number converts an abbreviated month name (e.g. "Nov") to its
// two-digit number string (e.g. "11"). Returns error if not recognized.
fn month_abbrev_to_number(abbrev string) !string {
	months := {
		'jan': '01'
		'feb': '02'
		'mar': '03'
		'apr': '04'
		'may': '05'
		'jun': '06'
		'jul': '07'
		'aug': '08'
		'sep': '09'
		'oct': '10'
		'nov': '11'
		'dec': '12'
	}
	return months[abbrev.to_lower()] or { error('unknown month abbreviation: ${abbrev}') }
}

// replace_month_name_in_input replaces abbreviated month names with numeric months
// in the input string when the format contains %b. Returns the modified input string
// and format string with %b replaced by %m.
fn replace_month_name_in_input(s string, fmt string) !(string, string) {
	if !fmt.contains('%b') {
		return s, fmt
	}
	// Find where %b appears in the format string and use that position info
	// to locate the month name in the input string.
	// Strategy: split the format at %b, match the prefix length to find the month name position.
	b_idx := fmt.index('%b') or { return s, fmt }
	// The part of the format before %b tells us how many characters precede the month name.
	prefix_fmt := fmt[..b_idx]
	// Count the expected length of the prefix by expanding strftime specifiers
	prefix_len := expanded_format_length(prefix_fmt, s)
	if prefix_len < 0 || prefix_len + 3 > s.len {
		return error('unable to locate month name in: ${s}')
	}
	month_str := s[prefix_len..prefix_len + 3]
	month_num := month_abbrev_to_number(month_str)!
	// Replace in input: swap the 3-letter month with 2-digit number
	new_s := s[..prefix_len] + month_num + s[prefix_len + 3..]
	new_fmt := fmt[..b_idx] + '%m' + fmt[b_idx + 2..]
	return new_s, new_fmt
}

// expanded_format_length calculates how many characters the format prefix consumes
// in the input string. This is a heuristic: literal chars map 1:1, format specifiers
// map to their expected widths.
fn expanded_format_length(prefix_fmt string, input string) int {
	mut len := 0
	mut i := 0
	for i < prefix_fmt.len {
		if prefix_fmt[i] == `%` && i + 1 < prefix_fmt.len {
			i++
			match prefix_fmt[i] {
				`Y` { len += 4 }
				`m`, `d`, `H`, `M`, `S` { len += 2 }
				`e` { len += 2 } // day with space padding
				`b` { len += 3 } // abbreviated month name
				`T` { len += 8 } // HH:MM:SS
				`R` { len += 5 } // HH:MM
				else { len += 2 } // default guess for unknown specifiers
			}
		} else {
			len += 1
		}
		i++
	}
	return len
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
				`T` {
					// %T = %H:%M:%S
					for c in 'HH:mm:ss' {
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

// parse_common_log(value) - parses a Common Log Format string into an object
// Format: host ident user [timestamp] "request" status size
fn fn_parse_common_log(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_common_log requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_common_log requires a string') }
	}
	// Parse: host ident user [timestamp] "request" status size
	mut i := 0
	bytes := s.bytes()

	// Helper: skip to next space, return token
	host := clf_read_token(bytes, mut &i)
	identity := clf_read_token(bytes, mut &i)
	user := clf_read_token(bytes, mut &i)

	// Read timestamp: [DD/Mon/YYYY:HH:MM:SS ±HHMM]
	clf_skip_spaces(bytes, mut &i)
	if i >= bytes.len || bytes[i] != `[` {
		return error('parse_common_log: expected [ for timestamp')
	}
	i++ // skip [
	mut ts_end := i
	for ts_end < bytes.len && bytes[ts_end] != `]` {
		ts_end++
	}
	ts_str := bytes[i..ts_end].bytestr()
	if ts_end < bytes.len {
		i = ts_end + 1 // skip ]
	}

	// Parse timestamp: DD/Mon/YYYY:HH:MM:SS ±HHMM
	parsed_ts := clf_parse_timestamp(ts_str)!

	// Read request: "method path protocol"
	clf_skip_spaces(bytes, mut &i)
	if i >= bytes.len || bytes[i] != `"` {
		return error('parse_common_log: expected " for request')
	}
	i++ // skip opening "
	mut req_end := i
	for req_end < bytes.len && bytes[req_end] != `"` {
		req_end++
	}
	request := bytes[i..req_end].bytestr()
	if req_end < bytes.len {
		i = req_end + 1 // skip closing "
	}

	// Parse method, path, protocol from request
	req_parts := request.split(' ')
	method := if req_parts.len >= 1 { req_parts[0] } else { '' }
	path := if req_parts.len >= 2 { req_parts[1] } else { '' }
	protocol := if req_parts.len >= 3 { req_parts[2] } else { '' }

	// Read status
	status_str := clf_read_token(bytes, mut &i)
	// Read size
	size_str := clf_read_token(bytes, mut &i)

	mut result := new_object_map()
	result.set('host', clf_value_or_null(host))
	if identity != '-' {
		result.set('identity', VrlValue(identity))
	}
	result.set('user', clf_value_or_null(user))
	result.set('timestamp', VrlValue(parsed_ts))
	result.set('message', VrlValue(request))
	result.set('method', VrlValue(method))
	result.set('path', VrlValue(path))
	result.set('protocol', VrlValue(protocol))
	result.set('status', if status_str == '-' {
		VrlValue(VrlNull{})
	} else {
		VrlValue(i64(status_str.int()))
	})
	result.set('size', if size_str == '-' {
		VrlValue(VrlNull{})
	} else {
		VrlValue(i64(size_str.int()))
	})
	return VrlValue(result)
}

fn clf_skip_spaces(bytes []u8, mut i &int) {
	unsafe {
		for *i < bytes.len && (bytes[*i] == ` ` || bytes[*i] == `\t`) {
			*i = *i + 1
		}
	}
}

fn clf_read_token(bytes []u8, mut i &int) string {
	clf_skip_spaces(bytes, mut i)
	mut start := unsafe { *i }
	unsafe {
		for *i < bytes.len && bytes[*i] != ` ` && bytes[*i] != `\t` {
			*i = *i + 1
		}
		return bytes[start..*i].bytestr()
	}
}

fn clf_value_or_null(s string) VrlValue {
	if s == '-' {
		return VrlValue(VrlNull{})
	}
	return VrlValue(s)
}

// parse_klog(value) - Parse Kubernetes log format (klog)
// Format: <level><monthday> <time> <pid> <file>:<line>] <message>
// Example: I0505 17:59:40.692994   28133 miscellaneous.go:42] some message
fn fn_parse_klog(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_klog requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_klog requires a string') }
	}
	trimmed := s.trim_space()
	if trimmed.len < 2 {
		return error('unable to parse klog: input too short')
	}
	// Parse level character: I=info, W=warning, E=error, F=fatal
	level_char := trimmed[0]
	level := match level_char {
		`I` { 'info' }
		`W` { 'warning' }
		`E` { 'error' }
		`F` { 'fatal' }
		else { return error('unable to parse klog: unknown level character: ${[level_char].bytestr()}') }
	}
	// Parse monthday (4 digits: MMDD)
	mut i := 1
	if i + 4 > trimmed.len {
		return error('unable to parse klog: missing date')
	}
	month_str := trimmed[i..i + 2]
	day_str := trimmed[i + 2..i + 4]
	i += 4
	// Skip space
	if i >= trimmed.len || trimmed[i] != ` ` {
		return error('unable to parse klog: expected space after date')
	}
	i++
	// Parse time (HH:MM:SS.microseconds)
	mut time_end := i
	for time_end < trimmed.len && trimmed[time_end] != ` ` {
		time_end++
	}
	time_str := trimmed[i..time_end]
	i = time_end
	// Skip spaces
	for i < trimmed.len && trimmed[i] == ` ` {
		i++
	}
	// Parse PID
	mut pid_end := i
	for pid_end < trimmed.len && trimmed[pid_end] != ` ` {
		pid_end++
	}
	pid_str := trimmed[i..pid_end]
	i = pid_end
	// Skip spaces
	for i < trimmed.len && trimmed[i] == ` ` {
		i++
	}
	// Parse file:line] - find the closing bracket
	mut bracket_pos := i
	for bracket_pos < trimmed.len && trimmed[bracket_pos] != `]` {
		bracket_pos++
	}
	if bracket_pos >= trimmed.len {
		return error('unable to parse klog: missing ] delimiter')
	}
	file_line := trimmed[i..bracket_pos]
	// Split file:line
	mut file := file_line
	mut line := ''
	if colon_idx := file_line.last_index(':') {
		file = file_line[..colon_idx]
		line = file_line[colon_idx + 1..]
	}
	i = bracket_pos + 1
	// Skip space after ]
	if i < trimmed.len && trimmed[i] == ` ` {
		i++
	}
	// Rest is message (trim trailing whitespace like upstream)
	message := if i < trimmed.len { trimmed[i..].trim_right(' \t\n\r') } else { '' }
	// Resolve year: if current month is January and log month is December, use previous year
	now := time.now()
	month_val := month_str.int()
	year := if now.month == 1 && month_val == 12 { now.year - 1 } else { now.year }
	// Build and parse timestamp
	ts_str := '${year}${month_str}${day_str} ${time_str}'
	// Parse: YYYYMMDD HH:MM:SS.ffffff
	t := time.parse_format(ts_str, 'YYYYMMDD HH:mm:ss') or {
		return error('failed parsing timestamp ${month_str}${day_str} ${time_str}')
	}
	// Extract microseconds from the time string (after the dot)
	mut microseconds := 0
	if dot_idx := time_str.index('.') {
		usec_str := time_str[dot_idx + 1..]
		if usec_str.len >= 6 {
			microseconds = usec_str[..6].int()
		} else {
			microseconds = usec_str.int()
			// Pad with zeros
			for _ in 0 .. 6 - usec_str.len {
				microseconds *= 10
			}
		}
	}
	ts := Timestamp{
		t: time.Time{
			year: t.year
			month: t.month
			day: t.day
			hour: t.hour
			minute: t.minute
			second: t.second
			nanosecond: microseconds * 1000
		}
	}
	mut result := new_object_map()
	result.set('file', VrlValue(file))
	result.set('id', VrlValue(i64(pid_str.int())))
	result.set('level', VrlValue(level))
	result.set('line', VrlValue(i64(line.int())))
	result.set('message', VrlValue(message))
	result.set('timestamp', VrlValue(ts))
	return VrlValue(result)
}

// parse_linux_authorization(value) - Parse Linux authorization log lines
// Format: <timestamp> <hostname> <process>[<pid>]: <message>
// Example: Mar  5 14:17:01 myhost CRON[1234]: pam_unix(cron:session): session opened
fn fn_parse_linux_authorization(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_linux_authorization requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_linux_authorization requires a string') }
	}
	bytes := s.bytes()
	mut i := 0
	// Parse timestamp: "Mon DD HH:MM:SS" or "Mon  D HH:MM:SS"
	// Month (3 chars)
	if i + 3 > bytes.len {
		return error('unable to parse linux authorization log: input too short')
	}
	month := s[i..i + 3]
	i += 3
	// Skip spaces
	for i < bytes.len && bytes[i] == ` ` {
		i++
	}
	// Day (1-2 digits)
	mut day_start := i
	for i < bytes.len && bytes[i] >= `0` && bytes[i] <= `9` {
		i++
	}
	if i == day_start {
		return error('unable to parse linux authorization log: missing day')
	}
	day := s[day_start..i]
	// Skip space
	for i < bytes.len && bytes[i] == ` ` {
		i++
	}
	// Time (HH:MM:SS)
	mut time_start := i
	for i < bytes.len && bytes[i] != ` ` {
		i++
	}
	timestamp_time := s[time_start..i]
	timestamp := '${month} ${day} ${timestamp_time}'
	// Skip space
	for i < bytes.len && bytes[i] == ` ` {
		i++
	}
	// Hostname
	mut host_start := i
	for i < bytes.len && bytes[i] != ` ` {
		i++
	}
	hostname := s[host_start..i]
	// Skip space
	for i < bytes.len && bytes[i] == ` ` {
		i++
	}
	// Process and optional PID: "process[pid]:" or "process:"
	mut proc_start := i
	mut process := ''
	mut pid := VrlValue(VrlNull{})
	// Find the colon that follows the process/pid
	mut colon_pos := -1
	for j := i; j < bytes.len; j++ {
		if bytes[j] == `:` {
			colon_pos = j
			break
		}
	}
	if colon_pos < 0 {
		return error('unable to parse linux authorization log: missing colon after process')
	}
	proc_part := s[proc_start..colon_pos]
	// Check for [pid]
	if bracket_start := proc_part.index('[') {
		process = proc_part[..bracket_start]
		bracket_end := proc_part.index(']') or { proc_part.len }
		pid_str := proc_part[bracket_start + 1..bracket_end]
		pid = VrlValue(i64(pid_str.int()))
	} else {
		process = proc_part
	}
	i = colon_pos + 1
	// Skip space after colon
	for i < bytes.len && bytes[i] == ` ` {
		i++
	}
	// Rest is message
	message := if i < bytes.len { s[i..] } else { '' }
	mut result := new_object_map()
	result.set('timestamp', VrlValue(timestamp))
	result.set('hostname', VrlValue(hostname))
	result.set('appname', VrlValue(process))
	result.set('procid', pid)
	result.set('message', VrlValue(message))
	return VrlValue(result)
}

// get_timezone_name() - Returns the system timezone name
fn fn_get_timezone_name(args []VrlValue) !VrlValue {
	// Check TZ environment variable first
	tz_env := os.getenv('TZ')
	if tz_env.len > 0 {
		return VrlValue(tz_env)
	}
	// Try reading /etc/timezone (Debian/Ubuntu)
	tz_file := os.read_file('/etc/timezone') or { '' }
	if tz_file.len > 0 {
		tz_val := tz_file.trim_space()
		// Normalize Etc/UTC and Etc/GMT to their short forms
		if tz_val == 'Etc/UTC' || tz_val == 'Etc/GMT' {
			return VrlValue('UTC')
		}
		return VrlValue(tz_val)
	}
	// Try reading /etc/localtime symlink target (RHEL/CentOS/Arch)
	link_target := os.real_path('/etc/localtime')
	if zi_pos := link_target.index('/zoneinfo/') {
		start := zi_pos + 10
		if start < link_target.len {
			tz_name := link_target[start..]
			if tz_name.len > 0 {
				// Normalize Etc/UTC and Etc/GMT to UTC
				if tz_name == 'Etc/UTC' || tz_name == 'Etc/GMT' {
					return VrlValue('UTC')
				}
				return VrlValue(tz_name)
			}
		}
	}
	// Fallback to UTC
	return VrlValue('UTC')
}

// haversine(lat1, lon1, lat2, lon2, [measurement_unit]) - Calculate great-circle distance
// and bearing between two points.
// Returns an object with "distance" and "bearing" fields.
// measurement_unit: "kilometers" (default) or "miles"
// Formula: 2 * R * asin(sqrt(sin²(Δlat/2) + cos(lat1)*cos(lat2)*sin²(Δlon/2)))
fn fn_haversine(args []VrlValue) !VrlValue {
	if args.len < 4 {
		return error('haversine requires 4 arguments (lat1, lon1, lat2, lon2)')
	}
	lat1 := get_float_arg(args[0]) or { return error('haversine: lat1 must be a number') }
	lon1 := get_float_arg(args[1]) or { return error('haversine: lon1 must be a number') }
	lat2 := get_float_arg(args[2]) or { return error('haversine: lat2 must be a number') }
	lon2 := get_float_arg(args[3]) or { return error('haversine: lon2 must be a number') }
	unit := if args.len > 4 {
		v := args[4]
		match v {
			string { v }
			else { 'kilometers' }
		}
	} else {
		'kilometers'
	}
	earth_radius_km := 6_371.0088
	earth_radius := if unit == 'miles' { earth_radius_km * 0.6213712 } else { earth_radius_km }
	lat1_rad := lat1 * math.pi / 180.0
	lon1_rad := lon1 * math.pi / 180.0
	lat2_rad := lat2 * math.pi / 180.0
	lon2_rad := lon2 * math.pi / 180.0
	dlat := lat2_rad - lat1_rad
	dlon := lon2_rad - lon1_rad
	a := math.sin(dlat / 2.0) * math.sin(dlat / 2.0) + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2.0) * math.sin(dlon / 2.0)
	distance_raw := 2.0 * math.asin(math.sqrt(a)) * earth_radius
	distance := round_to_precision_f64(distance_raw, 7)
	// Bearing calculation
	y := math.sin(dlon) * math.cos(lat2_rad)
	x := math.cos(lat1_rad) * math.sin(lat2_rad) - math.sin(lat1_rad) * math.cos(lat2_rad) * math.cos(dlon)
	bearing_raw := math.fmod(math.atan2(y, x) * 180.0 / math.pi + 360.0, 360.0)
	bearing := round_to_precision_f64(bearing_raw, 3)
	mut result := new_object_map()
	result.set('bearing', VrlValue(bearing))
	result.set('distance', VrlValue(distance))
	return VrlValue(result)
}

fn round_to_precision_f64(val f64, precision int) f64 {
	mut mult := 1.0
	for _ in 0 .. precision {
		mult *= 10.0
	}
	return math.round(val * mult) / mult
}

// Helper to extract a float from a VrlValue
fn get_float_arg(v VrlValue) !f64 {
	return match v {
		f64 { v }
		i64 { f64(v) }
		else { error('expected number') }
	}
}

fn clf_parse_timestamp(s string) !Timestamp {
	// Format: DD/Mon/YYYY:HH:MM:SS ±HHMM
	// Example: 03/Feb/2021:21:13:55 -0200
	if s.len < 20 {
		return error('invalid CLF timestamp: ${s}')
	}
	day := s[0..2].int()
	month_str := s[3..6]
	year := s[7..11].int()
	hour := s[12..14].int()
	minute := s[15..17].int()
	second := s[18..20].int()

	month_num := month_abbrev_to_number(month_str)!

	// Parse timezone offset if present
	mut tz_offset_seconds := 0
	if s.len > 20 {
		tz_part := s[20..].trim_space()
		if tz_part.len >= 5 && (tz_part[0] == `+` || tz_part[0] == `-`) {
			tz_hh := tz_part[1..3].int()
			tz_mm := tz_part[3..5].int()
			tz_offset_seconds = (tz_hh * 3600 + tz_mm * 60)
			if tz_part[0] == `-` {
				tz_offset_seconds = -tz_offset_seconds
			}
		}
	}

	// Build timestamp in UTC
	t := time.Time{
		year: year
		month: month_num.int()
		day: day
		hour: hour
		minute: minute
		second: second
	}
	// Convert from local (with offset) to UTC by subtracting the offset
	utc := time.unix(t.unix() - tz_offset_seconds)
	return Timestamp{t: utc}
}

// parse_syslog(value) - parses a syslog message (RFC 3164 and RFC 5424)
fn fn_parse_syslog(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_syslog requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_syslog requires a string') }
	}
	if s.len < 3 || s[0] != `<` {
		return error('unable to parse input as valid syslog message')
	}

	// Parse priority: <NNN>
	mut i := 1
	for i < s.len && s[i] != `>` {
		i++
	}
	if i >= s.len {
		return error('unable to parse input as valid syslog message')
	}
	pri_str := s[1..i]
	priority := pri_str.int()
	i++ // skip >

	facility := priority / 8
	severity := priority % 8

	// Determine RFC 5424 vs 3164: RFC 5424 has a version digit right after >
	if i < s.len && s[i].is_digit() {
		return parse_syslog_rfc5424(s[i..], facility, severity)
	}
	return parse_syslog_rfc3164(s[i..], facility, severity)
}

fn syslog_facility_name(code int) string {
	facilities := ['kern', 'user', 'mail', 'daemon', 'auth', 'syslog', 'lpr', 'news',
		'uucp', 'cron', 'authpriv', 'ftp', 'ntp', 'security', 'console', 'solaris-cron',
		'local0', 'local1', 'local2', 'local3', 'local4', 'local5', 'local6', 'local7']
	if code >= 0 && code < facilities.len {
		return facilities[code]
	}
	return 'unknown'
}

fn syslog_severity_name(code int) string {
	severities := ['emerg', 'alert', 'crit', 'err', 'warning', 'notice', 'info', 'debug']
	if code >= 0 && code < severities.len {
		return severities[code]
	}
	return 'unknown'
}

fn parse_syslog_rfc5424(s string, facility int, severity int) !VrlValue {
	// Format: version SP timestamp SP hostname SP appname SP procid SP msgid SP structured-data [SP message]
	// Example: 1 2021-02-03T21:13:55-02:00 hostname appname 1234 msgid [sd@123 key="val"] message
	mut result := new_object_map()
	result.set('facility', VrlValue(syslog_facility_name(facility)))
	result.set('severity', VrlValue(syslog_severity_name(severity)))

	mut pos := 0
	bytes := s.bytes()

	// Version
	version_str := syslog_read_token(bytes, mut &pos)
	result.set('version', VrlValue(i64(version_str.int())))

	// Timestamp
	ts_str := syslog_read_token(bytes, mut &pos)
	if ts_str == '-' {
		result.set('timestamp', VrlValue(VrlNull{}))
	} else {
		result.set('timestamp', VrlValue(ts_str))
	}

	// Hostname
	hostname := syslog_read_token(bytes, mut &pos)
	result.set('hostname', syslog_value_or_null(hostname))

	// Appname
	appname := syslog_read_token(bytes, mut &pos)
	result.set('appname', syslog_value_or_null(appname))

	// Procid
	procid := syslog_read_token(bytes, mut &pos)
	result.set('procid', syslog_value_or_null(procid))

	// Msgid
	msgid := syslog_read_token(bytes, mut &pos)
	result.set('msgid', syslog_value_or_null(msgid))

	// Structured data
	syslog_skip_spaces(bytes, mut &pos)
	if pos < bytes.len && bytes[pos] == `[` {
		// Parse structured data elements
		for pos < bytes.len && bytes[pos] == `[` {
			pos++ // skip [
			// Read SD-ID
			mut sd_id_end := pos
			for sd_id_end < bytes.len && bytes[sd_id_end] != ` ` && bytes[sd_id_end] != `]` {
				sd_id_end++
			}
			// sd_id := bytes[pos..sd_id_end].bytestr()  // available if needed
			pos = sd_id_end

			// Parse key=value pairs within the SD element
			for pos < bytes.len && bytes[pos] != `]` {
				syslog_skip_spaces(bytes, mut &pos)
				if pos < bytes.len && bytes[pos] == `]` {
					break
				}
				// Read key
				mut key_end := pos
				for key_end < bytes.len && bytes[key_end] != `=` && bytes[key_end] != `]`
					&& bytes[key_end] != ` ` {
					key_end++
				}
				key := bytes[pos..key_end].bytestr()
				pos = key_end
				if pos < bytes.len && bytes[pos] == `=` {
					pos++ // skip =
					// Read value (quoted)
					if pos < bytes.len && bytes[pos] == `"` {
						pos++ // skip opening "
						mut val := []u8{}
						for pos < bytes.len && bytes[pos] != `"` {
							if bytes[pos] == `\\` && pos + 1 < bytes.len {
								pos++
								val << bytes[pos]
							} else {
								val << bytes[pos]
							}
							pos++
						}
						if pos < bytes.len {
							pos++ // skip closing "
						}
						if key.len > 0 {
							result.set(key, VrlValue(val.bytestr()))
						}
					} else {
						// Unquoted value (non-standard but handle gracefully)
						mut val_end := pos
						for val_end < bytes.len && bytes[val_end] != ` `
							&& bytes[val_end] != `]` {
							val_end++
						}
						if key.len > 0 {
							result.set(key, VrlValue(bytes[pos..val_end].bytestr()))
						}
						pos = val_end
					}
				}
			}
			if pos < bytes.len && bytes[pos] == `]` {
				pos++ // skip ]
			}
		}
	} else if pos < bytes.len {
		// NILVALUE for structured data
		token := syslog_read_token(bytes, mut &pos)
		_ = token // discard the '-'
	}

	// Message (rest of string after optional space)
	syslog_skip_spaces(bytes, mut &pos)
	if pos < bytes.len {
		msg := bytes[pos..].bytestr()
		result.set('message', VrlValue(msg))
	} else {
		result.set('message', VrlValue(VrlNull{}))
	}

	return VrlValue(result)
}

fn parse_syslog_rfc3164(s string, facility int, severity int) !VrlValue {
	// Format: timestamp hostname message
	// Timestamp: "Mon DD HH:MM:SS" (BSD format) or could be other formats
	// Example: Feb  3 21:13:55 myhost my message here
	mut result := new_object_map()
	result.set('facility', VrlValue(syslog_facility_name(facility)))
	result.set('severity', VrlValue(syslog_severity_name(severity)))

	trimmed := s.trim_left(' ')
	bytes := trimmed.bytes()
	mut pos := 0

	// Try to parse BSD timestamp: "Mon DD HH:MM:SS" or "Mon  D HH:MM:SS"
	if trimmed.len >= 15 {
		month_str := trimmed[0..3]
		month_num := month_abbrev_to_number(month_str) or {
			// Not a recognized month, treat entire string as message
			result.set('timestamp', VrlValue(VrlNull{}))
			result.set('hostname', VrlValue(VrlNull{}))
			result.set('appname', VrlValue(VrlNull{}))
			result.set('procid', VrlValue(VrlNull{}))
			result.set('msgid', VrlValue(VrlNull{}))
			result.set('message', VrlValue(trimmed))
			result.set('version', VrlValue(VrlNull{}))
			return VrlValue(result)
		}
		// Skip month and spaces
		pos = 3
		syslog_skip_spaces(bytes, mut &pos)

		// Read day
		mut day_end := pos
		for day_end < bytes.len && bytes[day_end].is_digit() {
			day_end++
		}
		day_str := bytes[pos..day_end].bytestr()
		day := '${day_str.int():02d}'
		pos = day_end
		syslog_skip_spaces(bytes, mut &pos)

		// Read time: HH:MM:SS
		if pos + 8 <= bytes.len {
			time_str := bytes[pos..pos + 8].bytestr()
			pos += 8

			// Build an RFC3339-like timestamp (no year in BSD syslog, use current year)
			ts := '${time.now().year}-${month_num}-${day}T${time_str}+00:00'
			result.set('timestamp', VrlValue(ts))
		} else {
			result.set('timestamp', VrlValue(VrlNull{}))
		}
	} else {
		result.set('timestamp', VrlValue(VrlNull{}))
	}

	// Hostname
	syslog_skip_spaces(bytes, mut &pos)
	hostname := syslog_read_token(bytes, mut &pos)
	result.set('hostname', syslog_value_or_null(hostname))

	// Try to extract appname[procid]: from the message prefix
	syslog_skip_spaces(bytes, mut &pos)
	remaining := if pos < bytes.len { bytes[pos..].bytestr() } else { '' }

	// Check for "appname[procid]: message" or "appname: message" pattern
	mut appname := VrlValue(VrlNull{})
	mut procid := VrlValue(VrlNull{})
	mut message := remaining

	// Try ": " first, then ":" without space
	mut colon_idx := -1
	mut msg_offset := 2
	if ci := remaining.index(': ') {
		colon_idx = ci
		msg_offset = 2
	} else if ci2 := remaining.index(':') {
		colon_idx = ci2
		msg_offset = 1
	}
	if colon_idx >= 0 {
		prefix := remaining[..colon_idx]
		if bracket_idx := prefix.index('[') {
			// appname[procid]
			appname = VrlValue(prefix[..bracket_idx])
			pid := prefix[bracket_idx + 1..].trim_right(']')
			procid = VrlValue(pid)
		} else {
			appname = VrlValue(prefix)
		}
		message = remaining[colon_idx + msg_offset..]
	}

	result.set('appname', appname)
	result.set('procid', procid)
	result.set('msgid', VrlValue(VrlNull{}))
	result.set('version', VrlValue(VrlNull{}))
	result.set('message', VrlValue(message))

	return VrlValue(result)
}

fn syslog_skip_spaces(bytes []u8, mut i &int) {
	unsafe {
		for *i < bytes.len && (bytes[*i] == ` ` || bytes[*i] == `\t`) {
			*i = *i + 1
		}
	}
}

fn syslog_read_token(bytes []u8, mut i &int) string {
	syslog_skip_spaces(bytes, mut i)
	mut start := unsafe { *i }
	unsafe {
		for *i < bytes.len && bytes[*i] != ` ` && bytes[*i] != `\t` {
			*i = *i + 1
		}
		return bytes[start..*i].bytestr()
	}
}

fn syslog_value_or_null(s string) VrlValue {
	if s == '-' || s.len == 0 {
		return VrlValue(VrlNull{})
	}
	return VrlValue(s)
}

// parse_logfmt(value) - parses a logfmt-formatted string into an object
fn fn_parse_logfmt(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_logfmt requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_logfmt requires a string') }
	}
	mut result := new_object_map()
	mut i := 0
	bytes := s.bytes()
	for i < bytes.len {
		// Skip whitespace
		for i < bytes.len && (bytes[i] == ` ` || bytes[i] == `\t`) {
			i++
		}
		if i >= bytes.len {
			break
		}
		// Read key
		mut key_start := i
		for i < bytes.len && bytes[i] != `=` && bytes[i] != ` ` && bytes[i] != `\t` {
			i++
		}
		key := bytes[key_start..i].bytestr()
		if key.len == 0 {
			i++
			continue
		}
		// Check for = sign
		if i >= bytes.len || bytes[i] != `=` {
			// Key without value - per logfmt spec, standalone keys are boolean true
			result.set(key, VrlValue(true))
			continue
		}
		i++ // skip '='
		// Read value
		if i >= bytes.len || bytes[i] == ` ` || bytes[i] == `\t` {
			// Empty value
			result.set(key, VrlValue(''))
			continue
		}
		if bytes[i] == `"` || bytes[i] == `'` {
			// Quoted value
			quote := bytes[i]
			i++
			mut val := []u8{}
			for i < bytes.len && bytes[i] != quote {
				if bytes[i] == `\\` && i + 1 < bytes.len {
					next := bytes[i + 1]
					if next == quote || next == `\\` {
						val << next
						i += 2
						continue
					}
				}
				val << bytes[i]
				i++
			}
			if i < bytes.len {
				i++ // skip closing quote
			}
			result.set(key, VrlValue(val.bytestr()))
		} else {
			// Unquoted value
			mut val_start := i
			for i < bytes.len && bytes[i] != ` ` && bytes[i] != `\t` {
				i++
			}
			result.set(key, VrlValue(bytes[val_start..i].bytestr()))
		}
	}
	return VrlValue(result)
}

// parse_yaml(value) - Parse a YAML string into a VrlValue
fn fn_parse_yaml(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_yaml requires 1 argument')
	}
	a := args[0]
	match a {
		string { return yaml_parse(a) }
		else { return error('parse_yaml requires a string argument') }
	}
}

// yaml_parse is the entry point for YAML parsing
fn yaml_parse(input string) !VrlValue {
	lines := input.split('\n')
	mut idx := 0
	// skip leading blank lines and comments
	for idx < lines.len {
		trimmed := lines[idx].trim_space()
		if trimmed.len == 0 || trimmed.starts_with('#') || trimmed == '---' {
			idx++
			continue
		}
		break
	}
	if idx >= lines.len {
		return VrlValue(VrlNull{})
	}
	// Check if first non-blank line starts a flow value
	first := lines[idx].trim_space()
	if first.starts_with('{') || first.starts_with('[') {
		// Join remaining lines and parse as flow
		mut rest := []string{}
		for i in idx .. lines.len {
			rest << lines[i]
		}
		combined := rest.join('\n').trim_space()
		if combined.starts_with('{') {
			return yaml_parse_flow_mapping(combined)
		}
		return yaml_parse_flow_sequence(combined)
	}
	result, _ := yaml_parse_block(lines, idx, 0)!
	return result
}

// yaml_parse_block parses a block of YAML lines at a given indent level.
// Returns the parsed VrlValue and the next line index to process.
fn yaml_parse_block(lines []string, start int, min_indent int) !(VrlValue, int) {
	mut idx := start
	// skip blanks and comments
	for idx < lines.len {
		t := lines[idx].trim_space()
		if t.len == 0 || t.starts_with('#') {
			idx++
			continue
		}
		break
	}
	if idx >= lines.len {
		return VrlValue(VrlNull{}), idx
	}
	line := lines[idx]
	trimmed := line.trim_space()
	indent := yaml_indent(line)

	// sequence item
	if trimmed.starts_with('- ') || trimmed == '-' {
		return yaml_parse_sequence(lines, idx, indent)
	}
	// mapping (key: value)
	if yaml_is_mapping_line(trimmed) {
		return yaml_parse_mapping(lines, idx, indent)
	}
	// scalar
	val := yaml_parse_scalar(trimmed)
	return val, idx + 1
}

// yaml_parse_mapping parses a YAML mapping block
fn yaml_parse_mapping(lines []string, start int, base_indent int) !(VrlValue, int) {
	mut result := new_object_map()
	mut idx := start
	for idx < lines.len {
		line := lines[idx]
		trimmed := line.trim_space()
		if trimmed.len == 0 || trimmed.starts_with('#') {
			idx++
			continue
		}
		indent := yaml_indent(line)
		if indent < base_indent {
			break
		}
		if indent > base_indent {
			break
		}
		// handle sequence item containing a mapping
		if trimmed.starts_with('- ') || trimmed == '-' {
			break
		}
		if !yaml_is_mapping_line(trimmed) {
			break
		}
		key, val_part := yaml_split_mapping(trimmed)
		val_str := val_part.trim_space()

		if val_str.len == 0 {
			// Block value on next lines
			mut next := idx + 1
			// skip blank lines
			for next < lines.len && lines[next].trim_space().len == 0 {
				next++
			}
			if next < lines.len {
				next_indent := yaml_indent(lines[next])
				next_trimmed := lines[next].trim_space()
				if next_indent > base_indent {
					if next_trimmed.starts_with('- ') || next_trimmed == '-' {
						val, after := yaml_parse_sequence(lines, next, next_indent)!
						result.set(key, val)
						idx = after
						continue
					} else if next_trimmed.starts_with('|') || next_trimmed.starts_with('>') {
						val, after := yaml_parse_multiline_string(lines, next, base_indent)!
						result.set(key, val)
						idx = after
						continue
					} else {
						val, after := yaml_parse_block(lines, next, next_indent)!
						result.set(key, val)
						idx = after
						continue
					}
				} else if next_indent == base_indent
					&& (next_trimmed.starts_with('- ') || next_trimmed == '-') {
					// YAML allows sequence items at same indent as the mapping key
					val, after := yaml_parse_sequence(lines, next, next_indent)!
					result.set(key, val)
					idx = after
					continue
				}
			}
			result.set(key, VrlValue(VrlNull{}))
			idx = next
			continue
		}

		// Check for multiline indicators
		if val_str == '|' || val_str == '>' || val_str == '|-' || val_str == '>-'
			|| val_str == '|+' || val_str == '>+' {
			val, after := yaml_parse_multiline_string_from_indicator(lines, idx + 1, base_indent,
				val_str)!
			result.set(key, val)
			idx = after
			continue
		}

		// Inline flow
		if val_str.starts_with('{') {
			val := yaml_parse_flow_mapping(val_str)!
			result.set(key, val)
			idx++
			continue
		}
		if val_str.starts_with('[') {
			val := yaml_parse_flow_sequence(val_str)!
			result.set(key, val)
			idx++
			continue
		}
		// Inline scalar
		result.set(key, yaml_parse_scalar(val_str))
		idx++
	}
	return VrlValue(result), idx
}

// yaml_parse_sequence parses a YAML sequence block
fn yaml_parse_sequence(lines []string, start int, base_indent int) !(VrlValue, int) {
	mut result := []VrlValue{}
	mut idx := start
	for idx < lines.len {
		line := lines[idx]
		trimmed := line.trim_space()
		if trimmed.len == 0 || trimmed.starts_with('#') {
			idx++
			continue
		}
		indent := yaml_indent(line)
		if indent < base_indent {
			break
		}
		if indent > base_indent {
			break
		}
		if !trimmed.starts_with('- ') && trimmed != '-' {
			break
		}
		item_str := if trimmed == '-' { '' } else { trimmed[2..] }
		item_trimmed := item_str.trim_space()

		if item_trimmed.len == 0 {
			// Block value after bare dash
			mut next := idx + 1
			for next < lines.len && lines[next].trim_space().len == 0 {
				next++
			}
			if next < lines.len {
				next_indent := yaml_indent(lines[next])
				if next_indent > base_indent {
					val, after := yaml_parse_block(lines, next, next_indent)!
					result << val
					idx = after
					continue
				}
			}
			result << VrlValue(VrlNull{})
			idx++
			continue
		}

		// Check if item is itself a mapping
		if yaml_is_mapping_line(item_trimmed) {
			// Inline mapping starting on the same line as dash
			item_indent := base_indent + 2
			mut sub_lines := []string{}
			spaces := ' '.repeat(item_indent)
			sub_lines << '${spaces}${item_trimmed}'
			mut next := idx + 1
			for next < lines.len {
				nl := lines[next]
				nt := nl.trim_space()
				if nt.len == 0 || nt.starts_with('#') {
					sub_lines << nl
					next++
					continue
				}
				ni := yaml_indent(nl)
				if ni > base_indent {
					sub_lines << nl
					next++
					continue
				}
				break
			}
			val, _ := yaml_parse_mapping(sub_lines, 0, item_indent)!
			result << val
			idx = next
			continue
		}

		if item_trimmed.starts_with('- ') || item_trimmed == '-' {
			// Nested sequence
			item_indent := base_indent + 2
			mut sub_lines := []string{}
			spaces := ' '.repeat(item_indent)
			sub_lines << '${spaces}${item_trimmed}'
			mut next := idx + 1
			for next < lines.len {
				nl := lines[next]
				nt := nl.trim_space()
				if nt.len == 0 || nt.starts_with('#') {
					sub_lines << nl
					next++
					continue
				}
				ni := yaml_indent(nl)
				if ni > base_indent {
					sub_lines << nl
					next++
					continue
				}
				break
			}
			val, _ := yaml_parse_sequence(sub_lines, 0, item_indent)!
			result << val
			idx = next
			continue
		}

		if item_trimmed.starts_with('{') {
			val := yaml_parse_flow_mapping(item_trimmed)!
			result << val
			idx++
			continue
		}
		if item_trimmed.starts_with('[') {
			val := yaml_parse_flow_sequence(item_trimmed)!
			result << val
			idx++
			continue
		}

		// Plain scalar
		result << yaml_parse_scalar(item_trimmed)
		idx++
	}
	return VrlValue(result), idx
}

// yaml_parse_multiline_string handles | and > indicators on the value side of a mapping
fn yaml_parse_multiline_string(lines []string, indicator_line int, base_indent int) !(VrlValue, int) {
	indicator := lines[indicator_line].trim_space()
	return yaml_parse_multiline_string_from_indicator(lines, indicator_line + 1, base_indent,
		indicator)
}

fn yaml_parse_multiline_string_from_indicator(lines []string, start int, base_indent int, indicator string) !(VrlValue, int) {
	is_literal := indicator.starts_with('|') // literal block (preserve newlines)
	chomp := if indicator.ends_with('-') {
		'strip'
	} else if indicator.ends_with('+') {
		'keep'
	} else {
		'clip'
	}

	mut idx := start
	// Determine content indent from first non-empty content line
	mut content_indent := -1
	mut content_lines := []string{}

	for idx < lines.len {
		line := lines[idx]
		if line.trim_space().len == 0 {
			content_lines << ''
			idx++
			continue
		}
		ind := yaml_indent(line)
		if ind <= base_indent {
			break
		}
		if content_indent < 0 {
			content_indent = ind
		}
		if ind >= content_indent {
			content_lines << line[content_indent..]
		} else {
			break
		}
		idx++
	}

	// Remove trailing empty lines for strip/clip
	if chomp == 'strip' || chomp == 'clip' {
		for content_lines.len > 0 && content_lines.last().trim_space().len == 0 {
			content_lines.pop()
		}
	}

	mut result_str := ''
	if is_literal {
		result_str = content_lines.join('\n')
	} else {
		// Folded: replace single newlines with spaces, preserve double newlines
		mut parts := []string{}
		mut current := ''
		for cl in content_lines {
			if cl.trim_space().len == 0 {
				if current.len > 0 {
					parts << current
					current = ''
				}
				parts << ''
			} else {
				if current.len > 0 {
					current += ' ' + cl
				} else {
					current = cl
				}
			}
		}
		if current.len > 0 {
			parts << current
		}
		result_str = parts.join('\n')
	}

	if chomp == 'clip' && result_str.len > 0 {
		result_str += '\n'
	} else if chomp == 'keep' {
		result_str += '\n'
	}

	return VrlValue(result_str), idx
}

// yaml_parse_flow_mapping parses {key: val, key2: val2}
fn yaml_parse_flow_mapping(s string) !VrlValue {
	trimmed := s.trim_space()
	if !trimmed.starts_with('{') || !trimmed.ends_with('}') {
		return error('invalid YAML flow mapping')
	}
	inner := trimmed[1..trimmed.len - 1].trim_space()
	if inner.len == 0 {
		return VrlValue(new_object_map())
	}
	mut result := new_object_map()
	parts := yaml_split_flow(inner)
	for part in parts {
		p := part.trim_space()
		if p.len == 0 {
			continue
		}
		colon := yaml_find_colon(p)
		if colon < 0 {
			return error('invalid YAML flow mapping entry: ${p}')
		}
		key := yaml_unquote(p[..colon].trim_space())
		val_str := p[colon + 1..].trim_space()
		if val_str.starts_with('{') {
			val := yaml_parse_flow_mapping(val_str)!
			result.set(key, val)
		} else if val_str.starts_with('[') {
			val := yaml_parse_flow_sequence(val_str)!
			result.set(key, val)
		} else {
			result.set(key, yaml_parse_scalar(val_str))
		}
	}
	return VrlValue(result)
}

// yaml_parse_flow_sequence parses [a, b, c]
fn yaml_parse_flow_sequence(s string) !VrlValue {
	trimmed := s.trim_space()
	if !trimmed.starts_with('[') || !trimmed.ends_with(']') {
		return error('invalid YAML flow sequence')
	}
	inner := trimmed[1..trimmed.len - 1].trim_space()
	if inner.len == 0 {
		return VrlValue([]VrlValue{})
	}
	mut result := []VrlValue{}
	parts := yaml_split_flow(inner)
	for part in parts {
		p := part.trim_space()
		if p.len == 0 {
			continue
		}
		if p.starts_with('{') {
			val := yaml_parse_flow_mapping(p)!
			result << val
		} else if p.starts_with('[') {
			val := yaml_parse_flow_sequence(p)!
			result << val
		} else {
			result << yaml_parse_scalar(p)
		}
	}
	return VrlValue(result)
}

// yaml_split_flow splits a flow collection by commas, respecting nesting
fn yaml_split_flow(s string) []string {
	mut parts := []string{}
	mut depth_brace := 0
	mut depth_bracket := 0
	mut start := 0
	mut in_single_quote := false
	mut in_double_quote := false

	for i := 0; i < s.len; i++ {
		ch := s[i]
		if ch == `'` && !in_double_quote {
			in_single_quote = !in_single_quote
			continue
		}
		if ch == `"` && !in_single_quote {
			in_double_quote = !in_double_quote
			continue
		}
		if in_single_quote || in_double_quote {
			continue
		}
		if ch == `{` {
			depth_brace++
		} else if ch == `}` {
			depth_brace--
		} else if ch == `[` {
			depth_bracket++
		} else if ch == `]` {
			depth_bracket--
		} else if ch == `,` && depth_brace == 0 && depth_bracket == 0 {
			parts << s[start..i]
			start = i + 1
		}
	}
	if start < s.len {
		parts << s[start..]
	}
	return parts
}

// yaml_parse_scalar converts a YAML scalar string to a VrlValue
fn yaml_parse_scalar(s string) VrlValue {
	trimmed := s.trim_space()
	if trimmed.len == 0 {
		return VrlValue(VrlNull{})
	}

	// Strip inline comments (only if not in a quoted string)
	val := yaml_strip_comment(trimmed)

	// Null
	if val == 'null' || val == '~' || val == 'Null' || val == 'NULL' {
		return VrlValue(VrlNull{})
	}
	// Boolean
	if val == 'true' || val == 'True' || val == 'TRUE' || val == 'yes' || val == 'Yes'
		|| val == 'YES' || val == 'on' || val == 'On' || val == 'ON' {
		return VrlValue(true)
	}
	if val == 'false' || val == 'False' || val == 'FALSE' || val == 'no' || val == 'No'
		|| val == 'NO' || val == 'off' || val == 'Off' || val == 'OFF' {
		return VrlValue(false)
	}
	// Quoted strings
	if (val.starts_with('"') && val.ends_with('"')) || (val.starts_with("'") && val.ends_with("'")) {
		return VrlValue(yaml_unquote(val))
	}
	// Integer
	if yaml_is_integer(val) {
		return VrlValue(val.i64())
	}
	// Float
	if yaml_is_float(val) {
		if val == '.inf' || val == '.Inf' || val == '.INF' {
			return VrlValue(f64(math.inf(1)))
		}
		if val == '-.inf' || val == '-.Inf' || val == '-.INF' {
			return VrlValue(f64(math.inf(-1)))
		}
		if val == '.nan' || val == '.NaN' || val == '.NAN' {
			return VrlValue(f64(math.nan()))
		}
		return VrlValue(val.f64())
	}
	// Plain string
	return VrlValue(val)
}

fn yaml_strip_comment(s string) string {
	// Don't strip from quoted strings
	if s.starts_with('"') || s.starts_with("'") {
		return s
	}
	mut i := 0
	for i < s.len {
		if s[i] == `#` && i > 0 && s[i - 1] == ` ` {
			return s[..i].trim_right(' \t')
		}
		i++
	}
	return s
}

fn yaml_is_integer(s string) bool {
	if s.len == 0 {
		return false
	}
	start := if s[0] == `-` || s[0] == `+` { 1 } else { 0 }
	if start >= s.len {
		return false
	}
	// Octal 0o prefix
	if s.len > start + 1 && s[start] == `0` && (s[start + 1] == `o` || s[start + 1] == `O`) {
		return true
	}
	// Hex 0x prefix
	if s.len > start + 1 && s[start] == `0` && (s[start + 1] == `x` || s[start + 1] == `X`) {
		return true
	}
	for i in start .. s.len {
		if s[i] == `_` {
			continue
		}
		if !s[i].is_digit() {
			return false
		}
	}
	return true
}

fn yaml_is_float(s string) bool {
	if s == '.inf' || s == '.Inf' || s == '.INF' || s == '-.inf' || s == '-.Inf'
		|| s == '-.INF' || s == '.nan' || s == '.NaN' || s == '.NAN' {
		return true
	}
	if s.len == 0 {
		return false
	}
	mut has_dot := false
	mut has_e := false
	start := if s[0] == `-` || s[0] == `+` { 1 } else { 0 }
	if start >= s.len {
		return false
	}
	for i in start .. s.len {
		ch := s[i]
		if ch == `.` {
			if has_dot {
				return false
			}
			has_dot = true
		} else if ch == `e` || ch == `E` {
			if has_e {
				return false
			}
			has_e = true
		} else if ch == `+` || ch == `-` {
			if i == 0 || (s[i - 1] != `e` && s[i - 1] != `E`) {
				return false
			}
		} else if ch == `_` {
			continue
		} else if !ch.is_digit() {
			return false
		}
	}
	return has_dot || has_e
}

fn yaml_indent(line string) int {
	mut count := 0
	for c in line {
		if c == ` ` {
			count++
		} else {
			break
		}
	}
	return count
}

fn yaml_is_mapping_line(trimmed string) bool {
	if trimmed.len == 0 {
		return false
	}
	// Skip quoted keys
	if trimmed[0] == `"` {
		end := trimmed.index_after_('"', 1)
		if end > 0 && end + 1 < trimmed.len && trimmed[end + 1] == `:` {
			return true
		}
		return false
	}
	if trimmed[0] == `'` {
		end := trimmed.index_after_("'", 1)
		if end > 0 && end + 1 < trimmed.len && trimmed[end + 1] == `:` {
			return true
		}
		return false
	}
	// Find colon not inside quotes
	colon := yaml_find_colon(trimmed)
	if colon < 0 {
		return false
	}
	// Key: value requires colon followed by space or end of string
	if colon + 1 >= trimmed.len {
		return true
	}
	return trimmed[colon + 1] == ` ` || trimmed[colon + 1] == `\t`
}

fn yaml_find_colon(s string) int {
	mut in_single := false
	mut in_double := false
	for i := 0; i < s.len; i++ {
		ch := s[i]
		if ch == `'` && !in_double {
			in_single = !in_single
		} else if ch == `"` && !in_single {
			in_double = !in_double
		} else if ch == `:` && !in_single && !in_double {
			// Must be followed by space, tab, or end-of-string for block style
			if i + 1 >= s.len || s[i + 1] == ` ` || s[i + 1] == `\t` {
				return i
			}
		}
	}
	return -1
}

fn yaml_split_mapping(trimmed string) (string, string) {
	colon := yaml_find_colon(trimmed)
	if colon < 0 {
		return trimmed, ''
	}
	raw_key := trimmed[..colon].trim_space()
	key := yaml_unquote(raw_key)
	val := if colon + 1 < trimmed.len { trimmed[colon + 1..] } else { '' }
	return key, val
}

fn yaml_unquote(s string) string {
	if s.len < 2 {
		return s
	}
	if s[0] == `"` && s[s.len - 1] == `"` {
		inner := s[1..s.len - 1]
		// Handle escape sequences
		return inner.replace('\\n', '\n').replace('\\t', '\t').replace('\\"', '"').replace('\\\\',
			'\\')
	}
	if s[0] == `'` && s[s.len - 1] == `'` {
		inner := s[1..s.len - 1]
		// Single-quoted strings only escape '' -> '
		return inner.replace("''", "'")
	}
	return s
}

// parse_aws_cloudwatch_log_subscription_message(value) - parses an AWS CloudWatch Logs subscription message JSON string.
// Returns an object with: owner, message_type, log_group, log_stream, subscription_filters, log_events.
// The log_events array contains objects with: id, timestamp (as Timestamp), message.
fn fn_parse_aws_cloudwatch_log_subscription_message(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_aws_cloudwatch_log_subscription_message requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('parse_aws_cloudwatch_log_subscription_message requires a string') }
	}

	// Parse the JSON string
	parsed := parse_json_recursive(s) or { return error('unable to parse: ${err.msg()}') }

	// The parsed value must be an object
	obj := match parsed {
		ObjectMap { parsed }
		else { return error('unable to parse: expected object') }
	}

	// Extract required fields
	message_type_val := obj.get('messageType') or {
		return error('unable to parse: missing field messageType')
	}
	message_type := match message_type_val {
		string { message_type_val }
		else { return error('unable to parse: messageType must be a string') }
	}
	// Validate message type
	if message_type != 'DATA_MESSAGE' && message_type != 'CONTROL_MESSAGE' {
		return error('unable to parse: invalid messageType')
	}

	owner_val := obj.get('owner') or { return error('unable to parse: missing field owner') }
	owner := match owner_val {
		string { owner_val }
		else { return error('unable to parse: owner must be a string') }
	}

	log_group_val := obj.get('logGroup') or {
		return error('unable to parse: missing field logGroup')
	}
	log_group := match log_group_val {
		string { log_group_val }
		else { return error('unable to parse: logGroup must be a string') }
	}

	log_stream_val := obj.get('logStream') or {
		return error('unable to parse: missing field logStream')
	}
	log_stream := match log_stream_val {
		string { log_stream_val }
		else { return error('unable to parse: logStream must be a string') }
	}

	sub_filters_val := obj.get('subscriptionFilters') or {
		return error('unable to parse: missing field subscriptionFilters')
	}
	sub_filters_arr := match sub_filters_val {
		[]VrlValue { sub_filters_val }
		else { return error('unable to parse: subscriptionFilters must be an array') }
	}

	log_events_val := obj.get('logEvents') or {
		return error('unable to parse: missing field logEvents')
	}
	log_events_arr := match log_events_val {
		[]VrlValue { log_events_val }
		else { return error('unable to parse: logEvents must be an array') }
	}

	// Process log events: convert each to object with id, timestamp, message
	mut result_events := []VrlValue{cap: log_events_arr.len}
	for ev in log_events_arr {
		ev_obj := match ev {
			ObjectMap { ev }
			else { return error('unable to parse: logEvent must be an object') }
		}

		ev_id_val := ev_obj.get('id') or {
			return error('unable to parse: logEvent missing id')
		}
		ev_id := match ev_id_val {
			string { ev_id_val }
			else { return error('unable to parse: logEvent id must be a string') }
		}

		ev_ts_val := ev_obj.get('timestamp') or {
			return error('unable to parse: logEvent missing timestamp')
		}
		ev_ts_ms := match ev_ts_val {
			i64 { ev_ts_val }
			else { return error('unable to parse: logEvent timestamp must be an integer') }
		}

		ev_msg_val := ev_obj.get('message') or {
			return error('unable to parse: logEvent missing message')
		}
		ev_msg := match ev_msg_val {
			string { ev_msg_val }
			else { return error('unable to parse: logEvent message must be a string') }
		}

		// Convert millisecond timestamp to Timestamp
		secs := ev_ts_ms / 1000
		micro := (ev_ts_ms % 1000) * 1000
		ts := Timestamp{t: time.unix_microsecond(int(secs), int(micro))}

		mut ev_result := new_object_map()
		ev_result.set('id', VrlValue(ev_id))
		ev_result.set('timestamp', VrlValue(ts))
		ev_result.set('message', VrlValue(ev_msg))
		result_events << VrlValue(ev_result)
	}

	mut result := new_object_map()
	result.set('owner', VrlValue(owner))
	result.set('message_type', VrlValue(message_type))
	result.set('log_group', VrlValue(log_group))
	result.set('log_stream', VrlValue(log_stream))
	result.set('subscription_filters', VrlValue(sub_filters_arr))
	result.set('log_events', VrlValue(result_events))

	return VrlValue(result)
}
