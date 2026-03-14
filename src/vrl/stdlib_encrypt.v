module vrl

import crypto.aes
import crypto.cipher
import rand
import x.crypto.chacha20poly1305

// ============================================================================
// Cipher algorithm table
// ============================================================================

enum CipherMode {
	cfb
	ofb
	ctr
	ctr_le
	cbc
	siv
	chacha20_poly1305
	xchacha20_poly1305 // unsupported
	xsalsa20_poly1305  // unsupported
}

struct CipherInfo {
	mode        CipherMode
	key_len     int
	iv_len      int
	cbc_padding string // PKCS7, ANSIX923, ISO7816, ISO10126
}

fn get_cipher_info(algorithm string) !CipherInfo {
	return match algorithm {
		// AES-CFB
		'AES-256-CFB' { CipherInfo{ mode: .cfb, key_len: 32, iv_len: 16 } }
		'AES-192-CFB' { CipherInfo{ mode: .cfb, key_len: 24, iv_len: 16 } }
		'AES-128-CFB' { CipherInfo{ mode: .cfb, key_len: 16, iv_len: 16 } }
		// AES-OFB
		'AES-256-OFB' { CipherInfo{ mode: .ofb, key_len: 32, iv_len: 16 } }
		'AES-192-OFB' { CipherInfo{ mode: .ofb, key_len: 24, iv_len: 16 } }
		'AES-128-OFB' { CipherInfo{ mode: .ofb, key_len: 16, iv_len: 16 } }
		// AES-CTR (deprecated = BE)
		'AES-256-CTR', 'AES-256-CTR-BE' { CipherInfo{ mode: .ctr, key_len: 32, iv_len: 16 } }
		'AES-192-CTR', 'AES-192-CTR-BE' { CipherInfo{ mode: .ctr, key_len: 24, iv_len: 16 } }
		'AES-128-CTR', 'AES-128-CTR-BE' { CipherInfo{ mode: .ctr, key_len: 16, iv_len: 16 } }
		// AES-CTR-LE
		'AES-256-CTR-LE' { CipherInfo{ mode: .ctr_le, key_len: 32, iv_len: 16 } }
		'AES-192-CTR-LE' { CipherInfo{ mode: .ctr_le, key_len: 24, iv_len: 16 } }
		'AES-128-CTR-LE' { CipherInfo{ mode: .ctr_le, key_len: 16, iv_len: 16 } }
		// AES-CBC
		'AES-256-CBC-PKCS7' { CipherInfo{ mode: .cbc, key_len: 32, iv_len: 16, cbc_padding: 'PKCS7' } }
		'AES-192-CBC-PKCS7' { CipherInfo{ mode: .cbc, key_len: 24, iv_len: 16, cbc_padding: 'PKCS7' } }
		'AES-128-CBC-PKCS7' { CipherInfo{ mode: .cbc, key_len: 16, iv_len: 16, cbc_padding: 'PKCS7' } }
		'AES-256-CBC-ANSIX923' { CipherInfo{ mode: .cbc, key_len: 32, iv_len: 16, cbc_padding: 'ANSIX923' } }
		'AES-192-CBC-ANSIX923' { CipherInfo{ mode: .cbc, key_len: 24, iv_len: 16, cbc_padding: 'ANSIX923' } }
		'AES-128-CBC-ANSIX923' { CipherInfo{ mode: .cbc, key_len: 16, iv_len: 16, cbc_padding: 'ANSIX923' } }
		'AES-256-CBC-ISO7816' { CipherInfo{ mode: .cbc, key_len: 32, iv_len: 16, cbc_padding: 'ISO7816' } }
		'AES-192-CBC-ISO7816' { CipherInfo{ mode: .cbc, key_len: 24, iv_len: 16, cbc_padding: 'ISO7816' } }
		'AES-128-CBC-ISO7816' { CipherInfo{ mode: .cbc, key_len: 16, iv_len: 16, cbc_padding: 'ISO7816' } }
		'AES-256-CBC-ISO10126' { CipherInfo{ mode: .cbc, key_len: 32, iv_len: 16, cbc_padding: 'ISO10126' } }
		'AES-192-CBC-ISO10126' { CipherInfo{ mode: .cbc, key_len: 24, iv_len: 16, cbc_padding: 'ISO10126' } }
		'AES-128-CBC-ISO10126' { CipherInfo{ mode: .cbc, key_len: 16, iv_len: 16, cbc_padding: 'ISO10126' } }
		// AES-SIV (OpenSSL 3.0 only)
		'AES-128-SIV' { CipherInfo{ mode: .siv, key_len: 32, iv_len: 16 } }
		'AES-256-SIV' { CipherInfo{ mode: .siv, key_len: 64, iv_len: 16 } }
		// CHACHA20-POLY1305 (native V)
		'CHACHA20-POLY1305' { CipherInfo{ mode: .chacha20_poly1305, key_len: 32, iv_len: 12 } }
		// Not available without libsodium
		'XCHACHA20-POLY1305' { CipherInfo{ mode: .xchacha20_poly1305, key_len: 32, iv_len: 24 } }
		'XSALSA20-POLY1305' { CipherInfo{ mode: .xsalsa20_poly1305, key_len: 32, iv_len: 24 } }
		else { return error('Invalid algorithm: ${algorithm}') }
	}
}

// ============================================================================
// encrypt / decrypt using V native crypto (CFB, OFB, CTR, CBC)
// ============================================================================

fn v_aes_encrypt(plaintext []u8, key []u8, iv []u8, info CipherInfo) ![]u8 {
	block := aes.new_cipher(key)
	mut out := []u8{len: plaintext.len}

	match info.mode {
		.cfb {
			mut enc := cipher.new_cfb_encrypter(block, iv)
			enc.xor_key_stream(mut out, plaintext)
		}
		.ofb {
			mut ofb_ := cipher.new_ofb(block, iv)
			ofb_.xor_key_stream(mut out, plaintext)
		}
		.ctr, .ctr_le {
			actual_iv := if info.mode == .ctr_le { reverse_bytes(iv) } else { iv }
			mut ctr_ := cipher.new_ctr(block, actual_iv)
			ctr_.xor_key_stream(mut out, plaintext)
		}
		.cbc {
			padded := add_padding(plaintext, 16, info.cbc_padding)
			mut cbc_out := []u8{len: padded.len}
			mut cbc_ := cipher.new_cbc(block, iv)
			cbc_.encrypt_blocks(mut cbc_out, padded)
			return cbc_out
		}
		else {
			return error('internal: unexpected mode for V AES')
		}
	}
	return out
}

fn v_aes_decrypt(ciphertext_ []u8, key []u8, iv []u8, info CipherInfo) ![]u8 {
	block := aes.new_cipher(key)
	mut out := []u8{len: ciphertext_.len}

	match info.mode {
		.cfb {
			mut dec := cipher.new_cfb_decrypter(block, iv)
			dec.xor_key_stream(mut out, ciphertext_)
		}
		.ofb {
			mut ofb_ := cipher.new_ofb(block, iv)
			ofb_.xor_key_stream(mut out, ciphertext_)
		}
		.ctr, .ctr_le {
			actual_iv := if info.mode == .ctr_le { reverse_bytes(iv) } else { iv }
			mut ctr_ := cipher.new_ctr(block, actual_iv)
			ctr_.xor_key_stream(mut out, ciphertext_)
		}
		.cbc {
			mut cbc_ := cipher.new_cbc(block, iv)
			cbc_.decrypt_blocks(mut out, ciphertext_)
			return remove_padding(out, info.cbc_padding)
		}
		else {
			return error('internal: unexpected mode for V AES')
		}
	}
	return out
}

// ============================================================================
// Native AES-ECB (single block, no padding — used for encrypt_ip)
// ============================================================================

fn v_aes_ecb_encrypt(data []u8, key []u8) ![]u8 {
	if data.len != 16 {
		return error('ECB encrypt: data must be exactly 16 bytes')
	}
	block := aes.new_cipher(key)
	mut out := []u8{len: 16}
	block.encrypt(mut out, data)
	return out
}

fn v_aes_ecb_decrypt(data []u8, key []u8) ![]u8 {
	if data.len != 16 {
		return error('ECB decrypt: data must be exactly 16 bytes')
	}
	block := aes.new_cipher(key)
	mut out := []u8{len: 16}
	block.decrypt(mut out, data)
	return out
}

// ============================================================================
// Native AES-CMAC (RFC 4493) — building block for AES-SIV
// ============================================================================

fn aes_cmac(key []u8, message []u8) []u8 {
	block := aes.new_cipher(key)

	// Generate subkeys K1, K2
	mut zero := []u8{len: 16}
	mut l := []u8{len: 16}
	block.encrypt(mut l, zero)
	k1 := cmac_dbl(l)
	k2 := cmac_dbl(k1)

	n := if message.len == 0 { 1 } else { (message.len + 15) / 16 }
	last_block_complete := message.len > 0 && message.len % 16 == 0

	mut x := []u8{len: 16}
	// Process all blocks except the last
	for i in 0 .. n - 1 {
		mut y := []u8{len: 16}
		for j in 0 .. 16 {
			y[j] = x[j] ^ message[i * 16 + j]
		}
		block.encrypt(mut x, y)
	}

	// Process the last block
	mut last := []u8{len: 16}
	if last_block_complete {
		offset := (n - 1) * 16
		for j in 0 .. 16 {
			last[j] = message[offset + j] ^ k1[j]
		}
	} else {
		// Pad: message || 10...0
		offset := (n - 1) * 16
		remaining := message.len - offset
		for j in 0 .. remaining {
			last[j] = message[offset + j]
		}
		last[remaining] = 0x80
		for j in 0 .. 16 {
			last[j] ^= k2[j]
		}
	}
	mut y := []u8{len: 16}
	for j in 0 .. 16 {
		y[j] = x[j] ^ last[j]
	}
	mut mac := []u8{len: 16}
	block.encrypt(mut mac, y)
	return mac
}

fn cmac_dbl(data []u8) []u8 {
	mut result := []u8{len: 16}
	carry := data[0] >> 7
	for i in 0 .. 15 {
		result[i] = (data[i] << 1) | (data[i + 1] >> 7)
	}
	result[15] = data[15] << 1
	if carry == 1 {
		result[15] ^= 0x87 // Rb for 128-bit
	}
	return result
}

// ============================================================================
// Native AES-SIV (RFC 5297) — using CMAC + CTR
// ============================================================================

fn v_encrypt_siv(plaintext []u8, key []u8, nonce []u8) ![]u8 {
	// SIV key is split: first half = MAC key, second half = CTR key
	half := key.len / 2
	mac_key := key[..half]
	ctr_key := key[half..]

	// S2V: compute the SIV tag
	siv_tag := s2v(mac_key, nonce, plaintext)

	// CTR encrypt with SIV tag as IV (clear bits 31 and 63)
	mut ctr_iv := siv_tag.clone()
	ctr_iv[8] &= 0x7F
	ctr_iv[12] &= 0x7F

	ctr_block := aes.new_cipher(ctr_key)
	mut ciphertext := []u8{len: plaintext.len}
	mut ctr_ := cipher.new_ctr(ctr_block, ctr_iv)
	ctr_.xor_key_stream(mut ciphertext, plaintext)

	// Output: tag || ciphertext
	mut result := siv_tag.clone()
	result << ciphertext
	return result
}

fn v_decrypt_siv(ciphertext_with_tag []u8, key []u8, nonce []u8) ![]u8 {
	if ciphertext_with_tag.len < 16 {
		return error('decryption failed: ciphertext too short for SIV tag')
	}
	tag := ciphertext_with_tag[..16]
	ct := ciphertext_with_tag[16..]

	half := key.len / 2
	mac_key := key[..half]
	ctr_key := key[half..]

	// CTR decrypt
	mut ctr_iv := tag.clone()
	ctr_iv[8] &= 0x7F
	ctr_iv[12] &= 0x7F

	ctr_block := aes.new_cipher(ctr_key)
	mut plaintext := []u8{len: ct.len}
	mut ctr_ := cipher.new_ctr(ctr_block, ctr_iv)
	ctr_.xor_key_stream(mut plaintext, ct)

	// Verify tag
	expected := s2v(mac_key, nonce, plaintext)
	mut ok := true
	for i in 0 .. 16 {
		if expected[i] != tag[i] {
			ok = false
		}
	}
	if !ok {
		return error('decryption failed: authentication failed')
	}
	return plaintext
}

fn s2v(mac_key []u8, nonce []u8, plaintext []u8) []u8 {
	// S2V with 1 associated data string (nonce) + plaintext
	zero := []u8{len: 16}
	d := aes_cmac(mac_key, zero) // CMAC(zero)

	// Process nonce as AD
	d2 := cmac_xor_dbl(d, aes_cmac(mac_key, nonce))

	// Final: if plaintext >= 16 bytes, xor-end; else pad and dbl
	if plaintext.len >= 16 {
		mut t := plaintext.clone()
		offset := t.len - 16
		for i in 0 .. 16 {
			t[offset + i] ^= d2[i]
		}
		return aes_cmac(mac_key, t)
	} else {
		// Pad plaintext: plaintext || 10...0
		mut padded := plaintext.clone()
		padded << u8(0x80)
		for padded.len < 16 {
			padded << u8(0)
		}
		d3 := cmac_dbl(d2)
		for i in 0 .. 16 {
			padded[i] ^= d3[i]
		}
		return aes_cmac(mac_key, padded)
	}
}

fn cmac_xor_dbl(d []u8, cmac_val []u8) []u8 {
	doubled := cmac_dbl(d)
	mut result := []u8{len: 16}
	for i in 0 .. 16 {
		result[i] = doubled[i] ^ cmac_val[i]
	}
	return result
}

// ============================================================================
// Native V: AEAD (CHACHA20-POLY1305) via x.crypto.chacha20poly1305
// ============================================================================

fn v_encrypt_chacha20_poly1305(plaintext []u8, key []u8, nonce []u8) ![]u8 {
	// Returns ciphertext with appended 16-byte Poly1305 tag
	return chacha20poly1305.encrypt(plaintext, key, nonce, []) or {
		return error('encryption failed: ${err}')
	}
}

fn v_decrypt_chacha20_poly1305(ciphertext_with_tag []u8, key []u8, nonce []u8) ![]u8 {
	if ciphertext_with_tag.len < 16 {
		return error('decryption failed: ciphertext too short for authentication tag')
	}
	return chacha20poly1305.decrypt(ciphertext_with_tag, key, nonce, []) or {
		return error('decryption failed: authentication failed')
	}
}


// ============================================================================
// Padding helpers (CBC modes)
// ============================================================================

fn add_padding(data []u8, block_size int, padding string) []u8 {
	pad_len := block_size - (data.len % block_size)
	mut padded := data.clone()
	match padding {
		'PKCS7' {
			for _ in 0 .. pad_len {
				padded << u8(pad_len)
			}
		}
		'ANSIX923' {
			for _ in 0 .. pad_len - 1 {
				padded << u8(0)
			}
			padded << u8(pad_len)
		}
		'ISO7816' {
			padded << u8(0x80)
			for _ in 0 .. pad_len - 1 {
				padded << u8(0)
			}
		}
		'ISO10126' {
			mut rand_bytes := []u8{len: pad_len - 1}
			for i in 0 .. pad_len - 1 {
				rand_bytes[i] = u8(rand.u32() & 0xFF)
			}
			padded << rand_bytes
			padded << u8(pad_len)
		}
		else {}
	}
	return padded
}

fn remove_padding(data []u8, padding string) ![]u8 {
	if data.len == 0 {
		return error('decryption failed: empty data')
	}
	match padding {
		'PKCS7' {
			pad_len := int(data[data.len - 1])
			if pad_len == 0 || pad_len > 16 || pad_len > data.len {
				return error('decryption failed: invalid PKCS7 padding')
			}
			for i in 0 .. pad_len {
				if data[data.len - 1 - i] != u8(pad_len) {
					return error('decryption failed: invalid PKCS7 padding')
				}
			}
			return data[..data.len - pad_len].clone()
		}
		'ANSIX923' {
			pad_len := int(data[data.len - 1])
			if pad_len == 0 || pad_len > 16 || pad_len > data.len {
				return error('decryption failed: invalid ANSIX923 padding')
			}
			for i in 1 .. pad_len {
				if data[data.len - 1 - i] != 0 {
					return error('decryption failed: invalid ANSIX923 padding')
				}
			}
			return data[..data.len - pad_len].clone()
		}
		'ISO7816' {
			mut i := data.len - 1
			for i >= 0 && data[i] == 0 {
				i--
			}
			if i < 0 || data[i] != 0x80 {
				return error('decryption failed: invalid ISO7816 padding')
			}
			return data[..i].clone()
		}
		'ISO10126' {
			pad_len := int(data[data.len - 1])
			if pad_len == 0 || pad_len > 16 || pad_len > data.len {
				return error('decryption failed: invalid ISO10126 padding')
			}
			return data[..data.len - pad_len].clone()
		}
		else {
			return data.clone()
		}
	}
}

fn reverse_bytes(data []u8) []u8 {
	mut result := []u8{len: data.len}
	for i in 0 .. data.len {
		result[i] = data[data.len - 1 - i]
	}
	return result
}

// ============================================================================
// fn_encrypt / fn_decrypt — VRL function implementations
// ============================================================================

fn fn_encrypt(args []VrlValue) !VrlValue {
	if args.len < 4 {
		return error('encrypt requires 4 arguments')
	}
	plaintext := match args[0] {
		string { args[0] as string }
		else { return error('encrypt plaintext must be a string') }
	}
	algorithm := match args[1] {
		string { args[1] as string }
		else { return error('encrypt algorithm must be a string') }
	}
	key_str := match args[2] {
		string { args[2] as string }
		else { return error('encrypt key must be a string') }
	}
	iv_str := match args[3] {
		string { args[3] as string }
		else { return error('encrypt iv must be a string') }
	}

	info := get_cipher_info(algorithm)!
	key_bytes := key_str.bytes()
	iv_bytes := iv_str.bytes()

	if key_bytes.len != info.key_len {
		return error('Invalid key length. Expected ${info.key_len} bytes, got ${key_bytes.len}')
	}
	if iv_bytes.len != info.iv_len {
		return error('Invalid iv length. Expected ${info.iv_len} bytes, got ${iv_bytes.len}')
	}

	pt := plaintext.bytes()

	result := match info.mode {
		.cfb, .ofb, .ctr, .ctr_le, .cbc {
			v_aes_encrypt(pt, key_bytes, iv_bytes, info)!
		}
		.siv {
			v_encrypt_siv(pt, key_bytes, iv_bytes)!
		}
		.chacha20_poly1305 {
			v_encrypt_chacha20_poly1305(pt, key_bytes, iv_bytes)!
		}
		.xchacha20_poly1305, .xsalsa20_poly1305 {
			return error('${algorithm} requires libsodium which is not available')
		}
	}
	return VrlValue(result.bytestr())
}

fn fn_decrypt(args []VrlValue) !VrlValue {
	if args.len < 4 {
		return error('decrypt requires 4 arguments')
	}
	ct_str := match args[0] {
		string { args[0] as string }
		else { return error('decrypt ciphertext must be a string') }
	}
	algorithm := match args[1] {
		string { args[1] as string }
		else { return error('decrypt algorithm must be a string') }
	}
	key_str := match args[2] {
		string { args[2] as string }
		else { return error('decrypt key must be a string') }
	}
	iv_str := match args[3] {
		string { args[3] as string }
		else { return error('decrypt iv must be a string') }
	}

	info := get_cipher_info(algorithm)!
	key_bytes := key_str.bytes()
	iv_bytes := iv_str.bytes()

	if key_bytes.len != info.key_len {
		return error('Invalid key length. Expected ${info.key_len} bytes, got ${key_bytes.len}')
	}
	if iv_bytes.len != info.iv_len {
		return error('Invalid iv length. Expected ${info.iv_len} bytes, got ${iv_bytes.len}')
	}

	ct := ct_str.bytes()

	result := match info.mode {
		.cfb, .ofb, .ctr, .ctr_le, .cbc {
			v_aes_decrypt(ct, key_bytes, iv_bytes, info)!
		}
		.siv {
			v_decrypt_siv(ct, key_bytes, iv_bytes)!
		}
		.chacha20_poly1305 {
			v_decrypt_chacha20_poly1305(ct, key_bytes, iv_bytes)!
		}
		.xchacha20_poly1305, .xsalsa20_poly1305 {
			return error('${algorithm} requires libsodium which is not available')
		}
	}
	return VrlValue(result.bytestr())
}

// ============================================================================
// fn_encrypt_ip / fn_decrypt_ip
// ============================================================================

fn fn_encrypt_ip(args []VrlValue) !VrlValue {
	if args.len < 3 {
		return error('encrypt_ip requires 3 arguments')
	}
	ip := match args[0] {
		string { args[0] as string }
		else { return error('encrypt_ip: ip must be a string') }
	}
	key_str := match args[1] {
		string { args[1] as string }
		else { return error('encrypt_ip: key must be a string') }
	}
	mode := match args[2] {
		string { args[2] as string }
		else { return error('encrypt_ip: mode must be a string') }
	}

	match mode {
		'aes128' {
			key_bytes := key_str.bytes()
			if key_bytes.len != 16 {
				return error('Invalid key length. Expected 16 bytes, got ${key_bytes.len}')
			}
			if ip.contains(':') {
				ip_bytes := enc_parse_ipv6(ip)!
				encrypted := v_aes_ecb_encrypt(ip_bytes, key_bytes)!
				return VrlValue(enc_format_ipv6(encrypted))
			} else {
				ip_bytes := enc_parse_ipv4(ip)!
				// Use IPv4-mapped IPv6 format: ::ffff:x.x.x.x
				mut mapped := []u8{len: 16}
				mapped[10] = 0xFF
				mapped[11] = 0xFF
				mapped[12] = ip_bytes[0]
				mapped[13] = ip_bytes[1]
				mapped[14] = ip_bytes[2]
				mapped[15] = ip_bytes[3]
				encrypted := v_aes_ecb_encrypt(mapped, key_bytes)!
				return VrlValue(enc_format_ipv6(encrypted))
			}
		}
		'pfx' {
			return error('encrypt_ip pfx mode not yet implemented')
		}
		else {
			return error('Invalid mode: ${mode}')
		}
	}
}

fn fn_decrypt_ip(args []VrlValue) !VrlValue {
	if args.len < 3 {
		return error('decrypt_ip requires 3 arguments')
	}
	ip := match args[0] {
		string { args[0] as string }
		else { return error('decrypt_ip: ip must be a string') }
	}
	key_str := match args[1] {
		string { args[1] as string }
		else { return error('decrypt_ip: key must be a string') }
	}
	mode := match args[2] {
		string { args[2] as string }
		else { return error('decrypt_ip: mode must be a string') }
	}

	match mode {
		'aes128' {
			key_bytes := key_str.bytes()
			if key_bytes.len != 16 {
				return error('Invalid key length. Expected 16 bytes, got ${key_bytes.len}')
			}
			if ip.contains(':') {
				ip_bytes := enc_parse_ipv6(ip)!
				decrypted := v_aes_ecb_decrypt(ip_bytes, key_bytes)!
				// Check if result was originally IPv4-mapped IPv6 (::ffff:x.x.x.x)
				// Bytes 0-9 must be 0, bytes 10-11 must be 0xFF
				mut is_ipv4_mapped := true
				for i in 0 .. 10 {
					if decrypted[i] != 0 {
						is_ipv4_mapped = false
						break
					}
				}
				if is_ipv4_mapped && decrypted[10] == 0xFF && decrypted[11] == 0xFF {
					return VrlValue(enc_format_ipv4(decrypted[12..16]))
				}
				return VrlValue(enc_format_ipv6(decrypted))
			} else {
				// IPv4 input: use IPv4-mapped IPv6 format for decryption
				ip_bytes := enc_parse_ipv4(ip)!
				mut mapped := []u8{len: 16}
				mapped[10] = 0xFF
				mapped[11] = 0xFF
				mapped[12] = ip_bytes[0]
				mapped[13] = ip_bytes[1]
				mapped[14] = ip_bytes[2]
				mapped[15] = ip_bytes[3]
				decrypted := v_aes_ecb_decrypt(mapped, key_bytes)!
				return VrlValue(enc_format_ipv4(decrypted[12..16]))
			}
		}
		'pfx' {
			return error('decrypt_ip pfx mode not yet implemented')
		}
		else {
			return error('Invalid mode: ${mode}')
		}
	}
}

// ============================================================================
// IP address parsing helpers (prefixed to avoid name collision with stdlib_ip)
// ============================================================================

fn enc_parse_ipv4(s string) ![]u8 {
	parts := s.split('.')
	if parts.len != 4 {
		return error('invalid IPv4 address: ${s}')
	}
	mut result := []u8{len: 4}
	for i in 0 .. 4 {
		val := parts[i].int()
		if val < 0 || val > 255 {
			return error('invalid IPv4 address: ${s}')
		}
		result[i] = u8(val)
	}
	return result
}

fn enc_format_ipv4(data []u8) string {
	return '${data[0]}.${data[1]}.${data[2]}.${data[3]}'
}

fn enc_parse_ipv6(s string) ![]u8 {
	mut parts := []string{}
	if s.contains('::') {
		halves := s.split('::')
		left := if halves[0].len > 0 { halves[0].split(':') } else { []string{} }
		right := if halves.len > 1 && halves[1].len > 0 { halves[1].split(':') } else { []string{} }
		missing := 8 - left.len - right.len
		parts << left
		for _ in 0 .. missing {
			parts << '0'
		}
		parts << right
	} else {
		parts = s.split(':')
	}
	if parts.len != 8 {
		return error('invalid IPv6 address: ${s}')
	}
	mut result := []u8{len: 16}
	for i in 0 .. 8 {
		mut val := u16(0)
		for c in parts[i].bytes() {
			val = val << 4
			if c >= `0` && c <= `9` {
				val |= u16(c - `0`)
			} else if c >= `a` && c <= `f` {
				val |= u16(c - `a` + 10)
			} else if c >= `A` && c <= `F` {
				val |= u16(c - `A` + 10)
			} else {
				return error('invalid IPv6 address: ${s}')
			}
		}
		result[i * 2] = u8(val >> 8)
		result[i * 2 + 1] = u8(val & 0xFF)
	}
	return result
}

fn enc_format_ipv6(data []u8) string {
	mut groups := []string{cap: 8}
	for i in 0 .. 8 {
		val := u16(data[i * 2]) << 8 | u16(data[i * 2 + 1])
		groups << enc_hex16(val)
	}
	// Find longest run of zero groups for :: compression
	mut best_start := -1
	mut best_len := 0
	mut cur_start := -1
	mut cur_len := 0
	for i in 0 .. 8 {
		if groups[i] == '0' {
			if cur_start < 0 {
				cur_start = i
				cur_len = 1
			} else {
				cur_len++
			}
			if cur_len > best_len {
				best_start = cur_start
				best_len = cur_len
			}
		} else {
			cur_start = -1
			cur_len = 0
		}
	}
	if best_len >= 2 {
		mut result_parts := []string{}
		for i in 0 .. best_start {
			result_parts << groups[i]
		}
		if best_start == 0 {
			result_parts << ''
		}
		result_parts << ''
		if best_start + best_len == 8 {
			result_parts << ''
		}
		for i in best_start + best_len .. 8 {
			result_parts << groups[i]
		}
		return result_parts.join(':')
	}
	return groups.join(':')
}

fn enc_hex16(val u16) string {
	if val == 0 {
		return '0'
	}
	mut result := []u8{}
	mut v := val
	for v > 0 {
		nibble := u8(v & 0xF)
		result << if nibble < 10 { `0` + nibble } else { `a` + nibble - 10 }
		v = v >> 4
	}
	mut out := []u8{cap: result.len}
	for i := result.len - 1; i >= 0; i-- {
		out << result[i]
	}
	return out.bytestr()
}
