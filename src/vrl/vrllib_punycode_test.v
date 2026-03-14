module vrl

// Tests for vrllib_punycode.v

fn test_punycode_adapt_firsttime() {
	result := punycode_adapt(100, 1, true)
	assert result >= 0
}

fn test_punycode_adapt_not_firsttime() {
	result := punycode_adapt(100, 1, false)
	assert result >= 0
}

fn test_punycode_encode_digit_letter() {
	assert punycode_encode_digit(0) == `a`
	assert punycode_encode_digit(25) == `z`
}

fn test_punycode_encode_digit_number() {
	assert punycode_encode_digit(26) == `0`
	assert punycode_encode_digit(35) == `9`
}

fn test_punycode_decode_digit_lowercase() {
	assert punycode_decode_digit(`a`) == 0
	assert punycode_decode_digit(`z`) == 25
}

fn test_punycode_decode_digit_uppercase() {
	assert punycode_decode_digit(`A`) == 0
	assert punycode_decode_digit(`Z`) == 25
}

fn test_punycode_decode_digit_numbers() {
	assert punycode_decode_digit(`0`) == 26
	assert punycode_decode_digit(`9`) == 35
}

fn test_punycode_decode_digit_invalid() {
	assert punycode_decode_digit(`!`) == punycode_base
}

fn test_punycode_encode_label_ascii_only() {
	result := punycode_encode_label('hello'.runes()) or {
		assert false, 'encode ascii: ${err}'
		return
	}
	// All basic, handled == input.len, so no trailing hyphen
	assert result == 'hello'
}

fn test_punycode_encode_label_unicode() {
	// München -> mnchen-3ya
	result := punycode_encode_label('münchen'.runes()) or {
		assert false, 'encode unicode: ${err}'
		return
	}
	assert result == 'mnchen-3ya'
}

fn test_punycode_encode_label_all_unicode() {
	// Chinese characters
	result := punycode_encode_label('中文'.runes()) or {
		assert false, 'encode all unicode: ${err}'
		return
	}
	assert result.len > 0
}

fn test_punycode_decode_label_ascii() {
	result := punycode_decode_label('hello-') or {
		assert false, 'decode ascii: ${err}'
		return
	}
	assert result == 'hello'
}

fn test_punycode_decode_label_unicode() {
	result := punycode_decode_label('mnchen-3ya') or {
		assert false, 'decode unicode: ${err}'
		return
	}
	assert result == 'münchen'
}

fn test_punycode_decode_label_invalid_digit() {
	punycode_decode_label('!!!') or {
		assert err.msg().contains('invalid')
		return
	}
	assert false, 'expected error'
}

fn test_punycode_decode_label_non_basic() {
	// Non-basic char in basic section (before delimiter)
	punycode_decode_label('\x80-abc') or {
		assert err.msg().contains('non-basic')
		return
	}
	assert false, 'expected error'
}

fn test_punycode_encode_domain_ascii() {
	result := punycode_encode_domain('example.com')
	assert result == 'example.com'
}

fn test_punycode_encode_domain_unicode() {
	result := punycode_encode_domain('münchen.de')
	assert result == 'xn--mnchen-3ya.de'
}

fn test_punycode_encode_domain_mixed() {
	result := punycode_encode_domain('www.münchen.de')
	assert result == 'www.xn--mnchen-3ya.de'
}

fn test_fn_encode_punycode() {
	result := fn_encode_punycode([VrlValue('münchen.de')]) or {
		assert false, 'encode_punycode: ${err}'
		return
	}
	assert (result as string) == 'xn--mnchen-3ya.de'
}

fn test_fn_encode_punycode_no_args() {
	fn_encode_punycode([]) or {
		assert err.msg().contains('requires 1')
		return
	}
	assert false, 'expected error'
}

fn test_fn_encode_punycode_bad_type() {
	fn_encode_punycode([VrlValue(i64(42))]) or {
		assert err.msg().contains('string argument')
		return
	}
	assert false, 'expected error'
}

fn test_fn_decode_punycode() {
	result := fn_decode_punycode([VrlValue('xn--mnchen-3ya.de')]) or {
		assert false, 'decode_punycode: ${err}'
		return
	}
	assert (result as string) == 'münchen.de'
}

fn test_fn_decode_punycode_no_xn_prefix() {
	result := fn_decode_punycode([VrlValue('example.com')]) or {
		assert false, 'decode_punycode no xn: ${err}'
		return
	}
	assert (result as string) == 'example.com'
}

fn test_fn_decode_punycode_no_args() {
	fn_decode_punycode([]) or {
		assert err.msg().contains('requires 1')
		return
	}
	assert false, 'expected error'
}

fn test_fn_decode_punycode_bad_type() {
	fn_decode_punycode([VrlValue(i64(42))]) or {
		assert err.msg().contains('string argument')
		return
	}
	assert false, 'expected error'
}

fn test_punycode_roundtrip() {
	original := 'münchen.de'
	encoded := punycode_encode_domain(original)
	decoded := fn_decode_punycode([VrlValue(encoded)]) or {
		assert false, 'roundtrip decode: ${err}'
		return
	}
	assert (decoded as string) == original
}

fn test_utf32_to_utf8_ascii() {
	result := utf32_to_utf8(0x41) // 'A'
	assert result == [u8(0x41)]
}

fn test_utf32_to_utf8_two_byte() {
	result := utf32_to_utf8(0xFC) // 'ü'
	assert result.len == 2
}

fn test_utf32_to_utf8_three_byte() {
	result := utf32_to_utf8(0x4E2D) // '中'
	assert result.len == 3
}

fn test_utf32_to_utf8_four_byte() {
	result := utf32_to_utf8(0x1F600) // emoji
	assert result.len == 4
}

fn test_punycode_via_execute() {
	result := execute('.result = encode_punycode("münchen.de")', map[string]VrlValue{}) or {
		assert false, 'execute encode_punycode: ${err}'
		return
	}
	assert result == VrlValue('xn--mnchen-3ya.de')
}

fn test_decode_punycode_via_execute() {
	result := execute('.result = decode_punycode("xn--mnchen-3ya.de")', map[string]VrlValue{}) or {
		assert false, 'execute decode_punycode: ${err}'
		return
	}
	assert result == VrlValue('münchen.de')
}
