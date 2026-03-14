module vrl

import os

// Helper: write a schema file, run validate_json_schema, return result
fn validate_schema(json_str string, schema string, schema_file string) !VrlValue {
	os.write_file(schema_file, schema) or { panic(err) }
	prog := 'validate_json_schema!("${json_str}", schema_definition: "${schema_file}")'
	return execute(prog, map[string]VrlValue{})
}

// Helper: validate using encode_json on a VRL literal so we can test objects/arrays
fn validate_schema_vrl(vrl_expr string, schema string, schema_file string) !VrlValue {
	os.write_file(schema_file, schema) or { panic(err) }
	prog := 'validate_json_schema!(encode_json(${vrl_expr}), schema_definition: "${schema_file}")'
	return execute(prog, map[string]VrlValue{})
}

// ============================================================
// Basic object validation
// ============================================================

fn test_jsonschema_basic_valid() {
	schema := '{"type": "object", "required": ["name"], "properties": {"name": {"type": "string"}}}'
	path := '/tmp/test_schema_basic_valid.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema_vrl('{"name": "Alice"}', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_missing_required() {
	schema := '{"type": "object", "required": ["name"], "properties": {"name": {"type": "string"}}}'
	path := '/tmp/test_schema_missing_req.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema_vrl('{"age": 30}', schema, path) or {
		assert err.msg().contains('required property')
		return
	}
	panic('expected validation error for missing required property')
}

// ============================================================
// Type validation
// ============================================================

fn test_jsonschema_type_string() {
	schema := '{"type": "string"}'
	path := '/tmp/test_schema_type_str.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"hello\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_type_string_invalid() {
	schema := '{"type": "string"}'
	path := '/tmp/test_schema_type_str_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('42', schema, path) or {
		assert err.msg().contains('not of type')
		return
	}
	panic('expected type error')
}

fn test_jsonschema_type_number() {
	schema := '{"type": "number"}'
	path := '/tmp/test_schema_type_num.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('3.14', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_type_integer() {
	schema := '{"type": "integer"}'
	path := '/tmp/test_schema_type_int.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('42', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_type_integer_rejects_float() {
	schema := '{"type": "integer"}'
	path := '/tmp/test_schema_type_int_float.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('3.14', schema, path) or {
		assert err.msg().contains('not of type')
		return
	}
	panic('expected type error for float when integer expected')
}

fn test_jsonschema_type_boolean() {
	schema := '{"type": "boolean"}'
	path := '/tmp/test_schema_type_bool.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('true', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_type_array() {
	schema := '{"type": "array"}'
	path := '/tmp/test_schema_type_arr.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('[1,2,3]', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_type_object() {
	schema := '{"type": "object"}'
	path := '/tmp/test_schema_type_obj.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('{}', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_type_null() {
	schema := '{"type": "null"}'
	path := '/tmp/test_schema_type_null.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('null', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

// ============================================================
// String constraints
// ============================================================

fn test_jsonschema_string_minlength() {
	schema := '{"type": "string", "minLength": 3}'
	path := '/tmp/test_schema_minlen.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema(r'\"ab\"', schema, path) or {
		assert err.msg().contains('fewer than 3 characters')
		return
	}
	panic('expected minLength error')
}

fn test_jsonschema_string_maxlength() {
	schema := '{"type": "string", "maxLength": 5}'
	path := '/tmp/test_schema_maxlen.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema(r'\"abcdef\"', schema, path) or {
		assert err.msg().contains('more than 5 characters')
		return
	}
	panic('expected maxLength error')
}

fn test_jsonschema_string_length_valid() {
	schema := '{"type": "string", "minLength": 2, "maxLength": 5}'
	path := '/tmp/test_schema_len_valid.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"abc\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_string_pattern() {
	schema := '{"type": "string", "pattern": "^[a-z]+$"}'
	path := '/tmp/test_schema_pattern.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"hello\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_string_pattern_invalid() {
	schema := '{"type": "string", "pattern": "^[a-z]+$"}'
	path := '/tmp/test_schema_pattern_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema(r'\"Hello123\"', schema, path) or {
		assert err.msg().contains('does not match pattern')
		return
	}
	panic('expected pattern error')
}

// ============================================================
// Number constraints
// ============================================================

fn test_jsonschema_number_minimum() {
	schema := '{"type": "number", "minimum": 10}'
	path := '/tmp/test_schema_min.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('5', schema, path) or {
		assert err.msg().contains('less than')
		return
	}
	panic('expected minimum error')
}

fn test_jsonschema_number_maximum() {
	schema := '{"type": "number", "maximum": 100}'
	path := '/tmp/test_schema_max.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('150', schema, path) or {
		assert err.msg().contains('greater than')
		return
	}
	panic('expected maximum error')
}

fn test_jsonschema_number_range_valid() {
	schema := '{"type": "number", "minimum": 0, "maximum": 100}'
	path := '/tmp/test_schema_range.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('50', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_number_multiple_of() {
	schema := '{"type": "number", "multipleOf": 3}'
	path := '/tmp/test_schema_mult.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('9', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_number_multiple_of_invalid() {
	schema := '{"type": "number", "multipleOf": 3}'
	path := '/tmp/test_schema_mult_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('10', schema, path) or {
		assert err.msg().contains('not a multiple of')
		return
	}
	panic('expected multipleOf error')
}

fn test_jsonschema_number_exclusive_minimum() {
	schema := '{"type": "number", "exclusiveMinimum": 10}'
	path := '/tmp/test_schema_emin.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('10', schema, path) or {
		assert err.msg().contains('not greater than')
		return
	}
	panic('expected exclusiveMinimum error')
}

fn test_jsonschema_number_exclusive_maximum() {
	schema := '{"type": "number", "exclusiveMaximum": 10}'
	path := '/tmp/test_schema_emax.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('10', schema, path) or {
		assert err.msg().contains('not less than')
		return
	}
	panic('expected exclusiveMaximum error')
}

// ============================================================
// Array constraints
// ============================================================

fn test_jsonschema_array_min_items() {
	schema := '{"type": "array", "minItems": 3}'
	path := '/tmp/test_schema_minarr.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('[1,2]', schema, path) or {
		assert err.msg().contains('fewer than 3 items')
		return
	}
	panic('expected minItems error')
}

fn test_jsonschema_array_max_items() {
	schema := '{"type": "array", "maxItems": 2}'
	path := '/tmp/test_schema_maxarr.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('[1,2,3]', schema, path) or {
		assert err.msg().contains('more than 2 items')
		return
	}
	panic('expected maxItems error')
}

fn test_jsonschema_array_items_schema() {
	schema := '{"type": "array", "items": {"type": "integer"}}'
	path := '/tmp/test_schema_items.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('[1,2,3]', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_array_items_schema_invalid() {
	schema := '{"type": "array", "items": {"type": "integer"}}'
	path := '/tmp/test_schema_items_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema(r'[1,\"hello\",3]', schema, path) or {
		assert err.msg().contains('not of type')
		return
	}
	panic('expected items type error')
}

fn test_jsonschema_array_unique_items() {
	schema := '{"type": "array", "uniqueItems": true}'
	path := '/tmp/test_schema_unique.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('[1,1,2]', schema, path) or {
		assert err.msg().contains('not unique')
		return
	}
	panic('expected uniqueItems error')
}

fn test_jsonschema_array_contains() {
	schema := '{"type": "array", "contains": {"type": "string"}}'
	path := '/tmp/test_schema_contains.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('[1,2,3]', schema, path) or {
		assert err.msg().contains('contains')
		return
	}
	panic('expected contains error')
}

// ============================================================
// Object constraints
// ============================================================

fn test_jsonschema_additional_properties_false() {
	schema := '{"type": "object", "properties": {"name": {"type": "string"}}, "additionalProperties": false}'
	path := '/tmp/test_schema_addl.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema_vrl('{"name": "Alice", "extra": "field"}', schema, path) or {
		assert err.msg().contains('Additional property')
		return
	}
	panic('expected additionalProperties error')
}

fn test_jsonschema_min_properties() {
	schema := '{"type": "object", "minProperties": 2}'
	path := '/tmp/test_schema_minprop.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema_vrl('{"a": 1}', schema, path) or {
		assert err.msg().contains('fewer than 2 properties')
		return
	}
	panic('expected minProperties error')
}

fn test_jsonschema_max_properties() {
	schema := '{"type": "object", "maxProperties": 1}'
	path := '/tmp/test_schema_maxprop.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema_vrl('{"a": 1, "b": 2}', schema, path) or {
		assert err.msg().contains('more than 1 properties')
		return
	}
	panic('expected maxProperties error')
}

// ============================================================
// Enum & Const validation
// ============================================================

fn test_jsonschema_enum_valid() {
	schema := '{"enum": [1, 2, 3]}'
	path := '/tmp/test_schema_enum.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('2', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_enum_invalid() {
	schema := '{"enum": [1, 2, 3]}'
	path := '/tmp/test_schema_enum_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('5', schema, path) or {
		assert err.msg().contains('not one of the allowed enum values')
		return
	}
	panic('expected enum error')
}

fn test_jsonschema_const_valid() {
	schema := '{"const": 42}'
	path := '/tmp/test_schema_const.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('42', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_const_invalid() {
	schema := '{"const": 42}'
	path := '/tmp/test_schema_const_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('99', schema, path) or {
		assert err.msg().contains('does not match const')
		return
	}
	panic('expected const error')
}

// ============================================================
// Format validation
// ============================================================

fn test_jsonschema_format_email_valid() {
	schema := '{"type": "string", "format": "email"}'
	path := '/tmp/test_schema_email.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"user@example.com\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_format_email_invalid() {
	schema := '{"type": "string", "format": "email"}'
	path := '/tmp/test_schema_email_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema(r'\"not-an-email\"', schema, path) or {
		assert err.msg().contains('not a')
		return
	}
	panic('expected email format error')
}

fn test_jsonschema_format_date_valid() {
	schema := '{"type": "string", "format": "date"}'
	path := '/tmp/test_schema_date.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"2024-01-15\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_format_ipv4_valid() {
	schema := '{"type": "string", "format": "ipv4"}'
	path := '/tmp/test_schema_ipv4.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"192.168.1.1\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_format_ipv4_invalid() {
	schema := '{"type": "string", "format": "ipv4"}'
	path := '/tmp/test_schema_ipv4_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema(r'\"999.999.999.999\"', schema, path) or {
		assert err.msg().contains('not a')
		return
	}
	panic('expected ipv4 format error')
}

fn test_jsonschema_format_uuid_valid() {
	schema := '{"type": "string", "format": "uuid"}'
	path := '/tmp/test_schema_uuid.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"550e8400-e29b-41d4-a716-446655440000\"', schema, path) or {
		panic('${err}')
	}
	assert result == VrlValue(true)
}

fn test_jsonschema_format_uuid_invalid() {
	schema := '{"type": "string", "format": "uuid"}'
	path := '/tmp/test_schema_uuid_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema(r'\"not-a-uuid\"', schema, path) or {
		assert err.msg().contains('not a')
		return
	}
	panic('expected uuid format error')
}

fn test_jsonschema_format_hostname_valid() {
	schema := '{"type": "string", "format": "hostname"}'
	path := '/tmp/test_schema_hostname.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"example.com\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_format_ipv6_valid() {
	schema := '{"type": "string", "format": "ipv6"}'
	path := '/tmp/test_schema_ipv6.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"::1\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_format_datetime_valid() {
	schema := '{"type": "string", "format": "date-time"}'
	path := '/tmp/test_schema_datetime.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"2024-01-15T10:30:00Z\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_format_time_valid() {
	schema := '{"type": "string", "format": "time"}'
	path := '/tmp/test_schema_time.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"10:30:00Z\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_format_uri_valid() {
	schema := '{"type": "string", "format": "uri"}'
	path := '/tmp/test_schema_uri.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"https://example.com\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_format_unknown_rejected() {
	schema := '{"type": "string", "format": "unknown_fmt"}'
	path := '/tmp/test_schema_fmt_unk.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema(r'\"hello\"', schema, path) or {
		assert err.msg().contains('Unknown format')
		return
	}
	panic('expected unknown format error')
}

fn test_jsonschema_format_unknown_ignored() {
	schema := '{"type": "string", "format": "unknown_fmt"}'
	path := '/tmp/test_schema_fmt_ign.json'
	os.write_file(path, schema) or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	json_val := r'\"hello\"'
	prog := 'validate_json_schema!("${json_val}", schema_definition: "${path}", ignore_unknown_formats: true)'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue(true)
}

// ============================================================
// Schema composition: allOf, anyOf, oneOf, not
// ============================================================

fn test_jsonschema_allof() {
	schema := '{"allOf": [{"type": "number"}, {"minimum": 10}]}'
	path := '/tmp/test_schema_allof.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('15', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_allof_fail() {
	schema := '{"allOf": [{"type": "number"}, {"minimum": 10}]}'
	path := '/tmp/test_schema_allof_f.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('5', schema, path) or {
		assert err.msg().contains('less than')
		return
	}
	panic('expected allOf error')
}

fn test_jsonschema_anyof() {
	schema := '{"anyOf": [{"type": "string"}, {"type": "number"}]}'
	path := '/tmp/test_schema_anyof.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'\"hello\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_anyof_fail() {
	schema := '{"anyOf": [{"type": "string"}, {"type": "number"}]}'
	path := '/tmp/test_schema_anyof_f.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('true', schema, path) or {
		assert err.msg().contains('anyOf')
		return
	}
	panic('expected anyOf error')
}

fn test_jsonschema_oneof() {
	schema := '{"oneOf": [{"type": "string"}, {"type": "number"}]}'
	path := '/tmp/test_schema_oneof.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('42', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_oneof_multiple_match() {
	schema := '{"oneOf": [{"type": "number"}, {"minimum": 0}]}'
	path := '/tmp/test_schema_oneof_mm.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('5', schema, path) or {
		assert err.msg().contains('more than one')
		return
	}
	panic('expected oneOf multiple match error')
}

fn test_jsonschema_not() {
	schema := '{"not": {"type": "string"}}'
	path := '/tmp/test_schema_not.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('42', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_not_fail() {
	schema := '{"not": {"type": "string"}}'
	path := '/tmp/test_schema_not_f.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema(r'\"hello\"', schema, path) or {
		assert err.msg().contains('should not match')
		return
	}
	panic('expected not error')
}

// ============================================================
// Nested object validation
// ============================================================

fn test_jsonschema_nested_object() {
	schema := '{"type": "object", "properties": {"address": {"type": "object", "required": ["city"], "properties": {"city": {"type": "string"}, "zip": {"type": "string"}}}}}'
	path := '/tmp/test_schema_nested.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema_vrl('{"address": {"city": "NYC", "zip": "10001"}}', schema,
		path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_nested_object_invalid() {
	schema := '{"type": "object", "properties": {"address": {"type": "object", "required": ["city"], "properties": {"city": {"type": "string"}}}}}'
	path := '/tmp/test_schema_nested_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema_vrl('{"address": {"zip": "10001"}}', schema, path) or {
		assert err.msg().contains('required property')
		return
	}
	panic('expected nested required property error')
}

// ============================================================
// $ref resolution
// ============================================================

fn test_jsonschema_ref() {
	schema := '{"type": "object", "properties": {"name": {"\$ref": "#/\$defs/nameType"}}, "\$defs": {"nameType": {"type": "string", "minLength": 1}}}'
	path := '/tmp/test_schema_ref.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema_vrl('{"name": "Alice"}', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_ref_fail() {
	schema := '{"type": "object", "properties": {"name": {"\$ref": "#/\$defs/nameType"}}, "\$defs": {"nameType": {"type": "string", "minLength": 3}}}'
	path := '/tmp/test_schema_ref_f.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema_vrl('{"name": "Al"}', schema, path) or {
		assert err.msg().contains('fewer than 3 characters')
		return
	}
	panic('expected ref validation error')
}

// ============================================================
// Boolean schema
// ============================================================

fn test_jsonschema_boolean_schema_true() {
	schema := 'true'
	path := '/tmp/test_schema_boolT.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema('42', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_boolean_schema_false() {
	schema := 'false'
	path := '/tmp/test_schema_boolF.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('42', schema, path) or {
		assert err.msg().contains('Schema is false')
		return
	}
	panic('expected boolean false schema error')
}

// ============================================================
// Type as array (union types)
// ============================================================

fn test_jsonschema_type_union() {
	schema := '{"type": ["string", "number"]}'
	path := '/tmp/test_schema_union.json'
	defer {
		os.rm(path) or {}
	}
	r1 := validate_schema(r'\"hello\"', schema, path) or { panic('${err}') }
	assert r1 == VrlValue(true)
	r2 := validate_schema('42', schema, path) or { panic('${err}') }
	assert r2 == VrlValue(true)
}

fn test_jsonschema_type_union_fail() {
	schema := '{"type": ["string", "number"]}'
	path := '/tmp/test_schema_union_f.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('true', schema, path) or {
		assert err.msg().contains('not of type')
		return
	}
	panic('expected union type error')
}

// ============================================================
// Edge cases and error paths
// ============================================================

fn test_jsonschema_empty_json() {
	schema := '{"type": "string"}'
	path := '/tmp/test_schema_empty.json'
	os.write_file(path, schema) or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	prog := 'validate_json_schema!("", schema_definition: "${path}")'
	execute(prog, map[string]VrlValue{}) or {
		assert err.msg().contains('Empty JSON')
		return
	}
	panic('expected empty JSON error')
}

fn test_jsonschema_invalid_json() {
	schema := '{"type": "string"}'
	path := '/tmp/test_schema_invjson.json'
	os.write_file(path, schema) or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	prog := 'validate_json_schema!("{bad json", schema_definition: "${path}")'
	execute(prog, map[string]VrlValue{}) or {
		assert err.msg().contains('Invalid JSON')
		return
	}
	panic('expected invalid JSON error')
}

fn test_jsonschema_missing_schema_file() {
	prog := 'validate_json_schema!("42", schema_definition: "/tmp/nonexistent_schema_1234567.json")'
	execute(prog, map[string]VrlValue{}) or {
		assert err.msg().contains('Failed to open schema')
		return
	}
	panic('expected missing schema file error')
}

fn test_jsonschema_if_then_else() {
	schema := '{"if": {"type": "number", "minimum": 10}, "then": {"multipleOf": 5}, "else": {"const": 0}}'
	path := '/tmp/test_schema_ite.json'
	defer {
		os.rm(path) or {}
	}
	// if true (>=10), then must be multipleOf 5
	result := validate_schema('15', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_if_then_else_fail() {
	schema := '{"if": {"type": "number", "minimum": 10}, "then": {"multipleOf": 5}, "else": {"const": 0}}'
	path := '/tmp/test_schema_ite_f.json'
	defer {
		os.rm(path) or {}
	}
	// if true (>=10) but not multipleOf 5
	validate_schema('12', schema, path) or {
		assert err.msg().contains('not a multiple of')
		return
	}
	panic('expected if/then error')
}

fn test_jsonschema_property_names() {
	schema := '{"type": "object", "propertyNames": {"pattern": "^[a-z]+$"}}'
	path := '/tmp/test_schema_propnames.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema_vrl('{"abc": 1, "def": 2}', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_pattern_properties() {
	schema := '{"type": "object", "patternProperties": {"^x_": {"type": "string"}}}'
	path := '/tmp/test_schema_patprop.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema_vrl('{"x_name": "Alice"}', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_pattern_properties_invalid() {
	schema := '{"type": "object", "patternProperties": {"^x_": {"type": "string"}}}'
	path := '/tmp/test_schema_patprop_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema_vrl('{"x_count": 42}', schema, path) or {
		assert err.msg().contains('not of type')
		return
	}
	panic('expected patternProperties type error')
}

fn test_jsonschema_prefix_items() {
	schema := '{"type": "array", "prefixItems": [{"type": "string"}, {"type": "number"}]}'
	path := '/tmp/test_schema_prefix.json'
	defer {
		os.rm(path) or {}
	}
	result := validate_schema(r'[\"hello\", 42]', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_jsonschema_prefix_items_invalid() {
	schema := '{"type": "array", "prefixItems": [{"type": "string"}, {"type": "number"}]}'
	path := '/tmp/test_schema_prefix_inv.json'
	defer {
		os.rm(path) or {}
	}
	validate_schema('[42, 42]', schema, path) or {
		assert err.msg().contains('not of type')
		return
	}
	panic('expected prefixItems type error')
}
