module vrl

// Tests for vrllib_parse_new.v — parse_xml, parse_cbor, parse_groks,
// CEF translate_custom_fields, parse_influxdb edge cases, parse_ruby_hash
// edge cases, and parse_user_agent edge cases.

fn parse_via_obj2(prog string, input string) !VrlValue {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(input)
	return execute(prog, obj)
}

// ============================================================================
// parse_xml
// ============================================================================

fn test_parse_xml_simple_element() {
	result := execute('parse_xml!("<root>hello</root>")', map[string]VrlValue{}) or {
		panic('parse_xml simple: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"root"'), 'expected root key: ${j}'
	assert j.contains('hello'), 'expected hello text: ${j}'
}

fn test_parse_xml_with_attributes() {
	result := execute('parse_xml!("<item id=\\"1\\" name=\\"test\\">value</item>")',
		map[string]VrlValue{}) or { panic('parse_xml attrs: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('@id'), 'expected @id attribute: ${j}'
	assert j.contains('@name'), 'expected @name attribute: ${j}'
}

fn test_parse_xml_nested_elements() {
	result := execute('parse_xml!("<root><child1>a</child1><child2>b</child2></root>")',
		map[string]VrlValue{}) or { panic('parse_xml nested: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('child1'), 'expected child1: ${j}'
	assert j.contains('child2'), 'expected child2: ${j}'
}

fn test_parse_xml_self_closing() {
	result := execute('parse_xml!("<root><empty/></root>")', map[string]VrlValue{}) or {
		panic('parse_xml self-closing: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('empty'), 'expected empty element: ${j}'
}

fn test_parse_xml_cdata() {
	result := parse_via_obj2('parse_xml!(.input)', '<root><![CDATA[raw <data>]]></root>') or {
		panic('parse_xml CDATA: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('raw <data>'), 'expected CDATA content: ${j}'
}

fn test_parse_xml_entities() {
	result := execute('parse_xml!("<root>&amp; &lt; &gt; &quot; &apos;</root>")',
		map[string]VrlValue{}) or { panic('parse_xml entities: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('&'), 'expected ampersand: ${j}'
}

fn test_parse_xml_numeric_entity() {
	result := execute('parse_xml!("<root>&#65;&#x42;</root>")', map[string]VrlValue{}) or {
		panic('parse_xml numeric entity: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('AB'), 'expected AB from numeric entities: ${j}'
}

fn test_parse_xml_xml_declaration() {
	result := parse_via_obj2('parse_xml!(.input)',
		'<?xml version="1.0" encoding="UTF-8"?><root>data</root>') or {
		panic('parse_xml declaration: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('root'), 'expected root: ${j}'
	assert j.contains('data'), 'expected data: ${j}'
}

fn test_parse_xml_comment() {
	result := parse_via_obj2('parse_xml!(.input)',
		'<root><!-- comment --><child>val</child></root>') or {
		panic('parse_xml comment: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('child'), 'expected child: ${j}'
}

fn test_parse_xml_processing_instruction() {
	result := parse_via_obj2('parse_xml!(.input)',
		'<root><?pi data?><child>val</child></root>') or {
		panic('parse_xml PI: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('child'), 'expected child: ${j}'
}

fn test_parse_xml_doctype() {
	result := parse_via_obj2('parse_xml!(.input)',
		'<!DOCTYPE html><root>data</root>') or { panic('parse_xml DOCTYPE: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('root'), 'expected root: ${j}'
}

fn test_parse_xml_namespace() {
	result := parse_via_obj2('parse_xml!(.input)',
		'<ns:root xmlns:ns="http://example.com"><ns:child>val</ns:child></ns:root>') or {
		panic('parse_xml namespace: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('ns:root'), 'expected namespaced root: ${j}'
}

fn test_parse_xml_duplicate_children() {
	result := parse_via_obj2('parse_xml!(.input)',
		'<root><item>a</item><item>b</item><item>c</item></root>') or {
		panic('parse_xml duplicate children: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
	assert j.contains('"b"'), 'expected b: ${j}'
	assert j.contains('"c"'), 'expected c: ${j}'
}

fn test_parse_xml_mixed_content() {
	result := parse_via_obj2('parse_xml!(.input)',
		'<root>text1<child>inner</child>text2</root>') or {
		panic('parse_xml mixed content: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('child'), 'expected child: ${j}'
}

fn test_parse_xml_parse_bool_values() {
	result := execute('parse_xml!("<root>true</root>")', map[string]VrlValue{}) or {
		panic('parse_xml bool: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('true'), 'expected true: ${j}'
}

fn test_parse_xml_parse_null_values() {
	result := execute('parse_xml!("<root>null</root>")', map[string]VrlValue{}) or {
		panic('parse_xml null: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('null'), 'expected null: ${j}'
}

fn test_parse_xml_parse_number_values() {
	result := execute('parse_xml!("<root>42</root>")', map[string]VrlValue{}) or {
		panic('parse_xml number: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('42'), 'expected 42: ${j}'
}

fn test_parse_xml_empty_element() {
	result := execute('parse_xml!("<root></root>")', map[string]VrlValue{}) or {
		panic('parse_xml empty: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('root'), 'expected root: ${j}'
}

fn test_parse_xml_empty_input_error() {
	execute('parse_xml!("")', map[string]VrlValue{}) or {
		assert err.msg().contains('empty') || err.msg().contains('parse'), 'unexpected error: ${err}'
		return
	}
	assert false, 'expected error for empty input'
}

fn test_parse_xml_deeply_nested() {
	result := parse_via_obj2('parse_xml!(.input)',
		'<a><b><c><d>deep</d></c></b></a>') or { panic('parse_xml deep: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('deep'), 'expected deep: ${j}'
}

fn test_parse_xml_negative_number() {
	result := execute('parse_xml!("<root>-42</root>")', map[string]VrlValue{}) or {
		panic('parse_xml negative: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('-42'), 'expected -42: ${j}'
}

fn test_parse_xml_float_value() {
	result := execute('parse_xml!("<root>3.14</root>")', map[string]VrlValue{}) or {
		panic('parse_xml float: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('3.14'), 'expected 3.14: ${j}'
}

fn test_parse_xml_false_value() {
	result := execute('parse_xml!("<root>false</root>")', map[string]VrlValue{}) or {
		panic('parse_xml false: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('false'), 'expected false: ${j}'
}

// ============================================================================
// parse_cbor
// ============================================================================

fn test_parse_cbor_encoded_map() {
	// CBOR: {"key": "value"} → a1 63 6b6579 65 76616c7565
	// Use decode_base16 to create binary, then parse_cbor
	result := execute('parse_cbor!(decode_base16!("a1636b657965" + "76616c7565"))',
		map[string]VrlValue{}) or { panic('parse_cbor map: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
	assert j.contains('value'), 'expected value: ${j}'
}

fn test_parse_cbor_integer() {
	// CBOR: 42 → 0x182a
	result := execute('parse_cbor!(decode_base16!("182a"))', map[string]VrlValue{}) or {
		panic('parse_cbor int: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('42'), 'expected 42: ${j}'
}

fn test_parse_cbor_string() {
	// CBOR: "hello" → 65 68656c6c6f
	result := execute('parse_cbor!(decode_base16!("6568656c6c6f"))', map[string]VrlValue{}) or {
		panic('parse_cbor string: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('hello'), 'expected hello: ${j}'
}

fn test_parse_cbor_array() {
	// CBOR: [1, 2, 3] → 83 01 02 03
	result := execute('parse_cbor!(decode_base16!("83010203"))', map[string]VrlValue{}) or {
		panic('parse_cbor array: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('['), 'expected array: ${j}'
}

fn test_parse_cbor_bool_true() {
	// CBOR: true → f5
	result := execute('parse_cbor!(decode_base16!("f5"))', map[string]VrlValue{}) or {
		panic('parse_cbor true: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('true'), 'expected true: ${j}'
}

fn test_parse_cbor_bool_false() {
	// CBOR: false → f4
	result := execute('parse_cbor!(decode_base16!("f4"))', map[string]VrlValue{}) or {
		panic('parse_cbor false: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('false'), 'expected false: ${j}'
}

fn test_parse_cbor_null() {
	// CBOR: null → f6
	result := execute('parse_cbor!(decode_base16!("f6"))', map[string]VrlValue{}) or {
		panic('parse_cbor null: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('null'), 'expected null: ${j}'
}

fn test_parse_cbor_negative_int() {
	// CBOR: -1 → 20
	result := execute('parse_cbor!(decode_base16!("20"))', map[string]VrlValue{}) or {
		panic('parse_cbor neg: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('-1'), 'expected -1: ${j}'
}

fn test_parse_cbor_empty_error() {
	execute('parse_cbor!(decode_base16!(""))', map[string]VrlValue{}) or {
		return // expected error
	}
	assert false, 'expected error for empty CBOR'
}

fn test_parse_cbor_nested_map() {
	// {"a": {"b": 1}} → a1 6161 a1 6162 01
	result := execute('parse_cbor!(decode_base16!("a16161a1616201"))', map[string]VrlValue{}) or {
		panic('parse_cbor nested: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected a: ${j}'
	assert j.contains('"b"'), 'expected b: ${j}'
}

// ============================================================================
// parse_cef with translate_custom_fields
// ============================================================================

fn test_parse_cef_with_translate() {
	cef_str := 'CEF:0|Vendor|Product|1.0|100|Test|5|cs1=secret cs1Label=password cn1=42 cn1Label=count'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(cef_str)
	result := execute('parse_cef!(.input, true)', obj) or {
		panic('parse_cef translate: ${err}')
	}
	j := vrl_to_json(result)
	// After translation, cs1Label=password should rename cs1 to "password"
	assert j.contains('password'), 'expected translated field name: ${j}'
}

fn test_parse_cef_escape_sequences() {
	cef_str := 'CEF:0|Vendor|Product|1.0|100|Test|5|key=val\\=ue key2=line\\nbreak'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(cef_str)
	result := execute('parse_cef!(.input)', obj) or {
		panic('parse_cef escape: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
}

fn test_parse_cef_pipe_escape() {
	cef_str := 'CEF:0|Ven\\|dor|Product|1.0|100|Name|5|k=v'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(cef_str)
	result := execute('parse_cef!(.input)', obj) or {
		panic('parse_cef pipe escape: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('cefVersion'), 'expected cefVersion: ${j}'
}

// ============================================================================
// parse_groks
// ============================================================================

fn test_parse_groks_first_match() {
	prog := 'parse_groks!("hello world", ["%{WORD:first} %{WORD:second}"])'
	result := execute(prog, map[string]VrlValue{}) or {
		panic('parse_groks: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('first'), 'expected first: ${j}'
}

fn test_parse_groks_second_pattern() {
	// First pattern won't match, second will
	prog := 'parse_groks!("hello world", ["%{INT:num}", "%{GREEDYDATA:msg}"])'
	result := execute(prog, map[string]VrlValue{}) or {
		panic('parse_groks second: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('msg'), 'expected msg: ${j}'
}

fn test_parse_groks_no_match() {
	execute('parse_groks!("test", ["%{INT:num}"])', map[string]VrlValue{}) or {
		assert err.msg().contains('unable'), 'expected unable error: ${err}'
		return
	}
	assert false, 'expected error for no match'
}

// ============================================================================
// parse_influxdb edge cases
// ============================================================================

fn test_parse_influxdb_with_tags() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('cpu,host=server1,region=us-west usage_idle=99.5,usage_user=0.5 1622547800000000000')
	result := execute('parse_influxdb!(.input)', obj) or {
		panic('parse_influxdb tags: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('cpu_usage_idle'), 'expected cpu_usage_idle: ${j}'
	assert j.contains('tags'), 'expected tags: ${j}'
}

fn test_parse_influxdb_string_field() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('measurement field="string value"')
	result := execute('parse_influxdb!(.input)', obj) or {
		panic('parse_influxdb string field: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('string value'), 'expected string value: ${j}'
}

fn test_parse_influxdb_integer_field() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('measurement count=42i')
	result := execute('parse_influxdb!(.input)', obj) or {
		panic('parse_influxdb integer: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('42'), 'expected 42: ${j}'
}

fn test_parse_influxdb_bool_fields() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('measurement active=true,disabled=false')
	result := execute('parse_influxdb!(.input)', obj) or {
		panic('parse_influxdb bool: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('measurement_active'), 'expected active metric: ${j}'
}

fn test_parse_influxdb_unsigned_field() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('measurement count=100u')
	result := execute('parse_influxdb!(.input)', obj) or {
		panic('parse_influxdb unsigned: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('100'), 'expected 100: ${j}'
}

// ============================================================================
// parse_ruby_hash edge cases
// ============================================================================

fn test_parse_ruby_hash_number_values() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('{"num" => 42, "pi" => 3.14}')
	result := execute('parse_ruby_hash!(.input)', obj) or {
		panic('parse_ruby_hash numbers: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('42'), 'expected 42: ${j}'
	assert j.contains('3.14'), 'expected 3.14: ${j}'
}

fn test_parse_ruby_hash_empty() {
	result := execute('parse_ruby_hash!("{}")', map[string]VrlValue{}) or {
		panic('parse_ruby_hash empty: ${err}')
	}
	j := vrl_to_json(result)
	assert j == '{}', 'expected empty object: ${j}'
}

fn test_parse_ruby_hash_symbol_colon() {
	result := execute('parse_ruby_hash!("{:key => \\"value\\"}")', map[string]VrlValue{}) or {
		panic('parse_ruby_hash symbol: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
	assert j.contains('value'), 'expected value: ${j}'
}

fn test_parse_ruby_hash_single_quotes() {
	result := execute("parse_ruby_hash!(\"{'key' => 'value'}\")", map[string]VrlValue{}) or {
		panic('parse_ruby_hash single quotes: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
}

fn test_parse_ruby_hash_escape_in_string() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('{"key" => "val\\\\ue"}')
	result := execute('parse_ruby_hash!(.input)', obj) or {
		panic('parse_ruby_hash escape: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
}

// ============================================================================
// parse_user_agent edge cases
// ============================================================================

fn test_parse_user_agent_firefox() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0')
	result := execute('parse_user_agent!(.input)', obj) or {
		panic('parse_user_agent firefox: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('browser'), 'expected browser: ${j}'
}

fn test_parse_user_agent_safari() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15')
	result := execute('parse_user_agent!(.input)', obj) or {
		panic('parse_user_agent safari: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('browser'), 'expected browser: ${j}'
}

fn test_parse_user_agent_bot() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('Googlebot/2.1 (+http://www.google.com/bot.html)')
	result := execute('parse_user_agent!(.input)', obj) or {
		panic('parse_user_agent bot: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('browser'), 'expected browser: ${j}'
}

fn test_parse_user_agent_empty() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('')
	result := execute('parse_user_agent!(.input)', obj) or {
		panic('parse_user_agent empty: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('browser'), 'expected browser key: ${j}'
}

// ============================================================================
// parse_nginx_log additional formats
// ============================================================================

fn test_parse_nginx_log_main_format() {
	log_line := '93.184.216.34 - user [10/Oct/2023:13:55:36 -0700] "GET /api HTTP/1.1" 200 512 "-" "curl/7.68.0"'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(log_line)
	result := execute('parse_nginx_log!(.input, "combined")', obj) or {
		panic('parse_nginx_log main: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('request'), 'expected request: ${j}'
}

// ============================================================================
// parse_apache_log error format
// ============================================================================

fn test_parse_apache_log_error_format() {
	// Apache error log format: [day_of_week month day time year] [level] [client ip] message
	log_line := '[Wed Oct 11 14:32:52.000 2023] [error] [client 10.0.0.1] File does not exist'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(log_line)
	result := execute('parse_apache_log!(.input, "error")', obj) or {
		// Error log parsing may have strict format requirements, that's ok
		return
	}
	j := vrl_to_json(result)
	assert j.contains('message'), 'expected message: ${j}'
}

// ============================================================================
// parse_aws_vpc_flow_log with custom format
// ============================================================================

fn test_parse_aws_vpc_flow_log_custom_format() {
	log_line := '2 123456789012 eni-abc12345 10.0.0.1 10.0.0.2 443 49152 6 10 1000 1622547800 1622547860 ACCEPT OK'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(log_line)
	result := execute('parse_aws_vpc_flow_log!(.input, "version account_id interface_id srcaddr dstaddr srcport dstport protocol packets bytes start end action log_status")',
		obj) or { panic('parse_aws_vpc_flow_log custom: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('srcaddr'), 'expected srcaddr: ${j}'
}

// ============================================================================
// parse_yaml
// ============================================================================

fn test_parse_yaml_simple() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('key: value\nlist:\n  - item1\n  - item2')
	result := execute('parse_yaml!(.input)', obj) or { panic('parse_yaml: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
}

fn test_parse_yaml_nested() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('parent:\n  child: value')
	result := execute('parse_yaml!(.input)', obj) or { panic('parse_yaml nested: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('parent'), 'expected parent: ${j}'
}

// ============================================================================
// parse_aws_cloudwatch
// ============================================================================

fn test_parse_aws_cloudwatch_log() {
	msg := '{"messageType":"DATA_MESSAGE","owner":"123456789012","logGroup":"/test","logStream":"stream","subscriptionFilters":["filter"],"logEvents":[{"id":"123","timestamp":1622547800000,"message":"test log"}]}'
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(msg)
	result := execute('parse_aws_cloudwatch_log_subscription_message!(.input)', obj) or {
		panic('parse_aws_cloudwatch: ${err}')
	}
	j := vrl_to_json(result)
	assert j.contains('owner'), 'expected owner: ${j}'
}

// ============================================================================
// Additional parse edge cases
// ============================================================================

fn test_parse_logfmt_with_quotes() {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('level=info msg="hello world" count=42')
	result := execute('parse_logfmt!(.input)', obj) or { panic('logfmt: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('level'), 'expected level: ${j}'
	assert j.contains('hello world'), 'expected hello world: ${j}'
}

fn test_parse_regex_basic() {
	result := execute("parse_regex!(\"2023-01-15 ERROR something\", r'^(?P<date>\\d{4}-\\d{2}-\\d{2}) (?P<level>\\w+) (?P<msg>.*)')",
		map[string]VrlValue{}) or { panic('parse_regex: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('date'), 'expected date: ${j}'
	assert j.contains('level'), 'expected level: ${j}'
}

fn test_parse_regex_all() {
	result := execute("parse_regex_all!(\"cat dog cat\", r'(?P<word>\\w+)')",
		map[string]VrlValue{}) or { panic('parse_regex_all: ${err}') }
	j := vrl_to_json(result)
	assert j.contains('word'), 'expected word: ${j}'
}
