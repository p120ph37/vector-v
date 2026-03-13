module vrl

fn test_seahash_foo() {
	result := fn_seahash([VrlValue('foo')]) or { panic(err.msg()) }
	v := result as i64
	assert v == 4413582353838009230, 'seahash("foo") = ${v}'
}

fn test_seahash_bar() {
	result := fn_seahash([VrlValue('bar')]) or { panic(err.msg()) }
	v := result as i64
	assert v == -2796170501982571315, 'seahash("bar") = ${v}'
}

fn test_seahash_foobar() {
	result := fn_seahash([VrlValue('foobar')]) or { panic(err.msg()) }
	v := result as i64
	assert v == 5348458858952426560, 'seahash("foobar") = ${v}'
}

fn test_xxhash_xxh32_default() {
	result := fn_xxhash([VrlValue('foo')]) or { panic(err.msg()) }
	v := result as i64
	assert v == 3792637401, 'xxhash("foo") = ${v}'
}

fn test_xxhash_xxh64() {
	result := fn_xxhash([VrlValue('foo'), VrlValue('XXH64')]) or { panic(err.msg()) }
	v := result as i64
	assert v == 3728699739546630719, 'xxhash("foo", "XXH64") = ${v}'
}

fn test_xxhash_long_xxh32() {
	result := fn_xxhash([VrlValue('vrl xxhash hash function')]) or { panic(err.msg()) }
	v := result as i64
	assert v == 919261294, 'xxhash("vrl xxhash hash function") = ${v}'
}

fn test_xxhash_long_xxh64() {
	result := fn_xxhash([VrlValue('vrl xxhash hash function'), VrlValue('XXH64')]) or {
		panic(err.msg())
	}
	v := result as i64
	assert v == 7826295616420964813, 'xxhash("vrl xxhash hash function", "XXH64") = ${v}'
}

fn test_crc_default() {
	result := fn_crc([VrlValue('foo')]) or { panic(err.msg()) }
	v := result as string
	assert v == '2356372769', 'crc("foo") = ${v}'
}

fn test_crc_cksum() {
	result := fn_crc([VrlValue('foo'), VrlValue('CRC_32_CKSUM')]) or { panic(err.msg()) }
	v := result as string
	assert v == '4271552933', 'crc("foo", "CRC_32_CKSUM") = ${v}'
}

fn test_crc_maxim() {
	result := fn_crc([VrlValue('foo'), VrlValue('CRC_8_MAXIM_DOW')]) or { panic(err.msg()) }
	v := result as string
	assert v == '18', 'crc("foo", "CRC_8_MAXIM_DOW") = ${v}'
}

fn test_crc_redis() {
	result := fn_crc([VrlValue('foo'), VrlValue('CRC_64_REDIS')]) or { panic(err.msg()) }
	v := result as string
	assert v == '12626267673720558670', 'crc("foo", "CRC_64_REDIS") = ${v}'
}

fn test_xxhash_xxh3_64() {
	result := fn_xxhash([VrlValue('foo'), VrlValue('XXH3-64')]) or { panic(err.msg()) }
	_ := result as i64
	// Just verify it doesn't error - exact value depends on lib version
}

fn test_xxhash_xxh3_128() {
	result := fn_xxhash([VrlValue('foo'), VrlValue('XXH3-128')]) or { panic(err.msg()) }
	_ := result as string
	// Just verify it doesn't error - returns hex string
}

fn test_crc_82_darc() {
	// CRC-82/DARC check value for "123456789" is 0x09EA83F625023801FD612
	result := fn_crc([VrlValue('123456789'), VrlValue('CRC_82_DARC')]) or { panic(err.msg()) }
	v := result as string
	assert v == '749237524598872659187218', 'crc("123456789", "CRC_82_DARC") = ${v}'
}

fn test_crc_invalid() {
	_ := fn_crc([VrlValue('foo'), VrlValue('CRC_UNKNOWN')]) or {
		assert err.msg() == 'Invalid CRC algorithm: CRC_UNKNOWN'
		return
	}
	panic('expected error for invalid CRC algorithm')
}

fn test_snappy_roundtrip() {
	compressed := fn_encode_snappy([VrlValue('hello world')]) or { panic(err.msg()) }
	decompressed := fn_decode_snappy([compressed]) or { panic(err.msg()) }
	v := decompressed as string
	assert v == 'hello world', 'snappy roundtrip: got ${v}'
}

fn test_lz4_roundtrip() {
	compressed := fn_encode_lz4([VrlValue('hello world')]) or { panic(err.msg()) }
	decompressed := fn_decode_lz4([compressed]) or { panic(err.msg()) }
	v := decompressed as string
	assert v == 'hello world', 'lz4 roundtrip: got ${v}'
}
