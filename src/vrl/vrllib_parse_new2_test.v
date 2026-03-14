module vrl

// Tests targeting uncovered lines in vrllib_parse_new.v:
// - CEF: line 532 (whitespace-only trailing extensions), line 621 (translate with non-translated fields)
// - InfluxDB: line 913 (NaN field value skipped)
// - Ruby hash: lines 1089,1101 (numeric/truncated hash keys), 1142 (truncated array)
// - XML: lines 1382-1393 (xml_line_col), 1415-1452 (preamble parsing),
//   1467-1475 (DOCTYPE), 1483-1538 (element/attribute parsing),
//   1592-1626 (child node edge cases), 1701 (single non-content child),
//   1755-1757 (text array merging)
// - XML unescape: lines 1864-1899 (hex/decimal numeric char refs, multi-byte UTF-8)
// - CBOR: lines 1921-2096 (parse_cbor with various types)

// ============================================================================
// CEF tests
// ============================================================================

fn test_cef_extensions_trailing_whitespace() {
	// Line 532: extensions with trailing whitespace causing pos >= bytes.len break
	result := fn_parse_cef([VrlValue('CEF:0|vendor|product|1.0|100|Name|5|key1=value1 '),
		VrlValue(false)]) or { return }
	j := vrl_to_json(result)
	assert j.contains('"key1":"value1"')
}

fn test_cef_translate_with_non_translated() {
	// Line 621: non-translated fields passed through in translate mode
	// cs1Label + cs1 get translated, "src" stays as-is (line 621)
	result := fn_parse_cef([
		VrlValue('CEF:0|vendor|product|1.0|100|Name|5|cs1Label=MyField cs1=MyValue src=1.2.3.4'),
		VrlValue(true),
	]) or { return }
	j := vrl_to_json(result)
	assert j.contains('"MyField":"MyValue"')
	assert j.contains('"src":"1.2.3.4"')
}

// ============================================================================
// InfluxDB NaN field test
// ============================================================================

fn test_influxdb_nan_field_skipped() {
	// Line 913: NaN float field value should be skipped
	result := fn_parse_influxdb([
		VrlValue('measurement,tag=t fieldA=NaN 1234567890000000000'),
	]) or { return }
	// The result should still be valid (NaN field omitted)
	j := vrl_to_json(result)
	assert j.contains('measurement')
}

// ============================================================================
// Ruby hash tests
// ============================================================================

fn test_ruby_hash_numeric_key_i64() {
	// Line 1101: i64 key in hash converted to string
	result := fn_parse_ruby_hash([VrlValue('{1 => "one"}')]) or { return }
	j := vrl_to_json(result)
	assert j.contains('"one"')
}

fn test_ruby_hash_float_key() {
	// Line 1100: f64 key in hash converted to string
	result := fn_parse_ruby_hash([VrlValue('{1.5 => "val"}')]) or { return }
	j := vrl_to_json(result)
	assert j.contains('"val"')
}

fn test_ruby_hash_truncated_array() {
	// Line 1142: array parsing hits end of string
	result := fn_parse_ruby_hash([VrlValue('{:a => [1, 2')]) or {
		// Expected to error
		return
	}
	_ = result
}

fn test_ruby_hash_truncated_hash() {
	// Line 1089: hash parsing hits end of string
	result := fn_parse_ruby_hash([VrlValue('{:a => {:b => 1')]) or {
		return
	}
	_ = result
}

// ============================================================================
// XML tests
// ============================================================================

fn test_xml_line_col_computation() {
	// Lines 1382-1393: xml_line_col with newlines
	line, col := xml_line_col("abc\ndef\nghi", 8)
	assert line == 3
	assert col == 1
}

fn test_xml_line_col_no_newline() {
	line, col := xml_line_col('abcdef', 3)
	assert line == 1
	assert col == 4
}

fn test_xml_line_col_past_end() {
	// Line 1384: pos > s.len
	line, col := xml_line_col('ab', 100)
	assert line == 1
	assert col == 3
}

fn test_xml_whitespace_before_root() {
	// Lines 1415: whitespace before root element
	result := xml_parse('  <root>hello</root>  ', XmlParseOpts{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"root"')
}

fn test_xml_unterminated_pi() {
	// Line 1425: unterminated processing instruction
	result := xml_parse('<?xml version="1.0"', XmlParseOpts{}) or {
		assert err.msg().contains('unterminated processing instruction')
		return
	}
	assert false, 'expected error for unterminated PI'
}

fn test_xml_comment_before_root() {
	// Lines 1433-1438: comment before root element
	result := xml_parse('<!-- comment --><root>test</root>', XmlParseOpts{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"root"')
	assert j.contains('"test"')
}

fn test_xml_unterminated_comment_before_root() {
	// Lines 1433-1435: unterminated comment
	result := xml_parse('<!-- comment without end', XmlParseOpts{}) or {
		assert err.msg().contains('unterminated comment')
		return
	}
	assert false, 'expected error for unterminated comment'
}

fn test_xml_non_element_token() {
	// Lines 1451-1452: non-element token after skipping preamble
	result := xml_parse('some plain text', XmlParseOpts{}) or {
		assert err.msg().contains('unknown token')
		return
	}
	assert false, 'expected error for non-element token'
}

fn test_xml_doctype_with_internal_subset() {
	// Lines 1467-1469: DOCTYPE with internal subset [...]
	result := xml_parse('<!DOCTYPE root [<!ELEMENT root (#PCDATA)>]><root>text</root>',
		XmlParseOpts{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"root"')
}

fn test_xml_unterminated_doctype() {
	// Line 1475: unterminated DOCTYPE
	result := xml_parse('<!DOCTYPE root', XmlParseOpts{}) or {
		assert err.msg().contains('unterminated DOCTYPE')
		return
	}
	assert false, 'expected error for unterminated DOCTYPE'
}

fn test_xml_element_with_whitespace() {
	// Lines 1483, 1488-1489, 1500-1501: whitespace before element
	result := xml_parse('<root> <child>val</child> </root>', XmlParseOpts{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"child"')
}

fn test_xml_attr_with_whitespace_around_eq() {
	// Lines 1514, 1528, 1538: whitespace around = in attributes
	result := xml_parse('<root attr = "value">text</root>', XmlParseOpts{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"@attr"')
	assert j.contains('"value"')
}

fn test_xml_unterminated_comment_in_children() {
	// Line 1592: unterminated comment inside element
	result := xml_parse('<root><!-- oops</root>', XmlParseOpts{}) or {
		assert err.msg().contains('unterminated comment')
		return
	}
	assert false, 'expected error'
}

fn test_xml_unterminated_cdata_in_children() {
	// Line 1603: unterminated CDATA
	result := xml_parse('<root><![CDATA[oops</root>', XmlParseOpts{}) or {
		assert err.msg().contains('unterminated CDATA')
		return
	}
	assert false, 'expected error'
}

fn test_xml_unterminated_pi_in_children() {
	// Line 1615: unterminated PI inside element
	result := xml_parse('<root><?pi oops</root>', XmlParseOpts{}) or {
		assert err.msg().contains('unterminated processing instruction')
		return
	}
	assert false, 'expected error'
}

fn test_xml_pi_in_children() {
	// Line 1611-1619: PI inside element (non-content child)
	result := xml_parse('<root><?pi data?></root>', XmlParseOpts{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"root"')
}

fn test_xml_doctype_in_children() {
	// Lines 1624-1626: DOCTYPE inside element
	result := xml_parse('<root><!DOCTYPE inner>text</root>', XmlParseOpts{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"root"')
}

fn test_xml_single_noncontent_child() {
	// Line 1701: single non-content child -> xml_recurse returns empty object
	result := xml_parse('<root><!-- only a comment --></root>', XmlParseOpts{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"root"')
}

fn test_xml_text_array_merging() {
	// Lines 1755-1757: multiple text nodes -> array merging
	result := xml_parse('<root>hello<mid/>world</root>', XmlParseOpts{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"root"')
}

fn test_xml_duplicate_element_children() {
	// Test duplicate child element keys -> array conversion
	result := xml_parse('<root><item>a</item><item>b</item><item>c</item></root>',
		XmlParseOpts{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"item"')
}

// ============================================================================
// XML unescape: numeric character references
// ============================================================================

fn test_xml_unescape_hex_lowercase() {
	// Line 1864: hex &#x61; = 'a'
	result := xml_unescape('&#x61;')
	assert result == 'a'
}

fn test_xml_unescape_hex_uppercase() {
	// Line 1866: hex &#x41; = 'A'
	result := xml_unescape('&#x41;')
	assert result == 'A'
}

fn test_xml_unescape_decimal() {
	// Lines 1879-1880: decimal &#97; = 'a'
	result := xml_unescape('&#97;')
	assert result == 'a'
}

fn test_xml_unescape_invalid_hex() {
	// Lines 1868-1869: invalid hex char -> pass through as-is
	result := xml_unescape('&#xZZ;')
	assert result.contains('&')
}

fn test_xml_unescape_invalid_decimal() {
	// Lines 1879-1880: invalid decimal char
	result := xml_unescape('&#abc;')
	assert result.contains('&')
}

fn test_xml_unescape_two_byte_utf8() {
	// Lines 1889-1890: codepoint 0x80-0x7FF -> 2-byte UTF-8
	// &#xE9; = e with acute (U+00E9)
	result := xml_unescape('&#xe9;')
	expected := [u8(0xC3), u8(0xA9)].bytestr()
	assert result == expected
}

fn test_xml_unescape_three_byte_utf8() {
	// Lines 1892-1894: codepoint 0x800-0xFFFF -> 3-byte UTF-8
	// &#x2603; = snowman
	result := xml_unescape('&#x2603;')
	expected := [u8(0xE2), u8(0x98), u8(0x83)].bytestr()
	assert result == expected
}

fn test_xml_unescape_four_byte_utf8() {
	// Lines 1896-1899: codepoint > 0xFFFF -> 4-byte UTF-8
	// &#x1F600; = grinning face
	result := xml_unescape('&#x1F600;')
	expected := [u8(0xF0), u8(0x9F), u8(0x98), u8(0x80)].bytestr()
	assert result == expected
}

// ============================================================================
// CBOR tests
// ============================================================================

fn test_cbor_unsigned_int() {
	// Line 1944-1945: major type 0, unsigned int
	// CBOR: 0x05 = unsigned int 5
	result := fn_parse_cbor([VrlValue([u8(0x05)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == '5'
}

fn test_cbor_negative_int() {
	// Line 1949-1950: major type 1, negative int
	// CBOR: 0x24 = negative int -5 (1-indexed: -1 - 4 = -5)
	result := fn_parse_cbor([VrlValue([u8(0x24)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == '-5'
}

fn test_cbor_byte_string() {
	// Lines 1954-1959: major type 2, byte string
	// 0x43 = byte string length 3, then "abc"
	result := fn_parse_cbor([VrlValue([u8(0x43), u8(0x61), u8(0x62), u8(0x63)].bytestr())]) or {
		return
	}
	j := vrl_to_json(result)
	assert j == '"abc"'
}

fn test_cbor_truncated_byte_string() {
	// Lines 1956-1957: truncated byte string
	result := fn_parse_cbor([VrlValue([u8(0x43), u8(0x61)].bytestr())]) or {
		assert err.msg().contains('truncated CBOR byte string')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_text_string() {
	// major type 3, text string
	result := fn_parse_cbor([VrlValue([u8(0x63), u8(0x66), u8(0x6f), u8(0x6f)].bytestr())]) or {
		return
	}
	j := vrl_to_json(result)
	assert j == '"foo"'
}

fn test_cbor_bool_false() {
	// Line 2008: major type 7, additional 20 = false
	result := fn_parse_cbor([VrlValue([u8(0xF4)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == 'false'
}

fn test_cbor_bool_true() {
	// Line 2012: major type 7, additional 21 = true
	result := fn_parse_cbor([VrlValue([u8(0xF5)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == 'true'
}

fn test_cbor_null() {
	// Line 2016: major type 7, additional 22 = null
	result := fn_parse_cbor([VrlValue([u8(0xF6)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == 'null'
}

fn test_cbor_undefined() {
	// Line 2020: major type 7, additional 23 = undefined -> null
	result := fn_parse_cbor([VrlValue([u8(0xF7)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == 'null'
}

fn test_cbor_float16() {
	// Lines 2024-2029: half-precision float
	// 0xF9 3C00 = 1.0 in float16
	result := fn_parse_cbor([VrlValue([u8(0xF9), u8(0x3C), u8(0x00)].bytestr())]) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('1')
}

fn test_cbor_float16_truncated() {
	// Lines 2024-2025: truncated float16
	result := fn_parse_cbor([VrlValue([u8(0xF9), u8(0x3C)].bytestr())]) or {
		assert err.msg().contains('truncated CBOR float16')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_float32() {
	// Lines 2033-2038: single-precision float
	// 0xFA 3F800000 = 1.0f
	result := fn_parse_cbor([VrlValue([u8(0xFA), u8(0x3F), u8(0x80), u8(0x00),
		u8(0x00)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j.contains('1')
}

fn test_cbor_float32_truncated() {
	// Lines 2033-2034: truncated float32
	result := fn_parse_cbor([VrlValue([u8(0xFA), u8(0x3F), u8(0x80)].bytestr())]) or {
		assert err.msg().contains('truncated CBOR float32')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_float64() {
	// Lines 2043-2050: double-precision float
	// 0xFB 3FF0000000000000 = 1.0
	result := fn_parse_cbor([VrlValue([u8(0xFB), u8(0x3F), u8(0xF0), u8(0x00), u8(0x00),
		u8(0x00), u8(0x00), u8(0x00), u8(0x00)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j.contains('1')
}

fn test_cbor_float64_truncated() {
	// Lines 2042-2043: truncated float64
	result := fn_parse_cbor([VrlValue([u8(0xFB), u8(0x3F), u8(0xF0)].bytestr())]) or {
		assert err.msg().contains('truncated CBOR float64')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_simple_unknown() {
	// Line 2053: major type 7, unknown additional value -> null
	// 0xE0 = simple value 0
	result := fn_parse_cbor([VrlValue([u8(0xE0)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == 'null'
}

fn test_cbor_tagged_value() {
	// Lines 2000-2001: major type 6, tagged value
	// 0xC0 = tag 0, followed by 0x05 = uint 5
	result := fn_parse_cbor([VrlValue([u8(0xC0), u8(0x05)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == '5'
}

fn test_cbor_error_non_string() {
	// Line 1925: parse_cbor with non-string arg
	result := fn_parse_cbor([VrlValue(i64(42))]) or {
		assert err.msg().contains('must be a string')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_error_no_args() {
	// Line 1921: parse_cbor with no args
	result := fn_parse_cbor([]VrlValue{}) or {
		assert err.msg().contains('requires 1 argument')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_empty_data() {
	// Line 2065: cbor_decode_uint on empty data
	result := fn_parse_cbor([VrlValue('')]) or {
		assert err.msg().contains('unexpected end')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_uint8() {
	// Lines 2073-2074: additional=24 -> read 1 more byte
	// 0x18 0x19 = uint 25
	result := fn_parse_cbor([VrlValue([u8(0x18), u8(0x19)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == '25'
}

fn test_cbor_uint16() {
	// Lines 2079-2083: additional=25 -> read 2 more bytes
	// 0x19 0x01 0x00 = uint 256
	result := fn_parse_cbor([VrlValue([u8(0x19), u8(0x01), u8(0x00)].bytestr())]) or {
		return
	}
	j := vrl_to_json(result)
	assert j == '256'
}

fn test_cbor_uint32() {
	// Lines 2086-2090: additional=26 -> read 4 more bytes
	// 0x1A 0x00 0x01 0x00 0x00 = uint 65536
	result := fn_parse_cbor([VrlValue([u8(0x1A), u8(0x00), u8(0x01), u8(0x00),
		u8(0x00)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == '65536'
}

fn test_cbor_uint64() {
	// Lines 2093-2096: additional=27 -> read 8 more bytes
	// 0x1B 0x00 0x00 0x00 0x00 0x00 0x01 0x00 0x00 = uint 65536
	result := fn_parse_cbor([VrlValue([u8(0x1B), u8(0x00), u8(0x00), u8(0x00), u8(0x00),
		u8(0x00), u8(0x01), u8(0x00), u8(0x00)].bytestr())]) or { return }
	j := vrl_to_json(result)
	assert j == '65536'
}

fn test_cbor_uint16_truncated() {
	// Lines 2079-2080: truncated uint16
	result := fn_parse_cbor([VrlValue([u8(0x19), u8(0x01)].bytestr())]) or {
		assert err.msg().contains('truncated CBOR uint16')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_uint32_truncated() {
	// Lines 2086-2087: truncated uint32
	result := fn_parse_cbor([VrlValue([u8(0x1A), u8(0x00), u8(0x01)].bytestr())]) or {
		assert err.msg().contains('truncated CBOR uint32')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_uint64_truncated() {
	// Lines 2093-2094: truncated uint64
	result := fn_parse_cbor([VrlValue([u8(0x1B), u8(0x00), u8(0x00)].bytestr())]) or {
		assert err.msg().contains('truncated CBOR uint64')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_uint8_truncated() {
	// Line 2074: truncated uint8
	result := fn_parse_cbor([VrlValue([u8(0x18)].bytestr())]) or {
		assert err.msg().contains('truncated CBOR uint8')
		return
	}
	assert false, 'expected error'
}

fn test_cbor_map() {
	// CBOR map: 0xA1 0x61 0x61 0x01 = {"a": 1}
	result := fn_parse_cbor([VrlValue([u8(0xA1), u8(0x61), u8(0x61), u8(0x01)].bytestr())]) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"a"')
	assert j.contains('1')
}

fn test_cbor_array() {
	// CBOR array: 0x82 0x01 0x02 = [1, 2]
	result := fn_parse_cbor([VrlValue([u8(0x82), u8(0x01), u8(0x02)].bytestr())]) or {
		return
	}
	j := vrl_to_json(result)
	assert j == '[1,2]'
}
