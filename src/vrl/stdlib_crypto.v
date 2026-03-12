module vrl

import crypto.md5
import crypto.sha1
import crypto.sha256
import crypto.sha512
import crypto.hmac

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

// sha3 - not available in V stdlib, return error
fn fn_sha3(args []VrlValue) !VrlValue {
	return error('sha3 is not supported in this runtime')
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
