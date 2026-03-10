module vrl

import json
import time

// VrlValue represents a VRL value at runtime.
// Mirrors VRL's Value enum: Bytes, Integer, Float, Boolean, Object, Array, Timestamp, Regex, Null.
pub type VrlValue = string
	| int
	| f64
	| bool
	| []VrlValue
	| map[string]VrlValue
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
		int {
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
			return v.t.format_rfc3339()
		}
		VrlRegex {
			return v.pattern
		}
		[]VrlValue {
			return vrl_to_json(VrlValue(v))
		}
		map[string]VrlValue {
			return vrl_to_json(VrlValue(v))
		}
	}
}

// format_float formats a float, stripping trailing zeros but keeping at least one decimal.
fn format_float(f f64) string {
	// Check if it's an integer value
	if f == f64(i64(f)) && f < 1e15 && f > -1e15 {
		return '${i64(f)}.0'
	}
	s := '${f}'
	return s
}

// vrl_to_json converts a VrlValue to its JSON representation.
pub fn vrl_to_json(v VrlValue) string {
	match v {
		string {
			return json.encode(v)
		}
		int {
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
			return '"${v.t.format_rfc3339()}"'
		}
		VrlRegex {
			return '"${v.pattern}"'
		}
		[]VrlValue {
			mut parts := []string{}
			for item in v {
				parts << vrl_to_json(item)
			}
			return '[${parts.join(", ")}]'
		}
		map[string]VrlValue {
			mut parts := []string{}
			// Sort keys for deterministic output
			mut keys := v.keys()
			keys.sort()
			for k in keys {
				val := v[k] or { VrlValue(VrlNull{}) }
				parts << '"${k}": ${vrl_to_json(val)}'
			}
			return '{${parts.join(", ")}}'
		}
	}
}

// is_truthy checks if a VrlValue is truthy (for boolean context).
pub fn is_truthy(v VrlValue) bool {
	match v {
		bool { return v }
		VrlNull { return false }
		string { return v.len > 0 }
		int { return v != 0 }
		f64 { return v != 0.0 }
		else { return true }
	}
}

// values_equal checks if two VrlValues are equal.
pub fn values_equal(a VrlValue, b VrlValue) bool {
	return vrl_to_json(a) == vrl_to_json(b)
}
