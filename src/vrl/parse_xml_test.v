module vrl

// Tests for parse_xml — ported from upstream VRL conformance tests
// (upstream/vrl/src/stdlib/parse_xml.rs) plus additional test vectors
// exercising roxmltree feature parity: numeric character references,
// CDATA, namespaces, processing instructions, DOCTYPE, and edge cases.

// ---- helper ----

fn xml_parse_ok(input string, opts XmlParseOpts) VrlValue {
	return xml_parse(input, opts) or { panic('parse_xml failed: ${err.msg()}') }
}

fn xml_json(input string) string {
	v := xml_parse_ok(input, XmlParseOpts{})
	return vrl_to_json(v)
}

fn xml_json_opts(input string, opts XmlParseOpts) string {
	v := xml_parse_ok(input, opts)
	return vrl_to_json(v)
}

// ============================================================================
// Upstream VRL conformance tests  (18 test cases)
// ============================================================================

fn test_xml_simple_text() {
	assert xml_json('<a>test</a>') == '{"a":"test"}'
}

fn test_xml_include_attr() {
	assert xml_json('<a href="https://vector.dev">test</a>') == '{"a":{"@href":"https://vector.dev","text":"test"}}'
}

fn test_xml_exclude_attr() {
	r := xml_json_opts('<a href="https://vector.dev">test</a>', XmlParseOpts{
		include_attr: false
	})
	assert r == '{"a":"test"}'
}

fn test_xml_custom_text_key() {
	r := xml_json_opts('<b>test</b>', XmlParseOpts{
		text_key: 'node'
		always_use_text_key: true
	})
	assert r == '{"b":{"node":"test"}}'
}

fn test_xml_include_attributes_if_single_node() {
	r := xml_json('<root><node attr="value"><message>foo</message></node></root>')
	assert r == '{"root":{"node":{"@attr":"value","message":"foo"}}}'
}

fn test_xml_include_attributes_multiple_children() {
	r := xml_json('<root><node attr="value"><message>bar</message></node><node attr="value"><message>baz</message></node></root>')
	assert r == '{"root":{"node":[{"@attr":"value","message":"bar"},{"@attr":"value","message":"baz"}]}}'
}

fn test_xml_nested_object() {
	r := xml_json('<a attr="value"><b>one</b><c>two</c></a>')
	assert r == '{"a":{"@attr":"value","b":"one","c":"two"}}'
}

fn test_xml_nested_object_array() {
	assert xml_json('<a><b>one</b><b>two</b></a>') == '{"a":{"b":["one","two"]}}'
}

fn test_xml_header_and_comments() {
	input := '<?xml version="1.0" encoding="ISO-8859-1"?>
<!-- Example found somewhere in the deep depths of the web -->
<note>
    <to>Tove</to>
    <!-- Randomly inserted inner comment -->
    <from>Jani</from>
    <heading>Reminder</heading>
    <body>Don\'t forget me this weekend!</body>
</note>

<!-- Could literally be placed anywhere -->'
	r := xml_json(input)
	assert r == '{"note":{"body":"Don\'t forget me this weekend!","from":"Jani","heading":"Reminder","to":"Tove"}}'
}

fn test_xml_header_inside_element() {
	// PI inside element counts as child for flattening decision,
	// so text is wrapped in text_key instead of flattened.
	r := xml_json('<p><?xml?>text123</p>')
	assert r == '{"p":{"text":"text123"}}'
}

fn test_xml_mixed_types() {
	input := '<?xml version="1.0" encoding="ISO-8859-1"?>
<!-- Mixed types -->
<data>
    <!-- Booleans -->
    <item>true</item>
    <item>false</item>
    <!-- String -->
    <item>string!</item>
    <!-- Empty object -->
    <item />
    <!-- Literal value "null" -->
    <item>null</item>
    <!-- Integer -->
    <item>1</item>
    <!-- Float -->
    <item>1.0</item>
</data>'
	r := xml_json(input)
	assert r == '{"data":{"item":[true,false,"string!",{},null,1,1.0]}}'
}

fn test_xml_just_strings() {
	input := '<?xml version="1.0" encoding="ISO-8859-1"?>
<data>
    <item>true</item>
    <item>false</item>
    <item>string!</item>
    <item />
    <item>null</item>
    <item>1</item>
    <item>1.0</item>
</data>'
	r := xml_json_opts(input, XmlParseOpts{
		parse_null: false
		parse_bool: false
		parse_number: false
	})
	assert r == '{"data":{"item":["true","false","string!",{},"null","1","1.0"]}}'
}

fn test_xml_untrimmed() {
	r := xml_json_opts('<root>  <a>test</a>  </root>', XmlParseOpts{ trim: false })
	assert r == '{"root":{"a":"test","text":["  ","  "]}}'
}

fn test_xml_invalid_token() {
	xml_parse('true', XmlParseOpts{}) or {
		assert err.msg() == 'unable to parse xml: unknown token at 1:1'
		return
	}
	panic('expected error')
}

fn test_xml_flat_parent_property() {
	input := '<?xml version="1.0" encoding="UTF-8"?>
<MY_XML>
  <property1>
    <property1_a>a</property1_a>
    <property1_b>b</property1_b>
    <property1_c>c</property1_c>
  </property1>
  <property2>
    <property2_object>
      <property2a_a>a</property2a_a>
      <property2a_b>b</property2a_b>
      <property2a_c>c</property2a_c>
    </property2_object>
  </property2>
</MY_XML>'
	r := xml_json(input)
	assert r == '{"MY_XML":{"property1":{"property1_a":"a","property1_b":"b","property1_c":"c"},"property2":{"property2_object":{"property2a_a":"a","property2a_b":"b","property2a_c":"c"}}}}'
}

fn test_xml_nested_parent_property() {
	input := '<?xml version="1.0" encoding="UTF-8"?>
<MY_XML>
  <property1>
    <property1_a>a</property1_a>
    <property1_b>b</property1_b>
    <property1_c>c</property1_c>
  </property1>
  <property2>
    <property2_object>
      <property2a_a>a</property2a_a>
      <property2a_b>b</property2a_b>
      <property2a_c>c</property2a_c>
    </property2_object>
    <property2_object>
      <property2a_a>a</property2a_a>
      <property2a_b>b</property2a_b>
      <property2a_c>c</property2a_c>
    </property2_object>
  </property2>
</MY_XML>'
	r := xml_json(input)
	assert r == '{"MY_XML":{"property1":{"property1_a":"a","property1_b":"b","property1_c":"c"},"property2":{"property2_object":[{"property2a_a":"a","property2a_b":"b","property2a_c":"c"},{"property2a_a":"a","property2a_b":"b","property2a_c":"c"}]}}}'
}

fn test_xml_if_no_sibling() {
	assert xml_json('<root><a>test</a></root>') == '{"root":{"a":"test"}}'
}

fn test_xml_if_no_sibling2() {
	r := xml_json('<root><a><a1>test</a1></a><b>test2</b></root>')
	assert r == '{"root":{"a":{"a1":"test"},"b":"test2"}}'
}

// ============================================================================
// Upstream documentation example
// ============================================================================

fn test_xml_book_example() {
	input := '<book category="CHILDREN"><title lang="en">Harry Potter</title><author>J K. Rowling</author><year>2005</year></book>'
	r := xml_json_opts(input, XmlParseOpts{ parse_number: false })
	assert r == '{"book":{"@category":"CHILDREN","author":"J K. Rowling","title":{"@lang":"en","text":"Harry Potter"},"year":"2005"}}'
}

// ============================================================================
// Numeric character references  (roxmltree feature)
// ============================================================================

fn test_xml_numeric_decimal_entity() {
	// &#65; = 'A'
	assert xml_json('<x>&#65;</x>') == '{"x":"A"}'
}

fn test_xml_numeric_hex_entity() {
	// &#x41; = 'A'
	assert xml_json('<x>&#x41;</x>') == '{"x":"A"}'
}

fn test_xml_numeric_entity_multibyte() {
	// &#x00E9; = 'é'  (U+00E9, 2-byte UTF-8)
	assert xml_json('<x>caf&#xe9;</x>') == '{"x":"café"}'
}

fn test_xml_numeric_entity_3byte() {
	// &#x20AC; = '€'  (U+20AC, 3-byte UTF-8)
	assert xml_json('<x>&#x20AC;</x>') == '{"x":"€"}'
}

fn test_xml_numeric_entity_4byte() {
	// &#x1F600; = '😀'  (U+1F600, 4-byte UTF-8)
	assert xml_json('<x>&#x1F600;</x>') == '{"x":"😀"}'
}

fn test_xml_predefined_entities() {
	assert xml_json('<x>&amp; &lt; &gt; &quot; &apos;</x>') == '{"x":"& < > \\" \'"}'
}

fn test_xml_entity_in_attribute() {
	r := xml_json('<x a="1&amp;2">text</x>')
	assert r == '{"x":{"@a":"1&2","text":"text"}}'
}

fn test_xml_numeric_entity_in_attribute() {
	r := xml_json('<x a="&#65;B">text</x>')
	assert r == '{"x":{"@a":"AB","text":"text"}}'
}

// ============================================================================
// CDATA sections  (roxmltree feature)
// ============================================================================

fn test_xml_cdata_simple() {
	assert xml_json('<x><![CDATA[hello world]]></x>') == '{"x":"hello world"}'
}

fn test_xml_cdata_with_special_chars() {
	assert xml_json('<x><![CDATA[<b>not & tags</b>]]></x>') == '{"x":"<b>not & tags</b>"}'
}

fn test_xml_cdata_mixed_with_text() {
	// CDATA + text = two text children → array under text_key
	// Actually in upstream (roxmltree), CDATA is merged into text nodes.
	// If there's only a CDATA section, it becomes a single text child.
	assert xml_json('<x>pre<![CDATA[ mid ]]>post</x>') == '{"x":{"text":["pre"," mid ","post"]}}'
}

// ============================================================================
// Namespace support  (roxmltree feature — preserved as prefix in tag name)
// ============================================================================

fn test_xml_namespace_prefix_in_tag() {
	r := xml_json('<ns:root><ns:child>val</ns:child></ns:root>')
	assert r == '{"ns:root":{"ns:child":"val"}}'
}

fn test_xml_namespace_decl_as_attribute() {
	r := xml_json('<root xmlns:ns="http://example.com"><ns:child>val</ns:child></root>')
	assert r == '{"root":{"@xmlns:ns":"http://example.com","ns:child":"val"}}'
}

// ============================================================================
// Processing instructions  (roxmltree feature — silently discarded)
// ============================================================================

fn test_xml_pi_at_top_level() {
	// PIs before root element should be skipped
	r := xml_json('<?xml-stylesheet type="text/xsl" href="style.xsl"?><root>val</root>')
	assert r == '{"root":"val"}'
}

fn test_xml_pi_inside_element_with_child() {
	// PI counts as child for flattening, but doesn't appear in output
	r := xml_json('<root><?pi data?><child>val</child></root>')
	assert r == '{"root":{"child":"val"}}'
}

fn test_xml_multiple_pis() {
	r := xml_json('<?xml version="1.0"?><?pi1?><?pi2?><root>val</root>')
	assert r == '{"root":"val"}'
}

// ============================================================================
// DOCTYPE handling  (roxmltree feature — skipped)
// ============================================================================

fn test_xml_doctype_simple() {
	r := xml_json('<!DOCTYPE note SYSTEM "note.dtd"><note>hello</note>')
	assert r == '{"note":"hello"}'
}

fn test_xml_doctype_with_internal_subset() {
	input := '<!DOCTYPE note [
  <!ELEMENT note (#PCDATA)>
  <!ENTITY greeting "Hello">
]>
<note>world</note>'
	r := xml_json(input)
	assert r == '{"note":"world"}'
}

fn test_xml_doctype_after_xml_decl() {
	input := '<?xml version="1.0"?>
<!DOCTYPE root SYSTEM "root.dtd">
<root>val</root>'
	r := xml_json(input)
	assert r == '{"root":"val"}'
}

// ============================================================================
// Empty elements  (should produce {} not null)
// ============================================================================

fn test_xml_empty_self_closing() {
	assert xml_json('<root><item/></root>') == '{"root":{"item":{}}}'
}

fn test_xml_empty_explicit_close() {
	assert xml_json('<root><item></item></root>') == '{"root":{"item":{}}}'
}

fn test_xml_empty_root() {
	assert xml_json('<root/>') == '{"root":{}}'
}

fn test_xml_empty_with_attr() {
	r := xml_json('<item key="val"/>')
	assert r == '{"item":{"@key":"val"}}'
}

// ============================================================================
// Whitespace & trim behaviour
// ============================================================================

fn test_xml_trim_removes_inter_tag_whitespace() {
	// With trim=true (default), whitespace between tags is collapsed
	r := xml_json('<root>  <a>x</a>  <b>y</b>  </root>')
	assert r == '{"root":{"a":"x","b":"y"}}'
}

fn test_xml_untrim_preserves_whitespace_text() {
	r := xml_json_opts('<a>  hello  </a>', XmlParseOpts{ trim: false })
	assert r == '{"a":"  hello  "}'
}

fn test_xml_trim_preserves_inner_text_whitespace() {
	// Whitespace within text content (not between tags) is preserved
	r := xml_json('<a>hello   world</a>')
	assert r == '{"a":"hello   world"}'
}

// ============================================================================
// Comments  (silently discarded — roxmltree counts them as children)
// ============================================================================

fn test_xml_comment_only_child() {
	// Comment as only child → counts as 1 child, recurse returns empty object
	r := xml_json('<root><!-- comment --></root>')
	assert r == '{"root":{}}'
}

fn test_xml_comment_with_text() {
	// Comment + text = 2 children → recurse → text under text_key
	r := xml_json('<root><!-- comment -->hello</root>')
	assert r == '{"root":{"text":"hello"}}'
}

fn test_xml_comment_between_elements() {
	r := xml_json('<root><a>1</a><!-- comment --><b>2</b></root>')
	assert r == '{"root":{"a":1,"b":2}}'
}

// ============================================================================
// Attribute handling edge cases
// ============================================================================

fn test_xml_single_quoted_attribute() {
	r := xml_json("<x a='val'>text</x>")
	assert r == '{"x":{"@a":"val","text":"text"}}'
}

fn test_xml_multiple_attributes() {
	r := xml_json('<x a="1" b="2" c="3">text</x>')
	assert r == '{"x":{"@a":"1","@b":"2","@c":"3","text":"text"}}'
}

fn test_xml_custom_attr_prefix() {
	r := xml_json_opts('<x a="1">text</x>', XmlParseOpts{ attr_prefix: '_' })
	assert r == '{"x":{"_a":"1","text":"text"}}'
}

fn test_xml_attr_values_are_strings() {
	// Attribute values should NOT be parsed as scalars — always strings.
	// Even "true", "123", "null" stay as strings in attributes.
	r := xml_json('<x bool="true" num="42" nil="null">t</x>')
	assert r == '{"x":{"@bool":"true","@nil":"null","@num":"42","text":"t"}}'
}

// ============================================================================
// Error handling
// ============================================================================

fn test_xml_empty_input() {
	xml_parse('', XmlParseOpts{}) or {
		assert err.msg().contains('empty input')
		return
	}
	panic('expected error')
}

fn test_xml_whitespace_only_input() {
	xml_parse('   \n  ', XmlParseOpts{}) or {
		assert err.msg().contains('empty input')
		return
	}
	panic('expected error')
}

fn test_xml_unterminated_comment() {
	xml_parse('<root><!-- oops</root>', XmlParseOpts{}) or {
		assert err.msg().contains('unterminated comment')
		return
	}
	panic('expected error')
}

fn test_xml_unterminated_cdata() {
	xml_parse('<root><![CDATA[oops</root>', XmlParseOpts{}) or {
		assert err.msg().contains('unterminated CDATA')
		return
	}
	panic('expected error')
}

fn test_xml_unterminated_pi() {
	xml_parse('<?oops', XmlParseOpts{}) or {
		assert err.msg().contains('unterminated processing instruction')
		return
	}
	panic('expected error')
}

// ============================================================================
// Scalar parsing edge cases
// ============================================================================

fn test_xml_negative_integer() {
	assert xml_json('<x>-42</x>') == '{"x":-42}'
}

fn test_xml_float_scientific() {
	assert xml_json('<x>1.5e2</x>') == '{"x":150.0}'
}

fn test_xml_zero() {
	assert xml_json('<x>0</x>') == '{"x":0}'
}

fn test_xml_text_not_number() {
	assert xml_json('<x>abc123</x>') == '{"x":"abc123"}'
}

fn test_xml_parse_null_off() {
	r := xml_json_opts('<x>null</x>', XmlParseOpts{ parse_null: false })
	assert r == '{"x":"null"}'
}

fn test_xml_parse_bool_off() {
	r := xml_json_opts('<x>true</x>', XmlParseOpts{ parse_bool: false })
	assert r == '{"x":"true"}'
}

// ============================================================================
// Deeply nested structures
// ============================================================================

fn test_xml_deep_nesting() {
	assert xml_json('<a><b><c><d>deep</d></c></b></a>') == '{"a":{"b":{"c":{"d":"deep"}}}}'
}

fn test_xml_mixed_nesting_and_arrays() {
	r := xml_json('<root><a><x>1</x><x>2</x></a><a><x>3</x></a></root>')
	assert r == '{"root":{"a":[{"x":[1,2]},{"x":3}]}}'
}

// ============================================================================
// Adapted from libexpat test vectors (MIT license)
// Only tests exercising logic present in roxmltree — no DOM manipulation,
// no DTD validation, no external entity resolution.
// ============================================================================

fn test_expat_basic_element() {
	assert xml_json('<root/>') == '{"root":{}}'
}

fn test_expat_element_with_text() {
	assert xml_json('<doc>Hello, world!</doc>') == '{"doc":"Hello, world!"}'
}

fn test_expat_nested_elements() {
	assert xml_json('<doc><inner/>inner text</doc>') == '{"doc":{"inner":{},"text":"inner text"}}'
}

fn test_expat_attribute_order() {
	// Multiple attributes should all be included
	r := xml_json('<e a="1" b="2" c="3"/>')
	assert r == '{"e":{"@a":"1","@b":"2","@c":"3"}}'
}

fn test_expat_empty_attribute() {
	r := xml_json('<e attr="">text</e>')
	assert r == '{"e":{"@attr":"","text":"text"}}'
}

fn test_expat_predefined_entities_in_text() {
	r := xml_json('<e>&lt;&amp;&gt;</e>')
	assert r == '{"e":"<&>"}'
}

fn test_expat_predefined_entities_in_attr() {
	r := xml_json('<e a="&lt;&amp;&gt;">t</e>')
	assert r == '{"e":{"@a":"<&>","text":"t"}}'
}

fn test_expat_numeric_char_ref_decimal() {
	// &#97; = 'a'
	assert xml_json('<e>&#97;&#98;&#99;</e>') == '{"e":"abc"}'
}

fn test_expat_numeric_char_ref_hex() {
	// &#x61; = 'a', &#x62; = 'b'
	assert xml_json('<e>&#x61;&#x62;</e>') == '{"e":"ab"}'
}

fn test_expat_mixed_entities() {
	// Mix of predefined, decimal, and hex references
	r := xml_json('<e>&amp;&#65;&#x42;</e>')
	assert r == '{"e":"&AB"}'
}

fn test_expat_cdata_basic() {
	assert xml_json('<e><![CDATA[text]]></e>') == '{"e":"text"}'
}

fn test_expat_cdata_with_angle_brackets() {
	assert xml_json('<e><![CDATA[<not>a</tag>]]></e>') == '{"e":"<not>a</tag>"}'
}

fn test_expat_cdata_with_ampersand() {
	assert xml_json('<e><![CDATA[a&b]]></e>') == '{"e":"a&b"}'
}

fn test_expat_comment_ignored() {
	assert xml_json('<e><!-- hidden -->visible</e>') == '{"e":{"text":"visible"}}'
}

fn test_expat_pi_ignored() {
	assert xml_json('<e><?target data?>visible</e>') == '{"e":{"text":"visible"}}'
}

fn test_expat_self_closing() {
	assert xml_json('<doc><br/></doc>') == '{"doc":{"br":{}}}'
}

fn test_expat_whitespace_in_tags() {
	// Whitespace in tag/attribute syntax
	r := xml_json('<e   a = "v"  >text</e>')
	assert r == '{"e":{"@a":"v","text":"text"}}'
}

fn test_expat_newlines_in_content() {
	r := xml_json_opts("<e>line1\nline2</e>", XmlParseOpts{ trim: false })
	assert r == '{"e":"line1\\nline2"}'
}

fn test_expat_tab_in_content() {
	r := xml_json_opts("<e>col1\tcol2</e>", XmlParseOpts{ trim: false })
	assert r == '{"e":"col1\\tcol2"}'
}

fn test_expat_sibling_duplicates() {
	// Multiple siblings with same name become array
	r := xml_json('<root><item>a</item><item>b</item><item>c</item></root>')
	assert r == '{"root":{"item":["a","b","c"]}}'
}

fn test_expat_deeply_nested_attrs() {
	r := xml_json('<a x="1"><b y="2"><c z="3">val</c></b></a>')
	assert r == '{"a":{"@x":"1","b":{"@y":"2","c":{"@z":"3","text":"val"}}}}'
}

fn test_expat_unicode_text() {
	assert xml_json('<e>日本語テスト</e>') == '{"e":"日本語テスト"}'
}

fn test_expat_unicode_attribute() {
	r := xml_json('<e name="Ünïcödé">t</e>')
	assert r == '{"e":{"@name":"Ünïcödé","text":"t"}}'
}

fn test_expat_large_decimal_char_ref() {
	// &#8364; = '€'  (U+20AC)
	assert xml_json('<e>&#8364;</e>') == '{"e":"€"}'
}

fn test_expat_xml_decl_ignored() {
	assert xml_json('<?xml version="1.0" encoding="UTF-8"?><r>ok</r>') == '{"r":"ok"}'
}

fn test_expat_multiple_text_nodes_untrimmed() {
	// With trim=false, whitespace text nodes around elements are preserved
	r := xml_json_opts('<r> <a>x</a> <b>y</b> </r>', XmlParseOpts{ trim: false })
	// Three whitespace text nodes: before <a>, between </a> and <b>, after </b>
	assert r == '{"r":{"a":"x","b":"y","text":[" "," "," "]}}'
}

fn test_expat_empty_element_in_array() {
	// Mix of empty and non-empty siblings
	r := xml_json('<r><x/><x>val</x><x/></r>')
	assert r == '{"r":{"x":[{},"val",{}]}}'
}

fn test_expat_cdata_empty() {
	// Empty CDATA produces empty string text node; with parse_null=true (default),
	// empty string → null, matching upstream roxmltree+VRL behavior.
	assert xml_json('<e><![CDATA[]]></e>') == '{"e":null}'
}
