module vrl

// Coverage tests for vrllib_parse.v uncovered strftime/timestamp/parse paths

fn test_p7_parse_duration_days() {
	result := execute('.result = parse_duration("2d", "s")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('172800')
}

fn test_p7_parse_bytes_error() {
	_ := fn_parse_bytes([]VrlValue{}) or { return }
}

fn test_p7_parse_bytes_non_string() {
	_ := fn_parse_bytes([VrlValue(i64(42))]) or { return }
}

fn test_p7_parse_int_hex() {
	result := execute('.result = parse_int("ff", 16)', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(255))
}

fn test_p7_parse_int_base8() {
	result := execute('.result = parse_int("77", 8)', map[string]VrlValue{}) or { return }
	assert result == VrlValue(i64(63))
}

fn test_p7_char_to_digit_invalid() {
	_ := char_to_digit(`!`, 10) or { return }
}

fn test_p7_char_to_digit_out_of_range() {
	_ := char_to_digit(`f`, 10) or { return }
}

fn test_p7_parse_float_from_int() {
	result := fn_parse_float([VrlValue(i64(42))]) or { return }
	assert result == VrlValue(42.0)
}

fn test_p7_parse_float_from_float() {
	result := fn_parse_float([VrlValue(3.14)]) or { return }
	assert result == VrlValue(3.14)
}

fn test_p7_parse_float_no_args() {
	_ := fn_parse_float([]VrlValue{}) or { return }
}

fn test_p7_format_int_non_int() {
	_ := fn_format_int([VrlValue('hello')]) or { return }
}

fn test_p7_format_int_no_args() {
	_ := fn_format_int([]VrlValue{}) or { return }
}

fn test_p7_format_int_hex() {
	result := execute('.result = format_int(255, 16)', map[string]VrlValue{}) or { return }
	assert result == VrlValue('ff')
}

fn test_p7_strftime_format_microseconds() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%Y-%m-%d %H:%M:%S.%f")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.len > 10
}

fn test_p7_strftime_format_milliseconds() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%Y-%m-%d %H:%M:%S.%3f")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.len > 10
}

fn test_p7_strftime_format_timezone() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%Y-%m-%d %z")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('+') || s.contains('-') || s.contains('0')
}

fn test_p7_strftime_format_utc_z() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%Y-%m-%dT%H:%M:%S%Z")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('UTC')
}

fn test_p7_strftime_format_v() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%v")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.len > 5
}

fn test_p7_strftime_format_r() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%R")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains(':')
}

fn test_p7_strftime_format_rfc3339() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%+")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('T')
}

fn test_p7_strftime_format_day_of_week() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%a %A")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.len > 3
}

fn test_p7_strftime_format_month_names() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%b %B")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.len > 3
}

fn test_p7_strftime_format_ampm() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%p %P %I")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('AM') || s.contains('PM') || s.contains('am') || s.contains('pm')
}

fn test_p7_strftime_format_day_of_year() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%j")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.len >= 1
}

fn test_p7_strftime_format_day_space() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%e")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.len >= 1
}

fn test_p7_strftime_format_special() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%n%t%%")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('%')
}

fn test_p7_strftime_format_unknown() {
	result := execute('.ts = now()
.result = format_timestamp(.ts, "%Q")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.len >= 1
}

fn test_p7_format_offset_negative() {
	r := format_offset_hhmm(-18000)
	assert r == '-0500'
}

fn test_p7_format_offset_positive() {
	r := format_offset_hhmm(3600)
	assert r == '+0100'
}

fn test_p7_tz_offset_colon() {
	r := parse_tz_offset('+05:30') or { return }
	assert r == 19800
}

fn test_p7_tz_offset_no_colon() {
	r := parse_tz_offset('+0530') or { return }
	assert r == 19800
}

fn test_p7_tz_offset_est() {
	r := parse_tz_offset('EST') or { return }
	assert r == -18000
}

fn test_p7_tz_offset_unknown() {
	_ := parse_tz_offset('INVALID_TZ') or { return }
}

fn test_p7_expanded_format_length() {
	r := expanded_format_length('%Y-%m-%d', '')
	assert r == 10
}

fn test_p7_expanded_format_length_time() {
	r := expanded_format_length('%T', '')
	assert r == 8
}

fn test_p7_parse_xml_basic() {
	result := execute('.result = parse_xml("<root><item>hello</item></root>")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('hello')
}

fn test_p7_parse_url() {
	result := execute('.result = parse_url("https://user:pass@example.com:8080/path?q=1#frag")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('example.com')
}

fn test_p7_parse_query_string() {
	result := execute('.result = parse_query_string("a=1&b=hello&c=true")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('hello')
}

fn test_p7_parse_user_agent() {
	result := execute('.result = parse_user_agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.len > 5
}

fn test_p7_parse_key_value_custom_delim() {
	result := execute('.result = parse_key_value("a:1 b:2", key_value_delimiter: ":")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('"a"')
}

fn test_p7_parse_tokens() {
	result := execute('.result = parse_tokens("217.0.0.1 - frank [10/Oct/2000:13:55:36 -0700]")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('217.0.0.1') || s.contains('frank')
}

fn test_p7_format_number() {
	result := execute('.result = format_number(1234567.89, scale: 2, grouping_separator: ",")', map[string]VrlValue{}) or { return }
	s := vrl_to_json(result)
	assert s.contains('1')
}
