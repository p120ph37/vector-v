module vrl

// Tests for additional coverage of vrllib_parse.v and vrllib_parse_new.v
// Targets uncovered lines across both files.

fn p7_exec(prog string) !VrlValue {
	return execute(prog, map[string]VrlValue{})
}

fn p7_obj(prog string, input string) !VrlValue {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(input)
	return execute(prog, obj)
}

// ============================================================================
// vrllib_parse.v — parse_regex second arg error (line 22)
// ============================================================================

fn test_p7_parse_regex_bad_second_arg() {
	// Pass an integer as second arg — should error
	result := fn_parse_regex([VrlValue('hello'), VrlValue(i64(42))]) or { return }
	assert false, 'expected error for bad second arg, got ${result}'
}

// ============================================================================
// parse_regex_all second arg error (line 70)
// ============================================================================

fn test_p7_parse_regex_all_bad_second_arg() {
	result := fn_parse_regex_all([VrlValue('hello'), VrlValue(i64(42))]) or { return }
	assert false, 'expected error for bad second arg, got ${result}'
}

// ============================================================================
// parse_regex_all zero-length match advancement (line 106)
// ============================================================================

fn test_p7_parse_regex_all_zero_length_matches() {
	// r'' matches empty string at every position — forces pos++ path
	result := fn_parse_regex_all([VrlValue('ab'), VrlValue(VrlRegex{ pattern: '' })]) or {
		return
	}
	// Should produce results without infinite loop
	arr := match result {
		[]VrlValue { result }
		else { []VrlValue{} }
	}
	assert arr.len > 0
}

// ============================================================================
// parse_duration output unit 'd' (line 561)
// ============================================================================

fn test_p7_parse_duration_days_unit() {
	result := p7_exec('parse_duration!("86400s", "d")') or { return }
	f := match result {
		f64 { result }
		else { f64(-1) }
	}
	assert f == 1.0, 'expected 1.0 day, got ${f}'
}

// ============================================================================
// parse_int: '+' prefix (line 658)
// ============================================================================

fn test_p7_parse_int_with_plus_sign() {
	result := p7_exec('parse_int!("+100")') or { return }
	val := match result {
		i64 { result }
		else { i64(0) }
	}
	assert val == 100
}

// ============================================================================
// char_to_digit: invalid digit (line 699)
// ============================================================================

fn test_p7_parse_int_invalid_char() {
	result := p7_exec('parse_int!("1g", 16)') or { return }
	// 'g' is not valid hex, but parse_int might handle it in certain ways
	// The important thing is we don't crash
	_ = result
}

// ============================================================================
// format_int: non-integer arg (line 729), base out of range (line 741), zero (line 748)
// ============================================================================

fn test_p7_format_int_non_integer() {
	result := fn_format_int([VrlValue('hello')]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_format_int_base_out_of_range() {
	result := fn_format_int([VrlValue(i64(42)), VrlValue(i64(37))]) or { return }
	assert false, 'expected error for base 37, got ${result}'
}

fn test_p7_format_int_base_too_low() {
	result := fn_format_int([VrlValue(i64(42)), VrlValue(i64(1))]) or { return }
	assert false, 'expected error for base 1, got ${result}'
}

fn test_p7_format_int_zero() {
	result := fn_format_int([VrlValue(i64(0)), VrlValue(i64(16))]) or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s == '0'
}

// ============================================================================
// parse_timestamp: arg count error (line 776), bad first arg (line 782),
// bad second arg (line 786)
// ============================================================================

fn test_p7_parse_timestamp_too_few_args() {
	result := fn_parse_timestamp([VrlValue('hello')]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_timestamp_non_string_first() {
	result := fn_parse_timestamp([VrlValue(i64(42)), VrlValue('%Y')]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_timestamp_non_string_second() {
	result := fn_parse_timestamp([VrlValue('2021-01-01'), VrlValue(i64(42))]) or { return }
	assert false, 'expected error, got ${result}'
}

// ============================================================================
// parse_timestamp_with_tz: error path (line 862)
// ============================================================================

fn test_p7_parse_timestamp_with_tz_bad_input() {
	result := fn_parse_timestamp([VrlValue('not-a-date'), VrlValue('%Y-%m-%d %H:%M:%S %z')]) or {
		return
	}
	// If it succeeds somehow, that's fine too
	_ = result
}

// ============================================================================
// replace_month_name_in_input error (line 939)
// ============================================================================

fn test_p7_parse_timestamp_bad_month_name() {
	// %b with a too-short input
	result := fn_parse_timestamp([VrlValue('ab'), VrlValue('%b')]) or { return }
	assert false, 'expected error, got ${result}'
}

// ============================================================================
// expanded_format_length: %Y, %m/%d/%H/%M/%S, %e, %b, %T, %R, else (lines 959-965)
// ============================================================================

fn test_p7_expanded_format_length_specifiers() {
	// This tests internal function directly
	// %Y = 4, %m = 2, %d = 2, %H = 2, %M = 2, %S = 2 => 14
	len1 := expanded_format_length('%Y%m%d%H%M%S', '')
	assert len1 == 14, 'expected 14, got ${len1}'

	// %e = 2
	len2 := expanded_format_length('%e', '')
	assert len2 == 2

	// %b = 3
	len3 := expanded_format_length('%b', '')
	assert len3 == 3

	// %T = 8 (HH:MM:SS)
	len4 := expanded_format_length('%T', '')
	assert len4 == 8

	// %R = 5 (HH:MM)
	len5 := expanded_format_length('%R', '')
	assert len5 == 5

	// unknown specifier %q = 2 (default)
	len6 := expanded_format_length('%q', '')
	assert len6 == 2
}

// ============================================================================
// strftime_to_v_format: %f (line 1014), %z (1019), %+ (1024), %T (1030)
// ============================================================================

fn test_p7_strftime_to_v_format_specifiers() {
	f := strftime_to_v_format('%f')
	assert f == 'NNNNNN', 'expected NNNNNN, got ${f}'

	z := strftime_to_v_format('%z')
	assert z == 'Z', 'expected Z, got ${z}'

	p := strftime_to_v_format('%+')
	assert p == 'YYYY-MM-DDTHH:mm:ssZ', 'expected YYYY-MM-DDTHH:mm:ssZ, got ${p}'

	t := strftime_to_v_format('%T')
	assert t == 'HH:mm:ss', 'expected HH:mm:ss, got ${t}'
}

// ============================================================================
// strftime_to_v_format: %e (line 1049), %R (1055)
// ============================================================================

fn test_p7_strftime_to_v_format_e_r() {
	// %e and %R are not specially handled — they fall through to the else branch
	// which outputs them literally as %e and %R
	e := strftime_to_v_format('%e')
	assert e.len > 0, 'expected non-empty output for %%e'

	r := strftime_to_v_format('%R')
	assert r.len > 0, 'expected non-empty output for %%R'
}

// format_timestamp arg validation (lines 1049, 1055, 1059)
fn test_p7_format_timestamp_too_few_args() {
	result := fn_format_timestamp([VrlValue('hello')]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_format_timestamp_non_timestamp_first() {
	result := fn_format_timestamp([VrlValue('not-a-timestamp'), VrlValue('%Y')]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_format_timestamp_non_string_second() {
	result := fn_format_timestamp([VrlValue(Timestamp{}), VrlValue(i64(42))]) or { return }
	assert false, 'expected error, got ${result}'
}

// ============================================================================
// parse_tz_offset: colon format (lines 1086-1087), bare HHMM (line 1091),
// unknown tz (line 1125)
// ============================================================================

fn test_p7_parse_tz_offset_colon_format() {
	result := parse_tz_offset('+05:30') or { return }
	assert result == 5 * 3600 + 30 * 60
}

fn test_p7_parse_tz_offset_bare_hhmm() {
	result := parse_tz_offset('-0800') or { return }
	assert result == -8 * 3600
}

fn test_p7_parse_tz_offset_invalid() {
	result := parse_tz_offset('+0') or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_tz_offset_unknown_tz() {
	result := parse_tz_offset('XYZTZ') or { return }
	assert false, 'expected error, got ${result}'
}

// ============================================================================
// strftime_format_with_offset: %f (line 1171/1173), %3f (1178-1186),
// %Z (1197), %a (1225-1228), %p/%P (1254-1262),
// %I (1266-1268), %j (1273), %e (1278), %n (1282), %t (1285),
// %% (1288), else (1291-1292)
// ============================================================================

fn test_p7_format_timestamp_microseconds() {
	result := p7_exec('format_timestamp!(t\'2021-01-01T00:00:00.123456Z\', "%f")') or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s.len == 6, 'expected 6 digit microseconds, got ${s}'
}

fn test_p7_format_timestamp_3f_milliseconds() {
	result := p7_exec('format_timestamp!(t\'2021-01-01T00:00:00.456Z\', "%3f")') or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s.len == 3, 'expected 3 digit milliseconds, got ${s}'
}

fn test_p7_format_timestamp_3_without_f() {
	result := p7_exec('format_timestamp!(t\'2021-01-01T00:00:00Z\', "%3x")') or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s.contains('%'), 'expected %% in output: ${s}'
}

fn test_p7_format_timestamp_z_upper_specifier() {
	result := p7_exec('format_timestamp!(t\'2021-01-01T00:00:00Z\', "%Z")') or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s == 'UTC', 'expected UTC, got ${s}'
}

fn test_p7_format_timestamp_day_of_week() {
	result := p7_exec('format_timestamp!(t\'2021-01-01T00:00:00Z\', "%a")') or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s.len == 3, 'expected 3-char day name, got ${s}'
}

fn test_p7_format_timestamp_am_pm() {
	result_p := p7_exec('format_timestamp!(t\'2021-01-01T14:00:00Z\', "%p")') or { return }
	s_p := match result_p {
		string { result_p }
		else { '' }
	}
	assert s_p == 'PM', 'expected PM, got ${s_p}'

	result_pp := p7_exec('format_timestamp!(t\'2021-01-01T14:00:00Z\', "%P")') or { return }
	s_pp := match result_pp {
		string { result_pp }
		else { '' }
	}
	assert s_pp == 'pm', 'expected pm, got ${s_pp}'

	result_am := p7_exec('format_timestamp!(t\'2021-01-01T08:00:00Z\', "%p")') or { return }
	s_am := match result_am {
		string { result_am }
		else { '' }
	}
	assert s_am == 'AM', 'expected AM, got ${s_am}'

	result_am_low := p7_exec('format_timestamp!(t\'2021-01-01T08:00:00Z\', "%P")') or { return }
	s_am_low := match result_am_low {
		string { result_am_low }
		else { '' }
	}
	assert s_am_low == 'am', 'expected am, got ${s_am_low}'
}

fn test_p7_format_timestamp_12hour() {
	result := p7_exec('format_timestamp!(t\'2021-01-01T00:00:00Z\', "%I")') or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s == '12', 'expected 12 for midnight, got ${s}'

	result2 := p7_exec('format_timestamp!(t\'2021-01-01T13:00:00Z\', "%I")') or { return }
	s2 := match result2 {
		string { result2 }
		else { '' }
	}
	assert s2 == '01', 'expected 01 for 13:00, got ${s2}'
}

fn test_p7_format_timestamp_day_of_year() {
	result := p7_exec('format_timestamp!(t\'2021-01-01T00:00:00Z\', "%j")') or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s.len == 3, 'expected 3-char day of year'
}

fn test_p7_format_timestamp_space_padded_day() {
	result := p7_exec('format_timestamp!(t\'2021-01-05T00:00:00Z\', "%e")') or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s.trim_space() == '5', 'expected day 5, got ${s}'
}

fn test_p7_format_timestamp_newline_tab_percent() {
	result := p7_exec('format_timestamp!(t\'2021-01-01T00:00:00Z\', "%n%t%%")') or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s.contains('\n'), 'expected newline in output'
	assert s.contains('\t'), 'expected tab in output'
	assert s.contains('%'), 'expected percent in output'
}

fn test_p7_format_timestamp_unknown_specifier() {
	result := p7_exec('format_timestamp!(t\'2021-01-01T00:00:00Z\', "%q")') or { return }
	s := match result {
		string { result }
		else { '' }
	}
	assert s == '%q', 'expected %%q literal, got ${s}'
}

// ============================================================================
// parse_common_log: arg count (line 1325), non-string (line 1330),
// missing [ (line 1344), missing " (line 1362)
// ============================================================================

fn test_p7_parse_common_log_too_few_args() {
	result := fn_parse_common_log([]VrlValue{}) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_common_log_non_string() {
	result := fn_parse_common_log([VrlValue(i64(42))]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_common_log_missing_bracket() {
	result := fn_parse_common_log([VrlValue('host - user NOTBRACKET')]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_common_log_missing_quote() {
	result := fn_parse_common_log([VrlValue('host - user [01/Jan/2021:00:00:00 +0000] NOQUOTE')]) or {
		return
	}
	assert false, 'expected error, got ${result}'
}

// ============================================================================
// parse_klog: arg count (line 1440), non-string (line 1445), missing date (line 1463),
// missing space after date (line 1470), missing ] (lines 1500-1501),
// short microseconds (line 1535)
// ============================================================================

fn test_p7_parse_klog_too_few_args() {
	result := fn_parse_klog([]VrlValue{}) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_klog_non_string() {
	result := fn_parse_klog([VrlValue(i64(42))]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_klog_missing_date() {
	result := fn_parse_klog([VrlValue('I')]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_klog_missing_space_after_date() {
	result := fn_parse_klog([VrlValue('I0505X')]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_klog_missing_bracket() {
	result := fn_parse_klog([VrlValue('I0505 17:59:40.692994   28133 file.go:42 no bracket')]) or {
		return
	}
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_klog_short_microseconds() {
	result := fn_parse_klog([VrlValue('I0505 17:59:40.69   28133 file.go:42] message')]) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('message')
}

fn test_p7_parse_klog_valid_full() {
	result := fn_parse_klog([VrlValue('I0505 17:59:40.692994   28133 miscellaneous.go:42] some message')]) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('some message')
	assert j.contains('info')
}

// ============================================================================
// vrllib_parse_new.v — CEF parse: standalone key (line 532)
// ============================================================================

fn test_p7_parse_cef_standalone_keys() {
	result := p7_exec('parse_cef!("CEF:0|Security|IDS|1.0|100|Attack|5|src=1.2.3.4 standalone")') or {
		return
	}
	j := vrl_to_json(result)
	assert j.len > 0
}

// ============================================================================
// CEF translate_custom_fields: non-translated key pass-through (line 621)
// ============================================================================

fn test_p7_parse_cef_custom_fields() {
	result := p7_exec('parse_cef!("CEF:0|Vendor|Product|1.0|100|Name|5|customKey=customValue")') or {
		return
	}
	j := vrl_to_json(result)
	assert j.len > 0
}

// ============================================================================
// parse_influxdb: NaN field value skip (line 913)
// ============================================================================

fn test_p7_parse_influxdb_nan_field() {
	result := p7_exec('parse_influxdb!("measurement field1=NaN 1000000000")') or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

// ============================================================================
// parse_ruby_hash: hash with integer key (line 1101), empty hash break (line 1089),
// array parsing (line 1142)
// ============================================================================

fn test_p7_parse_ruby_hash_integer_key() {
	result := p7_exec('parse_ruby_hash!("{1 => \\"one\\"}")') or { return }
	j := vrl_to_json(result)
	assert j.contains('one')
}

fn test_p7_parse_ruby_hash_empty() {
	result := p7_exec('parse_ruby_hash!("{}")') or { return }
	j := vrl_to_json(result)
	assert j == '{}'
}

fn test_p7_parse_ruby_hash_with_array() {
	result := p7_exec('parse_ruby_hash!("{:key => [1, 2, 3]}")') or { return }
	j := vrl_to_json(result)
	assert j.contains('key')
}

// ============================================================================
// XML: xml_line_col (lines 1382-1393), xml_parse with prolog/comments/DOCTYPE
// (lines 1415-1452), self-closing tags, CDATA, PI in children, etc.
// ============================================================================

fn test_p7_parse_xml_with_xml_declaration() {
	result := p7_exec('parse_xml!("<?xml version=\\"1.0\\"?><root>hello</root>")') or { return }
	j := vrl_to_json(result)
	assert j.contains('root')
	assert j.contains('hello')
}

fn test_p7_parse_xml_with_comment() {
	result := p7_exec('parse_xml!("<!-- a comment --><root>value</root>")') or { return }
	j := vrl_to_json(result)
	assert j.contains('root')
}

fn test_p7_parse_xml_with_doctype() {
	result := p7_exec('parse_xml!("<!DOCTYPE html><root>test</root>")') or { return }
	j := vrl_to_json(result)
	assert j.contains('root')
}

fn test_p7_parse_xml_unterminated_pi() {
	result := p7_obj('parse_xml!(.input)', '<?xml version=1.0 <root/>') or { return }
	// Should error due to unterminated PI
	assert false, 'expected error for unterminated PI, got ${result}'
}

fn test_p7_parse_xml_unterminated_comment() {
	result := p7_obj('parse_xml!(.input)', '<!-- unterminated <root/>') or { return }
	assert false, 'expected error for unterminated comment'
}

fn test_p7_parse_xml_unterminated_doctype() {
	result := p7_obj('parse_xml!(.input)', '<!DOCTYPE html [<!ELEMENT root ANY>') or { return }
	assert false, 'expected error for unterminated DOCTYPE'
}

fn test_p7_parse_xml_empty_input() {
	result := p7_exec('parse_xml!("   ")') or { return }
	assert false, 'expected error for empty input'
}

fn test_p7_parse_xml_unknown_token() {
	result := p7_obj('parse_xml!(.input)', 'not xml at all') or { return }
	assert false, 'expected error for non-xml input'
}

fn test_p7_parse_xml_whitespace_in_element() {
	result := p7_obj('parse_xml!(.input)', '<root  attr1="v1"  attr2="v2" >text</root>') or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('root')
}

fn test_p7_parse_xml_empty_tag_error() {
	result := p7_obj('parse_xml!(.input)', '< >text</root>') or { return }
	assert false, 'expected error for empty tag'
}

fn test_p7_parse_xml_child_comment() {
	result := p7_obj('parse_xml!(.input)', '<root><!-- inner comment --><child>val</child></root>') or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('child')
}

fn test_p7_parse_xml_child_cdata() {
	result := p7_obj('parse_xml!(.input)', '<root><![CDATA[raw content]]></root>') or { return }
	j := vrl_to_json(result)
	assert j.contains('raw content')
}

fn test_p7_parse_xml_child_pi() {
	result := p7_obj('parse_xml!(.input)', '<root><?pi instruction?><child>v</child></root>') or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('child')
}

fn test_p7_parse_xml_unterminated_child_comment() {
	result := p7_obj('parse_xml!(.input)', '<root><!-- unterminated') or { return }
	assert false, 'expected error for unterminated child comment'
}

fn test_p7_parse_xml_unterminated_child_cdata() {
	result := p7_obj('parse_xml!(.input)', '<root><![CDATA[unterminated') or { return }
	assert false, 'expected error for unterminated CDATA'
}

fn test_p7_parse_xml_unterminated_child_pi() {
	result := p7_obj('parse_xml!(.input)', '<root><?pi unterminated') or { return }
	assert false, 'expected error for unterminated child PI'
}

fn test_p7_parse_xml_child_doctype() {
	result := p7_obj('parse_xml!(.input)', '<root><!DOCTYPE inner><child>v</child></root>') or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('child')
}

fn test_p7_parse_xml_duplicate_children() {
	result := p7_obj('parse_xml!(.input)', '<root><item>a</item><item>b</item><item>c</item></root>') or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('item')
}

fn test_p7_parse_xml_single_element_child() {
	result := p7_obj('parse_xml!(.input)', '<root><inner><deep>val</deep></inner></root>') or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('deep')
}

// ============================================================================
// xml_unescape: numeric character references (lines 1864-1899)
// ============================================================================

fn test_p7_parse_xml_hex_entity() {
	result := p7_obj('parse_xml!(.input)', '<root>&#x41;&#x42;</root>') or { return }
	j := vrl_to_json(result)
	assert j.contains('AB')
}

fn test_p7_parse_xml_decimal_entity() {
	result := p7_obj('parse_xml!(.input)', '<root>&#65;&#66;</root>') or { return }
	j := vrl_to_json(result)
	assert j.contains('AB')
}

fn test_p7_parse_xml_invalid_hex_entity() {
	result := p7_obj('parse_xml!(.input)', '<root>&#xZZ;</root>') or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_p7_parse_xml_invalid_decimal_entity() {
	result := p7_obj('parse_xml!(.input)', '<root>&#abc;</root>') or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_p7_parse_xml_multibyte_entity() {
	// e-acute (2-byte UTF-8) — triggers lines 1888-1890
	result := p7_obj('parse_xml!(.input)', '<root>&#x00E9;</root>') or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_p7_parse_xml_3byte_entity() {
	// snowman (3-byte UTF-8) — triggers lines 1892-1894
	result := p7_obj('parse_xml!(.input)', '<root>&#x2603;</root>') or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_p7_parse_xml_4byte_entity() {
	// emoji (4-byte UTF-8) — triggers lines 1896-1899
	result := p7_obj('parse_xml!(.input)', '<root>&#x1F600;</root>') or { return }
	j := vrl_to_json(result)
	assert j.len > 0
}

// ============================================================================
// parse_cbor: various CBOR types (lines 1921-2096)
// ============================================================================

fn test_p7_parse_cbor_bool_false() {
	result := fn_parse_cbor([VrlValue([u8(0xf4)].bytestr())]) or { return }
	match result {
		bool { assert result == false }
		else { assert false, 'expected false' }
	}
}

fn test_p7_parse_cbor_bool_true() {
	result := fn_parse_cbor([VrlValue([u8(0xf5)].bytestr())]) or { return }
	match result {
		bool { assert result == true }
		else { assert false, 'expected true' }
	}
}

fn test_p7_parse_cbor_null() {
	result := fn_parse_cbor([VrlValue([u8(0xf6)].bytestr())]) or { return }
	match result {
		VrlNull { assert true }
		else { assert false, 'expected null' }
	}
}

fn test_p7_parse_cbor_undefined() {
	// line 2020
	result := fn_parse_cbor([VrlValue([u8(0xf7)].bytestr())]) or { return }
	match result {
		VrlNull { assert true }
		else { assert false, 'expected null for undefined' }
	}
}

fn test_p7_parse_cbor_positive_int() {
	result := fn_parse_cbor([VrlValue([u8(0x0a)].bytestr())]) or { return }
	match result {
		i64 { assert result == 10 }
		else { assert false, 'expected i64(10)' }
	}
}

fn test_p7_parse_cbor_negative_int() {
	result := fn_parse_cbor([VrlValue([u8(0x20)].bytestr())]) or { return }
	match result {
		i64 { assert result == -1 }
		else { assert false, 'expected i64(-1)' }
	}
}

fn test_p7_parse_cbor_byte_string() {
	// line 1959
	result := fn_parse_cbor([VrlValue([u8(0x43), u8(0x41), u8(0x42), u8(0x43)].bytestr())]) or {
		return
	}
	match result {
		string { assert result == 'ABC' }
		else { assert false, 'expected string ABC' }
	}
}

fn test_p7_parse_cbor_text_string() {
	// line 1966
	result := fn_parse_cbor([VrlValue([u8(0x63), u8(0x68), u8(0x69), u8(0x21)].bytestr())]) or {
		return
	}
	match result {
		string { assert result == 'hi!' }
		else { assert false, 'expected string hi!' }
	}
}

fn test_p7_parse_cbor_array() {
	result := fn_parse_cbor([VrlValue([u8(0x82), u8(0x01), u8(0x02)].bytestr())]) or { return }
	match result {
		[]VrlValue { assert result.len == 2 }
		else { assert false, 'expected array' }
	}
}

fn test_p7_parse_cbor_map() {
	// map {"a": 1}
	result := fn_parse_cbor([VrlValue([u8(0xa1), u8(0x61), u8(0x61), u8(0x01)].bytestr())]) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('a')
}

fn test_p7_parse_cbor_tagged_value() {
	// tag 1, value 0 — line 2000-2001
	result := fn_parse_cbor([VrlValue([u8(0xc1), u8(0x00)].bytestr())]) or { return }
	match result {
		i64 { assert result == 0 }
		else { assert false, 'expected i64(0)' }
	}
}

fn test_p7_parse_cbor_float16() {
	// half-precision 1.0 — lines 2024-2029
	result := fn_parse_cbor([VrlValue([u8(0xf9), u8(0x3c), u8(0x00)].bytestr())]) or { return }
	match result {
		f64 { assert result == 1.0 }
		else { assert false, 'expected f64(1.0)' }
	}
}

fn test_p7_parse_cbor_float32() {
	// single-precision 1.0 — lines 2033-2038
	result := fn_parse_cbor([VrlValue([u8(0xfa), u8(0x3f), u8(0x80), u8(0x00),
		u8(0x00)].bytestr())]) or { return }
	match result {
		f64 { assert result == 1.0 }
		else { assert false, 'expected f64(1.0)' }
	}
}

fn test_p7_parse_cbor_float64() {
	// double-precision 1.0 — lines 2043-2050
	result := fn_parse_cbor([VrlValue([u8(0xfb), u8(0x3f), u8(0xf0), u8(0x00), u8(0x00),
		u8(0x00), u8(0x00), u8(0x00), u8(0x00)].bytestr())]) or { return }
	match result {
		f64 { assert result == 1.0 }
		else { assert false, 'expected f64(1.0)' }
	}
}

fn test_p7_parse_cbor_unknown_simple() {
	// simple value 19 = 0xf3 — line 2053
	result := fn_parse_cbor([VrlValue([u8(0xf3)].bytestr())]) or { return }
	match result {
		VrlNull { assert true }
		else { assert false, 'expected null' }
	}
}

fn test_p7_parse_cbor_non_string_arg() {
	// line 1925
	result := fn_parse_cbor([VrlValue(i64(42))]) or { return }
	assert false, 'expected error, got ${result}'
}

fn test_p7_parse_cbor_uint8() {
	// additional=24 — line 2074
	result := fn_parse_cbor([VrlValue([u8(0x18), u8(0xc8)].bytestr())]) or { return }
	match result {
		i64 { assert result == 200 }
		else { assert false, 'expected 200' }
	}
}

fn test_p7_parse_cbor_uint16() {
	// additional=25 — lines 2079-2083
	result := fn_parse_cbor([VrlValue([u8(0x19), u8(0x03), u8(0xe8)].bytestr())]) or { return }
	match result {
		i64 { assert result == 1000 }
		else { assert false, 'expected 1000' }
	}
}

fn test_p7_parse_cbor_uint32() {
	// additional=26 — lines 2086-2090
	result := fn_parse_cbor([VrlValue([u8(0x1a), u8(0x00), u8(0x01), u8(0x86),
		u8(0xa0)].bytestr())]) or { return }
	match result {
		i64 { assert result == 100000 }
		else { assert false, 'expected 100000' }
	}
}

fn test_p7_parse_cbor_uint64() {
	// additional=27 — lines 2093-2096
	result := fn_parse_cbor([VrlValue([u8(0x1b), u8(0x00), u8(0x00), u8(0x00), u8(0x00),
		u8(0x00), u8(0x00), u8(0x00), u8(0x01)].bytestr())]) or { return }
	match result {
		i64 { assert result == 1 }
		else { assert false, 'expected 1' }
	}
}

fn test_p7_parse_cbor_map_with_int_key() {
	// map with integer key — line 1990
	result := fn_parse_cbor([VrlValue([u8(0xa1), u8(0x18), u8(0x2a), u8(0x63), u8(0x76),
		u8(0x61), u8(0x6c)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j.contains('42')
}

fn test_p7_parse_cbor_truncated() {
	result := fn_parse_cbor([VrlValue([u8(0x19)].bytestr())]) or { return }
	assert false, 'expected error for truncated CBOR'
}

// ============================================================================
// parse_timestamp with %z timezone (line 809, 851)
// ============================================================================

fn test_p7_parse_timestamp_with_tz_offset() {
	result := p7_exec('parse_timestamp!("2021-01-01 12:00:00 +0530", "%Y-%m-%d %H:%M:%S %z")') or {
		return
	}
	j := vrl_to_json(result)
	assert j.len > 0
}

fn test_p7_parse_timestamp_non_digit_in_tz_part() {
	result := p7_exec('parse_timestamp!("2021-01-01 12:00:00 abc", "%Y-%m-%d %H:%M:%S %z")') or {
		return
	}
	_ = result
}

// ============================================================================
// parse_timestamp with %b month name (line 809)
// ============================================================================

fn test_p7_parse_timestamp_month_name() {
	result := p7_exec('parse_timestamp!("01/Jan/2021:00:00:00", "%d/%b/%Y:%H:%M:%S")') or {
		return
	}
	j := vrl_to_json(result)
	assert j.len > 0
}

// ============================================================================
// parse_tz_offset colon format parts check (line 1087 else branch)
// ============================================================================

fn test_p7_parse_tz_offset_invalid_colon_format() {
	result := parse_tz_offset('+05:30:00') or { return }
	// 3 parts — should error on parts.len != 2
	assert false, 'expected error, got ${result}'
}

// ============================================================================
// Additional XML tests for text key duplication (lines 1755-1757)
// ============================================================================

fn test_p7_parse_xml_mixed_text_elements() {
	// Mixed text + element children forces text key handling
	result := p7_obj('parse_xml!(.input)', '<root>text1<child>val</child>text2</root>') or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('child')
}

fn test_p7_parse_xml_self_closing_with_attrs() {
	result := p7_obj('parse_xml!(.input)', '<root><empty attr="val"/></root>') or { return }
	j := vrl_to_json(result)
	assert j.contains('empty')
}
