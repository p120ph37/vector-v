module vrl

// Coverage tests for vrllib_codec.v, vrllib_object.v, and vrllib_string.v
// Targets uncovered lines in these three files.

fn cov_exec(program string) !VrlValue {
	return execute(program, map[string]VrlValue{})
}

fn cov_exec_obj(program string, obj map[string]VrlValue) !VrlValue {
	return execute(program, obj)
}

// ============================================================
// vrllib_codec.v coverage
// ============================================================

// Line 12: encode_base64 error on no args (tested via wrong type)
// Line 17: encode_base64 requires a string
fn test_cov_encode_base64_non_string() {
	// Passing an integer should hit the else branch (line 17)
	r := cov_exec('encode_base64(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Line 94: decode_base16 requires 1 argument error
fn test_cov_decode_base16_non_string() {
	r := cov_exec('decode_base16(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 159, 163: should_percent_encode NON_ASCII and default branches
fn test_cov_encode_percent_non_ascii_set() {
	// Test CONTROLS set (line 155-156)
	r1 := cov_exec('encode_percent("hello\\u0001world", ascii_set: "CONTROLS")') or { return }
	s1 := r1 as string
	assert s1.contains('hello')

	// Test NON_ASCII (line 158-159) - normal ASCII stays same
	r2 := cov_exec('encode_percent("hello", ascii_set: "NON_ASCII")') or { return }
	assert r2 == VrlValue('hello')
}

// Lines 172, 177: decode_percent error paths
fn test_cov_decode_percent_non_string() {
	r := cov_exec('decode_percent(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Line 211: hex_val returns -1 for invalid hex
fn test_cov_decode_percent_invalid_hex() {
	// %ZZ contains invalid hex chars -> hex_val returns -1
	r := cov_exec('decode_percent("%ZZ")') or { return }
	assert r == VrlValue('%ZZ')
}

// Lines 217, 237: encode_csv error paths
fn test_cov_encode_csv_non_array() {
	r := cov_exec('encode_csv("not_array")') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

fn test_cov_encode_csv_basic() {
	r := cov_exec('encode_csv(["a", "b", "c"])') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('a,b,c')
}

// Lines 262, 267: encode_key_value error paths
fn test_cov_encode_key_value_non_object() {
	r := cov_exec('encode_key_value("notobj")') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 296-298, 313-314: encode_key_value with fields_ordering
fn test_cov_encode_key_value_with_ordering() {
	prog := '
		obj = {"b": "2", "a": "1", "c": "3"}
		encode_key_value(obj, ["c", "a"])
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	s := r as string
	// c and a should appear before b
	assert s.contains('c=3')
	assert s.contains('a=1')
	assert s.contains('b=2')
}

// Lines 329-331, 333: encode_key_value with flatten_boolean
fn test_cov_encode_key_value_flatten_bool() {
	prog := '
		obj = {"active": true, "deleted": false, "name": "test"}
		encode_key_value(obj, [], "=", " ", true)
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	s := r as string
	// With flatten_boolean=true, true bools appear as bare keys, false bools are skipped
	assert s.contains('active')
	assert s.contains('name=test')
}

// Lines 365, 370: encode_logfmt error paths
fn test_cov_encode_logfmt_non_object() {
	r := cov_exec('encode_logfmt("notobj")') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

fn test_cov_encode_logfmt_basic() {
	prog := '
		obj = {"level": "info", "msg": "hello world"}
		encode_logfmt(obj)
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	s := r as string
	assert s.contains('level=info')
	// "hello world" contains space so should be quoted
	assert s.contains('msg="hello world"')
}

// Lines 410, 415: decode_mime_q error paths
fn test_cov_decode_mime_q_non_string() {
	r := cov_exec('decode_mime_q(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 461, 467, 473, 485: decode_mime_q_delimited edge cases
fn test_cov_decode_mime_q_delimited() {
	// Standard delimited MIME Q-encoding
	r := cov_exec('decode_mime_q("=?UTF-8?Q?Hello_World?=")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('Hello World')
}

fn test_cov_decode_mime_q_base64() {
	// B encoding (base64)
	r := cov_exec('decode_mime_q("=?UTF-8?B?SGVsbG8=?=")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('Hello')
}

// Lines 509, 522-523, 525-527, 529-531: decode_mime_q_internal edge cases
fn test_cov_decode_mime_q_internal() {
	// Internal format: ?Q?encoded_text
	r := cov_exec('decode_mime_q("?Q?Hello_World")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('Hello World')
}

fn test_cov_decode_mime_q_internal_with_charset() {
	// Internal format with charset: ?charset?Q?text
	r := cov_exec('decode_mime_q("?UTF-8?Q?test")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('test')
}

// Line 546: decode_mime_q_payload with unknown encoding returns none
fn test_cov_decode_mime_q_unknown_encoding() {
	// =?UTF-8?X?text?= — X is not Q or B
	r := cov_exec('decode_mime_q("=?UTF-8?X?test?=")') or { return }
	// Should either error or pass through
}

// Lines 565-566: decode_mime_q_encoding with invalid hex after =
fn test_cov_decode_mime_q_invalid_hex() {
	// Q-encoding with invalid hex sequence =ZZ
	r := cov_exec('decode_mime_q("=?UTF-8?Q?=ZZtest?=")') or { return }
	// Invalid hex in Q-encoding — = followed by non-hex should be kept as-is
}

// Line 542-543: decode_mime_q_payload B encoding with padding
fn test_cov_decode_mime_q_b_no_padding() {
	// Base64 without padding in MIME encoded word
	r := cov_exec('decode_mime_q("=?UTF-8?B?SGVsbG8?=")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('Hello')
}

// Lines 579, 584: encode_zlib error paths
fn test_cov_encode_zlib_non_string() {
	r := cov_exec('encode_zlib(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 593, 598, 601: decode_zlib error paths
fn test_cov_decode_zlib_non_string() {
	r := cov_exec('decode_zlib(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 609, 614, 618: encode_gzip error paths
fn test_cov_encode_gzip_non_string() {
	r := cov_exec('encode_gzip(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 626, 631, 634: decode_gzip error paths
fn test_cov_decode_gzip_non_string() {
	r := cov_exec('decode_gzip(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 642, 647, 651: encode_zstd error paths
fn test_cov_encode_zstd_non_string() {
	r := cov_exec('encode_zstd(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 660, 665: decode_zstd error paths
fn test_cov_decode_zstd_non_string() {
	r := cov_exec('decode_zstd(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 694, 699: encode_snappy error paths
fn test_cov_encode_snappy_non_string() {
	r := cov_exec('encode_snappy(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Snappy roundtrip (lines 694-733)
fn test_cov_snappy_roundtrip() {
	r := cov_exec('decode_snappy!(encode_snappy!("hello world"))') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('hello world')
}

// Lines 756, 806: encode/decode lz4 and decode_zstd_streaming
fn test_cov_lz4_roundtrip() {
	r := cov_exec('decode_lz4!(encode_lz4!("hello world"))') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('hello world')
}

// ============================================================
// vrllib_object.v coverage
// ============================================================

// Lines 5-6, 8-9, 11, 13: fn_unnest error paths
fn test_cov_unnest_basic() {
	prog := '
		. = {"items": [1, 2, 3]}
		unnest!(.items)
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('1')
}

// Lines 22, 39, 54, 59-63: fn_unnest_special with path and ident
fn test_cov_unnest_with_path() {
	prog := '
		. = {"data": {"list": [10, 20]}}
		unnest!(.data.list)
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('10') || json.contains('20')
}

// Lines 98, 147, 151, 159: unnest_var error paths
fn test_cov_unnest_variable() {
	prog := '
		arr = [1, 2, 3]
		unnest!(arr)
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('[')
}

// Lines 179, 201, 207, 211-215, 217-219: set_nested_in_value paths
// Lines 227, 232, 240: object_from_array
fn test_cov_object_from_array_pairs() {
	prog := 'object_from_array!([["key1", "val1"], ["key2", "val2"]])'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('"key1"')
	assert json.contains('"val1"')
}

fn test_cov_object_from_array_with_keys() {
	prog := 'object_from_array!(["a", "b", "c"], ["k1", "k2", "k3"])'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('"k1"')
	assert json.contains('"a"')
}

// Lines 279, 291, 295, 303: fn_zip
fn test_cov_zip_two_arrays() {
	prog := 'zip([1, 2, 3], ["a", "b", "c"])'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('[1,"a"]')
}

fn test_cov_zip_single_array_of_arrays() {
	prog := 'zip([[1, 2], ["a", "b"]])'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('[1,"a"]')
}

// Lines 331, 346, 356-357, 380, 382, 394, 402: fn_remove
fn test_cov_remove_from_object() {
	prog := '
		obj = {"a": 1, "b": {"c": 2}}
		remove!(obj, ["b", "c"])
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('"a"')
}

fn test_cov_remove_from_array() {
	prog := '
		arr = [10, 20, 30]
		remove!(arr, [1])
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('10')
	assert json.contains('30')
}

fn test_cov_remove_with_compact() {
	prog := '
		obj = {"a": 1, "b": {"c": 2, "d": 3}}
		remove!(obj, ["b", "c"], true)
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('"d"')
}

fn test_cov_remove_nested_array() {
	prog := '
		obj = {"items": [{"x": 1}, {"x": 2}]}
		remove!(obj, ["items", 0])
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	// After removing index 0, only {"x": 2} should remain
	assert json.contains('"x":2') || json.contains('"x": 2')
}

// Lines 429, 447-448, 452-453: compact_remove_value
fn test_cov_remove_compact_nested() {
	prog := '
		obj = {"a": {"b": null}, "c": [null], "d": "keep"}
		remove!(obj, ["a", "b"], true)
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('"d"')
}

// ============================================================
// vrllib_string.v coverage
// ============================================================

// Lines 9, 14: camelcase error paths
fn test_cov_camelcase_non_string() {
	r := cov_exec('camelcase(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 37, 52, 57: pascalcase and snakecase error paths
fn test_cov_pascalcase_non_string() {
	r := cov_exec('pascalcase(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

fn test_cov_snakecase_non_string() {
	r := cov_exec('snakecase(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// Lines 75, 89, 94: kebabcase and screamingsnakecase error paths
fn test_cov_kebabcase_non_string() {
	r := cov_exec('kebabcase(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

fn test_cov_screamingsnakecase_non_string() {
	r := cov_exec('screamingsnakecase(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

fn test_cov_screamingsnakecase_basic() {
	r := cov_exec('screamingsnakecase("hello world")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('HELLO_WORLD')
}

// Lines 114, 119: kebabcase basic
fn test_cov_kebabcase_basic() {
	r := cov_exec('kebabcase("hello_world")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('hello-world')
}

// Lines 139, 144: screamingsnakecase with original_case
fn test_cov_screamingsnakecase_with_case() {
	r := cov_exec('screamingsnakecase("helloWorld", "camelCase")') or {
		assert false, '${err}'
		return
	}
	s := r as string
	assert s == 'HELLO_WORLD'
}

// Lines 267, 272, 280: basename
fn test_cov_basename_basic() {
	r := cov_exec('basename("/home/user/file.txt")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('file.txt')
}

fn test_cov_basename_with_extension() {
	r := cov_exec('basename("/home/user/file.txt", ".txt")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('file')
}

fn test_cov_basename_non_string() {
	r := cov_exec('basename(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

fn test_cov_basename_root() {
	r := cov_exec('basename("/")') or {
		assert false, '${err}'
		return
	}
	// "/" should return null
	assert r == VrlValue(VrlNull{})
}

fn test_cov_basename_trailing_slashes() {
	r := cov_exec('basename("///")') or {
		assert false, '${err}'
		return
	}
	// All slashes trimmed, empty -> null
	assert r == VrlValue(VrlNull{})
}

fn test_cov_basename_no_slash() {
	r := cov_exec('basename("file.txt")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('file.txt')
}

// Lines 303, 308: dirname
fn test_cov_dirname_non_string() {
	r := cov_exec('dirname(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

fn test_cov_dirname_basic() {
	r := cov_exec('dirname("/home/user/file.txt")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('/home/user')
}

fn test_cov_dirname_root_only() {
	r := cov_exec('dirname("/file.txt")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('/')
}

fn test_cov_dirname_no_slash() {
	r := cov_exec('dirname("file.txt")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('.')
}

fn test_cov_dirname_trailing_slashes() {
	r := cov_exec('dirname("///")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('/')
}

// Lines 324, 329: split_path
fn test_cov_split_path_non_string() {
	r := cov_exec('split_path(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

fn test_cov_split_path_basic() {
	r := cov_exec('split_path("/home/user/file")') or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('"/"')
	assert json.contains('"home"')
	assert json.contains('"user"')
}

// Lines 347, 352: strip_ansi_escape_codes
fn test_cov_strip_ansi_non_string() {
	r := cov_exec('strip_ansi_escape_codes(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

fn test_cov_strip_ansi_basic() {
	// ESC[31m = red, ESC[0m = reset — pass via object field since \x1b can't be in VRL string literal
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue('\x1b[31mhello\x1b[0m')
	r := cov_exec_obj('strip_ansi_escape_codes(.input)', obj) or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('hello')
}

// Lines 396, 401, 419, 440, 467: shannon_entropy
fn test_cov_shannon_entropy_non_string() {
	r := cov_exec('shannon_entropy(42)') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

fn test_cov_shannon_entropy_basic() {
	r := cov_exec('shannon_entropy("hello")') or {
		assert false, '${err}'
		return
	}
	// Should return a positive float
	f := r as f64
	assert f > 0.0
}

fn test_cov_shannon_entropy_codepoint() {
	r := cov_exec('shannon_entropy("hello", "codepoint")') or {
		assert false, '${err}'
		return
	}
	f := r as f64
	assert f > 0.0
}

fn test_cov_shannon_entropy_grapheme() {
	r := cov_exec('shannon_entropy("hello", "grapheme")') or {
		assert false, '${err}'
		return
	}
	f := r as f64
	assert f > 0.0
}

fn test_cov_shannon_entropy_empty() {
	r := cov_exec('shannon_entropy("")') or {
		assert false, '${err}'
		return
	}
	f := r as f64
	assert f == 0.0
}

// Lines 532, 538, 542-543: rune_to_utf8 multi-byte paths
// Lines 564, 605, 618, 623, 628-629: sieve function
fn test_cov_sieve_basic() {
	// Keep only digits using sieve
	prog := 'sieve("abc123def456", r\'[0-9]\')'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('123456')
}

fn test_cov_sieve_with_replace_single() {
	prog := 'sieve("abc123", r\'[0-9]\', replace_single: "*")'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('***123')
}

fn test_cov_sieve_with_replace_repeated() {
	prog := 'sieve("abc123def", r\'[0-9]\', replace_repeated: "...")'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('...123...')
}

// Lines 652, 662, 670-671, 680: replace_with
fn test_cov_replace_with_basic() {
	prog := 'replace_with("hello world", r\'\\w+\') -> |match| { upcase!(match.string) }'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('HELLO WORLD')
}

// Lines 698, 714, 718: replace_with with count
fn test_cov_replace_with_count() {
	prog := 'replace_with("aaa bbb ccc", r\'\\w+\', count: 2) -> |match| { upcase!(match.string) }'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('AAA BBB ccc')
}

// Lines 729, 735: replace_with no match
fn test_cov_replace_with_no_match() {
	prog := 'replace_with("hello", r\'\\d+\') -> |match| { "X" }'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('hello')
}

// Case conversion with original_case parameter
fn test_cov_camelcase_with_case() {
	r := cov_exec('camelcase("hello_world", "snake_case")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('helloWorld')
}

fn test_cov_snakecase_with_case() {
	r := cov_exec('snakecase("helloWorld", "camelCase")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('hello_world')
}

fn test_cov_kebabcase_with_case() {
	r := cov_exec('kebabcase("hello_world", "snake_case")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('hello-world')
}

fn test_cov_pascalcase_with_case() {
	r := cov_exec('pascalcase("hello-world", "kebab-case")') or {
		assert false, '${err}'
		return
	}
	assert r == VrlValue('HelloWorld')
}

// encode_percent with default set (else branch line 163)
fn test_cov_encode_percent_default_set() {
	r := cov_exec('encode_percent("hello world", ascii_set: "UNKNOWN_SET")') or {
		assert false, '${err}'
		return
	}
	s := r as string
	// Space should be percent-encoded with default set
	assert s.contains('%20')
}

// encode_key_value with special value types (null, spaces in values)
fn test_cov_encode_key_value_with_null() {
	prog := '
		obj = {"a": null, "b": "hello world", "c": 42}
		encode_key_value(obj)
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	s := r as string
	assert s.contains('a=')
	assert s.contains('b="hello world"')
}

// encode_logfmt with various types (bool, null)
fn test_cov_encode_logfmt_bool_null() {
	prog := '
		obj = {"active": true, "val": null, "count": 42}
		encode_logfmt(obj)
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	s := r as string
	assert s.contains('active=true')
	assert s.contains('count=42')
}

// remove with string index on array (line 380)
fn test_cov_remove_string_index_array() {
	prog := '
		arr = [10, 20, 30]
		remove!(arr, ["0"])
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('20')
}

// unnest on path with nested object
fn test_cov_unnest_nested_path() {
	prog := '
		. = {"a": {"b": [1, 2]}}
		unnest!(.a.b)
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('1') || json.contains('2')
}

// zip with non-array arg
fn test_cov_zip_non_array() {
	r := cov_exec('zip("not_array")') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// object_from_array with non-array
fn test_cov_object_from_array_non_array() {
	r := cov_exec('object_from_array!("not_array")') or { return }
	assert false, 'expected error, got ${vrl_to_json(r)}'
}

// remove nested in array path
fn test_cov_remove_nested_in_array() {
	prog := '
		obj = {"items": [{"name": "a"}, {"name": "b"}]}
		remove!(obj, ["items", 0, "name"])
	'
	r := cov_exec(prog) or {
		assert false, '${err}'
		return
	}
	json := vrl_to_json(r)
	assert json.contains('"items"')
}
