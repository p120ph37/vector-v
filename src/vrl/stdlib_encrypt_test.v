module vrl

// ============================================================================
// get_cipher_info tests
// ============================================================================

fn test_cipher_info_aes_cfb() {
	for algo in ['AES-128-CFB', 'AES-192-CFB', 'AES-256-CFB'] {
		info := get_cipher_info(algo) or { panic(err.msg()) }
		assert info.mode == .cfb
	}
}

fn test_cipher_info_aes_ofb() {
	for algo in ['AES-128-OFB', 'AES-192-OFB', 'AES-256-OFB'] {
		info := get_cipher_info(algo) or { panic(err.msg()) }
		assert info.mode == .ofb
	}
}

fn test_cipher_info_aes_ctr() {
	for algo in ['AES-128-CTR', 'AES-192-CTR', 'AES-256-CTR', 'AES-128-CTR-BE', 'AES-192-CTR-BE', 'AES-256-CTR-BE'] {
		info := get_cipher_info(algo) or { panic(err.msg()) }
		assert info.mode == .ctr
	}
}

fn test_cipher_info_aes_ctr_le() {
	for algo in ['AES-128-CTR-LE', 'AES-192-CTR-LE', 'AES-256-CTR-LE'] {
		info := get_cipher_info(algo) or { panic(err.msg()) }
		assert info.mode == .ctr_le
	}
}

fn test_cipher_info_aes_cbc() {
	for suffix in ['PKCS7', 'ANSIX923', 'ISO7816', 'ISO10126'] {
		for bits in ['128', '192', '256'] {
			algo := 'AES-${bits}-CBC-${suffix}'
			info := get_cipher_info(algo) or { panic(err.msg()) }
			assert info.mode == .cbc
			assert info.cbc_padding == suffix
		}
	}
}

fn test_cipher_info_siv() {
	i128 := get_cipher_info('AES-128-SIV') or { panic(err.msg()) }
	assert i128.mode == .siv
	assert i128.key_len == 32
	i256 := get_cipher_info('AES-256-SIV') or { panic(err.msg()) }
	assert i256.mode == .siv
	assert i256.key_len == 64
}

fn test_cipher_info_chacha20() {
	info := get_cipher_info('CHACHA20-POLY1305') or { panic(err.msg()) }
	assert info.mode == .chacha20_poly1305
	assert info.key_len == 32
	assert info.iv_len == 12
}

fn test_cipher_info_xchacha20() {
	info := get_cipher_info('XCHACHA20-POLY1305') or { panic(err.msg()) }
	assert info.mode == .xchacha20_poly1305
}

fn test_cipher_info_xsalsa20() {
	info := get_cipher_info('XSALSA20-POLY1305') or { panic(err.msg()) }
	assert info.mode == .xsalsa20_poly1305
}

fn test_cipher_info_invalid() {
	get_cipher_info('INVALID') or {
		assert err.msg().contains('Invalid algorithm')
		return
	}
	panic('expected error')
}

fn test_cipher_info_key_iv_lengths() {
	info := get_cipher_info('AES-256-CFB') or { panic(err.msg()) }
	assert info.key_len == 32
	assert info.iv_len == 16
	info2 := get_cipher_info('AES-192-CFB') or { panic(err.msg()) }
	assert info2.key_len == 24
	info3 := get_cipher_info('AES-128-CFB') or { panic(err.msg()) }
	assert info3.key_len == 16
}

// ============================================================================
// AES encrypt/decrypt round-trip tests (CFB, OFB, CTR, CTR-LE, CBC)
// ============================================================================

fn make_key(len int) []u8 {
	mut k := []u8{len: len}
	for i in 0 .. len {
		k[i] = u8(i + 1)
	}
	return k
}

fn make_iv() []u8 {
	mut iv := []u8{len: 16}
	for i in 0 .. 16 {
		iv[i] = u8(0xA0 + i)
	}
	return iv
}

fn test_aes_cfb_roundtrip() {
	key := make_key(32)
	iv := make_iv()
	info := CipherInfo{ mode: .cfb, key_len: 32, iv_len: 16 }
	pt := 'Hello, CFB mode!'.bytes()
	ct := v_aes_encrypt(pt, key, iv, info) or { panic(err.msg()) }
	assert ct != pt
	got := v_aes_decrypt(ct, key, iv, info) or { panic(err.msg()) }
	assert got == pt
}

fn test_aes_ofb_roundtrip() {
	key := make_key(32)
	iv := make_iv()
	info := CipherInfo{ mode: .ofb, key_len: 32, iv_len: 16 }
	pt := 'Hello, OFB mode!'.bytes()
	ct := v_aes_encrypt(pt, key, iv, info) or { panic(err.msg()) }
	assert ct != pt
	got := v_aes_decrypt(ct, key, iv, info) or { panic(err.msg()) }
	assert got == pt
}

fn test_aes_ctr_roundtrip() {
	key := make_key(32)
	iv := make_iv()
	info := CipherInfo{ mode: .ctr, key_len: 32, iv_len: 16 }
	pt := 'Hello, CTR mode!'.bytes()
	ct := v_aes_encrypt(pt, key, iv, info) or { panic(err.msg()) }
	assert ct != pt
	got := v_aes_decrypt(ct, key, iv, info) or { panic(err.msg()) }
	assert got == pt
}

fn test_aes_ctr_le_roundtrip() {
	key := make_key(32)
	iv := make_iv()
	info := CipherInfo{ mode: .ctr_le, key_len: 32, iv_len: 16 }
	pt := 'Hello, CTR-LE mode!'.bytes()
	ct := v_aes_encrypt(pt, key, iv, info) or { panic(err.msg()) }
	assert ct != pt
	got := v_aes_decrypt(ct, key, iv, info) or { panic(err.msg()) }
	assert got == pt
}

fn test_aes_cbc_pkcs7_roundtrip() {
	key := make_key(32)
	iv := make_iv()
	info := CipherInfo{ mode: .cbc, key_len: 32, iv_len: 16, cbc_padding: 'PKCS7' }
	pt := 'Hello, CBC PKCS7!'.bytes()
	ct := v_aes_encrypt(pt, key, iv, info) or { panic(err.msg()) }
	got := v_aes_decrypt(ct, key, iv, info) or { panic(err.msg()) }
	assert got == pt
}

fn test_aes_cbc_ansix923_roundtrip() {
	key := make_key(32)
	iv := make_iv()
	info := CipherInfo{ mode: .cbc, key_len: 32, iv_len: 16, cbc_padding: 'ANSIX923' }
	pt := 'Hello, ANSIX923!'.bytes()
	ct := v_aes_encrypt(pt, key, iv, info) or { panic(err.msg()) }
	got := v_aes_decrypt(ct, key, iv, info) or { panic(err.msg()) }
	assert got == pt
}

fn test_aes_cbc_iso7816_roundtrip() {
	key := make_key(32)
	iv := make_iv()
	info := CipherInfo{ mode: .cbc, key_len: 32, iv_len: 16, cbc_padding: 'ISO7816' }
	pt := 'Hello, ISO7816!'.bytes()
	ct := v_aes_encrypt(pt, key, iv, info) or { panic(err.msg()) }
	got := v_aes_decrypt(ct, key, iv, info) or { panic(err.msg()) }
	assert got == pt
}

fn test_aes_encrypt_unsupported_mode() {
	key := make_key(32)
	iv := make_iv()
	info := CipherInfo{ mode: .chacha20_poly1305, key_len: 32, iv_len: 12 }
	v_aes_encrypt('x'.bytes(), key, iv, info) or {
		assert err.msg().contains('unexpected mode')
		return
	}
	panic('expected error')
}

fn test_aes_decrypt_unsupported_mode() {
	key := make_key(32)
	iv := make_iv()
	info := CipherInfo{ mode: .chacha20_poly1305, key_len: 32, iv_len: 12 }
	v_aes_decrypt('x'.bytes(), key, iv, info) or {
		assert err.msg().contains('unexpected mode')
		return
	}
	panic('expected error')
}

// ============================================================================
// AES-ECB tests
// ============================================================================

fn test_aes_ecb_roundtrip() {
	key := make_key(16)
	data := []u8{len: 16, init: u8(index + 0x30)}
	ct := v_aes_ecb_encrypt(data, key) or { panic(err.msg()) }
	assert ct.len == 16
	assert ct != data
	pt := v_aes_ecb_decrypt(ct, key) or { panic(err.msg()) }
	assert pt == data
}

fn test_aes_ecb_wrong_length() {
	key := make_key(16)
	v_aes_ecb_encrypt([]u8{len: 8}, key) or {
		assert err.msg().contains('16 bytes')
		return
	}
	panic('expected error')
}

fn test_aes_ecb_decrypt_wrong_length() {
	key := make_key(16)
	v_aes_ecb_decrypt([]u8{len: 8}, key) or {
		assert err.msg().contains('16 bytes')
		return
	}
	panic('expected error')
}

// ============================================================================
// AES-CMAC tests
// ============================================================================

fn test_cmac_dbl() {
	data := []u8{len: 16, init: u8(index)}
	result := cmac_dbl(data)
	assert result.len == 16
	// Verify shift logic: first byte should be data[0]<<1 | data[1]>>7
	assert result[0] == ((data[0] << 1) | (data[1] >> 7))
}

fn test_cmac_dbl_carry() {
	// Set high bit of first byte to trigger carry
	mut data := []u8{len: 16}
	data[0] = 0x80
	result := cmac_dbl(data)
	assert result[15] == 0x87 // Rb XOR
}

fn test_aes_cmac_empty() {
	key := make_key(16)
	mac := aes_cmac(key, [])
	assert mac.len == 16
}

fn test_aes_cmac_short() {
	key := make_key(16)
	mac := aes_cmac(key, 'short'.bytes())
	assert mac.len == 16
}

fn test_aes_cmac_exact_block() {
	key := make_key(16)
	mac := aes_cmac(key, []u8{len: 16, init: u8(index)})
	assert mac.len == 16
}

fn test_aes_cmac_multi_block() {
	key := make_key(16)
	mac := aes_cmac(key, []u8{len: 48, init: u8(index)})
	assert mac.len == 16
}

// ============================================================================
// AES-SIV tests
// ============================================================================

fn test_aes_siv_roundtrip() {
	key := make_key(32) // 128-bit SIV: 16 MAC + 16 CTR
	nonce := make_iv()
	pt := 'SIV test plaintext'.bytes()
	ct := v_encrypt_siv(pt, key, nonce) or { panic(err.msg()) }
	assert ct.len == pt.len + 16 // 16-byte SIV tag prepended
	got := v_decrypt_siv(ct, key, nonce) or { panic(err.msg()) }
	assert got == pt
}

fn test_aes_siv_short_plaintext() {
	key := make_key(32)
	nonce := make_iv()
	pt := 'hi'.bytes() // less than 16 bytes
	ct := v_encrypt_siv(pt, key, nonce) or { panic(err.msg()) }
	got := v_decrypt_siv(ct, key, nonce) or { panic(err.msg()) }
	assert got == pt
}

fn test_aes_siv_decrypt_too_short() {
	key := make_key(32)
	nonce := make_iv()
	v_decrypt_siv([]u8{len: 8}, key, nonce) or {
		assert err.msg().contains('too short')
		return
	}
	panic('expected error')
}

fn test_aes_siv_decrypt_tampered() {
	key := make_key(32)
	nonce := make_iv()
	ct := v_encrypt_siv('test'.bytes(), key, nonce) or { panic(err.msg()) }
	mut tampered := ct.clone()
	tampered[0] ^= 0xFF
	v_decrypt_siv(tampered, key, nonce) or {
		assert err.msg().contains('authentication failed')
		return
	}
	panic('expected error')
}

// ============================================================================
// CHACHA20-POLY1305 tests
// ============================================================================

fn test_chacha20_poly1305_roundtrip() {
	key := make_key(32)
	mut nonce := []u8{len: 12}
	for i in 0 .. 12 {
		nonce[i] = u8(i + 1)
	}
	pt := 'ChaCha20-Poly1305 test!'.bytes()
	ct := v_encrypt_chacha20_poly1305(pt, key, nonce) or { panic(err.msg()) }
	assert ct.len == pt.len + 16 // 16-byte tag appended
	got := v_decrypt_chacha20_poly1305(ct, key, nonce) or { panic(err.msg()) }
	assert got == pt
}

fn test_chacha20_poly1305_empty() {
	key := make_key(32)
	mut nonce := []u8{len: 12}
	ct := v_encrypt_chacha20_poly1305([], key, nonce) or { panic(err.msg()) }
	assert ct.len == 16 // tag only
	got := v_decrypt_chacha20_poly1305(ct, key, nonce) or { panic(err.msg()) }
	assert got == []
}

fn test_chacha20_poly1305_decrypt_too_short() {
	key := make_key(32)
	nonce := []u8{len: 12}
	v_decrypt_chacha20_poly1305([]u8{len: 8}, key, nonce) or {
		assert err.msg().contains('too short')
		return
	}
	panic('expected error')
}

fn test_chacha20_poly1305_decrypt_tampered() {
	key := make_key(32)
	mut nonce := []u8{len: 12}
	ct := v_encrypt_chacha20_poly1305('test'.bytes(), key, nonce) or { panic(err.msg()) }
	mut tampered := ct.clone()
	tampered[0] ^= 0xFF
	v_decrypt_chacha20_poly1305(tampered, key, nonce) or {
		assert err.msg().contains('authentication failed')
		return
	}
	panic('expected error')
}

// ============================================================================
// Padding tests
// ============================================================================

fn test_add_remove_pkcs7() {
	data := 'hello'.bytes() // 5 bytes, pad to 16
	padded := add_padding(data, 16, 'PKCS7')
	assert padded.len == 16
	// Last 11 bytes should all be 11
	for i in 5 .. 16 {
		assert padded[i] == 11
	}
	got := remove_padding(padded, 'PKCS7') or { panic(err.msg()) }
	assert got == data
}

fn test_add_remove_ansix923() {
	data := 'hello'.bytes()
	padded := add_padding(data, 16, 'ANSIX923')
	assert padded.len == 16
	// Bytes 5..14 should be 0, byte 15 should be 11
	for i in 5 .. 15 {
		assert padded[i] == 0
	}
	assert padded[15] == 11
	got := remove_padding(padded, 'ANSIX923') or { panic(err.msg()) }
	assert got == data
}

fn test_add_remove_iso7816() {
	data := 'hello'.bytes()
	padded := add_padding(data, 16, 'ISO7816')
	assert padded.len == 16
	assert padded[5] == 0x80
	for i in 6 .. 16 {
		assert padded[i] == 0
	}
	got := remove_padding(padded, 'ISO7816') or { panic(err.msg()) }
	assert got == data
}

fn test_add_remove_iso10126() {
	data := 'hello'.bytes()
	padded := add_padding(data, 16, 'ISO10126')
	assert padded.len == 16
	assert padded[15] == 11 // pad length byte
	got := remove_padding(padded, 'ISO10126') or { panic(err.msg()) }
	assert got == data
}

fn test_remove_padding_empty() {
	remove_padding([], 'PKCS7') or {
		assert err.msg().contains('empty data')
		return
	}
	panic('expected error')
}

fn test_remove_padding_invalid_pkcs7() {
	mut data := []u8{len: 16}
	data[15] = 0 // invalid: pad length 0
	remove_padding(data, 'PKCS7') or {
		assert err.msg().contains('invalid PKCS7')
		return
	}
	panic('expected error')
}

fn test_remove_padding_invalid_pkcs7_mismatch() {
	mut data := []u8{len: 16}
	data[15] = 2
	data[14] = 99 // should be 2 but isn't
	remove_padding(data, 'PKCS7') or {
		assert err.msg().contains('invalid PKCS7')
		return
	}
	panic('expected error')
}

fn test_remove_padding_invalid_ansix923() {
	mut data := []u8{len: 16}
	data[15] = 0
	remove_padding(data, 'ANSIX923') or {
		assert err.msg().contains('invalid ANSIX923')
		return
	}
	panic('expected error')
}

fn test_remove_padding_invalid_ansix923_nonzero() {
	mut data := []u8{len: 16}
	data[15] = 3 // pad len 3
	data[14] = 0
	data[13] = 99 // should be 0
	remove_padding(data, 'ANSIX923') or {
		assert err.msg().contains('invalid ANSIX923')
		return
	}
	panic('expected error')
}

fn test_remove_padding_invalid_iso7816() {
	// All zeros, no 0x80 marker
	remove_padding([]u8{len: 16}, 'ISO7816') or {
		assert err.msg().contains('invalid ISO7816')
		return
	}
	panic('expected error')
}

fn test_remove_padding_invalid_iso10126() {
	mut data := []u8{len: 16}
	data[15] = 0
	remove_padding(data, 'ISO10126') or {
		assert err.msg().contains('invalid ISO10126')
		return
	}
	panic('expected error')
}

fn test_remove_padding_unknown() {
	data := []u8{len: 16, init: u8(0x41)}
	got := remove_padding(data, 'UNKNOWN') or { panic(err.msg()) }
	assert got == data
}

fn test_padding_pkcs7_too_large_pad() {
	mut data := []u8{len: 16}
	data[15] = 17 // > 16
	remove_padding(data, 'PKCS7') or {
		assert err.msg().contains('invalid PKCS7')
		return
	}
	panic('expected error')
}

// ============================================================================
// reverse_bytes tests
// ============================================================================

fn test_reverse_bytes() {
	assert reverse_bytes([u8(1), 2, 3, 4]) == [u8(4), 3, 2, 1]
	assert reverse_bytes([u8(0xFF)]) == [u8(0xFF)]
	assert reverse_bytes([]) == []
}

// ============================================================================
// fn_encrypt / fn_decrypt VRL interface tests
// ============================================================================

fn test_fn_encrypt_decrypt_cfb() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('hello world'), VrlValue('AES-256-CFB'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-256-CFB'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'hello world'
}

fn test_fn_encrypt_decrypt_ofb() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('hello world'), VrlValue('AES-256-OFB'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-256-OFB'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'hello world'
}

fn test_fn_encrypt_decrypt_ctr() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('hello world'), VrlValue('AES-256-CTR'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-256-CTR'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'hello world'
}

fn test_fn_encrypt_decrypt_ctr_le() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('hello world'), VrlValue('AES-256-CTR-LE'),
		VrlValue(key32), VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-256-CTR-LE'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'hello world'
}

fn test_fn_encrypt_decrypt_cbc_pkcs7() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('hello world'), VrlValue('AES-256-CBC-PKCS7'),
		VrlValue(key32), VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-256-CBC-PKCS7'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'hello world'
}

fn test_fn_encrypt_decrypt_siv() {
	// AES-128-SIV needs 32-byte key (16 MAC + 16 CTR)
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('hello SIV'), VrlValue('AES-128-SIV'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-128-SIV'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'hello SIV'
}

fn test_fn_encrypt_decrypt_chacha20_poly1305() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv12 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c'
	ct := fn_encrypt([VrlValue('hello chacha'), VrlValue('CHACHA20-POLY1305'),
		VrlValue(key32), VrlValue(iv12)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('CHACHA20-POLY1305'), VrlValue(key32),
		VrlValue(iv12)]) or { panic(err.msg()) }
	assert (pt as string) == 'hello chacha'
}

fn test_fn_encrypt_too_few_args() {
	fn_encrypt([VrlValue('a'), VrlValue('b')]) or {
		assert err.msg().contains('4 arguments')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_too_few_args() {
	fn_decrypt([VrlValue('a'), VrlValue('b')]) or {
		assert err.msg().contains('4 arguments')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_wrong_key_len() {
	fn_encrypt([VrlValue('hello'), VrlValue('AES-256-CFB'), VrlValue('shortkey'),
		VrlValue('\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf')]) or {
		assert err.msg().contains('Invalid key length')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_wrong_iv_len() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	fn_encrypt([VrlValue('hello'), VrlValue('AES-256-CFB'), VrlValue(key32),
		VrlValue('short')]) or {
		assert err.msg().contains('Invalid iv length')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_wrong_key_len() {
	fn_decrypt([VrlValue('ct'), VrlValue('AES-256-CFB'), VrlValue('shortkey'),
		VrlValue('\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf')]) or {
		assert err.msg().contains('Invalid key length')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_wrong_iv_len() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	fn_decrypt([VrlValue('ct'), VrlValue('AES-256-CFB'), VrlValue(key32),
		VrlValue('short')]) or {
		assert err.msg().contains('Invalid iv length')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_non_string_plaintext() {
	fn_encrypt([VrlValue(i64(42)), VrlValue('AES-256-CFB'), VrlValue('k'),
		VrlValue('iv')]) or {
		assert err.msg().contains('plaintext must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_non_string_algo() {
	fn_encrypt([VrlValue('pt'), VrlValue(i64(42)), VrlValue('k'), VrlValue('iv')]) or {
		assert err.msg().contains('algorithm must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_non_string_key() {
	fn_encrypt([VrlValue('pt'), VrlValue('AES-256-CFB'), VrlValue(i64(42)),
		VrlValue('iv')]) or {
		assert err.msg().contains('key must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_non_string_iv() {
	fn_encrypt([VrlValue('pt'), VrlValue('AES-256-CFB'), VrlValue('k'),
		VrlValue(i64(42))]) or {
		assert err.msg().contains('iv must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_non_string_ct() {
	fn_decrypt([VrlValue(i64(42)), VrlValue('AES-256-CFB'), VrlValue('k'),
		VrlValue('iv')]) or {
		assert err.msg().contains('ciphertext must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_non_string_algo() {
	fn_decrypt([VrlValue('ct'), VrlValue(i64(42)), VrlValue('k'), VrlValue('iv')]) or {
		assert err.msg().contains('algorithm must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_non_string_key() {
	fn_decrypt([VrlValue('ct'), VrlValue('AES-256-CFB'), VrlValue(i64(42)),
		VrlValue('iv')]) or {
		assert err.msg().contains('key must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_non_string_iv() {
	fn_decrypt([VrlValue('ct'), VrlValue('AES-256-CFB'), VrlValue('k'),
		VrlValue(i64(42))]) or {
		assert err.msg().contains('iv must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_xchacha20_unsupported() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv24 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18'
	fn_encrypt([VrlValue('hello'), VrlValue('XCHACHA20-POLY1305'), VrlValue(key32),
		VrlValue(iv24)]) or {
		assert err.msg().contains('libsodium')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_xchacha20_unsupported() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv24 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18'
	fn_decrypt([VrlValue('hello world test ciphertext here!'), VrlValue('XCHACHA20-POLY1305'),
		VrlValue(key32), VrlValue(iv24)]) or {
		assert err.msg().contains('libsodium')
		return
	}
	panic('expected error')
}

// ============================================================================
// fn_encrypt_ip / fn_decrypt_ip tests
// ============================================================================

fn test_fn_encrypt_ip_aes128_ipv4() {
	key16 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
	ct := fn_encrypt_ip([VrlValue('192.168.1.1'), VrlValue(key16), VrlValue('aes128')]) or {
		panic(err.msg())
	}
	ct_str := ct as string
	// Encrypted IPv4 returns IPv6 format
	assert ct_str.contains(':')
	// Decrypt should recover original
	pt := fn_decrypt_ip([VrlValue(ct_str), VrlValue(key16), VrlValue('aes128')]) or {
		panic(err.msg())
	}
	assert (pt as string) == '192.168.1.1'
}

fn test_fn_encrypt_ip_aes128_ipv6() {
	key16 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
	ct := fn_encrypt_ip([VrlValue('2001:db8::1'), VrlValue(key16), VrlValue('aes128')]) or {
		panic(err.msg())
	}
	ct_str := ct as string
	pt := fn_decrypt_ip([VrlValue(ct_str), VrlValue(key16), VrlValue('aes128')]) or {
		panic(err.msg())
	}
	assert (pt as string) == '2001:db8::1'
}

fn test_fn_encrypt_ip_too_few_args() {
	fn_encrypt_ip([VrlValue('1.2.3.4'), VrlValue('k')]) or {
		assert err.msg().contains('3 arguments')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_ip_too_few_args() {
	fn_decrypt_ip([VrlValue('1.2.3.4'), VrlValue('k')]) or {
		assert err.msg().contains('3 arguments')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_ip_wrong_key_len() {
	fn_encrypt_ip([VrlValue('1.2.3.4'), VrlValue('short'), VrlValue('aes128')]) or {
		assert err.msg().contains('Expected 16 bytes')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_ip_wrong_key_len() {
	fn_decrypt_ip([VrlValue('::1'), VrlValue('short'), VrlValue('aes128')]) or {
		assert err.msg().contains('Expected 16 bytes')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_ip_invalid_mode() {
	key16 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
	fn_encrypt_ip([VrlValue('1.2.3.4'), VrlValue(key16), VrlValue('invalid')]) or {
		assert err.msg().contains('Invalid mode')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_ip_invalid_mode() {
	key16 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
	fn_decrypt_ip([VrlValue('::1'), VrlValue(key16), VrlValue('invalid')]) or {
		assert err.msg().contains('Invalid mode')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_ip_pfx_unsupported() {
	key16 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
	fn_encrypt_ip([VrlValue('1.2.3.4'), VrlValue(key16), VrlValue('pfx')]) or {
		assert err.msg().contains('not yet implemented')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_ip_pfx_unsupported() {
	key16 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
	fn_decrypt_ip([VrlValue('::1'), VrlValue(key16), VrlValue('pfx')]) or {
		assert err.msg().contains('not yet implemented')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_ip_non_string_ip() {
	fn_encrypt_ip([VrlValue(i64(42)), VrlValue('k'), VrlValue('aes128')]) or {
		assert err.msg().contains('ip must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_ip_non_string_key() {
	fn_encrypt_ip([VrlValue('1.2.3.4'), VrlValue(i64(42)), VrlValue('aes128')]) or {
		assert err.msg().contains('key must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_encrypt_ip_non_string_mode() {
	fn_encrypt_ip([VrlValue('1.2.3.4'), VrlValue('k'), VrlValue(i64(42))]) or {
		assert err.msg().contains('mode must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_ip_non_string_ip() {
	fn_decrypt_ip([VrlValue(i64(42)), VrlValue('k'), VrlValue('aes128')]) or {
		assert err.msg().contains('ip must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_ip_non_string_key() {
	fn_decrypt_ip([VrlValue('::1'), VrlValue(i64(42)), VrlValue('aes128')]) or {
		assert err.msg().contains('key must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_ip_non_string_mode() {
	fn_decrypt_ip([VrlValue('::1'), VrlValue('k'), VrlValue(i64(42))]) or {
		assert err.msg().contains('mode must be a string')
		return
	}
	panic('expected error')
}

fn test_fn_decrypt_ip_ipv4_input() {
	// Test decrypt_ip with IPv4 format input (non-colon path)
	key16 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
	// Encrypt then decrypt using IPv4 as intermediary
	ct := fn_encrypt_ip([VrlValue('10.0.0.1'), VrlValue(key16), VrlValue('aes128')]) or {
		panic(err.msg())
	}
	ct_str := ct as string
	pt := fn_decrypt_ip([VrlValue(ct_str), VrlValue(key16), VrlValue('aes128')]) or {
		panic(err.msg())
	}
	assert (pt as string) == '10.0.0.1'
}

// ============================================================================
// IP address helper tests
// ============================================================================

fn test_enc_parse_ipv4_valid() {
	result := enc_parse_ipv4('192.168.1.1') or { panic(err.msg()) }
	assert result == [u8(192), 168, 1, 1]
}

fn test_enc_parse_ipv4_invalid() {
	enc_parse_ipv4('1.2.3') or {
		assert err.msg().contains('invalid IPv4')
		return
	}
	panic('expected error')
}

fn test_enc_format_ipv4() {
	assert enc_format_ipv4([u8(10), 0, 0, 1]) == '10.0.0.1'
}

fn test_enc_parse_ipv6_full() {
	result := enc_parse_ipv6('2001:0db8:0000:0000:0000:0000:0000:0001') or { panic(err.msg()) }
	assert result.len == 16
	assert result[0] == 0x20
	assert result[1] == 0x01
}

fn test_enc_parse_ipv6_compressed() {
	result := enc_parse_ipv6('::1') or { panic(err.msg()) }
	assert result.len == 16
	assert result[15] == 1
	for i in 0 .. 15 {
		assert result[i] == 0
	}
}

fn test_enc_parse_ipv6_invalid() {
	enc_parse_ipv6('not:an:ip') or {
		assert err.msg().contains('invalid IPv6')
		return
	}
	panic('expected error')
}

fn test_enc_parse_ipv6_bad_char() {
	enc_parse_ipv6('zzzz:0000:0000:0000:0000:0000:0000:0001') or {
		assert err.msg().contains('invalid IPv6')
		return
	}
	panic('expected error')
}

fn test_enc_format_ipv6_with_compression() {
	// ::1
	mut data := []u8{len: 16}
	data[15] = 1
	result := enc_format_ipv6(data)
	assert result == '::1'
}

fn test_enc_format_ipv6_no_compression() {
	// All non-zero
	data := []u8{len: 16, init: u8(index + 1)}
	result := enc_format_ipv6(data)
	assert !result.contains('::')
	assert result.contains(':')
}

fn test_enc_format_ipv6_single_zero_no_compress() {
	// Single zero group should not use :: (needs >= 2)
	mut data := []u8{len: 16, init: u8(0x11)}
	data[0] = 0
	data[1] = 0
	result := enc_format_ipv6(data)
	// Single zero group — no :: compression
	assert !result.contains('::')
}

fn test_enc_hex16() {
	assert enc_hex16(0) == '0'
	assert enc_hex16(255) == 'ff'
	assert enc_hex16(4096) == '1000'
	assert enc_hex16(0xabcd) == 'abcd'
}

fn test_enc_parse_ipv6_left_compressed() {
	// ::ffff:c0a8:0101 (IPv4-mapped)
	result := enc_parse_ipv6('::ffff:c0a8:101') or { panic(err.msg()) }
	assert result.len == 16
	assert result[10] == 0xFF
	assert result[11] == 0xFF
}

fn test_enc_parse_ipv6_right_compressed() {
	// 2001:db8::
	result := enc_parse_ipv6('2001:db8::') or { panic(err.msg()) }
	assert result.len == 16
	assert result[0] == 0x20
	assert result[1] == 0x01
	assert result[2] == 0x0d
	assert result[3] == 0xb8
	for i in 4 .. 16 {
		assert result[i] == 0
	}
}

fn test_enc_format_ipv6_trailing_zeros() {
	// 2001:db8:: — zeros at end
	mut data := []u8{len: 16}
	data[0] = 0x20
	data[1] = 0x01
	data[2] = 0x0d
	data[3] = 0xb8
	result := enc_format_ipv6(data)
	assert result == '2001:db8::'
}

// ============================================================================
// cmac_xor_dbl test
// ============================================================================

fn test_cmac_xor_dbl() {
	d := []u8{len: 16, init: u8(index)}
	cmac_val := []u8{len: 16, init: u8(0xFF - index)}
	result := cmac_xor_dbl(d, cmac_val)
	assert result.len == 16
}

// ============================================================================
// s2v tests
// ============================================================================

fn test_s2v_short_plaintext() {
	key := make_key(16)
	nonce := make_iv()
	result := s2v(key, nonce, 'hi'.bytes())
	assert result.len == 16
}

fn test_s2v_long_plaintext() {
	key := make_key(16)
	nonce := make_iv()
	result := s2v(key, nonce, []u8{len: 48, init: u8(index)})
	assert result.len == 16
}

// ============================================================================
// CBC with different key sizes
// ============================================================================

fn test_fn_encrypt_decrypt_cbc_192() {
	key24 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('test 192'), VrlValue('AES-192-CBC-PKCS7'), VrlValue(key24),
		VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-192-CBC-PKCS7'), VrlValue(key24),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'test 192'
}

fn test_fn_encrypt_decrypt_cbc_128() {
	key16 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('test 128'), VrlValue('AES-128-CBC-PKCS7'), VrlValue(key16),
		VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-128-CBC-PKCS7'), VrlValue(key16),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'test 128'
}

fn test_fn_encrypt_decrypt_cbc_ansix923() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('test ansi'), VrlValue('AES-256-CBC-ANSIX923'),
		VrlValue(key32), VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-256-CBC-ANSIX923'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'test ansi'
}

fn test_fn_encrypt_decrypt_cbc_iso7816() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('test iso7816'), VrlValue('AES-256-CBC-ISO7816'),
		VrlValue(key32), VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-256-CBC-ISO7816'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'test iso7816'
}

fn test_fn_encrypt_decrypt_cbc_iso10126() {
	key32 := '\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20'
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('test iso10126'), VrlValue('AES-256-CBC-ISO10126'),
		VrlValue(key32), VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-256-CBC-ISO10126'), VrlValue(key32),
		VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'test iso10126'
}

// ============================================================================
// AES-256-SIV test
// ============================================================================

fn test_fn_encrypt_decrypt_siv_256() {
	// AES-256-SIV needs 64-byte key
	mut key64 := []u8{len: 64}
	for i in 0 .. 64 {
		key64[i] = u8(i + 1)
	}
	iv16 := '\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf'
	ct := fn_encrypt([VrlValue('hello SIV 256'), VrlValue('AES-256-SIV'),
		VrlValue(key64.bytestr()), VrlValue(iv16)]) or { panic(err.msg()) }
	ct_str := ct as string
	pt := fn_decrypt([VrlValue(ct_str), VrlValue('AES-256-SIV'),
		VrlValue(key64.bytestr()), VrlValue(iv16)]) or { panic(err.msg()) }
	assert (pt as string) == 'hello SIV 256'
}

// ============================================================================
// Exact-block-size padding (pad_len = block_size)
// ============================================================================

fn test_padding_exact_block_pkcs7() {
	// 16 bytes = exact block, adds full block of padding
	data := []u8{len: 16, init: u8(0x41)}
	padded := add_padding(data, 16, 'PKCS7')
	assert padded.len == 32
	for i in 16 .. 32 {
		assert padded[i] == 16
	}
	got := remove_padding(padded, 'PKCS7') or { panic(err.msg()) }
	assert got == data
}
