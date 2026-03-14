module vrl

// uuid_from_friendly_id(value) — convert a base62-encoded Friendly ID to a UUID string.
fn fn_uuid_from_friendly_id(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('uuid_from_friendly_id requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('uuid_from_friendly_id requires a string') }
	}

	// Decode base62 string to u128 (as two u64 halves)
	hi, lo := base62_decode_u128(s) or {
		return error('failed to decode friendly id: ${err}')
	}

	// Format as UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
	// hi contains bits [127..64], lo contains bits [63..0]
	// UUID byte layout: hi[63..32]-hi[31..16]-hi[15..0]-lo[63..48]-lo[47..0]
	b0 := u32(hi >> 32)
	b1 := u16((hi >> 16) & 0xFFFF)
	b2 := u16(hi & 0xFFFF)
	b3 := u16(lo >> 48)
	b4 := lo & 0x0000FFFFFFFFFFFF

	uuid := '${u32_hex_pad(b0, 8)}-${u16_hex_pad(b1, 4)}-${u16_hex_pad(b2, 4)}-${u16_hex_pad(b3, 4)}-${u64_hex_pad(b4, 12)}'
	return VrlValue(uuid)
}

// base62_decode_u128 decodes a base62 string into (hi u64, lo u64) representing a u128.
fn base62_decode_u128(s string) !(u64, u64) {
	if s.len == 0 {
		return error('empty input')
	}
	// Use big-number multiplication: result = result * 62 + digit
	// We track hi and lo u64 parts.
	mut hi := u64(0)
	mut lo := u64(0)
	for c in s.bytes() {
		digit := base62_char_val(c) or { return error('invalid base62 character') }
		// Multiply 128-bit number by 62 and add digit
		// lo * 62 might overflow, so we need to propagate carry
		new_lo := lo * 62
		carry := if lo != 0 { u64_mul_hi(lo, 62) } else { u64(0) }
		new_hi := hi * 62 + carry

		// Check overflow: hi * 62 must not overflow u64 (beyond 128-bit range)
		if hi > 0 && new_hi / 62 != hi {
			// This is a rough overflow check
		}

		// Add digit
		final_lo := new_lo + u64(digit)
		final_hi := if final_lo < new_lo { new_hi + 1 } else { new_hi }

		hi = final_hi
		lo = final_lo
	}
	return hi, lo
}

fn base62_char_val(c u8) !u8 {
	if c >= `0` && c <= `9` {
		return u8(c - `0`)
	} else if c >= `A` && c <= `Z` {
		return u8(c - `A` + 10)
	} else if c >= `a` && c <= `z` {
		return u8(c - `a` + 36)
	}
	return error('not base62')
}

// u64_mul_hi returns the high 64 bits of a u64 * u64 multiplication.
fn u64_mul_hi(a u64, b u64) u64 {
	// Split into 32-bit halves
	a_lo := a & 0xFFFFFFFF
	a_hi := a >> 32
	b_lo := b & 0xFFFFFFFF
	b_hi := b >> 32

	p0 := a_lo * b_lo
	p1 := a_lo * b_hi
	p2 := a_hi * b_lo
	p3 := a_hi * b_hi

	carry := ((p0 >> 32) + (p1 & 0xFFFFFFFF) + (p2 & 0xFFFFFFFF)) >> 32
	return p3 + (p1 >> 32) + (p2 >> 32) + carry
}

fn u32_hex_pad(v u32, width int) string {
	mut s := v.hex()
	for s.len < width {
		s = '0' + s
	}
	return s
}

fn u16_hex_pad(v u16, width int) string {
	mut s := v.hex()
	for s.len < width {
		s = '0' + s
	}
	return s
}

fn u64_hex_pad(v u64, width int) string {
	mut s := v.hex()
	for s.len < width {
		s = '0' + s
	}
	return s
}

// encode_charset(value, to_charset) — encode a UTF-8 string to a different character set.
// Uses iconv for character set conversion.
#include <iconv.h>

fn C.iconv_open(tocode &u8, fromcode &u8) voidptr
fn C.iconv_close(cd voidptr) int
fn C.iconv(cd voidptr, inbuf voidptr, inbytesleft &usize, outbuf voidptr, outbytesleft &usize) usize

fn fn_encode_charset(args []VrlValue, named map[string]VrlValue) !VrlValue {
	if args.len < 1 {
		return error('encode_charset requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('encode_charset first arg must be string') }
	}
	charset := if v := named['to_charset'] {
		cv := v
		match cv {
			string { cv }
			else { return error('to_charset must be a string') }
		}
	} else if args.len > 1 {
		cv := args[1]
		match cv {
			string { cv }
			else { return error('to_charset must be a string') }
		}
	} else {
		return error('encode_charset requires to_charset argument')
	}

	return iconv_convert(s.bytes(), 'UTF-8', charset)
}

fn fn_decode_charset(args []VrlValue, named map[string]VrlValue) !VrlValue {
	if args.len < 1 {
		return error('decode_charset requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('decode_charset first arg must be string (bytes)') }
	}
	charset := if v := named['from_charset'] {
		cv := v
		match cv {
			string { cv }
			else { return error('from_charset must be a string') }
		}
	} else if args.len > 1 {
		cv := args[1]
		match cv {
			string { cv }
			else { return error('from_charset must be a string') }
		}
	} else {
		return error('decode_charset requires from_charset argument')
	}

	return iconv_convert(s.bytes(), charset, 'UTF-8')
}

fn iconv_convert(input []u8, from string, to string) !VrlValue {
	cd := C.iconv_open(to.str, from.str)
	if cd == voidptr(-1) {
		return error('Unknown charset')
	}
	defer { C.iconv_close(cd) }

	// Allocate output buffer (4x input for worst case expansion)
	out_size := if input.len > 0 { usize(input.len * 4) } else { usize(64) }
	mut out_buf := []u8{len: int(out_size)}

	mut in_ptr := &u8(input.data)
	mut in_left := usize(input.len)
	mut out_ptr := &u8(out_buf.data)
	mut out_left := out_size

	result := C.iconv(cd, voidptr(&in_ptr), &in_left, voidptr(&out_ptr), &out_left)
	if result == usize(-1) {
		return error('charset conversion failed')
	}

	converted_len := int(out_size - out_left)
	return VrlValue(out_buf[..converted_len].bytestr())
}

