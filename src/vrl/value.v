module vrl

import json
import time

// VrlValue represents a VRL value at runtime.
// Mirrors VRL's Value enum: Bytes, Integer, Float, Boolean, Object, Array, Timestamp, Regex, Null.
pub type VrlValue = string
	| i64
	| f64
	| bool
	| []VrlValue
	| ObjectMap
	| Timestamp
	| VrlRegex
	| VrlNull

// Timestamp wraps time.Time to distinguish from other types.
pub struct Timestamp {
pub:
	t time.Time
}

// VrlRegex holds a compiled regex pattern string.
pub struct VrlRegex {
pub:
	pattern string
}

// VrlNull represents the null value.
pub struct VrlNull {}

// to_string converts a VrlValue to its display string.
pub fn vrl_to_string(v VrlValue) string {
	match v {
		string {
			return v
		}
		i64 {
			return '${v}'
		}
		f64 {
			return format_float(v)
		}
		bool {
			return if v { 'true' } else { 'false' }
		}
		VrlNull {
			return 'null'
		}
		Timestamp {
			return format_timestamp(v.t)
		}
		VrlRegex {
			return v.pattern
		}
		[]VrlValue {
			return vrl_to_json(VrlValue(v))
		}
		ObjectMap {
			return vrl_to_json(VrlValue(v))
		}
	}
}

// format_timestamp formats a time.Time as RFC3339 matching Rust chrono's
// to_rfc3339_opts(SecondsFormat::AutoSi, true): uses 0, 3, 6, or 9 fractional
// digits — the minimum needed to represent the stored precision without
// trailing zeros.  V's time.Time stores microsecond precision, so we emit
// up to 6 digits.
fn format_timestamp(t time.Time) string {
	micro := t.unix_micro()
	frac_us := micro % 1_000_000
	// Normalize negative fractional part
	frac := if frac_us < 0 { frac_us + 1_000_000 } else { frac_us }

	// Build date-time prefix: 2020-12-30T22:20:53
	// We use V's format but replace its fractional handling with our own.
	base := t.format_rfc3339()

	// Find the 'T' separator to get the date-time prefix without fractional part
	// V's format_rfc3339 produces e.g. "2020-12-30T22:20:53.824Z"
	// We need to strip from '.' onwards and rebuild
	mut dt := ''
	mut suffix := 'Z'
	dot_idx := base.index('.') or { -1 }
	if dot_idx >= 0 {
		dt = base[..dot_idx]
		// Find timezone suffix after fractional digits
		rest := base[dot_idx + 1..]
		for i, c in rest {
			if c == `Z` || c == `+` || c == `-` {
				suffix = rest[i..]
				break
			}
		}
	} else {
		// No fractional part in V's output
		// Strip trailing Z/+offset
		if base.ends_with('Z') {
			dt = base[..base.len - 1]
			suffix = 'Z'
		} else {
			// Find +/- timezone offset
			for i := base.len - 1; i >= 0; i-- {
				if base[i] == `+` || (base[i] == `-` && i > 10) {
					dt = base[..i]
					suffix = base[i..]
					break
				}
			}
		}
	}

	// AutoSi: use minimum digits (0, 3, or 6) to represent precision
	if frac == 0 {
		return '${dt}${suffix}'
	} else if frac % 1000 == 0 {
		ms := frac / 1000
		return '${dt}.${ms:03}${suffix}'
	} else {
		return '${dt}.${frac:06}${suffix}'
	}
}

// format_float formats a float, stripping trailing zeros but keeping at least one decimal.
fn format_float(f f64) string {
	// Check if it's an integer value
	if f == f64(i64(f)) && f < 1e15 && f > -1e15 {
		return '${i64(f)}.0'
	}
	s := '${f}'
	// If V uses scientific notation, convert to decimal
	if s.contains('e') || s.contains('E') {
		return float_to_decimal(s, f)
	}
	return s
}

// float_to_decimal converts scientific notation string to decimal form.
fn float_to_decimal(s string, f f64) string {
	e_idx := s.index_any('eE')
	if e_idx < 0 { return s }
	mantissa := s[..e_idx]
	exp := s[e_idx + 1..].int()
	is_neg := f < 0

	mut digits := mantissa.replace('.', '').replace('-', '')
	dot_idx := mantissa.index('.') or { -1 }
	mut dec_pos := if dot_idx >= 0 {
		if is_neg { dot_idx - 1 } else { dot_idx }
	} else {
		digits.len
	}
	dec_pos += exp

	if dec_pos >= digits.len {
		for digits.len < dec_pos { digits += '0' }
		result := '${digits}.0'
		return if is_neg { '-${result}' } else { result }
	}
	if dec_pos <= 0 {
		result := '0.${"0".repeat(-dec_pos)}${digits}'
		return if is_neg { '-${result}' } else { result }
	}
	result := '${digits[..dec_pos]}.${digits[dec_pos..]}'
	return if is_neg { '-${result}' } else { result }
}

// vrl_to_json converts a VrlValue to its JSON representation.
pub fn vrl_to_json(v VrlValue) string {
	match v {
		string {
			return json.encode(v)
		}
		i64 {
			return '${v}'
		}
		f64 {
			return format_float(v)
		}
		bool {
			return if v { 'true' } else { 'false' }
		}
		VrlNull {
			return 'null'
		}
		Timestamp {
			ts := format_timestamp(v.t)
			return '"${ts}"'
		}
		VrlRegex {
			return "\"r'${v.pattern}'\""
		}
		[]VrlValue {
			mut parts := []string{}
			for item in v {
				parts << vrl_to_json(item)
			}
			return '[${parts.join(",")}]'
		}
		ObjectMap {
			mut parts := []string{}
			// Sort keys for deterministic output
			mut all_keys := v.keys()
			all_keys.sort()
			for k in all_keys {
				val := v.get(k) or { VrlValue(VrlNull{}) }
				parts << '"${k}":${vrl_to_json(val)}'
			}
			return '{${parts.join(",")}}'
		}
	}
}

// vrl_to_json_pretty converts a VrlValue to pretty-printed JSON.
pub fn vrl_to_json_pretty(v VrlValue, indent int) string {
	prefix := '  '.repeat(indent)
	inner := '  '.repeat(indent + 1)
	match v {
		string { return json.encode(v) }
		i64 { return '${v}' }
		f64 { return format_float(v) }
		bool { return if v { 'true' } else { 'false' } }
		VrlNull { return 'null' }
		Timestamp {
			ts := format_timestamp(v.t)
			return '"${ts}"'
		}
		VrlRegex { return "\"r'${v.pattern}'\"" }
		[]VrlValue {
			if v.len == 0 { return '[]' }
			mut parts := []string{}
			for item in v {
				parts << '${inner}${vrl_to_json_pretty(item, indent + 1)}'
			}
			return '[\n${parts.join(",\n")}\n${prefix}]'
		}
		ObjectMap {
			if v.len() == 0 { return '{}' }
			mut parts := []string{}
			mut all_keys := v.keys()
			all_keys.sort()
			for k in all_keys {
				val := v.get(k) or { VrlValue(VrlNull{}) }
				parts << '${inner}"${k}": ${vrl_to_json_pretty(val, indent + 1)}'
			}
			return '{\n${parts.join(",\n")}\n${prefix}}'
		}
	}
}

// is_truthy checks if a VrlValue is truthy (for boolean context).
pub fn is_truthy(v VrlValue) bool {
	match v {
		bool { return v }
		VrlNull { return false }
		string { return v.len > 0 }
		i64 { return v != 0 }
		f64 { return v != 0.0 }
		else { return true }
	}
}

// values_equal checks if two VrlValues are equal.
pub fn values_equal(a VrlValue, b VrlValue) bool {
	match a {
		i64 {
			match b {
				i64 { return a == b }
				f64 { return f64(a) == b }
				else { return false }
			}
		}
		f64 {
			match b {
				f64 { return a == b }
				i64 { return a == f64(b) }
				else { return false }
			}
		}
		string {
			match b {
				string { return a == b }
				else { return false }
			}
		}
		bool {
			match b {
				bool { return a == b }
				else { return false }
			}
		}
		VrlNull {
			return b is VrlNull
		}
		[]VrlValue {
			match b {
				[]VrlValue {
					if a.len != b.len {
						return false
					}
					for i in 0 .. a.len {
						if !values_equal(a[i], b[i]) {
							return false
						}
					}
					return true
				}
				else { return false }
			}
		}
		ObjectMap {
			match b {
				ObjectMap {
					if a.len() != b.len() {
						return false
					}
					if a.is_large {
						for k, v in a.hm {
							if bv := b.get(k) {
								if !values_equal(v, bv) {
									return false
								}
							} else {
								return false
							}
						}
					} else {
						for i in 0 .. a.ks.len {
							if bv := b.get(a.ks[i]) {
								if !values_equal(a.vs[i], bv) {
									return false
								}
							} else {
								return false
							}
						}
					}
					return true
				}
				else { return false }
			}
		}
		Timestamp {
			match b {
				Timestamp { return a.t == b.t }
				else { return false }
			}
		}
		VrlRegex {
			match b {
				VrlRegex { return a.pattern == b.pattern }
				else { return false }
			}
		}
	}
}
