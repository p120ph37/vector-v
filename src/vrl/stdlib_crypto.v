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
