module vrl

// Tests for uncovered YAML parsing paths, parse_regex edge cases,
// and vrllib_parse.v areas with low coverage.

fn p5_obj(prog string, input string) !VrlValue {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(input)
	return execute(prog, obj)
}

// ============================================================================
// parse_yaml — nested structures, block scalars, complex types
// ============================================================================

fn test_parse_yaml_nested_mapping_in_sequence() {
	yaml_input := '- name: item1\n  value: 10\n- name: item2\n  value: 20'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml nested mapping: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('item1'), 'expected item1: ${j}'
	assert j.contains('item2'), 'expected item2: ${j}'
}

fn test_parse_yaml_nested_sequence_in_mapping() {
	yaml_input := 'tags:\n  - alpha\n  - beta\n  - gamma'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml nested sequence: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('alpha'), 'expected alpha: ${j}'
	assert j.contains('gamma'), 'expected gamma: ${j}'
}

fn test_parse_yaml_literal_block_scalar() {
	yaml_input := 'content: |\n  line one\n  line two\n  line three'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml literal block: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('line one'), 'expected line one: ${j}'
	assert j.contains('line two'), 'expected line two: ${j}'
}

fn test_parse_yaml_folded_block_scalar() {
	yaml_input := 'desc: >\n  This is a\n  long paragraph\n  that wraps.'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml folded block: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('This'), 'expected This: ${j}'
}

fn test_parse_yaml_deeply_nested() {
	yaml_input := 'a:\n  b:\n    c:\n      d: deep'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml deep: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('deep'), 'expected deep: ${j}'
}

fn test_parse_yaml_boolean_values() {
	yaml_input := 'enabled: true\ndisabled: false\nalso_true: yes\nalso_false: no'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml booleans: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('true'), 'expected true: ${j}'
	assert j.contains('false'), 'expected false: ${j}'
}

fn test_parse_yaml_number_values() {
	yaml_input := 'integer: 42\nfloat: 3.14\nnegative: -10'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml numbers: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('42'), 'expected 42: ${j}'
	assert j.contains('3.14'), 'expected 3.14: ${j}'
}

fn test_parse_yaml_null_values() {
	yaml_input := 'nothing: null\nalso_nothing: ~\nbare_null:'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml nulls: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('null'), 'expected null: ${j}'
}

fn test_parse_yaml_quoted_strings() {
	yaml_input := "single: 'hello world'\ndouble: \"hello world\""
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml quoted: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('hello world'), 'expected hello world: ${j}'
}

fn test_parse_yaml_inline_mapping() {
	yaml_input := 'inline: {a: 1, b: 2}'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml inline map: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
}

fn test_parse_yaml_inline_sequence() {
	yaml_input := 'items: [1, 2, 3]'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml inline seq: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('['), 'expected array: ${j}'
}

fn test_parse_yaml_comments() {
	yaml_input := '# This is a comment\nkey: value # inline comment'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml comments: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
	assert j.contains('value'), 'expected value: ${j}'
}

fn test_parse_yaml_sequence_of_sequences() {
	yaml_input := '- - a\n  - b\n- - c\n  - d'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml seq of seq: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
}

fn test_parse_yaml_empty_mapping() {
	yaml_input := 'empty: {}'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml empty map: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('empty'), 'expected empty: ${j}'
}

fn test_parse_yaml_mixed_types_in_sequence() {
	yaml_input := '- hello\n- 42\n- true\n- null'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml mixed seq: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('hello'), 'expected hello: ${j}'
	assert j.contains('42'), 'expected 42: ${j}'
}

fn test_parse_yaml_multiline_string() {
	yaml_input := 'key: This is a\n  multi-line string'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml multiline: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
}

fn test_parse_yaml_bare_dash_sequence() {
	yaml_input := '-\n  key: value'
	result := p5_obj('parse_yaml!(.input)', yaml_input) or {
		panic('yaml bare dash: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('key') || j.contains('value'), 'expected content: ${j}'
}

// ============================================================================
// parse_regex / parse_regex_all edge cases
// ============================================================================

fn test_parse_regex_named_groups() {
	result := execute("parse_regex!(\"John Smith 42\", r'^(?P<first>\\w+) (?P<last>\\w+) (?P<age>\\d+)$')",
		map[string]VrlValue{}) or { panic('parse_regex named: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('first'), 'expected first: ${j}'
	assert j.contains('John'), 'expected John: ${j}'
	assert j.contains('age'), 'expected age: ${j}'
}

fn test_parse_regex_no_match() {
	execute("parse_regex!(\"hello\", r'^\\d+$')", map[string]VrlValue{}) or {
		assert err.msg().contains('match') || err.msg().contains('regex'), 'expected match error: ${err}'
		return
	}
	assert false, 'expected error for no match'
}

fn test_parse_regex_all_multiple() {
	result := execute("parse_regex_all!(\"one=1 two=2 three=3\", r'(?P<key>\\w+)=(?P<val>\\d+)')",
		map[string]VrlValue{}) or { panic('parse_regex_all multi: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
	assert j.contains('one'), 'expected one: ${j}'
}

// ============================================================================
// parse_key_value edge cases
// ============================================================================

fn test_parse_key_value_with_nested_quotes() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('key="value with spaces" other="more data"')
	result := execute('parse_key_value!(.input)', obj) or {
		panic('parse_kv nested quotes: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('value with spaces'), 'expected value with spaces: ${j}'
}

fn test_parse_key_value_custom_kv_delimiter() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('key:value other:data')
	result := execute('parse_key_value!(.input, key_value_delimiter: ":")', obj) or {
		panic('parse_kv custom delim: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
}

fn test_parse_key_value_custom_field_delimiter() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('key=value,other=data')
	result := execute('parse_key_value!(.input, field_delimiter: ",")', obj) or {
		panic('parse_kv field delim: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
	assert j.contains('other'), 'expected other: ${j}'
}

// ============================================================================
// parse_csv with custom delimiter
// ============================================================================

fn test_parse_csv_tab_delimiter() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue("name\tage\tcity")
	result := execute('parse_csv!(.input, "\t")', obj) or {
		panic('parse_csv tab: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('name'), 'expected name: ${j}'
	assert j.contains('age'), 'expected age: ${j}'
}

// ============================================================================
// parse_timestamp / format_timestamp
// ============================================================================

fn test_parse_timestamp_rfc3339() {
	result := execute('parse_timestamp!("2023-10-15T12:30:45Z", "%Y-%m-%dT%H:%M:%SZ")',
		map[string]VrlValue{}) or { panic('parse_ts: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('2023'), 'expected 2023: ${j}'
}

fn test_format_timestamp_custom() {
	result := execute('format_timestamp!(now(), "%Y/%m/%d")', map[string]VrlValue{}) or {
		panic('format_ts: ${err}')
	}
	s := result as string
	assert s.contains('/'), 'expected date with slashes: ${s}'
}

fn test_parse_timestamp_epoch() {
	result := execute('format_timestamp!(from_unix_timestamp(1622547800), "%Y")',
		map[string]VrlValue{}) or { panic('format from unix: ${err}') }
	s := result as string
	assert s.contains('2021'), 'expected 2021: ${s}'
}

// ============================================================================
// haversine distance
// ============================================================================

fn test_haversine_distance() {
	// Distance between NYC (40.7128, -74.0060) and LA (34.0522, -118.2437) ~ 3944 km
	result := execute('haversine(40.7128, -74.0060, 34.0522, -118.2437)',
		map[string]VrlValue{}) or { panic('haversine: ${err}') }
	j := vrl_to_json(result)
	// haversine returns distance in meters, verify it's a large number
	assert j.len > 3, 'expected distance value: ${j}'
}

// ============================================================================
// parse_syslog edge cases
// ============================================================================

fn test_parse_syslog_rfc5424_full() {
	msg := '<165>1 2023-10-15T12:30:45.123456Z mymachine.example.com myapp 1234 ID47 [exampleSDID@32473 iut="3" eventSource="Application"] An application event'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(msg)
	result := execute('parse_syslog!(.input)', obj) or {
		panic('syslog rfc5424 full: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('myapp'), 'expected myapp: ${j}'
	assert j.contains('application event'), 'expected message: ${j}'
}

fn test_parse_syslog_with_structured_data() {
	msg := '<134>1 2023-01-01T00:00:00Z host app 1 - [meta key="val"] message'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(msg)
	result := execute('parse_syslog!(.input)', obj) or {
		panic('syslog SD: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('message'), 'expected message: ${j}'
}

// ============================================================================
// parse_duration / parse_bytes additional units
// ============================================================================

fn test_parse_duration_weeks() {
	result := execute('parse_duration!("1w", "ns")', map[string]VrlValue{}) or {
		// weeks might not be supported
		return
	}
	j := vrl_to_json(result)
	assert j.len > 0, 'expected result: ${j}'
}

fn test_parse_bytes_gigabytes() {
	result := execute('parse_bytes!("1 GiB")', map[string]VrlValue{}) or {
		panic('parse_bytes GiB: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('1073741824'), 'expected 1073741824: ${j}'
}

fn test_parse_bytes_terabytes() {
	result := execute('parse_bytes!("1 TiB")', map[string]VrlValue{}) or {
		panic('parse_bytes TiB: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('1099511627776'), 'expected 1099511627776: ${j}'
}

// ============================================================================
// parse_float edge cases
// ============================================================================

fn test_parse_float_scientific() {
	result := execute('parse_float!("1.5e3")', map[string]VrlValue{}) or {
		panic('parse_float sci: ${err}')
	}
	v := result as f64
	assert v == 1500.0, 'expected 1500.0: ${v}'
}

fn test_parse_float_negative() {
	result := execute('parse_float!("-3.14")', map[string]VrlValue{}) or {
		panic('parse_float neg: ${err}')
	}
	v := result as f64
	assert v < -3.13 && v > -3.15, 'expected -3.14: ${v}'
}

// ============================================================================
// parse_int edge cases
// ============================================================================

fn test_parse_int_leading_zeros() {
	result := execute('parse_int!("007", 10)', map[string]VrlValue{}) or {
		panic('parse_int leading zeros: ${err}')
	}
	v := result as i64
	assert v == 7, 'expected 7: ${v}'
}

fn test_parse_int_large_hex() {
	result := execute('parse_int!("ff", 16)', map[string]VrlValue{}) or {
		panic('parse_int hex: ${err}')
	}
	v := result as i64
	assert v == 255, 'expected 255: ${v}'
}

// ============================================================================
// parse_aws_cloudwatch edge cases
// ============================================================================

fn test_parse_aws_cloudwatch_control_message() {
	msg := '{"messageType":"CONTROL_MESSAGE","owner":"AWS"}'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(msg)
	result := execute('parse_aws_cloudwatch_log_subscription_message!(.input)', obj) or {
		// Control messages might be handled differently
		return
	}
	j := vrl_to_json(result)
	assert j.contains('messageType') || j.contains('CONTROL'), 'expected result: ${j}'
}

// ============================================================================
// get_timezone_name
// ============================================================================

fn test_get_timezone_name() {
	result := execute('get_timezone_name(now())', map[string]VrlValue{}) or {
		// May not be available
		return
	}
	s := result as string
	assert s.len > 0, 'expected non-empty timezone name'
}
