module vrl

import os
import pcre2

// validate_json_schema validates a JSON string against a JSON Schema definition file.
// Parameters: value (string), schema_definition (string path), ignore_unknown_formats (bool, optional default false)
// Returns true if valid, error with details if invalid.
fn fn_validate_json_schema(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('validate_json_schema requires at least 2 arguments')
	}
	value_str := match args[0] {
		string { args[0] as string }
		else { return error('validate_json_schema: value must be a string') }
	}
	schema_path := match args[1] {
		string { args[1] as string }
		else { return error('validate_json_schema: schema_definition must be a string') }
	}
	ignore_unknown_formats := if args.len > 2 {
		match args[2] {
			bool { args[2] as bool }
			else { false }
		}
	} else {
		false
	}

	// Empty JSON check
	if value_str.trim_space().len == 0 {
		return error('Empty JSON value')
	}

	// Strip BOM
	trimmed := if value_str.len >= 3 && value_str[0] == 0xEF && value_str[1] == 0xBB
		&& value_str[2] == 0xBF {
		value_str[3..]
	} else {
		value_str
	}

	// Parse the JSON value
	json_val := parse_json_recursive(trimmed) or {
		return error('Invalid JSON: ${err.msg()}')
	}

	// Load and parse the schema
	schema_str := os.read_file(schema_path) or {
		return error("Failed to open schema definition file '${schema_path}': ${err.msg()}")
	}
	schema := parse_json_recursive(schema_str) or {
		return error("Failed to parse schema definition file '${schema_path}': ${err.msg()}")
	}

	// Validate
	mut ctx := JsonSchemaContext{
		root_schema: schema
		ignore_unknown_formats: ignore_unknown_formats
	}
	errors := ctx.validate(json_val, schema, '/')
	if errors.len == 0 {
		return VrlValue(true)
	}
	error_msg := errors.join(', ')
	return error('JSON schema validation failed: ${error_msg}')
}

struct JsonSchemaContext {
	root_schema         VrlValue
	ignore_unknown_formats bool
}

// validate checks a value against a schema node and returns a list of error strings.
fn (mut ctx JsonSchemaContext) validate(value VrlValue, schema VrlValue, path string) []string {
	schema_obj := match schema {
		ObjectMap { schema as ObjectMap }
		bool {
			// boolean schema: true accepts everything, false rejects everything
			b := schema as bool
			if b {
				return []
			}
			return ['Schema is false at ${path}']
		}
		else { return [] } // non-object schema, skip
	}

	mut errors := []string{}

	// Handle $ref
	if ref_val := schema_obj.get('\$ref') {
		ref_str := match ref_val {
			string { ref_val as string }
			else { '' }
		}
		if ref_str.len > 0 {
			resolved := ctx.resolve_ref(ref_str)
			if resolved is ObjectMap {
				errors << ctx.validate(value, resolved, path)
			}
		}
	}

	// type validation
	if type_val := schema_obj.get('type') {
		match type_val {
			string {
				type_str := type_val as string
				type_err := jsonschema_check_type(value, type_str, path)
				if type_err.len > 0 {
					errors << type_err
					return errors // type mismatch, skip further checks
				}
			}
			[]VrlValue {
				// type as array of types (union)
				type_arr := type_val as []VrlValue
				mut matched := false
				for t in type_arr {
					ts := match t {
						string { t as string }
						else { continue }
					}
					if jsonschema_check_type(value, ts, path).len == 0 {
						matched = true
						break
					}
				}
				if !matched {
					type_names := type_arr.map(fn (v VrlValue) string {
						return match v {
							string { v as string }
							else { '?' }
						}
					})
					errors << '${jsonschema_display(value)} is not of type ${type_names.join(", ")} at ${path}'
					return errors
				}
			}
			else {}
		}
	}

	// enum
	if enum_val := schema_obj.get('enum') {
		if enum_val is []VrlValue {
			arr := enum_val as []VrlValue
			mut found := false
			for item in arr {
				if jsonschema_values_equal(value, item) {
					found = true
					break
				}
			}
			if !found {
				errors << '${jsonschema_display(value)} is not one of the allowed enum values at ${path}'
			}
		}
	}

	// const
	if const_val := schema_obj.get('const') {
		if !jsonschema_values_equal(value, const_val) {
			errors << '${jsonschema_display(value)} does not match const at ${path}'
		}
	}

	// String validations
	if value is string {
		s := value as string

		// minLength
		if ml := schema_obj.get('minLength') {
			min_len := jsonschema_to_int(ml)
			if min_len >= 0 && s.len < min_len {
				errors << '"${s}" has fewer than ${min_len} characters at ${path}'
			}
		}
		// maxLength
		if ml := schema_obj.get('maxLength') {
			max_len := jsonschema_to_int(ml)
			if max_len >= 0 && s.len > max_len {
				errors << '"${s}" has more than ${max_len} characters at ${path}'
			}
		}
		// pattern
		if pat_val := schema_obj.get('pattern') {
			if pat_val is string {
				pat := pat_val as string
				if !jsonschema_regex_matches(pat, s) {
					errors << '"${s}" does not match pattern "${pat}" at ${path}'
				}
			}
		}
		// format
		if fmt_val := schema_obj.get('format') {
			if fmt_val is string {
				fmt_str := fmt_val as string
				fmt_err := ctx.validate_format(s, fmt_str, path)
				if fmt_err.len > 0 {
					errors << fmt_err
				}
			}
		}
	}

	// Number validations
	val_f := jsonschema_to_f64(value)
	is_number := (value is i64) || (value is f64)
	if is_number {
		if min_val := schema_obj.get('minimum') {
			min_f := jsonschema_to_f64(min_val)
			if val_f < min_f {
				errors << '${jsonschema_display(value)} is less than ${min_f} at ${path}'
			}
		}
		if max_val := schema_obj.get('maximum') {
			max_f := jsonschema_to_f64(max_val)
			if val_f > max_f {
				errors << '${jsonschema_display(value)} is greater than ${max_f} at ${path}'
			}
		}
		if emin := schema_obj.get('exclusiveMinimum') {
			emin_f := jsonschema_to_f64(emin)
			if val_f <= emin_f {
				errors << '${jsonschema_display(value)} is not greater than ${emin_f} at ${path}'
			}
		}
		if emax := schema_obj.get('exclusiveMaximum') {
			emax_f := jsonschema_to_f64(emax)
			if val_f >= emax_f {
				errors << '${jsonschema_display(value)} is not less than ${emax_f} at ${path}'
			}
		}
		if mult := schema_obj.get('multipleOf') {
			mult_f := jsonschema_to_f64(mult)
			if mult_f > 0 {
				remainder := val_f - (int(val_f / mult_f) * mult_f)
				if remainder > 1e-10 || remainder < -1e-10 {
					errors << '${jsonschema_display(value)} is not a multiple of ${mult_f} at ${path}'
				}
			}
		}
	}

	// Object validations
	if value is ObjectMap {
		obj := value as ObjectMap
		keys := obj.keys()

		// required
		if req_val := schema_obj.get('required') {
			if req_val is []VrlValue {
				req_arr := req_val as []VrlValue
				for ritem in req_arr {
					if ritem is string {
						rkey := ritem as string
						_ := obj.get(rkey) or {
							errors << '"${rkey}" is a required property at ${path}'
							continue
						}
					}
				}
			}
		}

		// properties
		if props_val := schema_obj.get('properties') {
			if props_val is ObjectMap {
				props := props_val as ObjectMap
				for pkey in props.keys() {
					if pv := obj.get(pkey) {
						prop_schema := props.get(pkey) or { continue }
						sub_path := if path == '/' { '/${pkey}' } else { '${path}/${pkey}' }
						errors << ctx.validate(pv, prop_schema, sub_path)
					}
				}
			}
		}

		// additionalProperties
		if addl_val := schema_obj.get('additionalProperties') {
			props_keys := if pv := schema_obj.get('properties') {
				if pv is ObjectMap {
					(pv as ObjectMap).keys()
				} else {
					[]string{}
				}
			} else {
				[]string{}
			}
			pat_props_keys := if ppv := schema_obj.get('patternProperties') {
				if ppv is ObjectMap {
					(ppv as ObjectMap).keys()
				} else {
					[]string{}
				}
			} else {
				[]string{}
			}

			for k in keys {
				if k in props_keys {
					continue
				}
				// Check pattern properties
				mut matched_pattern := false
				for pp in pat_props_keys {
					if jsonschema_regex_matches(pp, k) {
						matched_pattern = true
						break
					}
				}
				if matched_pattern {
					continue
				}
				// Apply additionalProperties schema
				match addl_val {
					bool {
						if !(addl_val as bool) {
							errors << 'Additional property "${k}" is not allowed at ${path}'
						}
					}
					ObjectMap {
						sub_path := if path == '/' {
							'/${k}'
						} else {
							'${path}/${k}'
						}
						kv := obj.get(k) or { continue }
						errors << ctx.validate(kv, addl_val, sub_path)
					}
					else {}
				}
			}
		}

		// patternProperties
		if pp_val := schema_obj.get('patternProperties') {
			if pp_val is ObjectMap {
				pp := pp_val as ObjectMap
				for pat_key in pp.keys() {
					pat_schema := pp.get(pat_key) or { continue }
					for k in keys {
						if jsonschema_regex_matches(pat_key, k) {
							sub_path := if path == '/' {
								'/${k}'
							} else {
								'${path}/${k}'
							}
							kv := obj.get(k) or { continue }
							errors << ctx.validate(kv, pat_schema, sub_path)
						}
					}
				}
			}
		}

		// minProperties / maxProperties
		if mp := schema_obj.get('minProperties') {
			min_p := jsonschema_to_int(mp)
			if min_p >= 0 && keys.len < min_p {
				errors << 'Object has fewer than ${min_p} properties at ${path}'
			}
		}
		if mp := schema_obj.get('maxProperties') {
			max_p := jsonschema_to_int(mp)
			if max_p >= 0 && keys.len > max_p {
				errors << 'Object has more than ${max_p} properties at ${path}'
			}
		}

		// propertyNames
		if pn := schema_obj.get('propertyNames') {
			for k in keys {
				errors << ctx.validate(VrlValue(k), pn, path)
			}
		}
	}

	// Array validations
	if value is []VrlValue {
		arr := value as []VrlValue

		// items
		if items_val := schema_obj.get('items') {
			for i, item in arr {
				sub_path := if path == '/' { '/${i}' } else { '${path}/${i}' }
				errors << ctx.validate(item, items_val, sub_path)
			}
		}

		// prefixItems
		if pi_val := schema_obj.get('prefixItems') {
			if pi_val is []VrlValue {
				pi_arr := pi_val as []VrlValue
				for i, pi_schema in pi_arr {
					if i < arr.len {
						sub_path := if path == '/' { '/${i}' } else { '${path}/${i}' }
						errors << ctx.validate(arr[i], pi_schema, sub_path)
					}
				}
			}
		}

		// minItems
		if mi := schema_obj.get('minItems') {
			min_i := jsonschema_to_int(mi)
			if min_i >= 0 && arr.len < min_i {
				errors << 'Array has fewer than ${min_i} items at ${path}'
			}
		}
		// maxItems
		if mi := schema_obj.get('maxItems') {
			max_i := jsonschema_to_int(mi)
			if max_i >= 0 && arr.len > max_i {
				errors << 'Array has more than ${max_i} items at ${path}'
			}
		}
		// uniqueItems
		if ui := schema_obj.get('uniqueItems') {
			if ui is bool && (ui as bool) {
				for i, a in arr {
					for j := i + 1; j < arr.len; j++ {
						if jsonschema_values_equal(a, arr[j]) {
							errors << 'Array items are not unique at ${path}'
							break
						}
					}
				}
			}
		}
		// contains
		if contains_val := schema_obj.get('contains') {
			mut found := false
			for item in arr {
				if ctx.validate(item, contains_val, path).len == 0 {
					found = true
					break
				}
			}
			if !found {
				errors << 'No items match "contains" schema at ${path}'
			}
		}
	}

	// allOf
	if allof := schema_obj.get('allOf') {
		if allof is []VrlValue {
			for sub in allof as []VrlValue {
				errors << ctx.validate(value, sub, path)
			}
		}
	}

	// anyOf
	if anyof := schema_obj.get('anyOf') {
		if anyof is []VrlValue {
			mut any_match := false
			for sub in anyof as []VrlValue {
				if ctx.validate(value, sub, path).len == 0 {
					any_match = true
					break
				}
			}
			if !any_match {
				errors << '${jsonschema_display(value)} does not match any of the "anyOf" schemas at ${path}'
			}
		}
	}

	// oneOf
	if oneof := schema_obj.get('oneOf') {
		if oneof is []VrlValue {
			mut match_count := 0
			for sub in oneof as []VrlValue {
				if ctx.validate(value, sub, path).len == 0 {
					match_count++
				}
			}
			if match_count == 0 {
				errors << '${jsonschema_display(value)} does not match any "oneOf" schemas at ${path}'
			} else if match_count > 1 {
				errors << '${jsonschema_display(value)} matches more than one "oneOf" schema at ${path}'
			}
		}
	}

	// not
	if not_val := schema_obj.get('not') {
		if ctx.validate(value, not_val, path).len == 0 {
			errors << '${jsonschema_display(value)} should not match the "not" schema at ${path}'
		}
	}

	// if/then/else
	if if_val := schema_obj.get('if') {
		if ctx.validate(value, if_val, path).len == 0 {
			// condition passed - apply "then" if present
			if then_val := schema_obj.get('then') {
				errors << ctx.validate(value, then_val, path)
			}
		} else {
			// condition failed - apply "else" if present
			if else_val := schema_obj.get('else') {
				errors << ctx.validate(value, else_val, path)
			}
		}
	}

	return errors
}

// resolve_ref resolves a $ref URI. Only supports local refs (#/...) and #/$defs/...
fn (ctx &JsonSchemaContext) resolve_ref(ref_str string) VrlValue {
	if !ref_str.starts_with('#/') {
		return VrlValue(VrlNull{})
	}
	parts := ref_str[2..].split('/')
	mut current := ctx.root_schema
	for part in parts {
		if current is ObjectMap {
			obj := current as ObjectMap
			current = obj.get(part) or { return VrlValue(VrlNull{}) }
		} else {
			return VrlValue(VrlNull{})
		}
	}
	return current
}

// validate_format checks known format specifiers
fn (ctx &JsonSchemaContext) validate_format(s string, fmt string, path string) []string {
	match fmt {
		'email' {
			if !jsonschema_is_valid_email(s) {
				return ['"${s}" is not a "${fmt}" at ${path}']
			}
		}
		'date-time' {
			if !jsonschema_is_valid_datetime(s) {
				return ['"${s}" is not a "${fmt}" at ${path}']
			}
		}
		'date' {
			if !jsonschema_is_valid_date(s) {
				return ['"${s}" is not a "${fmt}" at ${path}']
			}
		}
		'time' {
			if !jsonschema_is_valid_time(s) {
				return ['"${s}" is not a "${fmt}" at ${path}']
			}
		}
		'uri', 'uri-reference', 'iri', 'iri-reference' {
			if !jsonschema_is_valid_uri(s) {
				return ['"${s}" is not a "${fmt}" at ${path}']
			}
		}
		'ipv4' {
			if !jsonschema_is_valid_ipv4(s) {
				return ['"${s}" is not a "${fmt}" at ${path}']
			}
		}
		'ipv6' {
			if !jsonschema_is_valid_ipv6(s) {
				return ['"${s}" is not a "${fmt}" at ${path}']
			}
		}
		'hostname' {
			if !jsonschema_is_valid_hostname(s) {
				return ['"${s}" is not a "${fmt}" at ${path}']
			}
		}
		'uuid' {
			if !jsonschema_is_valid_uuid(s) {
				return ['"${s}" is not a "${fmt}" at ${path}']
			}
		}
		'regex' {
			// Check if the string is a valid regex
			_ := pcre2.compile(s) or {
				return ['"${s}" is not a "${fmt}" at ${path}']
			}
		}
		else {
			if !ctx.ignore_unknown_formats {
				return ["Unknown format: '${fmt}'. Adjust configuration to ignore unrecognized formats"]
			}
		}
	}
	return []
}

// jsonschema_check_type checks if value matches a JSON Schema type string
fn jsonschema_check_type(value VrlValue, type_str string, path string) []string {
	valid := match type_str {
		'string' { value is string }
		'number' { (value is i64) || (value is f64) }
		'integer' { value is i64 }
		'boolean' { value is bool }
		'array' { value is []VrlValue }
		'object' { value is ObjectMap }
		'null' { value is VrlNull }
		else { true }
	}
	if !valid {
		return ['${jsonschema_display(value)} is not of type "${type_str}" at ${path}']
	}
	return []
}

// jsonschema_display returns a compact display for a value
fn jsonschema_display(value VrlValue) string {
	match value {
		string { return '"${value as string}"' }
		i64 { return '${value as i64}' }
		f64 { return '${value as f64}' }
		bool { return if value as bool { 'true' } else { 'false' } }
		VrlNull { return 'null' }
		[]VrlValue { return '[...]' }
		ObjectMap { return '{...}' }
		else { return '?' }
	}
}

// jsonschema_values_equal compares two VRL values for equality
fn jsonschema_values_equal(a VrlValue, b VrlValue) bool {
	match a {
		string {
			if b is string {
				return (a as string) == (b as string)
			}
			return false
		}
		i64 {
			if b is i64 {
				return (a as i64) == (b as i64)
			}
			if b is f64 {
				return f64(a as i64) == (b as f64)
			}
			return false
		}
		f64 {
			if b is f64 {
				return (a as f64) == (b as f64)
			}
			if b is i64 {
				return (a as f64) == f64(b as i64)
			}
			return false
		}
		bool {
			if b is bool {
				return (a as bool) == (b as bool)
			}
			return false
		}
		VrlNull {
			return b is VrlNull
		}
		[]VrlValue {
			if b is []VrlValue {
				aa := a as []VrlValue
				ba := b as []VrlValue
				if aa.len != ba.len {
					return false
				}
				for i, av in aa {
					if !jsonschema_values_equal(av, ba[i]) {
						return false
					}
				}
				return true
			}
			return false
		}
		ObjectMap {
			if b is ObjectMap {
				ao := a as ObjectMap
				bo := b as ObjectMap
				ak := ao.keys()
				bk := bo.keys()
				if ak.len != bk.len {
					return false
				}
				for k in ak {
					av := ao.get(k) or { return false }
					bv := bo.get(k) or { return false }
					if !jsonschema_values_equal(av, bv) {
						return false
					}
				}
				return true
			}
			return false
		}
		else {
			return false
		}
	}
}

// jsonschema_to_int converts a VrlValue to int (for schema numeric constraints)
fn jsonschema_to_int(v VrlValue) int {
	match v {
		i64 { return int(v as i64) }
		f64 { return int(v as f64) }
		else { return -1 }
	}
}

// jsonschema_to_f64 converts a VrlValue to f64
fn jsonschema_to_f64(v VrlValue) f64 {
	match v {
		f64 { return v as f64 }
		i64 { return f64(v as i64) }
		else { return 0.0 }
	}
}

// Format validators

fn jsonschema_is_valid_email(s string) bool {
	// RFC 5321 basic email validation
	mut at := -1
	for i, ch in s.bytes() {
		if ch == `@` {
			at = i
			break
		}
	}
	if at <= 0 || at >= s.len - 1 {
		return false
	}
	local := s[..at]
	domain := s[at + 1..]
	if local.len == 0 || local.len > 64 {
		return false
	}
	if domain.len == 0 || domain.len > 255 {
		return false
	}
	// Domain must have at least one dot
	if !domain.contains('.') {
		return false
	}
	// Domain parts must not be empty
	parts := domain.split('.')
	for part in parts {
		if part.len == 0 {
			return false
		}
	}
	return true
}

fn jsonschema_is_valid_datetime(s string) bool {
	// ISO 8601 date-time: YYYY-MM-DDTHH:MM:SS[.frac](Z|+HH:MM|-HH:MM)
	if s.len < 20 {
		return false
	}
	// Must have T or t separator
	if s[10] != `T` && s[10] != `t` {
		return false
	}
	return jsonschema_is_valid_date(s[..10]) && jsonschema_is_valid_time(s[11..])
}

fn jsonschema_is_valid_date(s string) bool {
	// YYYY-MM-DD
	if s.len != 10 {
		return false
	}
	if s[4] != `-` || s[7] != `-` {
		return false
	}
	for i in [0, 1, 2, 3, 5, 6, 8, 9] {
		if !s[i].is_digit() {
			return false
		}
	}
	return true
}

fn jsonschema_is_valid_time(s string) bool {
	// HH:MM:SS[.frac](Z|+HH:MM|-HH:MM)
	if s.len < 8 {
		return false
	}
	if s[2] != `:` || s[5] != `:` {
		return false
	}
	// Check digits
	for i in [0, 1, 3, 4, 6, 7] {
		if !s[i].is_digit() {
			return false
		}
	}
	// Rest should be optional fractional seconds + timezone
	mut pos := 8
	if pos < s.len && s[pos] == `.` {
		pos++
		for pos < s.len && s[pos].is_digit() {
			pos++
		}
	}
	if pos >= s.len {
		return true // no timezone specified is ok
	}
	if s[pos] == `Z` || s[pos] == `z` {
		return pos == s.len - 1
	}
	if s[pos] == `+` || s[pos] == `-` {
		tz := s[pos + 1..]
		if tz.len == 5 && tz[2] == `:` {
			return true
		}
	}
	return false
}

fn jsonschema_is_valid_uri(s string) bool {
	// Very basic URI validation - must have scheme://
	if s.contains('://') {
		return true
	}
	// URI-reference can be relative
	return s.len > 0
}

fn jsonschema_is_valid_ipv4(s string) bool {
	parts := s.split('.')
	if parts.len != 4 {
		return false
	}
	for part in parts {
		if part.len == 0 || part.len > 3 {
			return false
		}
		for ch in part.bytes() {
			if !ch.is_digit() {
				return false
			}
		}
		n := part.int()
		if n < 0 || n > 255 {
			return false
		}
		// No leading zeros
		if part.len > 1 && part[0] == `0` {
			return false
		}
	}
	return true
}

fn jsonschema_is_valid_ipv6(s string) bool {
	// Basic IPv6 validation
	if s.len < 2 || s.len > 45 {
		return false
	}
	// Must contain at least one colon
	if !s.contains(':') {
		return false
	}
	return true
}

fn jsonschema_is_valid_hostname(s string) bool {
	if s.len == 0 || s.len > 253 {
		return false
	}
	labels := s.split('.')
	for label in labels {
		if label.len == 0 || label.len > 63 {
			return false
		}
		if label[0] == `-` || label[label.len - 1] == `-` {
			return false
		}
		for ch in label.bytes() {
			if !ch.is_alnum() && ch != `-` {
				return false
			}
		}
	}
	return true
}

fn jsonschema_is_valid_uuid(s string) bool {
	// UUID format: 8-4-4-4-12 hex digits
	if s.len != 36 {
		return false
	}
	if s[8] != `-` || s[13] != `-` || s[18] != `-` || s[23] != `-` {
		return false
	}
	for i, ch in s.bytes() {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			continue
		}
		if !ch.is_hex_digit() {
			return false
		}
	}
	return true
}

// jsonschema_regex_matches returns true if the pattern matches the string
fn jsonschema_regex_matches(pattern string, s string) bool {
	re := pcre2.compile(pattern) or { return false }
	_ := re.find(s) or { return false }
	return true
}
