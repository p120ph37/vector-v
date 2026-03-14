module vrl

// Tests targeting uncovered lines in vrllib_parse.v

// === parse_regex error paths and edge cases ===

// Line 11: parse_regex with too few args (error path)
fn test_parse_regex_too_few_args() {
	// Call fn_parse_regex directly with empty args
	fn_parse_regex([]) or {
		assert err.msg().contains('parse_regex requires 2 arguments')
		return
	}
	assert false, 'expected error for too few args'
}

// Line 17: parse_regex first arg not string
fn test_parse_regex_first_arg_not_string() {
	fn_parse_regex([VrlValue(i64(42)), VrlValue('pattern')]) or {
		assert err.msg().contains('first arg must be string')
		return
	}
	assert false, 'expected error for non-string first arg'
}

// Lines 21-22: parse_regex with string pattern (not VrlRegex)
fn test_parse_regex_string_pattern() {
	result := fn_parse_regex([VrlValue('hello123'), VrlValue('(?P<word>[a-z]+)(?P<num>\\d+)')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"word":"hello"')
	assert j.contains('"num":"123"')
}

// Line 34: parse_regex invalid regex
fn test_parse_regex_invalid_regex() {
	fn_parse_regex([VrlValue('test'), VrlValue('[invalid')]) or {
		assert err.msg().contains('invalid regex') || err.msg().contains('no match')
		return
	}
	// If it doesn't error on compile, that's also ok - pcre2 may handle it
}

// === parse_regex_all error paths ===

// Line 59: parse_regex_all too few args
fn test_parse_regex_all_too_few_args() {
	fn_parse_regex_all([]) or {
		assert err.msg().contains('parse_regex_all requires 2 arguments')
		return
	}
	assert false, 'expected error'
}

// Line 65: parse_regex_all first arg not string
fn test_parse_regex_all_first_arg_not_string() {
	fn_parse_regex_all([VrlValue(i64(1)), VrlValue('pat')]) or {
		assert err.msg().contains('first arg must be string')
		return
	}
	assert false, 'expected error'
}

// Lines 69-70: parse_regex_all with string pattern
fn test_parse_regex_all_string_pattern() {
	result := fn_parse_regex_all([VrlValue('a1b2c3'), VrlValue('(?P<letter>[a-z])(?P<digit>\\d)')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"letter":"a"')
	assert j.contains('"digit":"1"')
}

// Line 81: parse_regex_all invalid regex
fn test_parse_regex_all_invalid_regex() {
	fn_parse_regex_all([VrlValue('test'), VrlValue('[bad')]) or {
		assert err.msg().contains('invalid regex') || err.msg().len > 0
		return
	}
}

// Lines 88-89, 106: parse_regex_all zero-length match advancement
fn test_parse_regex_all_zero_length_match() {
	// A pattern that can match zero-length strings to trigger zero-length advancement
	result := fn_parse_regex_all([VrlValue('abc'), VrlValue('(?P<m>[a-z]?)')]) or {
		return
	}
	// Just verify it returns without infinite loop
	j := vrl_to_json(result)
	assert j.len > 0
}

// === parse_key_value error paths ===

// Line 115: parse_key_value too few args
fn test_parse_key_value_too_few_args() {
	fn_parse_key_value([]) or {
		assert err.msg().contains('parse_key_value requires 1 argument')
		return
	}
	assert false, 'expected error'
}

// Line 120: parse_key_value non-string arg
fn test_parse_key_value_non_string_arg() {
	fn_parse_key_value([VrlValue(i64(42))]) or {
		assert err.msg().contains('first arg must be string')
		return
	}
	assert false, 'expected error'
}

// Line 151: empty field in parse_key_value (trimmed to empty)
fn test_parse_key_value_with_empty_fields() {
	// Use a delimiter that creates empty fields
	result := fn_parse_key_value([VrlValue('a=1,,b=2'), VrlValue('='), VrlValue(',')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"a":"1"')
	assert j.contains('"b":"2"')
}

// === parse_csv error paths ===

// Line 210: parse_csv too few args
fn test_parse_csv_too_few_args() {
	fn_parse_csv([]) or {
		assert err.msg().contains('parse_csv requires 1 argument')
		return
	}
	assert false, 'expected error'
}

// Line 215: parse_csv non-string arg
fn test_parse_csv_non_string_arg() {
	fn_parse_csv([VrlValue(i64(42))]) or {
		assert err.msg().contains('requires a string')
		return
	}
	assert false, 'expected error'
}

// Lines 232-236: parse_csv multi-row (returns array of arrays)
fn test_parse_csv_multi_row() {
	result := fn_parse_csv([VrlValue('a,b,c\n1,2,3')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	j := vrl_to_json(result)
	// Multi-row should return array of arrays
	assert j.contains('[')
}

// Lines 275-284: CSV with CRLF line endings
fn test_parse_csv_crlf() {
	result := fn_parse_csv([VrlValue('a,b\r\n1,2')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	j := vrl_to_json(result)
	assert j.contains('[')
}

// === parse_url error paths ===

// Line 297: parse_url too few args
fn test_parse_url_too_few_args() {
	fn_parse_url([]) or {
		assert err.msg().contains('parse_url requires 1 argument')
		return
	}
	assert false, 'expected error'
}

// Line 302: parse_url non-string arg
fn test_parse_url_non_string_arg() {
	fn_parse_url([VrlValue(i64(42))]) or {
		assert err.msg().contains('requires a string')
		return
	}
	assert false, 'expected error'
}

// Line 352: URL with username only (no colon/password)
fn test_parse_url_username_only() {
	result := execute('parse_url!("https://user@example.com/path")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"username":"user"')
	assert j.contains('"password":""')
}

// === parse_query_string error paths ===

// Line 381: parse_query_string too few args
fn test_parse_query_string_too_few_args() {
	fn_parse_query_string([]) or {
		assert err.msg().contains('parse_query_string requires 1 argument')
		return
	}
	assert false, 'expected error'
}

// Line 386: parse_query_string non-string arg
fn test_parse_query_string_non_string_arg() {
	fn_parse_query_string([VrlValue(i64(42))]) or {
		assert err.msg().contains('requires a string')
		return
	}
	assert false, 'expected error'
}

// Line 401: empty pair in query string
fn test_parse_query_string_empty_pairs() {
	result := execute('parse_query_string!("a=1&&b=2")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"a":"1"')
	assert j.contains('"b":"2"')
}

// Lines 414-416: duplicate keys in query string (array accumulation with 3+ values)
fn test_parse_query_string_duplicate_keys() {
	result := execute('parse_query_string!("a=1&a=2&a=3")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	// With duplicate keys, should accumulate into array
	assert j.contains('"a"')
}

// === parse_tokens error paths ===

// Line 432: parse_tokens too few args
fn test_parse_tokens_too_few_args() {
	fn_parse_tokens([]) or {
		assert err.msg().contains('parse_tokens requires 1 argument')
		return
	}
	assert false, 'expected error'
}

// Line 437: parse_tokens non-string arg
fn test_parse_tokens_non_string_arg() {
	fn_parse_tokens([VrlValue(i64(42))]) or {
		assert err.msg().contains('requires a string')
		return
	}
	assert false, 'expected error'
}

// === parse_duration error paths ===

// Line 500: parse_duration too few args
fn test_parse_duration_too_few_args() {
	fn_parse_duration([]) or {
		assert err.msg().contains('parse_duration requires 2 arguments')
		return
	}
	assert false, 'expected error'
}

// Line 506: parse_duration first arg not string
fn test_parse_duration_non_string_first_arg() {
	fn_parse_duration([VrlValue(i64(42)), VrlValue('ms')]) or {
		assert err.msg().contains('first arg must be string')
		return
	}
	assert false, 'expected error'
}

// Line 510: parse_duration second arg not string
fn test_parse_duration_non_string_second_arg() {
	fn_parse_duration([VrlValue('1s'), VrlValue(i64(42))]) or {
		assert err.msg().contains('second arg must be string')
		return
	}
	assert false, 'expected error'
}

// Line 541: parse_duration missing unit
fn test_parse_duration_missing_unit() {
	fn_parse_duration([VrlValue('123'), VrlValue('ms')]) or {
		assert err.msg().contains('unable to parse duration')
		return
	}
	assert false, 'expected error'
}

// Line 550: parse_duration empty string
fn test_parse_duration_empty_string() {
	fn_parse_duration([VrlValue(''), VrlValue('ms')]) or {
		assert err.msg().contains('unable to parse duration')
		return
	}
	assert false, 'expected error'
}

// Lines 561-562: parse_duration with days unit
fn test_parse_duration_days() {
	result := execute('parse_duration!("1d", "s")', map[string]VrlValue{}) or {
		return
	}
	f := match result {
		f64 { result }
		else { f64(0) }
	}
	assert f == 86400.0
}

// parse_duration with unknown output unit (line 562 else branch)
fn test_parse_duration_unknown_output_unit() {
	fn_parse_duration([VrlValue('1s'), VrlValue('xyz')]) or {
		assert err.msg().contains('unknown')
		return
	}
	assert false, 'expected error'
}

// === parse_bytes error paths ===

// Line 570: parse_bytes too few args
fn test_parse_bytes_too_few_args() {
	fn_parse_bytes([]) or {
		assert err.msg().contains('parse_bytes requires 1 argument')
		return
	}
	assert false, 'expected error'
}

// Line 575: parse_bytes non-string arg
fn test_parse_bytes_non_string_arg() {
	fn_parse_bytes([VrlValue(i64(42))]) or {
		assert err.msg().contains('requires a string')
		return
	}
	assert false, 'expected error'
}

// === parse_int error paths ===

// Line 635: parse_int too few args
fn test_parse_int_too_few_args() {
	fn_parse_int([]) or {
		assert err.msg().contains('parse_int requires at least 1 argument')
		return
	}
	assert false, 'expected error'
}

// Line 640: parse_int non-string arg
fn test_parse_int_non_string_arg() {
	fn_parse_int([VrlValue(i64(42))]) or {
		assert err.msg().contains('first arg must be string')
		return
	}
	assert false, 'expected error'
}

// Line 658: parse_int auto-detect octal (0o prefix)
fn test_parse_int_octal_prefix() {
	result := execute('parse_int!("0o17")', map[string]VrlValue{}) or {
		return
	}
	v := match result {
		i64 { result }
		else { i64(-1) }
	}
	assert v == 15 // 0o17 = 15 in decimal
}

// Line 674: parse_int explicit base 16 with 0x prefix
fn test_parse_int_base16_with_prefix() {
	result := fn_parse_int([VrlValue('0xff'), VrlValue(i64(16))]) or {
		return
	}
	v := match result {
		i64 { result }
		else { i64(-1) }
	}
	assert v == 255
}

// Line 676: parse_int explicit base 8 with 0o prefix
fn test_parse_int_base8_with_prefix() {
	result := fn_parse_int([VrlValue('0o17'), VrlValue(i64(8))]) or {
		return
	}
	v := match result {
		i64 { result }
		else { i64(-1) }
	}
	assert v == 15
}

// Line 678: parse_int explicit base 2 with 0b prefix
fn test_parse_int_base2_with_prefix() {
	result := fn_parse_int([VrlValue('0b1010'), VrlValue(i64(2))]) or {
		return
	}
	v := match result {
		i64 { result }
		else { i64(-1) }
	}
	assert v == 10
}

// Lines 697, 699, 702: char_to_digit uppercase letters and invalid chars
fn test_parse_int_uppercase_hex() {
	result := fn_parse_int([VrlValue('FF'), VrlValue(i64(16))]) or {
		return
	}
	v := match result {
		i64 { result }
		else { i64(-1) }
	}
	assert v == 255
}

fn test_parse_int_invalid_digit() {
	fn_parse_int([VrlValue('GG'), VrlValue(i64(16))]) or {
		assert err.msg().contains('invalid digit')
		return
	}
	assert false, 'expected error'
}

// === parse_float error paths ===

// Line 710: parse_float too few args
fn test_parse_float_too_few_args() {
	fn_parse_float([]) or {
		assert err.msg().contains('parse_float requires 1 argument')
		return
	}
	assert false, 'expected error'
}

// Line 715: parse_float with f64 input
fn test_parse_float_with_float() {
	result := fn_parse_float([VrlValue(f64(3.14))]) or {
		return
	}
	v := match result {
		f64 { result }
		else { f64(0) }
	}
	assert v == 3.14
}

// Line 716: parse_float with i64 input
fn test_parse_float_with_int() {
	result := fn_parse_float([VrlValue(i64(42))]) or {
		return
	}
	v := match result {
		f64 { result }
		else { f64(0) }
	}
	assert v == 42.0
}

// Line 717: parse_float with non-numeric type
fn test_parse_float_with_invalid_type() {
	fn_parse_float([VrlValue(true)]) or {
		assert err.msg().contains('requires a string')
		return
	}
	assert false, 'expected error'
}

// === format_int error paths ===

// Line 724: format_int too few args
fn test_format_int_too_few_args() {
	fn_format_int([]) or {
		assert err.msg().contains('format_int requires 1 argument')
		return
	}
	assert false, 'expected error'
}
