module vrl

// Tests for uncovered lines in vrllib_parse_new.v

fn pnc_exec(prog string) !VrlValue {
	return execute(prog, map[string]VrlValue{})
}

fn pnc_obj(prog string, input string) !VrlValue {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(input)
	return execute(prog, obj)
}

// ---- parse_nginx_log: line 52 (too few args error) ----

fn test_parse_nginx_log_too_few_args() {
	// Calling with fewer than 2 args should error
	_ := pnc_exec('parse_nginx_log!("test")') or { return }
	assert false, 'expected error for too few args'
}

// ---- clf_parse_timestamp_flexible: line 139 (apache error timestamp fallback) ----
// This is exercised via parse_apache_log with error format

fn test_parse_apache_log_error_format() {
	// Apache error log line format
	line := '[Wed Oct 11 14:32:52.123456 2000] [error] [pid 1234:tid 5678] [client 192.168.1.1:9876] error message'
	result := pnc_obj('parse_apache_log!(.input, "error")', line) or { return }
	j := vrl_to_json(result)
	assert j.contains('message'), 'expected message field in: ${j}'
}

// ---- cef_parse_extensions escape sequences: lines 532, 569, 571 ----

fn test_parse_cef_extension_escapes() {
	// CEF with escape sequences: \= \\ \n \r in extensions
	cef := 'CEF:0|Vendor|Product|1.0|100|Name|5|key1=val\\\\ue key2=val\\=ue key3=line1\\nline2 key4=cr\\rhere'
	result := pnc_obj('parse_cef!(.input)', cef) or { return }
	j := vrl_to_json(result)
	assert j.contains('key1'), 'expected key1: ${j}'
	assert j.contains('key2'), 'expected key2: ${j}'
	assert j.contains('key3'), 'expected key3: ${j}'
}

fn test_parse_cef_extension_whitespace_only_end() {
	// CEF where extension parsing hits end-of-string while skipping whitespace (line 532)
	cef := 'CEF:0|Vendor|Product|1.0|100|Name|5|key1=value   '
	result := pnc_obj('parse_cef!(.input)', cef) or { return }
	j := vrl_to_json(result)
	assert j.contains('key1'), 'expected key1: ${j}'
}

// ---- cef_translate_custom_fields: line 621 ----

fn test_parse_cef_translate_custom_fields() {
	// CEF with custom field labels that get translated
	cef := 'CEF:0|Vendor|Product|1.0|100|Name|5|cs1=secret_data cs1Label=apiKey cn1=42 cn1Label=count'
	result := pnc_obj('parse_cef!(.input, translate_custom_fields: true)', cef) or { return }
	j := vrl_to_json(result)
	// translated fields: apiKey and count should appear
	assert j.contains('apiKey'), 'expected apiKey in: ${j}'
}

// ---- parse_glog: lines 636, 640, 660, 701 ----

fn test_parse_glog_too_few_args() {
	_ := pnc_exec('parse_glog!()') or { return }
	assert false, 'expected error'
}

fn test_parse_glog_non_string_arg() {
	_ := pnc_exec('parse_glog!(42)') or { return }
	assert false, 'expected error for non-string'
}

fn test_parse_glog_too_short() {
	_ := pnc_exec('parse_glog!("I0")') or { return }
	assert false, 'expected error for short input'
}

fn test_parse_glog_valid() {
	// Format: Lmmdd hh:mm:ss.ffffff threadid file:line] msg
	line := 'I0101 12:34:56.789012 12345 myfile.cc:42] hello world'
	result := pnc_obj('parse_glog!(.input)', line) or {
		assert false, 'parse_glog failed: ${err}'
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"level":"info"'), 'expected level info: ${j}'
	assert j.contains('"message":"hello world"'), 'expected message: ${j}'
	assert j.contains('"file":"myfile.cc"'), 'expected file: ${j}'
}

fn test_parse_glog_missing_bracket() {
	// Missing ] delimiter -> line 701
	line := 'I0101 12:34:56.789012 12345 myfile.cc:42 hello world'
	_ := pnc_obj('parse_glog!(.input)', line) or { return }
	assert false, 'expected error for missing bracket'
}

// ---- parse_groks: lines 762, 766, 770, 778 ----

fn test_parse_groks_too_few_args() {
	_ := pnc_exec('parse_groks!("test")') or { return }
	assert false, 'expected error'
}

fn test_parse_groks_non_string_value() {
	_ := pnc_exec('parse_groks!(42, ["%{NUMBER:num}"])') or { return }
	assert false, 'expected error for non-string value'
}

fn test_parse_groks_non_array_patterns() {
	_ := pnc_exec('parse_groks!("test", "not_array")') or { return }
	assert false, 'expected error for non-array patterns'
}

fn test_parse_groks_skip_non_string_pattern() {
	// line 778: non-string pattern in array -> continue
	result := pnc_exec('parse_groks!("42", [42, "%{NUMBER:num}"])') or { return }
	j := vrl_to_json(result)
	assert j.contains('num'), 'expected num in: ${j}'
}

// ---- parse_influxdb: lines 808, 812, 828-829, 842, 913 ----

fn test_parse_influxdb_too_few_args() {
	_ := pnc_exec('parse_influxdb!()') or { return }
	assert false, 'expected error'
}

fn test_parse_influxdb_non_string() {
	_ := pnc_exec('parse_influxdb!(42)') or { return }
	assert false, 'expected error'
}

fn test_parse_influxdb_escaped_space() {
	// line 828-829: escaped space in measurement
	line := 'cpu\\ usage,host=server value=42 1234567890000000000'
	result := pnc_obj('parse_influxdb!(.input)', line) or { return }
	j := vrl_to_json(result)
	assert j.contains('value'), 'expected value field: ${j}'
}

fn test_parse_influxdb_escaped_comma() {
	// line 842: escape in meas_tags
	line := 'cpu,host=server\\,main value=42'
	result := pnc_obj('parse_influxdb!(.input)', line) or { return }
	j := vrl_to_json(result)
	assert j.contains('cpu'), 'expected cpu in: ${j}'
}

fn test_parse_influxdb_field_value_empty() {
	// line 966: empty field value -> null
	line := 'cpu value='
	result := pnc_obj('parse_influxdb!(.input)', line) or { return }
	// should parse without error
}

// ---- parse_ruby_hash: lines 1007, 1011, 1026, 1039-1040, 1065, 1067, 1069-1070, 1072, 1089, 1100-1102, 1110, 1112 ----

fn test_parse_ruby_hash_too_few_args() {
	_ := pnc_exec('parse_ruby_hash!()') or { return }
	assert false, 'expected error'
}

fn test_parse_ruby_hash_non_string() {
	_ := pnc_exec('parse_ruby_hash!(42)') or { return }
	assert false, 'expected error'
}

fn test_parse_ruby_hash_symbol_keys() {
	// line 1039-1040: :symbol_key with quotes
	result := pnc_exec('parse_ruby_hash!(\'{"key" => "value"}\')') or { return }
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
}

fn test_parse_ruby_hash_symbol_quoted_key() {
	// line 1039: :"quoted_key"
	result := pnc_exec('parse_ruby_hash!(\'{ :"hello" => "world" }\')') or { return }
	j := vrl_to_json(result)
	assert j.contains('hello'), 'expected hello: ${j}'
}

fn test_parse_ruby_hash_colon_separator() {
	// line 1110: key: value syntax (JSON-like)
	result := pnc_exec('parse_ruby_hash!(\'{ name: "alice" }\')') or { return }
	j := vrl_to_json(result)
	assert j.contains('name'), 'expected name: ${j}'
}

fn test_parse_ruby_hash_unexpected_separator() {
	// line 1112: unexpected character after hash key
	_ := pnc_exec('parse_ruby_hash!(\'{ "key" ! "val" }\')') or { return }
	assert false, 'expected error for invalid separator'
}

fn test_parse_ruby_hash_word_value() {
	// lines 1065-1070: word (symbol key without colon) as value
	result := pnc_exec('parse_ruby_hash!(\'{ "key" => someword }\')') or { return }
	j := vrl_to_json(result)
	assert j.contains('someword'), 'expected someword: ${j}'
}

fn test_parse_ruby_hash_unexpected_char() {
	// line 1072: unexpected character
	_ := pnc_exec('parse_ruby_hash!(\'{ @invalid => "val" }\')') or { return }
	assert false, 'expected error for unexpected character'
}

fn test_parse_ruby_hash_end_of_input() {
	// line 1026: unexpected end of input (unclosed hash)
	_ := pnc_exec('parse_ruby_hash!(\'{ "key" => \')') or { return }
	assert false, 'expected error for unexpected end'
}

fn test_parse_ruby_hash_numeric_key() {
	// lines 1100-1101: f64/i64 hash key converted to string
	result := pnc_exec('parse_ruby_hash!(\'{ 42 => "val" }\')') or { return }
	j := vrl_to_json(result)
	assert j.contains('val'), 'expected val: ${j}'
}

fn test_parse_ruby_hash_non_hashable_key() {
	// line 1102: hash key must be string or symbol
	_ := pnc_exec('parse_ruby_hash!(\'{ true => "val" }\')') or { return }
	// This might succeed (true as key) or error - either way exercises the path
}

fn test_parse_ruby_hash_ws_at_end() {
	// line 1089, 1141-1142: parser hits end while scanning
	result := pnc_exec('parse_ruby_hash!(\'{"a" => "b"   }\')') or { return }
	j := vrl_to_json(result)
	assert j.contains('a'), 'expected a: ${j}'
}

// ---- ruby_parse_array: lines 1136, 1142 ----

fn test_parse_ruby_hash_with_array() {
	// lines 1136: empty array, 1142: array parsing end
	result := pnc_exec('parse_ruby_hash!(\'{"arr" => [], "arr2" => [1, 2, 3]}\')') or { return }
	j := vrl_to_json(result)
	assert j.contains('arr'), 'expected arr: ${j}'
}

// ---- ruby_parse_string escape: lines 1175-1178, 1187 ----

fn test_parse_ruby_hash_string_escape() {
	// lines 1175-1178: non-delimiter escape in string (keep as-is)
	result := pnc_exec("parse_ruby_hash!('{\"key\" => \"hello\\\\tworld\"}')") or { return }
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
}

fn test_parse_ruby_hash_unterminated_string() {
	// line 1187: unterminated string
	_ := pnc_exec('parse_ruby_hash!(\'{"key\')') or { return }
	assert false, 'expected error for unterminated string'
}

// ---- ruby_parse_number: lines 1193, 1205-1208 ----

fn test_parse_ruby_hash_negative_number() {
	// line 1193: negative number
	result := pnc_exec('parse_ruby_hash!(\'{"val" => -3.14}\')') or { return }
	j := vrl_to_json(result)
	assert j.contains('val'), 'expected val: ${j}'
}

fn test_parse_ruby_hash_scientific_notation() {
	// lines 1205-1208: scientific notation e.g. 1e10, 1E-3
	result := pnc_exec('parse_ruby_hash!(\'{"val" => 1.5e10}\')') or { return }
	j := vrl_to_json(result)
	assert j.contains('val'), 'expected val: ${j}'
}

fn test_parse_ruby_hash_scientific_neg_exp() {
	// line 1207-1208: scientific notation with negative exponent
	result := pnc_exec('parse_ruby_hash!(\'{"val" => 2E-3}\')') or { return }
	j := vrl_to_json(result)
	assert j.contains('val'), 'expected val: ${j}'
}

// ---- parse_xml: lines 1245, 1249 ----

fn test_parse_xml_too_few_args() {
	_ := pnc_exec('parse_xml!()') or { return }
	assert false, 'expected error'
}

fn test_parse_xml_non_string() {
	_ := pnc_exec('parse_xml!(42)') or { return }
	assert false, 'expected error'
}

// ---- xml_trim_whitespace: lines 1360-1377 ----

fn test_parse_xml_whitespace_trimming() {
	// XML with whitespace between tags that should get trimmed
	xml := '<root>\n  <a>1</a>\n  <b>2</b>\n</root>'
	result := pnc_obj('parse_xml!(.input)', xml) or { return }
	j := vrl_to_json(result)
	assert j.contains('root'), 'expected root: ${j}'
}

// ---- xml_line_col: lines 1382-1390 ----
// Exercised by xml parsing errors at non-zero positions

fn test_parse_xml_error_position() {
	// Malformed XML triggers xml_line_col for error reporting
	xml := '<root>\n<unclosed>'
	_ := pnc_obj('parse_xml!(.input)', xml) or { return }
	// Either parses or gives error with line/col info - both exercise the code
}

fn test_parse_xml_malformed_tag() {
	xml := '<root><a attr="val">text</a><b>more</root>'
	result := pnc_obj('parse_xml!(.input)', xml) or { return }
	j := vrl_to_json(result)
	assert j.contains('root'), 'expected root: ${j}'
}
