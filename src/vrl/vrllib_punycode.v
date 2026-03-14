module vrl

// Punycode (RFC 3492) encode and decode for internationalized domain names.

const punycode_base = 36
const punycode_tmin = 1
const punycode_tmax = 26
const punycode_skew = 38
const punycode_damp = 700
const punycode_initial_bias = 72
const punycode_initial_n = 128

// punycode_adapt implements the bias adaptation function from RFC 3492 section 6.1.
fn punycode_adapt(delta_arg int, numpoints int, firsttime bool) int {
	mut delta := if firsttime { delta_arg / punycode_damp } else { delta_arg / 2 }
	delta += delta / numpoints
	mut k := 0
	for delta > ((punycode_base - punycode_tmin) * punycode_tmax) / 2 {
		delta /= punycode_base - punycode_tmin
		k += punycode_base
	}
	return k + ((punycode_base - punycode_tmin + 1) * delta) / (delta + punycode_skew)
}

// punycode_encode_digit converts a digit value (0-35) to the corresponding ASCII code point.
fn punycode_encode_digit(d int) u8 {
	if d < 26 {
		return u8(d + 97) // a-z
	}
	return u8(d - 26 + 48) // 0-9
}

// punycode_decode_digit converts an ASCII code point to a digit value (0-35).
fn punycode_decode_digit(cp u8) int {
	if cp >= `a` && cp <= `z` {
		return int(cp - `a`)
	}
	if cp >= `A` && cp <= `Z` {
		return int(cp - `A`)
	}
	if cp >= `0` && cp <= `9` {
		return int(cp - `0`) + 26
	}
	return punycode_base // invalid
}

// punycode_encode_label encodes a single Unicode label to Punycode.
fn punycode_encode_label(input []rune) !string {
	mut output := []u8{}

	// Copy basic code points to output
	for cp in input {
		if int(cp) < 0x80 {
			output << u8(cp)
		}
	}
	basic_len := output.len
	mut handled := basic_len

	if basic_len > 0 && handled < input.len {
		output << `-`
	}

	mut n := punycode_initial_n
	mut delta := 0
	mut bias := punycode_initial_bias

	for handled < input.len {
		// Find the minimum code point >= n among unhandled characters
		mut m := 0x10FFFF
		for cp in input {
			cp_val := int(cp)
			if cp_val >= n && cp_val < m {
				m = cp_val
			}
		}

		// Increase delta to account for skipped code points
		diff := m - n
		if diff > (0x7FFFFFFF - delta) / (handled + 1) {
			return error('punycode overflow')
		}
		delta += diff * (handled + 1)
		n = m

		for cp in input {
			cp_val := int(cp)
			if cp_val < n {
				delta++
				if delta == 0 {
					return error('punycode overflow')
				}
			}
			if cp_val == n {
				mut q := delta
				mut k := punycode_base
				for {
					t := if k <= bias {
						punycode_tmin
					} else if k >= bias + punycode_tmax {
						punycode_tmax
					} else {
						k - bias
					}
					if q < t {
						break
					}
					output << punycode_encode_digit(t + (q - t) % (punycode_base - t))
					q = (q - t) / (punycode_base - t)
					k += punycode_base
				}
				output << punycode_encode_digit(q)
				bias = punycode_adapt(delta, handled + 1, handled == basic_len)
				delta = 0
				handled++
			}
		}
		delta++
		n++
	}

	return output.bytestr()
}

// punycode_decode_label decodes a single Punycode label to Unicode.
fn punycode_decode_label(input string) !string {
	mut output := []rune{}

	// Find the last delimiter to separate basic from extended parts
	mut basic_end := -1
	for i := input.len - 1; i >= 0; i-- {
		if input[i] == `-` {
			basic_end = i
			break
		}
	}

	// Copy basic code points
	if basic_end > 0 {
		for i := 0; i < basic_end; i++ {
			cp := input[i]
			if cp >= 0x80 {
				return error('invalid punycode: non-basic character in basic section')
			}
			output << rune(cp)
		}
	}

	mut n := punycode_initial_n
	mut i := 0
	mut bias := punycode_initial_bias
	mut idx := if basic_end >= 0 { basic_end + 1 } else { 0 }

	for idx < input.len {
		mut old_i := i
		mut w := 1
		mut k := punycode_base

		for {
			if idx >= input.len {
				return error('invalid punycode: unexpected end of input')
			}
			digit := punycode_decode_digit(input[idx])
			idx++
			if digit >= punycode_base {
				return error('invalid punycode: invalid digit')
			}
			if digit > (0x7FFFFFFF - i) / w {
				return error('punycode overflow')
			}
			i += digit * w

			t := if k <= bias {
				punycode_tmin
			} else if k >= bias + punycode_tmax {
				punycode_tmax
			} else {
				k - bias
			}
			if digit < t {
				break
			}
			if w > 0x7FFFFFFF / (punycode_base - t) {
				return error('punycode overflow')
			}
			w *= punycode_base - t
			k += punycode_base
		}

		out_len := output.len + 1
		bias = punycode_adapt(i - old_i, out_len, old_i == 0)

		if i / out_len > 0x7FFFFFFF - n {
			return error('punycode overflow')
		}
		n += i / out_len
		i = i % out_len

		// Insert the decoded character at position i
		output.insert(i, rune(n))
		i++
	}

	mut result := []u8{cap: output.len * 4}
	for cp in output {
		encoded := utf32_to_utf8(int(cp))
		result << encoded
	}
	return result.bytestr()
}

// utf32_to_utf8 converts a Unicode code point to its UTF-8 byte representation.
fn utf32_to_utf8(cp int) []u8 {
	if cp < 0x80 {
		return [u8(cp)]
	} else if cp < 0x800 {
		return [u8(0xC0 | (cp >> 6)), u8(0x80 | (cp & 0x3F))]
	} else if cp < 0x10000 {
		return [u8(0xE0 | (cp >> 12)), u8(0x80 | ((cp >> 6) & 0x3F)), u8(0x80 | (cp & 0x3F))]
	} else {
		return [u8(0xF0 | (cp >> 18)), u8(0x80 | ((cp >> 12) & 0x3F)), u8(0x80 | ((cp >> 6) & 0x3F)),
			u8(0x80 | (cp & 0x3F))]
	}
}

// punycode_encode_domain encodes a Unicode domain to ASCII-compatible encoding.
// Used by parse_url and encode_punycode.
fn punycode_encode_domain(s string) string {
	labels := s.split('.')
	mut result_labels := []string{}
	for label in labels {
		runes := label.runes()
		mut has_non_ascii := false
		for cp in runes {
			if int(cp) >= 0x80 {
				has_non_ascii = true
				break
			}
		}
		if has_non_ascii {
			mut lower_runes := []rune{cap: runes.len}
			for cp in runes {
				cp_val := int(cp)
				if cp_val >= `A` && cp_val <= `Z` {
					lower_runes << rune(cp_val + 32)
				} else {
					lower_runes << cp
				}
			}
			encoded := punycode_encode_label(lower_runes) or { return s }
			result_labels << 'xn--${encoded}'
		} else {
			result_labels << label
		}
	}
	return result_labels.join('.')
}

// fn_encode_punycode encodes a Unicode domain name to Punycode (IDNA).
fn fn_encode_punycode(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('encode_punycode requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('encode_punycode requires a string argument') }
	}
	return VrlValue(punycode_encode_domain(s))
}

// fn_decode_punycode decodes a Punycode (IDNA) domain name to Unicode.
fn fn_decode_punycode(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('decode_punycode requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('decode_punycode requires a string argument') }
	}

	labels := s.split('.')
	mut result_labels := []string{}
	for label in labels {
		lower_label := label.to_lower()
		if lower_label.starts_with('xn--') {
			decoded := punycode_decode_label(lower_label[4..])!
			result_labels << decoded
		} else {
			result_labels << lower_label
		}
	}
	return VrlValue(result_labels.join('.'))
}
