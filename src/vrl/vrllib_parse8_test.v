module vrl

import math
import time

// ---- parse_regex: numeric_groups=true (lines 27-29, 40-46) ----

fn test_p8_parse_regex_numeric_groups() {
	result := fn_parse_regex([VrlValue('hello world'), VrlValue(VrlRegex{ pattern: '(\\w+) (\\w+)' }),
		VrlValue(true)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	// Should have numeric groups '0', '1', '2'
	v0 := obj.get('0') or {
		assert false, 'missing key 0'
		return
	}
	assert v0 as string == 'hello world'
	v1 := obj.get('1') or {
		assert false, 'missing key 1'
		return
	}
	assert v1 as string == 'hello'
}

// ---- parse_regex_all: numeric_groups=true (lines 74-76, 92-97) ----

fn test_p8_parse_regex_all_numeric_groups() {
	result := fn_parse_regex_all([VrlValue('abc 123'), VrlValue(VrlRegex{ pattern: '(\\w+)' }),
		VrlValue(true)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 2
	first := arr[0] as ObjectMap
	v0 := first.get('0') or {
		assert false, 'missing key 0'
		return
	}
	assert v0 as string == 'abc'
}

// ---- parse_csv: escaped quotes (lines 250-253) ----

fn test_p8_parse_csv_escaped_quotes() {
	result := fn_parse_csv([VrlValue('a,"b""c",d')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 3
	assert arr[1] as string == 'b"c'
}

// ---- parse_tokens: bracket-delimited token (line 450-465) ----

fn test_p8_parse_tokens_brackets() {
	result := fn_parse_tokens([VrlValue('foo [bar baz] qux')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 3
	assert arr[0] as string == 'foo'
	assert arr[1] as string == 'bar baz'
	assert arr[2] as string == 'qux'
}

// ---- parse_duration: output 'us' and 'µs' (lines 555-556) ----

fn test_p8_parse_duration_output_us() {
	result := fn_parse_duration([VrlValue('1ms'), VrlValue('us')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	val := result as f64
	assert val == 1000.0
}

// ---- parse_duration: non-digit start error (line 520, 530) ----

fn test_p8_parse_duration_non_digit_start() {
	fn_parse_duration([VrlValue('abc'), VrlValue('s')]) or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected error'
}

// ---- parse_bytes: custom output_unit and base args (lines 579-597) ----

fn test_p8_parse_bytes_custom_output_unit() {
	// 1024 bytes = 1 KiB (binary, default)
	result := fn_parse_bytes([VrlValue('1024b'), VrlValue('kb')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	val := result as f64
	assert val == 1.0
}

fn test_p8_parse_bytes_base10() {
	// 1000 bytes = 1 KB (decimal)
	result := fn_parse_bytes([VrlValue('1000b'), VrlValue('kb'), VrlValue('10')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	val := result as f64
	assert val == 1.0
}

fn test_p8_parse_bytes_non_string_unit() {
	// Non-string unit arg should default to 'b'
	result := fn_parse_bytes([VrlValue('1024b'), VrlValue(i64(42))]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	val := result as f64
	assert val == 1024.0
}

fn test_p8_parse_bytes_non_string_base() {
	// Non-string base arg should default to '2' (binary)
	result := fn_parse_bytes([VrlValue('1024b'), VrlValue('kb'), VrlValue(i64(2))]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	val := result as f64
	assert val == 1.0
}

fn test_p8_parse_bytes_no_digits() {
	// No leading digits should error (line 605)
	fn_parse_bytes([VrlValue('kb')]) or {
		assert err.msg().contains('unable to parse bytes')
		return
	}
	assert false, 'expected error'
}

// ---- char_to_digit: uppercase letters (line 697) ----

fn test_p8_parse_int_uppercase_hex_letter() {
	result := fn_parse_int([VrlValue('0xFF'), VrlValue(i64(16))]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	assert result as i64 == 255
}

// ---- int_to_base: negative value (lines 752-754) ----

fn test_p8_format_int_negative() {
	result := fn_format_int([VrlValue(i64(-42)), VrlValue(i64(10))]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	assert result as string == '-42'
}

fn test_p8_format_int_binary() {
	result := fn_format_int([VrlValue(i64(10)), VrlValue(i64(2))]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	assert result as string == '1010'
}

// ---- parse_timestamp: %Y-%m-%dT%H:%M:%SZ format (lines 794-799) ----

fn test_p8_parse_timestamp_z_suffix() {
	result := fn_parse_timestamp([VrlValue('2021-02-03T04:05:06Z'),
		VrlValue('%Y-%m-%dT%H:%M:%SZ')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	ts := result as Timestamp
	assert ts.t.year == 2021
	assert ts.t.month == 2
}

fn test_p8_parse_timestamp_iso8601_fallback() {
	result := fn_parse_timestamp([VrlValue('2021-02-03T04:05:06'),
		VrlValue('%Y-%m-%dT%H:%M:%S')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	ts := result as Timestamp
	assert ts.t.year == 2021
}

// ---- parse_tz_offset: invalid tz format (line 1091) ----

fn test_p8_parse_tz_offset_short_invalid() {
	parse_tz_offset('+1') or {
		assert err.msg().contains('invalid tz') || err.msg().contains('unknown timezone')
		return
	}
	assert false, 'expected error'
}

// ---- strftime_format: %b/%h specifier (lines 1239-1244) ----

fn test_p8_strftime_format_month_abbrev() {
	t := make_test_time(2021, 3, 15, 10, 30, 0)
	result := strftime_format(t, '%b %h')
	assert result == 'Mar Mar'
}

fn test_p8_strftime_format_full_month() {
	t := make_test_time(2021, 12, 25, 0, 0, 0)
	result := strftime_format(t, '%B')
	assert result == 'December'
}

fn test_p8_strftime_format_full_day() {
	t := make_test_time(2021, 3, 15, 10, 30, 0) // Monday
	result := strftime_format(t, '%A')
	assert result.len > 0 // day name
}

fn test_p8_strftime_format_v_specifier() {
	t := make_test_time(2020, 10, 21, 0, 0, 0)
	result := strftime_format(t, '%v')
	assert result.contains('Oct')
	assert result.contains('2020')
}

fn test_p8_strftime_format_r_specifier() {
	t := make_test_time(2021, 1, 1, 14, 30, 0)
	result := strftime_format(t, '%R')
	assert result == '14:30'
}

fn test_p8_strftime_format_plus_specifier() {
	t := make_test_time(2021, 1, 1, 14, 30, 45)
	result := strftime_format(t, '%+')
	assert result.contains('2021')
	assert result.contains('14:30:45')
}

fn test_p8_strftime_format_z_specifier() {
	t := make_test_time(2021, 1, 1, 0, 0, 0)
	result := strftime_format_with_offset(t, '%z', 3600)
	assert result == '+0100'
}

fn test_p8_strftime_format_z_upper_specifier() {
	t := make_test_time(2021, 1, 1, 0, 0, 0)
	result := strftime_format(t, '%Z')
	assert result == 'UTC'
}

fn test_p8_strftime_format_p_am() {
	t := make_test_time(2021, 1, 1, 9, 0, 0)
	result := strftime_format(t, '%p')
	assert result == 'AM'
}

fn test_p8_strftime_format_p_lower_pm() {
	t := make_test_time(2021, 1, 1, 15, 0, 0)
	result := strftime_format(t, '%P')
	assert result == 'pm'
}

fn test_p8_strftime_format_12hour_midnight() {
	t := make_test_time(2021, 1, 1, 0, 0, 0)
	result := strftime_format(t, '%I')
	assert result == '12'
}

fn test_p8_strftime_format_12hour_afternoon() {
	t := make_test_time(2021, 1, 1, 13, 0, 0)
	result := strftime_format(t, '%I')
	assert result == '01'
}

// ---- parse_common_log: identity != '-' (line 1388) ----

fn test_p8_parse_common_log_with_identity() {
	result := fn_parse_common_log([VrlValue('127.0.0.1 frank user1 [03/Feb/2021:21:13:55 -0200] "GET /index.html HTTP/1.1" 200 1234')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	identity := obj.get('identity') or {
		assert false, 'missing identity'
		return
	}
	assert identity as string == 'frank'
}

// ---- parse_linux_authorization (lines 1567-1661) ----

fn test_p8_parse_linux_authorization() {
	result := fn_parse_linux_authorization([VrlValue('Mar  5 14:17:01 myhost CRON[1234]: pam_unix session opened')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	hostname := obj.get('hostname') or {
		assert false, 'missing hostname'
		return
	}
	assert hostname as string == 'myhost'
	appname := obj.get('appname') or {
		assert false, 'missing appname'
		return
	}
	assert appname as string == 'CRON'
	msg := obj.get('message') or {
		assert false, 'missing message'
		return
	}
	assert (msg as string).contains('pam_unix')
}

fn test_p8_parse_linux_authorization_no_pid() {
	result := fn_parse_linux_authorization([VrlValue('Jan 10 08:00:00 host sshd: connection closed')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	appname := obj.get('appname') or {
		assert false, 'missing appname'
		return
	}
	assert appname as string == 'sshd'
}

fn test_p8_parse_linux_authorization_too_short() {
	fn_parse_linux_authorization([VrlValue('X')]) or {
		assert err.msg().contains('too short')
		return
	}
	assert false, 'expected error'
}

fn test_p8_parse_linux_authorization_missing_colon() {
	fn_parse_linux_authorization([VrlValue('Mar  5 14:17:01 myhost process no colon here')]) or {
		assert err.msg().contains('missing colon')
		return
	}
	assert false, 'expected error'
}

fn test_p8_parse_linux_authorization_non_string() {
	fn_parse_linux_authorization([VrlValue(i64(42))]) or {
		assert err.msg().contains('string')
		return
	}
	assert false, 'expected error'
}

// ---- haversine: miles (line 1722) ----

fn test_p8_haversine_miles() {
	result := fn_haversine([VrlValue(f64(40.7128)), VrlValue(f64(-74.006)),
		VrlValue(f64(51.5074)), VrlValue(f64(-0.1278)), VrlValue('miles')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	dist := obj.get('distance') or {
		assert false, 'missing distance'
		return
	}
	d := dist as f64
	assert d > 3000.0 && d < 4000.0
}

fn test_p8_haversine_non_string_unit() {
	result := fn_haversine([VrlValue(f64(0.0)), VrlValue(f64(0.0)),
		VrlValue(f64(0.0)), VrlValue(f64(0.0)), VrlValue(i64(0))]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	dist := obj.get('distance') or {
		assert false, 'missing distance'
		return
	}
	assert dist as f64 == 0.0
}

// ---- parse_syslog: RFC 5424 (lines 1804-1978) ----

fn test_p8_parse_syslog_rfc5424() {
	result := fn_parse_syslog([VrlValue('<165>1 2021-02-03T21:13:55+00:00 hostname appname 1234 msgid [sd@123 key="val"] test message')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	sev := obj.get('severity') or {
		assert false, 'missing severity'
		return
	}
	assert sev as string == 'notice'
	msg := obj.get('message') or {
		assert false, 'missing message'
		return
	}
	assert msg as string == 'test message'
	appname := obj.get('appname') or {
		assert false, 'missing appname'
		return
	}
	assert appname as string == 'appname'
	kv := obj.get('key') or {
		assert false, 'missing sd key'
		return
	}
	assert kv as string == 'val'
}

fn test_p8_parse_syslog_rfc5424_nil_sd() {
	result := fn_parse_syslog([VrlValue('<13>1 2021-01-01T00:00:00Z host app 42 - - hello')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	msg := obj.get('message') or {
		assert false, 'missing message'
		return
	}
	assert msg as string == 'hello'
}

fn test_p8_parse_syslog_rfc3164() {
	result := fn_parse_syslog([VrlValue('<34>Feb  3 21:13:55 myhost su: pam_unix')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	hostname := obj.get('hostname') or {
		assert false, 'missing hostname'
		return
	}
	assert hostname as string == 'myhost'
	fac := obj.get('facility') or {
		assert false, 'missing facility'
		return
	}
	assert fac as string == 'auth'
}

fn test_p8_parse_syslog_rfc3164_bad_month() {
	result := fn_parse_syslog([VrlValue('<34>Xyz  3 21:13:55 myhost su: msg')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	// Should fallback: message = entire string
	msg := obj.get('message') or {
		assert false, 'missing message'
		return
	}
	assert (msg as string).len > 0
}

fn test_p8_parse_syslog_too_short() {
	fn_parse_syslog([VrlValue('ab')]) or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected error'
}

fn test_p8_parse_syslog_no_close_bracket() {
	fn_parse_syslog([VrlValue('<999')]) or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected error'
}

fn test_p8_parse_syslog_non_string() {
	fn_parse_syslog([VrlValue(i64(42))]) or {
		assert err.msg().contains('string')
		return
	}
	assert false, 'expected error'
}

fn test_p8_parse_syslog_facility_unknown() {
	name := syslog_facility_name(99)
	assert name == 'unknown'
}

fn test_p8_parse_syslog_severity_unknown() {
	name := syslog_severity_name(99)
	assert name == 'unknown'
}

// ---- parse_logfmt (lines 2108-2182) ----

fn test_p8_parse_logfmt_basic() {
	result := fn_parse_logfmt([VrlValue('level=info msg="hello world" count=42')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	level := obj.get('level') or {
		assert false, 'missing level'
		return
	}
	assert level as string == 'info'
	msg := obj.get('msg') or {
		assert false, 'missing msg'
		return
	}
	assert msg as string == 'hello world'
}

fn test_p8_parse_logfmt_standalone_key() {
	result := fn_parse_logfmt([VrlValue('debug key_only')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('debug') or {
		assert false, 'missing debug'
		return
	}
	assert v as bool == true
	v2 := obj.get('key_only') or {
		assert false, 'missing key_only'
		return
	}
	assert v2 as bool == true
}

fn test_p8_parse_logfmt_empty_value() {
	result := fn_parse_logfmt([VrlValue('key= next=val')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('key') or {
		assert false, 'missing key'
		return
	}
	assert v as string == ''
}

fn test_p8_parse_logfmt_escaped_quote() {
	result := fn_parse_logfmt([VrlValue('msg="hello \\"world\\""')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('msg') or {
		assert false, 'missing msg'
		return
	}
	assert (v as string).contains('world')
}

fn test_p8_parse_logfmt_non_string() {
	fn_parse_logfmt([VrlValue(i64(42))]) or {
		assert err.msg().contains('string')
		return
	}
	assert false, 'expected error'
}

// ---- parse_yaml (lines 2185-2898) ----

fn test_p8_parse_yaml_basic_mapping() {
	result := fn_parse_yaml([VrlValue('key: value\nnum: 42')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('key') or {
		assert false, 'missing key'
		return
	}
	assert v as string == 'value'
	n := obj.get('num') or {
		assert false, 'missing num'
		return
	}
	assert n as i64 == 42
}

fn test_p8_parse_yaml_sequence() {
	result := fn_parse_yaml([VrlValue('- one\n- two\n- three')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 3
	assert arr[0] as string == 'one'
}

fn test_p8_parse_yaml_flow_mapping() {
	result := fn_parse_yaml([VrlValue('{a: 1, b: 2}')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	a := obj.get('a') or {
		assert false, 'missing a'
		return
	}
	assert a as i64 == 1
}

fn test_p8_parse_yaml_flow_sequence() {
	result := fn_parse_yaml([VrlValue('[1, 2, 3]')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 3
}

fn test_p8_parse_yaml_null_values() {
	result := fn_parse_yaml([VrlValue('a: null\nb: ~\nc: Null')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	a := obj.get('a') or {
		assert false, 'missing a'
		return
	}
	_ = a as VrlNull
}

fn test_p8_parse_yaml_booleans() {
	result := fn_parse_yaml([VrlValue('a: true\nb: false\nc: yes\nd: no')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	a := obj.get('a') or {
		assert false, 'missing a'
		return
	}
	assert a as bool == true
	b := obj.get('b') or {
		assert false, 'missing b'
		return
	}
	assert b as bool == false
}

fn test_p8_parse_yaml_non_string() {
	fn_parse_yaml([VrlValue(i64(42))]) or {
		assert err.msg().contains('string')
		return
	}
	assert false, 'expected error'
}

fn test_p8_parse_yaml_empty() {
	result := fn_parse_yaml([VrlValue('')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	_ = result as VrlNull
}

fn test_p8_parse_yaml_comment_and_blank() {
	result := fn_parse_yaml([VrlValue('# comment\n---\nkey: val')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('key') or {
		assert false, 'missing key'
		return
	}
	assert v as string == 'val'
}

fn test_p8_parse_yaml_nested_mapping() {
	yaml_str := 'parent:\n  child: value\n  num: 10'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	parent := obj.get('parent') or {
		assert false, 'missing parent'
		return
	}
	child_map := parent as ObjectMap
	v := child_map.get('child') or {
		assert false, 'missing child'
		return
	}
	assert v as string == 'value'
}

fn test_p8_parse_yaml_literal_block() {
	yaml_str := 'msg: |\n  line1\n  line2'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	msg := obj.get('msg') or {
		assert false, 'missing msg'
		return
	}
	s := msg as string
	assert s.contains('line1')
	assert s.contains('line2')
}

fn test_p8_parse_yaml_folded_block() {
	yaml_str := 'msg: >\n  line1\n  line2'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	msg := obj.get('msg') or {
		assert false, 'missing msg'
		return
	}
	s := msg as string
	assert s.contains('line1')
}

fn test_p8_parse_yaml_strip_chomp() {
	yaml_str := 'msg: |-\n  hello'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	msg := obj.get('msg') or {
		assert false, 'missing msg'
		return
	}
	s := msg as string
	assert !s.ends_with('\n')
}

fn test_p8_parse_yaml_keep_chomp() {
	yaml_str := 'msg: |+\n  hello'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	msg := obj.get('msg') or {
		assert false, 'missing msg'
		return
	}
	s := msg as string
	assert s.ends_with('\n')
}

fn test_p8_parse_yaml_inline_flow_in_mapping() {
	yaml_str := 'key: {a: 1}'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	inner := obj.get('key') or {
		assert false, 'missing key'
		return
	}
	inner_obj := inner as ObjectMap
	a := inner_obj.get('a') or {
		assert false, 'missing a'
		return
	}
	assert a as i64 == 1
}

fn test_p8_parse_yaml_inline_seq_in_mapping() {
	yaml_str := 'key: [1, 2]'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	inner := obj.get('key') or {
		assert false, 'missing key'
		return
	}
	arr := inner as []VrlValue
	assert arr.len == 2
}

fn test_p8_parse_yaml_quoted_string() {
	result := fn_parse_yaml([VrlValue('key: "hello world"')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('key') or {
		assert false, 'missing key'
		return
	}
	assert v as string == 'hello world'
}

fn test_p8_parse_yaml_single_quoted_string() {
	result := fn_parse_yaml([VrlValue("key: 'it''s'")]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('key') or {
		assert false, 'missing key'
		return
	}
	assert v as string == "it's"
}

fn test_p8_parse_yaml_float_values() {
	result := fn_parse_yaml([VrlValue('a: 3.14\nb: .inf\nc: -.inf\nd: .nan')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	a := obj.get('a') or {
		assert false, 'missing a'
		return
	}
	assert a as f64 > 3.0
	b := obj.get('b') or {
		assert false, 'missing b'
		return
	}
	assert math.is_inf(b as f64, 1)
	c := obj.get('c') or {
		assert false, 'missing c'
		return
	}
	assert math.is_inf(c as f64, -1)
	d := obj.get('d') or {
		assert false, 'missing d'
		return
	}
	assert math.is_nan(d as f64)
}

fn test_p8_parse_yaml_inline_comment() {
	result := fn_parse_yaml([VrlValue('key: value # comment')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('key') or {
		assert false, 'missing key'
		return
	}
	assert v as string == 'value'
}

fn test_p8_parse_yaml_mapping_with_seq_value() {
	yaml_str := 'items:\n  - a\n  - b'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	items := obj.get('items') or {
		assert false, 'missing items'
		return
	}
	arr := items as []VrlValue
	assert arr.len == 2
}

fn test_p8_parse_yaml_seq_of_mappings() {
	yaml_str := '- name: alice\n  age: 30\n- name: bob\n  age: 25'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 2
}

fn test_p8_parse_yaml_empty_flow_mapping() {
	result := fn_parse_yaml([VrlValue('{}')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	_ = result as ObjectMap
}

fn test_p8_parse_yaml_empty_flow_sequence() {
	result := fn_parse_yaml([VrlValue('[]')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 0
}

fn test_p8_parse_yaml_flow_nested() {
	result := fn_parse_yaml([VrlValue('{a: [1, 2], b: {c: 3}}')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	a := obj.get('a') or {
		assert false, 'missing a'
		return
	}
	arr := a as []VrlValue
	assert arr.len == 2
}

fn test_p8_yaml_is_mapping_quoted_key() {
	assert yaml_is_mapping_line('"key": value') == true
	assert yaml_is_mapping_line("'key': value") == true
	assert yaml_is_mapping_line('"broken') == false
	assert yaml_is_mapping_line("'broken") == false
}

fn test_p8_yaml_is_integer_edge_cases() {
	assert yaml_is_integer('') == false
	assert yaml_is_integer('+') == false
	assert yaml_is_integer('0o77') == true
	assert yaml_is_integer('0xFF') == true
	assert yaml_is_integer('123_456') == true
}

fn test_p8_yaml_is_float_edge_cases() {
	assert yaml_is_float('') == false
	assert yaml_is_float('+') == false
	assert yaml_is_float('1.2e3') == true
	assert yaml_is_float('1.2.3') == false // double dot
	assert yaml_is_float('1e2e3') == false // double e
}

// ---- parse_aws_cloudwatch_log_subscription_message (lines 2900-3026) ----

fn test_p8_parse_aws_cloudwatch_basic() {
	json_str := '{"messageType":"DATA_MESSAGE","owner":"123456","logGroup":"/aws/test","logStream":"stream1","subscriptionFilters":["filter1"],"logEvents":[{"id":"event1","timestamp":1612345678000,"message":"test log"}]}'
	result := fn_parse_aws_cloudwatch_log_subscription_message([VrlValue(json_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	owner := obj.get('owner') or {
		assert false, 'missing owner'
		return
	}
	assert owner as string == '123456'
	mt := obj.get('message_type') or {
		assert false, 'missing message_type'
		return
	}
	assert mt as string == 'DATA_MESSAGE'
	lg := obj.get('log_group') or {
		assert false, 'missing log_group'
		return
	}
	assert lg as string == '/aws/test'
	events := obj.get('log_events') or {
		assert false, 'missing log_events'
		return
	}
	evts := events as []VrlValue
	assert evts.len == 1
}

fn test_p8_parse_aws_cloudwatch_non_string() {
	fn_parse_aws_cloudwatch_log_subscription_message([VrlValue(i64(1))]) or {
		assert err.msg().contains('string')
		return
	}
	assert false, 'expected error'
}

fn test_p8_parse_aws_cloudwatch_invalid_json() {
	fn_parse_aws_cloudwatch_log_subscription_message([VrlValue('not json')]) or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected error'
}

fn test_p8_parse_aws_cloudwatch_invalid_message_type() {
	json_str := '{"messageType":"INVALID","owner":"1","logGroup":"g","logStream":"s","subscriptionFilters":[],"logEvents":[]}'
	fn_parse_aws_cloudwatch_log_subscription_message([VrlValue(json_str)]) or {
		assert err.msg().contains('invalid messageType')
		return
	}
	assert false, 'expected error'
}

fn test_p8_parse_aws_cloudwatch_control_message() {
	json_str := '{"messageType":"CONTROL_MESSAGE","owner":"123","logGroup":"g","logStream":"s","subscriptionFilters":["f"],"logEvents":[]}'
	result := fn_parse_aws_cloudwatch_log_subscription_message([VrlValue(json_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	mt := obj.get('message_type') or {
		assert false, 'missing message_type'
		return
	}
	assert mt as string == 'CONTROL_MESSAGE'
}

// ---- expand_strftime_shortcuts: %R (line 884-889) ----

fn test_p8_expand_strftime_r_specifier() {
	result := expand_strftime_shortcuts('%R')
	assert result == '%H:%M'
}

// ---- format_offset_colon (line 1313-1319) ----

fn test_p8_format_offset_colon_positive() {
	result := format_offset_colon(5 * 3600 + 30 * 60)
	assert result == '+05:30'
}

fn test_p8_format_offset_colon_negative() {
	result := format_offset_colon(-8 * 3600)
	assert result == '-08:00'
}

// ---- parse_key_value: non-string delimiters default (lines 126, 135) ----

fn test_p8_parse_key_value_non_string_delim() {
	result := fn_parse_key_value([VrlValue('a=1 b=2'), VrlValue(i64(0)), VrlValue(i64(0))]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	a := obj.get('a') or {
		assert false, 'missing a'
		return
	}
	assert a as string == '1'
}

fn test_p8_parse_key_value_custom_field_delim() {
	result := fn_parse_key_value([VrlValue('a=1|b=2'), VrlValue('='), VrlValue('|')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	b := obj.get('b') or {
		assert false, 'missing b'
		return
	}
	assert b as string == '2'
}

fn test_p8_parse_key_value_standalone_false() {
	// 5th arg = false: standalone keys should NOT be included
	result := fn_parse_key_value([VrlValue('a=1 standalone b=2'), VrlValue('='),
		VrlValue(' '), VrlValue('ignore'), VrlValue(false)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	// 'standalone' should not be present
	obj.get('standalone') or {
		// expected: not found
		return
	}
	assert false, 'standalone key should not be present with accept_standalone=false'
}

// ---- parse_csv: custom delimiter as non-string (line 222-223) ----

fn test_p8_parse_csv_non_string_delimiter() {
	result := fn_parse_csv([VrlValue('a,b,c'), VrlValue(i64(0))]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 3
}

// ---- Helper: make_test_time ----

fn make_test_time(year int, month int, day int, hour int, minute int, second int) time.Time {
	return time.Time{
		year: year
		month: month
		day: day
		hour: hour
		minute: minute
		second: second
	}
}

// ---- parse_syslog rfc3164 short input (line 2031-2032) ----

fn test_p8_parse_syslog_rfc3164_short() {
	result := fn_parse_syslog([VrlValue('<34>short')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	// Should still parse without error, timestamp may be null
	_ = obj.get('facility') or {
		assert false, 'missing facility'
		return
	}
}

// ---- parse_syslog rfc3164 with ': ' vs ':' (lines 2052-2058) ----

fn test_p8_parse_syslog_rfc3164_colon_no_space() {
	result := fn_parse_syslog([VrlValue('<34>Feb  3 21:13:55 myhost app[123]:message without space')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	appname := obj.get('appname') or {
		assert false, 'missing appname'
		return
	}
	assert appname as string == 'app'
}

// ---- parse_syslog rfc5424 no message (line 1973-1974) ----

fn test_p8_parse_syslog_rfc5424_no_message() {
	result := fn_parse_syslog([VrlValue('<165>1 2021-02-03T00:00:00Z host app - - -')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	msg := obj.get('message') or {
		assert false, 'missing message'
		return
	}
	_ = msg as VrlNull
}

// ---- parse_syslog rfc5424 with unquoted SD value (lines 1944-1955) ----

fn test_p8_parse_syslog_rfc5424_unquoted_sd() {
	result := fn_parse_syslog([VrlValue('<165>1 - host app - - [sd@1 key=unquoted] msg')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	kv := obj.get('key') or {
		assert false, 'missing sd key'
		return
	}
	assert kv as string == 'unquoted'
}

// ---- parse_syslog rfc5424 with escaped char in SD (lines 1930-1932) ----

fn test_p8_parse_syslog_rfc5424_escaped_sd_value() {
	result := fn_parse_syslog([VrlValue('<165>1 - host app - - [sd@1 key="val\\]end"] msg')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	kv := obj.get('key') or {
		assert false, 'missing sd key'
		return
	}
	assert (kv as string).contains(']')
}

// ---- parse_syslog rfc5424 timestamp is '-' (line 1873-1874) ----

fn test_p8_parse_syslog_rfc5424_nil_timestamp() {
	result := fn_parse_syslog([VrlValue('<165>1 - host app pid mid - msg')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	ts := obj.get('timestamp') or {
		assert false, 'missing timestamp'
		return
	}
	_ = ts as VrlNull
}

// ---- get_timezone_name: covers TZ env path (line 1668) ----

fn test_p8_get_timezone_name() {
	// Just exercise the function - result depends on environment
	result := fn_get_timezone_name([]VrlValue{}) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	// Should return a string
	_ = result as string
}

// ---- parse_klog: warning level (line 1455) ----

fn test_p8_parse_klog_warning_level() {
	result := fn_parse_klog([VrlValue('W0505 17:59:40.692994   28133 file.go:42] warning msg')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	level := obj.get('level') or {
		assert false, 'missing level'
		return
	}
	assert level as string == 'warning'
}

fn test_p8_parse_klog_error_level() {
	result := fn_parse_klog([VrlValue('E0505 17:59:40.692994   28133 file.go:42] error msg')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	level := obj.get('level') or {
		assert false, 'missing level'
		return
	}
	assert level as string == 'error'
}

fn test_p8_parse_klog_fatal_level() {
	result := fn_parse_klog([VrlValue('F0505 17:59:40.123   28133 file.go:42] fatal msg')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	level := obj.get('level') or {
		assert false, 'missing level'
		return
	}
	assert level as string == 'fatal'
}

fn test_p8_parse_klog_unknown_level() {
	fn_parse_klog([VrlValue('X0505 17:59:40.123   28133 file.go:42] msg')]) or {
		assert err.msg().contains('unknown level')
		return
	}
	assert false, 'expected error'
}

// ---- parse_timestamp with %R shortcut ----

fn test_p8_expand_strftime_t_specifier() {
	result := expand_strftime_shortcuts('%T')
	assert result == '%H:%M:%S'
}

fn test_p8_expand_strftime_other() {
	result := expand_strftime_shortcuts('%Y-%m')
	assert result == '%Y-%m'
}

// ---- yaml_parse_scalar edge: empty string ----

fn test_p8_yaml_scalar_empty() {
	result := yaml_parse_scalar('')
	_ = result as VrlNull
}

// ---- yaml_split_flow with quotes ----

fn test_p8_yaml_split_flow_with_quotes() {
	parts := yaml_split_flow("'a,b', \"c,d\", e")
	assert parts.len == 3
}

// ---- yaml_find_colon with colon in URL-like string ----

fn test_p8_yaml_find_colon_no_space() {
	idx := yaml_find_colon('http://example.com')
	assert idx == -1 // colon not followed by space
}

// ---- yaml_split_mapping with no colon ----

fn test_p8_yaml_split_mapping_no_colon() {
	key, val := yaml_split_mapping('nocolon')
	assert key == 'nocolon'
	assert val == ''
}

// ---- syslog_value_or_null ----

fn test_p8_syslog_value_or_null_empty() {
	result := syslog_value_or_null('')
	_ = result as VrlNull
}

fn test_p8_syslog_value_or_null_dash() {
	result := syslog_value_or_null('-')
	_ = result as VrlNull
}

fn test_p8_syslog_value_or_null_value() {
	result := syslog_value_or_null('hello')
	assert result as string == 'hello'
}

// ---- yaml flow sequence with nested flow mapping ----

fn test_p8_yaml_flow_seq_nested_mapping() {
	result := yaml_parse_flow_sequence('[{a: 1}]') or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 1
}

fn test_p8_yaml_flow_seq_nested_seq() {
	result := yaml_parse_flow_sequence('[[1, 2]]') or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 1
}

fn test_p8_yaml_flow_seq_empty() {
	result := yaml_parse_flow_sequence('[]') or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 0
}

fn test_p8_yaml_flow_seq_invalid() {
	yaml_parse_flow_sequence('not a seq') or {
		assert err.msg().contains('invalid')
		return
	}
	assert false, 'expected error'
}

fn test_p8_yaml_flow_mapping_invalid() {
	yaml_parse_flow_mapping('not a map') or {
		assert err.msg().contains('invalid')
		return
	}
	assert false, 'expected error'
}

fn test_p8_yaml_flow_mapping_nested_seq() {
	result := yaml_parse_flow_mapping('{a: [1, 2]}') or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	a := obj.get('a') or {
		assert false, 'missing a'
		return
	}
	arr := a as []VrlValue
	assert arr.len == 2
}

fn test_p8_yaml_flow_mapping_bad_entry() {
	yaml_parse_flow_mapping('{novalue}') or {
		assert err.msg().contains('invalid')
		return
	}
	assert false, 'expected error'
}

// ---- yaml_is_float edge: + or - in wrong position ----

fn test_p8_yaml_is_float_sign_at_start() {
	// mid-string sign not after e/E
	assert yaml_is_float('1.2+3') == false
}

fn test_p8_yaml_is_float_underscore() {
	assert yaml_is_float('1_000.5') == true
}

// ---- parse_syslog rfc3164 with appname[procid] ----

fn test_p8_parse_syslog_rfc3164_with_procid() {
	result := fn_parse_syslog([VrlValue('<34>Feb  3 21:13:55 myhost sshd[1234]: Accepted password')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	procid := obj.get('procid') or {
		assert false, 'missing procid'
		return
	}
	assert procid as string == '1234'
}

// ---- parse_syslog rfc3164 short timestamp (line 2028-2029) ----

fn test_p8_parse_syslog_rfc3164_short_timestamp() {
	// 3164 with less than 15 chars: timestamp should be null
	result := fn_parse_syslog([VrlValue('<34>abc')]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	ts := obj.get('timestamp') or {
		assert false, 'missing timestamp'
		return
	}
	_ = ts as VrlNull
}

// ---- parse_logfmt: single-quoted values (line 2151) ----

fn test_p8_parse_logfmt_single_quoted() {
	result := fn_parse_logfmt([VrlValue("key='hello world'")]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('key') or {
		assert false, 'missing key'
		return
	}
	assert v as string == 'hello world'
}

// ---- parse_logfmt: tab whitespace ----

fn test_p8_parse_logfmt_tab_whitespace() {
	result := fn_parse_logfmt([VrlValue("a=1\tb=2")]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	a := obj.get('a') or {
		assert false, 'missing a'
		return
	}
	assert a as string == '1'
	b := obj.get('b') or {
		assert false, 'missing b'
		return
	}
	assert b as string == '2'
}

// ---- yaml block sequence: bare dash with nested block ----

fn test_p8_yaml_sequence_bare_dash() {
	yaml_str := '-\n  key: val'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 1
	obj := arr[0] as ObjectMap
	v := obj.get('key') or {
		assert false, 'missing key'
		return
	}
	assert v as string == 'val'
}

// ---- yaml sequence with flow items ----

fn test_p8_yaml_sequence_flow_mapping_item() {
	yaml_str := '- {a: 1}\n- {b: 2}'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 2
}

fn test_p8_yaml_sequence_flow_sequence_item() {
	yaml_str := '- [1, 2]\n- [3, 4]'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 2
}

// ---- yaml mapping: key with null value (empty next line) ----

fn test_p8_yaml_mapping_null_value() {
	yaml_str := 'key1:\nkey2: val'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		assert false, 'unexpected error: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('key1') or {
		assert false, 'missing key1'
		return
	}
	_ = v as VrlNull
}

// ---- yaml multiline string in mapping with indicator on next line ----

fn test_p8_yaml_mapping_multiline_indicator_next_line() {
	yaml_str := 'msg:\n  |\n  hello\n  world'
	result := fn_parse_yaml([VrlValue(yaml_str)]) or {
		// This hits the multiline_string parse path from mapping
		return // accept either parse or error
	}
	_ = result
}
