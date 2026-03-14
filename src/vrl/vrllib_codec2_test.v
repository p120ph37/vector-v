module vrl

// ============================================================
// Compression codec roundtrips
// ============================================================

fn test_zlib_roundtrip() {
	result := execute('decode_zlib!(encode_zlib!("hello world"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('hello world')
}

fn test_zlib_roundtrip_longer() {
	result := execute('decode_zlib!(encode_zlib!("the quick brown fox jumps over the lazy dog"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('the quick brown fox jumps over the lazy dog')
}

fn test_zlib_roundtrip_large() {
	// Build a large string via VRL
	prog := 'decode_zlib!(encode_zlib!("abcdefghij" + "abcdefghij" + "abcdefghij" + "abcdefghij" + "abcdefghij"))'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('abcdefghijabcdefghijabcdefghijabcdefghijabcdefghij')
}

fn test_gzip_roundtrip() {
	result := execute('decode_gzip!(encode_gzip!("hello world"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('hello world')
}

fn test_gzip_roundtrip_longer() {
	result := execute('decode_gzip!(encode_gzip!("the quick brown fox jumps over the lazy dog"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('the quick brown fox jumps over the lazy dog')
}

fn test_gzip_roundtrip_special_chars() {
	prog := 'decode_gzip!(encode_gzip!("line1\\nline2\\ttab"))'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('line1\nline2\ttab')
}

fn test_zstd_roundtrip() {
	result := execute('decode_zstd!(encode_zstd!("hello world"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('hello world')
}

fn test_zstd_roundtrip_longer() {
	result := execute('decode_zstd!(encode_zstd!("the quick brown fox jumps over the lazy dog"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('the quick brown fox jumps over the lazy dog')
}

fn test_snappy_roundtrip() {
	result := execute('decode_snappy!(encode_snappy!("hello world"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('hello world')
}

fn test_snappy_roundtrip_longer() {
	result := execute('decode_snappy!(encode_snappy!("the quick brown fox jumps over the lazy dog"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('the quick brown fox jumps over the lazy dog')
}

fn test_snappy_roundtrip_repeated() {
	prog := 'decode_snappy!(encode_snappy!("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
}

fn test_lz4_roundtrip() {
	result := execute('decode_lz4!(encode_lz4!("hello world"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('hello world')
}

fn test_lz4_roundtrip_longer() {
	result := execute('decode_lz4!(encode_lz4!("abcdefghijklmnopqrstuvwxyz"))', map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('abcdefghijklmnopqrstuvwxyz')
}

fn test_lz4_roundtrip_large() {
	prog := 'decode_lz4!(encode_lz4!("the quick brown fox jumps over the lazy dog"))'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('the quick brown fox jumps over the lazy dog')
}

// ============================================================
// Percent encoding
// ============================================================

fn test_encode_percent_basic() {
	result := execute('encode_percent("hello world")', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('hello%20world')
}

fn test_encode_percent_special_chars() {
	result := execute('encode_percent("a=b&c=d")', map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('a%3Db%26c%3Dd')
}

fn test_encode_percent_already_safe() {
	result := execute('encode_percent("abc123")', map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('abc123')
}

fn test_encode_percent_controls() {
	result := execute('encode_percent("hello world", ascii_set: "CONTROLS")', map[string]VrlValue{}) or {
		panic('${err}')
	}
	// CONTROLS only encodes control chars (0x00-0x1F and 0x7F), space (0x20) is not a control char
	assert result == VrlValue('hello world')
}

fn test_decode_percent_basic() {
	result := execute('decode_percent("hello%20world")', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('hello world')
}

fn test_decode_percent_special_chars() {
	result := execute('decode_percent("a%3Db%26c%3Dd")', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('a=b&c=d')
}

fn test_percent_roundtrip() {
	result := execute('decode_percent(encode_percent("hello world! @#\$%"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('hello world! @#\$%')
}

fn test_decode_percent_passthrough() {
	result := execute('decode_percent("abc123")', map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('abc123')
}

// ============================================================
// CSV encoding edge cases
// ============================================================

fn test_encode_csv_simple() {
	result := execute('encode_csv(["a", "b", "c"])', map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('a,b,c')
}

fn test_encode_csv_with_commas() {
	result := execute('encode_csv(["hello, world", "foo"])', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('"hello, world",foo')
}

fn test_encode_csv_with_quotes() {
	result := execute('encode_csv(["say \\"hi\\"", "ok"])', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('"say ""hi""",ok')
}

fn test_encode_csv_with_newlines() {
	result := execute('encode_csv(["line1\\nline2", "ok"])', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('"line1\nline2",ok')
}

fn test_encode_csv_numbers() {
	result := execute('encode_csv([1, 2.5, true])', map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('1,2.5,true')
}

fn test_encode_csv_custom_delimiter() {
	result := execute('encode_csv(["a", "b", "c"], delimiter: ";")', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('a;b;c')
}

fn test_encode_csv_single_field() {
	result := execute('encode_csv(["only"])', map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('only')
}

// ============================================================
// Key-value encoding
// ============================================================

fn test_encode_key_value_basic() {
	prog := 'encode_key_value({"level": "info", "msg": "hello"})'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	s := result as string
	// Keys are sorted
	assert s.contains('level=info')
	assert s.contains('msg=hello')
}

fn test_encode_key_value_custom_delimiters() {
	prog := 'encode_key_value({"a": "1", "b": "2"}, key_value_delimiter: ":", field_delimiter: ",")'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	s := result as string
	assert s.contains('a:1')
	assert s.contains('b:2')
	assert s.contains(',')
}

fn test_encode_key_value_value_with_spaces() {
	prog := 'encode_key_value({"msg": "hello world"})'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	s := result as string
	assert s.contains('msg="hello world"')
}

fn test_encode_key_value_null_value() {
	prog := 'encode_key_value({"key": null})'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	s := result as string
	assert s.contains('key=')
}

fn test_encode_key_value_integer_value() {
	prog := 'encode_key_value({"count": 42, "name": "test"})'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	s := result as string
	assert s.contains('count=42')
	assert s.contains('name=test')
}

// ============================================================
// Logfmt encoding
// ============================================================

fn test_encode_logfmt_basic() {
	prog := 'encode_logfmt({"level": "info", "msg": "request"})'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	s := result as string
	assert s.contains('level=info')
	assert s.contains('msg=request')
}

fn test_encode_logfmt_with_spaces() {
	prog := 'encode_logfmt({"msg": "hello world"})'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	s := result as string
	assert s.contains('msg="hello world"')
}

fn test_encode_logfmt_bool() {
	prog := 'encode_logfmt({"active": true})'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('active=true')
}

fn test_encode_logfmt_null() {
	prog := 'encode_logfmt({"key": null})'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('key=')
}

fn test_encode_logfmt_number() {
	prog := 'encode_logfmt({"count": 42})'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('count=42')
}

// ============================================================
// MIME-Q decoding
// ============================================================

fn test_decode_mime_q_q_encoding() {
	// =?charset?Q?encoded_text?=
	prog := 'decode_mime_q!("=?UTF-8?Q?hello_world?=")'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('hello world')
}

fn test_decode_mime_q_b_encoding() {
	// =?charset?B?base64_text?=
	prog := 'decode_mime_q!("=?UTF-8?B?aGVsbG8gd29ybGQ=?=")'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('hello world')
}

fn test_decode_mime_q_hex_escape() {
	// =XX hex escapes in Q encoding
	prog := 'decode_mime_q!("=?UTF-8?Q?hello=20world?=")'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('hello world')
}

fn test_decode_mime_q_mixed_text() {
	// Text with encoded word embedded
	prog := 'decode_mime_q!("Subject: =?UTF-8?Q?Re:_hello?=")'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('Subject: Re: hello')
}

fn test_decode_mime_q_internal_format() {
	// Internal format: ?encoding?text (no delimiters)
	prog := 'decode_mime_q!("?Q?hello_world")'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('hello world')
}

fn test_decode_mime_q_internal_b_encoding() {
	prog := 'decode_mime_q!("?B?aGVsbG8gd29ybGQ")'
	result := execute(prog, map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('hello world')
}

fn test_decode_mime_q_invalid() {
	prog := 'decode_mime_q!("not encoded at all")'
	execute(prog, map[string]VrlValue{}) or {
		assert err.msg().contains('unable to decode')
		return
	}
	panic('expected decode_mime_q error')
}

// ============================================================
// Base64 edge cases
// ============================================================

fn test_encode_base64_no_padding() {
	result := execute('encode_base64("a", padding: false)', map[string]VrlValue{}) or {
		panic('${err}')
	}
	s := result as string
	assert !s.ends_with('=')
}

fn test_encode_base64_url_safe() {
	result := execute('encode_base64("subjects?_d", charset: "url_safe")', map[string]VrlValue{}) or {
		panic('${err}')
	}
	s := result as string
	assert !s.contains('+')
	assert !s.contains('/')
}

fn test_decode_base64_url_safe() {
	// Roundtrip with url_safe charset
	result := execute('decode_base64!(encode_base64("hello+world/foo", charset: "url_safe"), charset: "url_safe")', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('hello+world/foo')
}

// ============================================================
// Base16 roundtrip
// ============================================================

fn test_base16_roundtrip() {
	result := execute('decode_base16!(encode_base16("hello"))', map[string]VrlValue{}) or {
		panic('${err}')
	}
	assert result == VrlValue('hello')
}

fn test_encode_base16_known() {
	result := execute('encode_base16("AB")', map[string]VrlValue{}) or { panic('${err}') }
	assert result == VrlValue('4142')
}
