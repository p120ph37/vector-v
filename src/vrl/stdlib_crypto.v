module vrl

import crypto.md5
import crypto.sha1
import crypto.sha256
import crypto.sha512
import crypto.hmac
import hash.crc32

// sha1(value)
fn fn_sha1(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('sha1 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('sha1 requires a string') }
	}
	return VrlValue(sha1.hexhash(s))
}

// sha2(value, [variant])
fn fn_sha2(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('sha2 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('sha2 requires a string') }
	}
	variant := if args.len > 1 {
		v := args[1]
		match v {
			string { v }
			else { 'SHA-512/256' }
		}
	} else {
		'SHA-512/256'
	}
	match variant {
		'SHA-224' {
			digest := sha256.sum224(s.bytes())
			return VrlValue(digest_to_hex(digest[..], 28))
		}
		'SHA-256' {
			return VrlValue(sha256.hexhash(s))
		}
		'SHA-384' {
			digest := sha512.sum384(s.bytes())
			return VrlValue(digest_to_hex(digest[..], 48))
		}
		'SHA-512' {
			return VrlValue(sha512.hexhash(s))
		}
		'SHA-512/224' {
			digest := sha512.sum512_224(s.bytes())
			return VrlValue(digest_to_hex(digest[..], 28))
		}
		'SHA-512/256' {
			digest := sha512.sum512_256(s.bytes())
			return VrlValue(digest_to_hex(digest[..], 32))
		}
		else {
			return error('unknown SHA-2 variant: ${variant}')
		}
	}
}

fn digest_to_hex(data []u8, len int) string {
	mut result := []u8{cap: len * 2}
	for i in 0 .. len {
		hi := data[i] >> 4
		lo := data[i] & 0x0F
		result << if hi < 10 { `0` + hi } else { `a` + hi - 10 }
		result << if lo < 10 { `0` + lo } else { `a` + lo - 10 }
	}
	return result.bytestr()
}

// sha3(value, [variant]) - SHA-3 (Keccak) hash
fn fn_sha3(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('sha3 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('sha3 requires a string') }
	}
	variant := if args.len > 1 {
		v := args[1]
		match v {
			string { v }
			else { 'SHA3-512' }
		}
	} else {
		'SHA3-512'
	}
	match variant {
		'SHA3-224' {
			digest := keccak_hash(s.bytes(), 144, 28)
			return VrlValue(digest_to_hex(digest[..], 28))
		}
		'SHA3-256' {
			digest := keccak_hash(s.bytes(), 136, 32)
			return VrlValue(digest_to_hex(digest[..], 32))
		}
		'SHA3-384' {
			digest := keccak_hash(s.bytes(), 104, 48)
			return VrlValue(digest_to_hex(digest[..], 48))
		}
		'SHA3-512' {
			digest := keccak_hash(s.bytes(), 72, 64)
			return VrlValue(digest_to_hex(digest[..], 64))
		}
		else {
			return error('unknown SHA-3 variant: ${variant}')
		}
	}
}

// Keccak-f[1600] round constants
const keccak_rc = [
	u64(0x0000000000000001), u64(0x0000000000008082), u64(0x800000000000808A),
	u64(0x8000000080008000), u64(0x000000000000808B), u64(0x0000000080000001),
	u64(0x8000000080008081), u64(0x8000000000008009), u64(0x000000000000008A),
	u64(0x0000000000000088), u64(0x0000000080008009), u64(0x000000008000000A),
	u64(0x000000008000808B), u64(0x800000000000008B), u64(0x8000000000008089),
	u64(0x8000000000008003), u64(0x8000000000008002), u64(0x8000000000000080),
	u64(0x000000000000800A), u64(0x800000008000000A), u64(0x8000000080008081),
	u64(0x8000000000008080), u64(0x0000000080000001), u64(0x8000000080008008),
]

// Keccak rotation offsets for rho step
const keccak_rotc = [
	1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62,
	18, 39, 61, 20, 44,
]

// Keccak pi step lane indices
const keccak_piln = [
	10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20,
	14, 22, 9, 6, 1,
]

// rot64 rotates a u64 left by n bits
fn rot64(x u64, n int) u64 {
	return (x << u64(n)) | (x >> u64(64 - n))
}

// keccak_f1600 performs the Keccak-f[1600] permutation in place
fn keccak_f1600(mut st [25]u64) {
	mut bc := [5]u64{}
	for round in 0 .. 24 {
		// Theta
		for i in 0 .. 5 {
			bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20]
		}
		for i in 0 .. 5 {
			t := bc[(i + 4) % 5] ^ rot64(bc[(i + 1) % 5], 1)
			for j_ in [0, 5, 10, 15, 20] {
				st[j_ + i] ^= t
			}
		}
		// Rho and Pi
		t := st[1]
		mut cur := t
		for i in 0 .. 24 {
			j := keccak_piln[i]
			tmp := st[j]
			st[j] = rot64(cur, keccak_rotc[i])
			cur = tmp
		}
		// Chi
		for j_ in [0, 5, 10, 15, 20] {
			for i in 0 .. 5 {
				bc[i] = st[j_ + i]
			}
			for i in 0 .. 5 {
				st[j_ + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5]
			}
		}
		// Iota
		st[0] ^= keccak_rc[round]
	}
}

// keccak_hash computes SHA3 hash with given rate and output length
fn keccak_hash(input []u8, rate int, out_len int) []u8 {
	mut st := [25]u64{}

	// Absorb phase
	mut offset := 0
	for offset + rate <= input.len {
		for i in 0 .. rate / 8 {
			lane := u64(input[offset + i * 8]) |
				(u64(input[offset + i * 8 + 1]) << 8) |
				(u64(input[offset + i * 8 + 2]) << 16) |
				(u64(input[offset + i * 8 + 3]) << 24) |
				(u64(input[offset + i * 8 + 4]) << 32) |
				(u64(input[offset + i * 8 + 5]) << 40) |
				(u64(input[offset + i * 8 + 6]) << 48) |
				(u64(input[offset + i * 8 + 7]) << 56)
			st[i] ^= lane
		}
		keccak_f1600(mut st)
		offset += rate
	}

	// Pad: copy remaining bytes into temp buffer
	remaining := input.len - offset
	mut temp := []u8{len: rate, init: 0}
	for i in 0 .. remaining {
		temp[i] = input[offset + i]
	}
	// SHA3 domain separation byte
	temp[remaining] = 0x06
	temp[rate - 1] |= 0x80

	// XOR padded block into state
	for i in 0 .. rate / 8 {
		lane := u64(temp[i * 8]) |
			(u64(temp[i * 8 + 1]) << 8) |
			(u64(temp[i * 8 + 2]) << 16) |
			(u64(temp[i * 8 + 3]) << 24) |
			(u64(temp[i * 8 + 4]) << 32) |
			(u64(temp[i * 8 + 5]) << 40) |
			(u64(temp[i * 8 + 6]) << 48) |
			(u64(temp[i * 8 + 7]) << 56)
		st[i] ^= lane
	}
	keccak_f1600(mut st)

	// Squeeze: extract out_len bytes
	mut out := []u8{len: out_len}
	// Process full 8-byte lanes, plus any remaining bytes
	num_full_lanes := out_len / 8
	for i in 0 .. num_full_lanes {
		out[i * 8] = u8(st[i])
		out[i * 8 + 1] = u8(st[i] >> 8)
		out[i * 8 + 2] = u8(st[i] >> 16)
		out[i * 8 + 3] = u8(st[i] >> 24)
		out[i * 8 + 4] = u8(st[i] >> 32)
		out[i * 8 + 5] = u8(st[i] >> 40)
		out[i * 8 + 6] = u8(st[i] >> 48)
		out[i * 8 + 7] = u8(st[i] >> 56)
	}
	// Handle remaining bytes (e.g., 4 bytes for SHA3-224's 28-byte output)
	rem := out_len % 8
	if rem > 0 {
		lane := st[num_full_lanes]
		for j in 0 .. rem {
			out[num_full_lanes * 8 + j] = u8(lane >> (j * 8))
		}
	}
	return out
}

// md5(value)
fn fn_md5(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('md5 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('md5 requires a string') }
	}
	return VrlValue(md5.hexhash(s))
}

// hmac(value, key, [algorithm], [output])
fn fn_hmac(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('hmac requires at least 2 arguments')
	}
	a0 := args[0]
	a1 := args[1]
	value := match a0 {
		string { a0 }
		else { return error('hmac value must be a string') }
	}
	key := match a1 {
		string { a1 }
		else { return error('hmac key must be a string') }
	}
	algorithm := if args.len > 2 {
		v := args[2]
		match v {
			string { v }
			else { 'SHA-256' }
		}
	} else {
		'SHA-256'
	}
	mut raw_bytes := []u8{}
	match algorithm {
		'SHA-256' {
			h := hmac.new(key.bytes(), value.bytes(), sha256.sum, sha256.block_size)
			raw_bytes = h.clone()
		}
		'SHA-512' {
			h := hmac.new(key.bytes(), value.bytes(), sha512.sum512, sha512.block_size)
			raw_bytes = h.clone()
		}
		'SHA-1', 'SHA1' {
			h := hmac.new(key.bytes(), value.bytes(), sha1.sum, sha1.block_size)
			raw_bytes = h.clone()
		}
		'SHA-224' {
			h := hmac.new(key.bytes(), value.bytes(), sha256.sum224, sha256.block_size)
			raw_bytes = h[..28].clone()
		}
		'SHA-384' {
			h := hmac.new(key.bytes(), value.bytes(), sha512.sum384, sha512.block_size)
			raw_bytes = h[..48].clone()
		}
		else {
			return error('unsupported hmac algorithm: ${algorithm}')
		}
	}
	// Return raw bytes as a string (callers use encode_base64/encode_base16)
	return VrlValue(raw_bytes.bytestr())
}

// crc32(value) - Compute CRC32 checksum using IEEE polynomial
fn fn_crc32(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('crc32 requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('crc32 requires a string') }
	}
	checksum := crc32.sum(s.bytes())
	return VrlValue(i64(checksum))
}

// seahash(value) - SeaHash: a non-cryptographic hash function
// Reference: https://docs.rs/seahash
fn fn_seahash(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('seahash requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('seahash requires a string') }
	}
	h := seahash_hash(s.bytes())
	// Cast u64 to i64 (wrapping, same as upstream Rust `as i64`)
	return VrlValue(i64(h))
}

fn seahash_hash(data []u8) u64 {
	// SeaHash state (4 lanes)
	mut s0 := u64(0x16f11fe89b0d677c)
	mut s1 := u64(0xb480a793d8e6c86c)
	mut s2 := u64(0x6fe2e5aaf078ebc9)
	mut s3 := u64(0x14f994a4c5259381)
	mut written := u64(0)

	// Process 32-byte blocks
	mut i := 0
	for i + 32 <= data.len {
		s0 = seahash_diffuse(s0 ^ seahash_read_u64(data, i))
		s1 = seahash_diffuse(s1 ^ seahash_read_u64(data, i + 8))
		s2 = seahash_diffuse(s2 ^ seahash_read_u64(data, i + 16))
		s3 = seahash_diffuse(s3 ^ seahash_read_u64(data, i + 24))
		i += 32
		written += 32
	}

	// Process remaining 8-byte chunks via push (rotating state lanes)
	for i + 8 <= data.len {
		v := seahash_read_u64(data, i)
		a := seahash_diffuse(s0 ^ v)
		s0 = s1
		s1 = s2
		s2 = s3
		s3 = a
		i += 8
		written += 8
	}

	// Handle tail bytes (< 8 bytes)
	ntail := data.len - i
	if ntail > 0 {
		mut v := u64(0)
		for j in 0 .. ntail {
			v |= u64(data[i + j]) << u64(j * 8)
		}
		s0 = seahash_diffuse(s0 ^ v)
	}

	// Finalize: combine lanes with total length
	return seahash_diffuse(s0 ^ s1 ^ s2 ^ s3 ^ (written + u64(ntail)))
}

fn seahash_diffuse(mut_v u64) u64 {
	mut v := mut_v
	v = v * u64(0x6eed0e9da4d94a4f)
	a := v >> 32
	b := v >> 60
	v ^= a >> b
	v = v * u64(0x6eed0e9da4d94a4f)
	return v
}

fn seahash_read_u64(data []u8, offset int) u64 {
	return u64(data[offset]) |
		(u64(data[offset + 1]) << 8) |
		(u64(data[offset + 2]) << 16) |
		(u64(data[offset + 3]) << 24) |
		(u64(data[offset + 4]) << 32) |
		(u64(data[offset + 5]) << 40) |
		(u64(data[offset + 6]) << 48) |
		(u64(data[offset + 7]) << 56)
}

// xxHash C library bindings via wrapper to avoid namespace conflicts with V's bundled zstd/xxhash
#flag -lxxhash
#flag @VMODROOT/src/vrl/xxh3_128_wrapper.o
#include "@VMODROOT/src/vrl/xxhash_header.h"
fn C.xxhash_wrap_32(input voidptr, length usize, seed u32) u32
fn C.xxhash_wrap_64(input voidptr, length usize, seed u64) u64
fn C.xxhash_wrap_xxh3_64(input voidptr, length usize) u64
fn C.xxhash_wrap_xxh3_128(input voidptr, length usize, out_hi &u64, out_lo &u64)

// xxhash(value, [variant]) - xxHash non-cryptographic hash
// Supports: XXH32 (default), XXH64, XXH3-64, XXH3-128
fn fn_xxhash(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('xxhash requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('xxhash requires a string') }
	}
	variant := if args.len > 1 {
		v := args[1]
		match v {
			string { v }
			else { 'XXH32' }
		}
	} else {
		'XXH32'
	}
	data := s.bytes()
	match variant {
		'XXH32' {
			h := C.xxhash_wrap_32(data.data, usize(data.len), u32(0))
			return VrlValue(i64(h))
		}
		'XXH64' {
			h := C.xxhash_wrap_64(data.data, usize(data.len), u64(0))
			return VrlValue(i64(h))
		}
		'XXH3-64' {
			h := C.xxhash_wrap_xxh3_64(data.data, usize(data.len))
			return VrlValue(i64(h))
		}
		'XXH3-128' {
			mut hi := u64(0)
			mut lo := u64(0)
			C.xxhash_wrap_xxh3_128(data.data, usize(data.len), &hi, &lo)
			// Return as string "high64low64" in hex, matching upstream Rust format
			high_hex := u64_to_hex(hi)
			low_hex := u64_to_hex(lo)
			return VrlValue('${high_hex}${low_hex}')
		}
		else {
			return error("Variant must be either 'XXH32', 'XXH64', 'XXH3-64', or 'XXH3-128'")
		}
	}
}

fn u64_to_hex(v u64) string {
	mut result := []u8{cap: 16}
	for i := 60; i >= 0; i -= 4 {
		nibble := u8((v >> u64(i)) & 0xF)
		result << if nibble < 10 { `0` + nibble } else { `a` + nibble - 10 }
	}
	return result.bytestr()
}

// CRC algorithm parameters
struct CrcParams {
	width    int
	poly     u64
	init     u64
	refin    bool
	refout   bool
	xorout   u64
}

// crc(value, [algorithm]) - Generic CRC with many algorithm variants
// Default algorithm: CRC_32_ISO_HDLC
fn fn_crc(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('crc requires 1 argument')
	}
	a := args[0]
	s := match a {
		string { a }
		else { return error('crc requires a string') }
	}
	algorithm := if args.len > 1 {
		v := args[1]
		match v {
			string { v }
			else { 'CRC_32_ISO_HDLC' }
		}
	} else {
		'CRC_32_ISO_HDLC'
	}
	if algorithm == 'CRC_82_DARC' {
		return crc82_darc(s.bytes())
	}
	params := crc_get_params(algorithm) or { return error(err.msg()) }
	result := crc_compute(s.bytes(), params)
	return VrlValue('${result}')
}

fn crc_reflect(v u64, width int) u64 {
	mut r := u64(0)
	for i in 0 .. width {
		if (v >> u64(i)) & 1 != 0 {
			r |= u64(1) << u64(width - 1 - i)
		}
	}
	return r
}

fn crc_compute(data []u8, p CrcParams) u64 {
	mask := if p.width >= 64 { ~u64(0) } else { (u64(1) << u64(p.width)) - 1 }
	mut crc := p.init & mask

	for b in data {
		mut byte_val := u64(b)
		if p.refin {
			byte_val = crc_reflect(byte_val, 8)
		}
		if p.width >= 8 {
			crc ^= byte_val << u64(p.width - 8)
		} else {
			crc ^= byte_val >> u64(8 - p.width)
		}
		for _ in 0 .. 8 {
			if (crc >> u64(p.width - 1)) & 1 != 0 {
				crc = (crc << 1) ^ p.poly
			} else {
				crc = crc << 1
			}
			crc &= mask
		}
	}

	if p.refout {
		crc = crc_reflect(crc, p.width)
	}
	return (crc ^ p.xorout) & mask
}

fn crc_get_params(algorithm string) !CrcParams {
	match algorithm {
		// 3-bit
		'CRC_3_GSM' { return CrcParams{3, 0x3, 0x0, false, false, 0x7} }
		'CRC_3_ROHC' { return CrcParams{3, 0x3, 0x7, true, true, 0x0} }
		// 4-bit
		'CRC_4_G_704' { return CrcParams{4, 0x3, 0x0, true, true, 0x0} }
		'CRC_4_INTERLAKEN' { return CrcParams{4, 0x3, 0xF, false, false, 0xF} }
		// 5-bit
		'CRC_5_EPC_C1G2' { return CrcParams{5, 0x09, 0x09, false, false, 0x00} }
		'CRC_5_G_704' { return CrcParams{5, 0x15, 0x00, true, true, 0x00} }
		'CRC_5_USB' { return CrcParams{5, 0x05, 0x1F, true, true, 0x1F} }
		// 6-bit
		'CRC_6_CDMA2000_A' { return CrcParams{6, 0x27, 0x3F, false, false, 0x00} }
		'CRC_6_CDMA2000_B' { return CrcParams{6, 0x07, 0x3F, false, false, 0x00} }
		'CRC_6_DARC' { return CrcParams{6, 0x19, 0x00, true, true, 0x00} }
		'CRC_6_GSM' { return CrcParams{6, 0x2F, 0x00, false, false, 0x3F} }
		'CRC_6_G_704' { return CrcParams{6, 0x03, 0x00, true, true, 0x00} }
		// 7-bit
		'CRC_7_MMC' { return CrcParams{7, 0x09, 0x00, false, false, 0x00} }
		'CRC_7_ROHC' { return CrcParams{7, 0x4F, 0x7F, true, true, 0x00} }
		'CRC_7_UMTS' { return CrcParams{7, 0x45, 0x00, false, false, 0x00} }
		// 8-bit
		'CRC_8_AUTOSAR' { return CrcParams{8, 0x2F, 0xFF, false, false, 0xFF} }
		'CRC_8_BLUETOOTH' { return CrcParams{8, 0xA7, 0x00, true, true, 0x00} }
		'CRC_8_CDMA2000' { return CrcParams{8, 0x9B, 0xFF, false, false, 0x00} }
		'CRC_8_DARC' { return CrcParams{8, 0x39, 0x00, true, true, 0x00} }
		'CRC_8_DVB_S2' { return CrcParams{8, 0xD5, 0x00, false, false, 0x00} }
		'CRC_8_GSM_A' { return CrcParams{8, 0x1D, 0x00, false, false, 0x00} }
		'CRC_8_GSM_B' { return CrcParams{8, 0x49, 0x00, false, false, 0xFF} }
		'CRC_8_HITAG' { return CrcParams{8, 0x1D, 0xFF, false, false, 0x00} }
		'CRC_8_I_432_1' { return CrcParams{8, 0x07, 0x00, false, false, 0x55} }
		'CRC_8_I_CODE' { return CrcParams{8, 0x1D, 0xFD, false, false, 0x00} }
		'CRC_8_LTE' { return CrcParams{8, 0x9B, 0x00, false, false, 0x00} }
		'CRC_8_MAXIM_DOW' { return CrcParams{8, 0x31, 0x00, true, true, 0x00} }
		'CRC_8_MIFARE_MAD' { return CrcParams{8, 0x1D, 0xC7, false, false, 0x00} }
		'CRC_8_NRSC_5' { return CrcParams{8, 0x31, 0xFF, false, false, 0x00} }
		'CRC_8_OPENSAFETY' { return CrcParams{8, 0x2F, 0x00, false, false, 0x00} }
		'CRC_8_ROHC' { return CrcParams{8, 0x07, 0xFF, true, true, 0x00} }
		'CRC_8_SAE_J1850' { return CrcParams{8, 0x1D, 0xFF, false, false, 0xFF} }
		'CRC_8_SMBUS' { return CrcParams{8, 0x07, 0x00, false, false, 0x00} }
		'CRC_8_TECH_3250' { return CrcParams{8, 0x1D, 0xFF, true, true, 0x00} }
		'CRC_8_WCDMA' { return CrcParams{8, 0x9B, 0x00, true, true, 0x00} }
		// 10-bit
		'CRC_10_ATM' { return CrcParams{10, 0x233, 0x000, false, false, 0x000} }
		'CRC_10_CDMA2000' { return CrcParams{10, 0x3D9, 0x3FF, false, false, 0x000} }
		'CRC_10_GSM' { return CrcParams{10, 0x175, 0x000, false, false, 0x3FF} }
		// 11-bit
		'CRC_11_FLEXRAY' { return CrcParams{11, 0x385, 0x01A, false, false, 0x000} }
		'CRC_11_UMTS' { return CrcParams{11, 0x307, 0x000, false, false, 0x000} }
		// 12-bit
		'CRC_12_CDMA2000' { return CrcParams{12, 0xF13, 0xFFF, false, false, 0x000} }
		'CRC_12_DECT' { return CrcParams{12, 0x80F, 0x000, false, false, 0x000} }
		'CRC_12_GSM' { return CrcParams{12, 0xD31, 0x000, false, false, 0xFFF} }
		'CRC_12_UMTS' { return CrcParams{12, 0x80F, 0x000, false, true, 0x000} }
		// 13-bit
		'CRC_13_BBC' { return CrcParams{13, 0x1CF5, 0x0000, false, false, 0x0000} }
		// 14-bit
		'CRC_14_DARC' { return CrcParams{14, 0x0805, 0x0000, true, true, 0x0000} }
		'CRC_14_GSM' { return CrcParams{14, 0x202D, 0x0000, false, false, 0x3FFF} }
		// 15-bit
		'CRC_15_CAN' { return CrcParams{15, 0x4599, 0x0000, false, false, 0x0000} }
		'CRC_15_MPT1327' { return CrcParams{15, 0x6815, 0x0000, false, false, 0x0001} }
		// 16-bit
		'CRC_16_ARC' { return CrcParams{16, 0x8005, 0x0000, true, true, 0x0000} }
		'CRC_16_CDMA2000' { return CrcParams{16, 0xC867, 0xFFFF, false, false, 0x0000} }
		'CRC_16_CMS' { return CrcParams{16, 0x8005, 0xFFFF, false, false, 0x0000} }
		'CRC_16_DDS_110' { return CrcParams{16, 0x8005, 0x800D, false, false, 0x0000} }
		'CRC_16_DECT_R' { return CrcParams{16, 0x0589, 0x0000, false, false, 0x0001} }
		'CRC_16_DECT_X' { return CrcParams{16, 0x0589, 0x0000, false, false, 0x0000} }
		'CRC_16_DNP' { return CrcParams{16, 0x3D65, 0x0000, true, true, 0xFFFF} }
		'CRC_16_EN_13757' { return CrcParams{16, 0x3D65, 0x0000, false, false, 0xFFFF} }
		'CRC_16_GENIBUS' { return CrcParams{16, 0x1021, 0xFFFF, false, false, 0xFFFF} }
		'CRC_16_GSM' { return CrcParams{16, 0x1021, 0x0000, false, false, 0xFFFF} }
		'CRC_16_IBM_3740' { return CrcParams{16, 0x1021, 0xFFFF, false, false, 0x0000} }
		'CRC_16_IBM_SDLC' { return CrcParams{16, 0x1021, 0xFFFF, true, true, 0xFFFF} }
		'CRC_16_ISO_IEC_14443_3_A' { return CrcParams{16, 0x1021, 0x6363, true, true, 0x0000} }
		'CRC_16_KERMIT' { return CrcParams{16, 0x1021, 0x0000, true, true, 0x0000} }
		'CRC_16_LJ1200' { return CrcParams{16, 0x6F63, 0x0000, false, false, 0x0000} }
		'CRC_16_M17' { return CrcParams{16, 0x5935, 0xFFFF, false, false, 0x0000} }
		'CRC_16_MAXIM_DOW' { return CrcParams{16, 0x8005, 0x0000, true, true, 0xFFFF} }
		'CRC_16_MCRF4XX' { return CrcParams{16, 0x1021, 0xFFFF, true, true, 0x0000} }
		'CRC_16_MODBUS' { return CrcParams{16, 0x8005, 0xFFFF, true, true, 0x0000} }
		'CRC_16_NRSC_5' { return CrcParams{16, 0x080B, 0xFFFF, true, true, 0x0000} }
		'CRC_16_OPENSAFETY_A' { return CrcParams{16, 0x5935, 0x0000, false, false, 0x0000} }
		'CRC_16_OPENSAFETY_B' { return CrcParams{16, 0x755B, 0x0000, false, false, 0x0000} }
		'CRC_16_PROFIBUS' { return CrcParams{16, 0x1DCF, 0xFFFF, false, false, 0xFFFF} }
		'CRC_16_RIELLO' { return CrcParams{16, 0x1021, 0xB2AA, true, true, 0x0000} }
		'CRC_16_SPI_FUJITSU' { return CrcParams{16, 0x1021, 0x1D0F, false, false, 0x0000} }
		'CRC_16_T10_DIF' { return CrcParams{16, 0x8BB7, 0x0000, false, false, 0x0000} }
		'CRC_16_TELEDISK' { return CrcParams{16, 0xA097, 0x0000, false, false, 0x0000} }
		'CRC_16_TMS37157' { return CrcParams{16, 0x1021, 0x89EC, true, true, 0x0000} }
		'CRC_16_UMTS' { return CrcParams{16, 0x8005, 0x0000, false, false, 0x0000} }
		'CRC_16_USB' { return CrcParams{16, 0x8005, 0xFFFF, true, true, 0xFFFF} }
		'CRC_16_XMODEM' { return CrcParams{16, 0x1021, 0x0000, false, false, 0x0000} }
		// 17-bit
		'CRC_17_CAN_FD' { return CrcParams{17, 0x1685B, 0x00000, false, false, 0x00000} }
		// 21-bit
		'CRC_21_CAN_FD' { return CrcParams{21, 0x102899, 0x000000, false, false, 0x000000} }
		// 24-bit
		'CRC_24_BLE' { return CrcParams{24, 0x00065B, 0x555555, true, true, 0x000000} }
		'CRC_24_FLEXRAY_A' { return CrcParams{24, 0x5D6DCB, 0xFEDCBA, false, false, 0x000000} }
		'CRC_24_FLEXRAY_B' { return CrcParams{24, 0x5D6DCB, 0xABCDEF, false, false, 0x000000} }
		'CRC_24_INTERLAKEN' { return CrcParams{24, 0x328B63, 0xFFFFFF, false, false, 0xFFFFFF} }
		'CRC_24_LTE_A' { return CrcParams{24, 0x864CFB, 0x000000, false, false, 0x000000} }
		'CRC_24_LTE_B' { return CrcParams{24, 0x800063, 0x000000, false, false, 0x000000} }
		'CRC_24_OPENPGP' { return CrcParams{24, 0x864CFB, 0xB704CE, false, false, 0x000000} }
		'CRC_24_OS_9' { return CrcParams{24, 0x800063, 0xFFFFFF, false, false, 0xFFFFFF} }
		// 30-bit
		'CRC_30_CDMA' { return CrcParams{30, 0x2030B9C7, 0x3FFFFFFF, false, false, 0x3FFFFFFF} }
		// 31-bit
		'CRC_31_PHILIPS' { return CrcParams{31, 0x04C11DB7, 0x7FFFFFFF, false, false, 0x7FFFFFFF} }
		// 32-bit
		'CRC_32_AIXM' { return CrcParams{32, 0x814141AB, 0x00000000, false, false, 0x00000000} }
		'CRC_32_AUTOSAR' { return CrcParams{32, 0xF4ACFB13, 0xFFFFFFFF, true, true, 0xFFFFFFFF} }
		'CRC_32_BASE91_D' { return CrcParams{32, 0xA833982B, 0xFFFFFFFF, true, true, 0xFFFFFFFF} }
		'CRC_32_BZIP2' { return CrcParams{32, 0x04C11DB7, 0xFFFFFFFF, false, false, 0xFFFFFFFF} }
		'CRC_32_CD_ROM_EDC' { return CrcParams{32, 0x8001801B, 0x00000000, true, true, 0x00000000} }
		'CRC_32_CKSUM' { return CrcParams{32, 0x04C11DB7, 0x00000000, false, false, 0xFFFFFFFF} }
		'CRC_32_ISCSI' { return CrcParams{32, 0x1EDC6F41, 0xFFFFFFFF, true, true, 0xFFFFFFFF} }
		'CRC_32_ISO_HDLC' { return CrcParams{32, 0x04C11DB7, 0xFFFFFFFF, true, true, 0xFFFFFFFF} }
		'CRC_32_JAMCRC' { return CrcParams{32, 0x04C11DB7, 0xFFFFFFFF, true, true, 0x00000000} }
		'CRC_32_MEF' { return CrcParams{32, 0x741B8CD7, 0xFFFFFFFF, true, true, 0x00000000} }
		'CRC_32_MPEG_2' { return CrcParams{32, 0x04C11DB7, 0xFFFFFFFF, false, false, 0x00000000} }
		'CRC_32_XFER' { return CrcParams{32, 0x000000AF, 0x00000000, false, false, 0x00000000} }
		// 40-bit
		'CRC_40_GSM' { return CrcParams{40, 0x0004820009, 0x0000000000, false, false, 0xFFFFFFFFFF} }
		// 64-bit
		'CRC_64_ECMA_182' { return CrcParams{64, 0x42F0E1EBA9EA3693, 0x0000000000000000, false, false, 0x0000000000000000} }
		'CRC_64_GO_ISO' { return CrcParams{64, 0x000000000000001B, 0xFFFFFFFFFFFFFFFF, true, true, 0xFFFFFFFFFFFFFFFF} }
		'CRC_64_MS' { return CrcParams{64, 0x259C84CBA6426349, 0xFFFFFFFFFFFFFFFF, true, true, 0x0000000000000000} }
		'CRC_64_REDIS' { return CrcParams{64, 0xAD93D23594C935A9, 0x0000000000000000, true, true, 0x0000000000000000} }
		'CRC_64_WE' { return CrcParams{64, 0x42F0E1EBA9EA3693, 0xFFFFFFFFFFFFFFFF, false, false, 0xFFFFFFFFFFFFFFFF} }
		'CRC_64_XZ' { return CrcParams{64, 0x42F0E1EBA9EA3693, 0xFFFFFFFFFFFFFFFF, true, true, 0xFFFFFFFFFFFFFFFF} }
		else { return error('Invalid CRC algorithm: ${algorithm}') }
	}
}

// CRC-82/DARC: width=82, poly=0x0308C0111011401440411, init=0, refin=true, refout=true, xorout=0
// Uses u128 emulation via high/low u64 pair
fn crc82_darc(data []u8) !VrlValue {
	// poly = 0x0308C0111011401440411 (82-bit)
	// poly >> 64 = 0x308C, poly & 0xFFFFFFFFFFFFFFFF = 0x0111011401440411
	poly_hi := u64(0x308C)
	poly_lo := u64(0x0111011401440411)
	mask_hi := u64(0x3FFFF) // top 18 bits of 82-bit value
	mask_lo := ~u64(0) // full 64 bits

	mut crc_hi := u64(0)
	mut crc_lo := u64(0)

	for b in data {
		// reflect input byte
		byte_val := crc_reflect(u64(b), 8)

		// XOR byte into top of 82-bit CRC: crc ^= byte_val << 74
		// 74 = 64 + 10, so shift goes into high part
		crc_hi ^= byte_val << 10

		for _ in 0 .. 8 {
			// Check top bit (bit 81)
			top_bit := (crc_hi >> 17) & 1
			// Shift left by 1: carry from bit 63 of low to bit 0 of high
			carry := (crc_lo >> 63) & 1
			crc_lo = crc_lo << 1
			crc_hi = (crc_hi << 1) | carry
			if top_bit != 0 {
				crc_lo ^= poly_lo
				crc_hi ^= poly_hi
			}
			// Mask to 82 bits
			crc_hi &= mask_hi
			crc_lo &= mask_lo
		}
	}

	// reflect output (82 bits)
	mut out_hi := u64(0)
	mut out_lo := u64(0)
	// Reflect 82-bit value: bit i -> bit 81-i
	for i in 0 .. 82 {
		mut src_bit := u64(0)
		if i < 64 {
			src_bit = (crc_lo >> u64(i)) & 1
		} else {
			src_bit = (crc_hi >> u64(i - 64)) & 1
		}
		dest := 81 - i
		if dest < 64 {
			out_lo |= src_bit << u64(dest)
		} else {
			out_hi |= src_bit << u64(dest - 64)
		}
	}

	// xorout = 0, so no XOR needed
	// Format as decimal string (matching upstream)
	return VrlValue(u128_to_decimal(out_hi, out_lo))
}

// Convert a 128-bit value (hi:lo) to decimal string
fn u128_to_decimal(hi u64, lo u64) string {
	if hi == 0 {
		return '${lo}'
	}
	// Use repeated division by 10
	mut digits := []u8{}
	mut h := hi
	mut l := lo
	for h > 0 || l > 0 {
		// Divide 128-bit (h:l) by 10, get remainder
		mut rem := h % 10
		h = h / 10
		// Now divide (rem:l) where rem is < 10
		// l_new = (rem << 64 + l) / 10, new_rem = (rem << 64 + l) % 10
		// Split into manageable parts to avoid overflow
		full_hi := rem
		// (full_hi << 64 + l) / 10
		// = (full_hi * (2^64 / 10) * 10 + full_hi * (2^64 % 10) + l) / 10
		// Simpler: use the standard long division approach
		// dividend = full_hi * 2^64 + l
		// 2^64 = 1844674407370955161 * 10 + 6
		q_from_hi := full_hi * u64(1844674407370955161)
		r_from_hi := full_hi * 6
		sum := l + r_from_hi
		carry := if sum < l { u64(1) } else { u64(0) }
		q_from_lo := sum / 10
		rem = sum % 10
		l = q_from_hi + q_from_lo + carry * u64(1844674407370955161) + (carry * 6 + rem) / 10
		rem = (carry * 6 + rem) % 10
		digits << u8(`0` + rem)
	}
	if digits.len == 0 {
		return '0'
	}
	// Reverse digits
	mut result := []u8{cap: digits.len}
	for i := digits.len - 1; i >= 0; i-- {
		result << digits[i]
	}
	return result.bytestr()
}
