module vrl

import encoding.base64
import encoding.hex

// encode_base64(value, [padding, charset])
fn fn_encode_base64(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('encode_base64 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('encode_base64 requires a string') }
	}
	padding := if args.len > 1 { get_bool_arg(args[1], true) } else { true }
	charset := if args.len > 2 {
		v := args[2]
		match v {
			string { v }
			else { 'standard' }
		}
	} else {
		'standard'
	}
	mut result := if charset == 'url_safe' {
		encoded := base64.url_encode(s.bytes())
		// url_encode strips padding, re-add if needed
		if padding {
			rem := encoded.len % 4
			if rem > 0 { '${encoded}${'='.repeat(4 - rem)}' } else { encoded }
		} else {
			encoded
		}
	} else {
		encoded := base64.encode(s.bytes())
		if !padding { encoded.trim_right('=') } else { encoded }
	}
	return VrlValue(result)
}

// decode_base64(value, [charset])
fn fn_decode_base64(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('decode_base64 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('decode_base64 requires a string') }
	}
	charset := if args.len > 1 {
		v := args[1]
		match v {
			string { v }
			else { 'standard' }
		}
	} else {
		'standard'
	}
	// Add padding if missing
	mut padded := s
	rem := padded.len % 4
	if rem > 0 {
		padded = padded + '='.repeat(4 - rem)
	}
	decoded := if charset == 'url_safe' {
		base64.url_decode(padded)
	} else {
		base64.decode(padded)
	}
	return VrlValue(decoded.bytestr())
}

// encode_base16(value)
fn fn_encode_base16(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('encode_base16 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('encode_base16 requires a string') }
	}
	return VrlValue(hex.encode(s.bytes()))
}

// decode_base16(value)
fn fn_decode_base16(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('decode_base16 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('decode_base16 requires a string') }
	}
	decoded := hex.decode(s) or { return error('invalid base16 input') }
	return VrlValue(decoded.bytestr())
}

// encode_percent(value, [ascii_set])
fn fn_encode_percent(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('encode_percent requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('encode_percent requires a string') }
	}
	ascii_set := if args.len > 1 {
		v := args[1]
		match v {
			string { v }
			else { 'NON_ALPHANUMERIC' }
		}
	} else {
		'NON_ALPHANUMERIC'
	}
	return VrlValue(percent_encode(s, ascii_set))
}

fn percent_encode(s string, ascii_set string) string {
	mut result := []u8{cap: s.len * 3}
	for c in s.bytes() {
		if should_percent_encode(c, ascii_set) {
			result << `%`
			hi := c >> 4
			lo := c & 0x0F
			result << hex_digit(hi)
			result << hex_digit(lo)
		} else {
			result << c
		}
	}
	return result.bytestr()
}

fn hex_digit(v u8) u8 {
	if v < 10 {
		return `0` + v
	}
	return `A` + v - 10
}

fn should_percent_encode(c u8, ascii_set string) bool {
	match ascii_set {
		'NON_ALPHANUMERIC' {
			return !((c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`))
		}
		'CONTROLS' {
			return c <= 0x1F || c == 0x7F
		}
		'NON_ASCII' {
			return c > 0x7E
		}
		else {
			// Default: encode everything except unreserved
			return !((c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
				|| c == `-` || c == `_` || c == `.` || c == `~`)
		}
	}
}

// decode_percent(value)
fn fn_decode_percent(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('decode_percent requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('decode_percent requires a string') }
	}
	return VrlValue(percent_decode(s))
}

fn percent_decode(s string) string {
	mut result := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		if s[i] == `%` && i + 2 < s.len {
			hi := hex_val(s[i + 1])
			lo := hex_val(s[i + 2])
			if hi >= 0 && lo >= 0 {
				result << u8(hi * 16 + lo)
				i += 3
				continue
			}
		}
		result << s[i]
		i++
	}
	return result.bytestr()
}

fn hex_val(c u8) int {
	if c >= `0` && c <= `9` {
		return int(c - `0`)
	}
	if c >= `a` && c <= `f` {
		return int(c - `a` + 10)
	}
	if c >= `A` && c <= `F` {
		return int(c - `A` + 10)
	}
	return -1
}

// encode_csv(value, [delimiter])
fn fn_encode_csv(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('encode_csv requires 1 argument')
	}
	a := args[0]
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
	match a {
		[]VrlValue {
			// Single row (array of values)
			return VrlValue(encode_csv_row(a, delimiter))
		}
		else {
			return error('encode_csv requires an array')
		}
	}
}

fn encode_csv_row(row []VrlValue, delimiter u8) string {
	mut parts := []string{}
	for item in row {
		parts << encode_csv_field(vrl_to_string(item), delimiter)
	}
	return parts.join(delimiter.ascii_str())
}

fn encode_csv_field(s string, delimiter u8) string {
	needs_quoting := s.contains(delimiter.ascii_str()) || s.contains('"') || s.contains('\n')
		|| s.contains('\r')
	if needs_quoting {
		return '"' + s.replace('"', '""') + '"'
	}
	return s
}

// encode_key_value(value, [fields_ordering, key_value_delimiter, field_delimiter, flatten_boolean])
fn fn_encode_key_value(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('encode_key_value requires 1 argument')
	}
	a := args[0]
	obj := match a {
		ObjectMap { a }
		else { return error('encode_key_value requires an object') }
	}
	kv_delim := if args.len > 2 {
		v := args[2]
		match v {
			string { v }
			else { '=' }
		}
	} else {
		'='
	}
	field_delim := if args.len > 3 {
		v := args[3]
		match v {
			string { v }
			else { ' ' }
		}
	} else {
		' '
	}
	flatten_bool := if args.len > 4 { get_bool_arg(args[4], false) } else { false }

	// Get field ordering
	mut ordered_keys := []string{}
	if args.len > 1 {
		fo := args[1]
		match fo {
			[]VrlValue {
				for item in fo {
					k := item
					match k {
						string { ordered_keys << k }
						else {}
					}
				}
			}
			else {}
		}
	}

	mut all_keys := obj.keys()
	all_keys.sort()

	// Build ordered list: specified keys first, then remaining sorted
	mut final_keys := []string{}
	for k in ordered_keys {
		if obj.has(k) {
			final_keys << k
		}
	}
	for k in all_keys {
		if k !in final_keys {
			final_keys << k
		}
	}

	mut parts := []string{}
	for k in final_keys {
		val := obj.get(k) or { continue }
		v := val
		match v {
			bool {
				if flatten_bool {
					if v {
						parts << k
					}
					continue
				}
			}
			else {}
		}
		val_str := kv_encode_value(val)
		parts << '${k}${kv_delim}${val_str}'
	}
	return VrlValue(parts.join(field_delim))
}

fn kv_encode_value(v VrlValue) string {
	val := v
	match val {
		string {
			if val.contains(' ') || val.contains('"') || val.contains('=') {
				return '"' + val.replace('\\', '\\\\').replace('"', '\\"') + '"'
			}
			return val
		}
		VrlNull {
			return ''
		}
		else {
			return vrl_to_string(v)
		}
	}
}

// encode_logfmt(value)
fn fn_encode_logfmt(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('encode_logfmt requires 1 argument')
	}
	a := args[0]
	obj := match a {
		ObjectMap { a }
		else { return error('encode_logfmt requires an object') }
	}
	mut all_keys := obj.keys()
	all_keys.sort()
	mut parts := []string{}
	for k in all_keys {
		val := obj.get(k) or { continue }
		val_str := logfmt_encode_value(val)
		parts << '${k}=${val_str}'
	}
	return VrlValue(parts.join(' '))
}

fn logfmt_encode_value(v VrlValue) string {
	val := v
	match val {
		string {
			if val.contains(' ') || val.contains('"') || val.contains('=') {
				return '"' + val.replace('\\', '\\\\').replace('"', '\\"') + '"'
			}
			return val
		}
		bool {
			return if val { 'true' } else { 'false' }
		}
		VrlNull {
			return ''
		}
		else {
			return vrl_to_string(v)
		}
	}
}
