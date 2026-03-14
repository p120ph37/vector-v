module vrl

// Tests targeting uncovered lines across multiple smaller files:
// vrllib_community_id.v, vrllib_crypto.v, vrllib_dns.v, vrllib_etld.v,
// vrllib_grok.v, vrllib_ip.v, vrllib_ip2.v, vrllib_object.v,
// vrllib_string.v, vrllib_enumerate.v, vrllib_codec.v

fn f4_run(source string) !VrlValue {
	return execute(source, map[string]VrlValue{})
}

fn f4_run_obj(source string, obj map[string]VrlValue) !VrlValue {
	return execute(source, obj)
}

// ============================================================
// vrllib_community_id.v — community_id function
// ============================================================

// Basic TCP community_id (covers lines 10-139 including port protocol path)
fn test_f4_community_id_tcp() {
	result := f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "5.6.7.8", protocol: 6, source_port: 1234, destination_port: 80)') or {
		assert false, 'community_id TCP failed: ${err}'
		return
	}
	s := result as string
	assert s.starts_with('1:')
}

// UDP community_id with reversed ordering (dst < src triggers swap, lines 79-83)
fn test_f4_community_id_udp_reversed() {
	result := f4_run('community_id(source_ip: "5.6.7.8", destination_ip: "1.2.3.4", protocol: 17, source_port: 80, destination_port: 1234)') or {
		assert false, 'community_id UDP reversed failed: ${err}'
		return
	}
	s := result as string
	assert s.starts_with('1:')
}

// Equal IPs, equal ports path (line 77-78)
fn test_f4_community_id_equal_ips_ports() {
	result := f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "1.2.3.4", protocol: 6, source_port: 80, destination_port: 80)') or {
		assert false, 'community_id equal failed: ${err}'
		return
	}
	s := result as string
	assert s.starts_with('1:')
}

// Equal IPs, src_port > dst_port (swap path, line 79-83 with equal IPs)
fn test_f4_community_id_equal_ips_port_swap() {
	result := f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "1.2.3.4", protocol: 6, source_port: 8080, destination_port: 80)') or {
		assert false, 'community_id equal ips port swap: ${err}'
		return
	}
	s := result as string
	assert s.starts_with('1:')
}

// ICMP protocol (lines 86-106, is_one_way path)
fn test_f4_community_id_icmp() {
	result := f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "5.6.7.8", protocol: 1, source_port: 8, destination_port: 0)') or {
		assert false, 'community_id ICMP failed: ${err}'
		return
	}
	s := result as string
	assert s.starts_with('1:')
}

// ICMP with dst < src (lines 92-96)
fn test_f4_community_id_icmp_reversed() {
	result := f4_run('community_id(source_ip: "5.6.7.8", destination_ip: "1.2.3.4", protocol: 1, source_port: 8, destination_port: 0)') or {
		assert false, 'community_id ICMP reversed: ${err}'
		return
	}
	s := result as string
	assert s.starts_with('1:')
}

// ICMP with equal IPs, src_port > dst_port (lines 100-104)
fn test_f4_community_id_icmp_equal_ips() {
	result := f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "1.2.3.4", protocol: 1, source_port: 8, destination_port: 0)') or {
		assert false, 'community_id ICMP equal: ${err}'
		return
	}
	s := result as string
	assert s.starts_with('1:')
}

// ICMPv6 protocol (line 201-221, is_v6 icmp_port_map path)
fn test_f4_community_id_icmpv6() {
	result := f4_run('community_id(source_ip: "::1", destination_ip: "::2", protocol: 58, source_port: 128, destination_port: 129)') or {
		assert false, 'community_id ICMPv6 failed: ${err}'
		return
	}
	s := result as string
	assert s.starts_with('1:')
}

// Protocol without ports (e.g. GRE=47, lines 127 has_ports false, no port protocol)
fn test_f4_community_id_no_ports() {
	result := f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "5.6.7.8", protocol: 47)') or {
		assert false, 'community_id no ports: ${err}'
		return
	}
	s := result as string
	assert s.starts_with('1:')
}

// Error: protocol out of range (line 21)
fn test_f4_community_id_bad_protocol() {
	f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "5.6.7.8", protocol: 999)') or {
		assert err.msg().contains('protocol must be between')
		return
	}
	assert false, 'expected error'
}

// Error: seed out of range (line 29)
fn test_f4_community_id_bad_seed() {
	f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "5.6.7.8", protocol: 6, source_port: 80, destination_port: 80, seed: 99999)') or {
		assert err.msg().contains('seed must be between')
		return
	}
	assert false, 'expected error'
}

// Error: TCP missing ports (line 37)
fn test_f4_community_id_tcp_no_ports() {
	f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "5.6.7.8", protocol: 6)') or {
		assert err.msg().contains('port')
		return
	}
	assert false, 'expected error'
}

// Error: invalid source IP (line 61)
fn test_f4_community_id_bad_src_ip() {
	f4_run('community_id(source_ip: "not_an_ip", destination_ip: "5.6.7.8", protocol: 47)') or {
		assert err.msg().contains('parse')
		return
	}
	assert false, 'expected error'
}

// Error: invalid dest IP (line 63)
fn test_f4_community_id_bad_dst_ip() {
	f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "bad", protocol: 47)') or {
		assert err.msg().contains('parse')
		return
	}
	assert false, 'expected error'
}

// Error: source port out of range (line 46)
fn test_f4_community_id_bad_src_port() {
	f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "5.6.7.8", protocol: 47, source_port: 99999)') or {
		assert err.msg().contains('source port')
		return
	}
	assert false, 'expected error'
}

// Error: dest port out of range (line 53)
fn test_f4_community_id_bad_dst_port() {
	f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "5.6.7.8", protocol: 47, source_port: 80, destination_port: 99999)') or {
		assert err.msg().contains('destination port')
		return
	}
	assert false, 'expected error'
}

// With custom seed (line 27-31)
fn test_f4_community_id_with_seed() {
	result := f4_run('community_id(source_ip: "1.2.3.4", destination_ip: "5.6.7.8", protocol: 6, source_port: 80, destination_port: 1234, seed: 1)') or {
		assert false, 'community_id seed: ${err}'
		return
	}
	s := result as string
	assert s.starts_with('1:')
}

// ============================================================
// vrllib_crypto.v — hmac, sha2 variants, sha3, crc
// ============================================================

// HMAC with SHA-512 (line 304-306)
fn test_f4_hmac_sha512() {
	result := f4_run('encode_base64(hmac("hello", "key", "SHA-512"))') or {
		assert false, 'hmac sha512: ${err}'
		return
	}
	s := result as string
	assert s.len > 0
}

// HMAC with SHA-1 (line 308-310)
fn test_f4_hmac_sha1() {
	result := f4_run('encode_base64(hmac("hello", "key", "SHA-1"))') or {
		assert false, 'hmac sha1: ${err}'
		return
	}
	s := result as string
	assert s.len > 0
}

// HMAC with SHA-224 (line 312-314)
fn test_f4_hmac_sha224() {
	result := f4_run('encode_base64(hmac("hello", "key", "SHA-224"))') or {
		assert false, 'hmac sha224: ${err}'
		return
	}
	s := result as string
	assert s.len > 0
}

// HMAC with SHA-384 (line 316-318)
fn test_f4_hmac_sha384() {
	result := f4_run('encode_base64(hmac("hello", "key", "SHA-384"))') or {
		assert false, 'hmac sha384: ${err}'
		return
	}
	s := result as string
	assert s.len > 0
}

// HMAC unsupported algorithm (line 321)
fn test_f4_hmac_bad_algorithm() {
	f4_run('hmac("hello", "key", "MD5")') or {
		assert err.msg().contains('unsupported')
		return
	}
	assert false, 'expected error'
}

// SHA-2 SHA-224 variant (line 43-46)
fn test_f4_sha2_224() {
	result := f4_run('sha2("hello", "SHA-224")') or {
		assert false, 'sha2 224: ${err}'
		return
	}
	s := result as string
	assert s.len == 56 // 28 bytes = 56 hex chars
}

// SHA-2 SHA-384 variant (line 50-52)
fn test_f4_sha2_384() {
	result := f4_run('sha2("hello", "SHA-384")') or {
		assert false, 'sha2 384: ${err}'
		return
	}
	s := result as string
	assert s.len == 96 // 48 bytes = 96 hex chars
}

// SHA-2 SHA-512 variant (line 54-55)
fn test_f4_sha2_512() {
	result := f4_run('sha2("hello", "SHA-512")') or {
		assert false, 'sha2 512: ${err}'
		return
	}
	s := result as string
	assert s.len == 128
}

// SHA-2 SHA-512/224 variant (line 57-59)
fn test_f4_sha2_512_224() {
	result := f4_run('sha2("hello", "SHA-512/224")') or {
		assert false, 'sha2 512/224: ${err}'
		return
	}
	s := result as string
	assert s.len == 56
}

// SHA-2 unknown variant (line 65-67)
fn test_f4_sha2_bad_variant() {
	f4_run('sha2("hello", "SHA-999")') or {
		assert err.msg().contains('unknown SHA-2 variant')
		return
	}
	assert false, 'expected error'
}

// SHA-3 SHA3-224 variant (line 102-104)
fn test_f4_sha3_224() {
	result := f4_run('sha3("hello", "SHA3-224")') or {
		assert false, 'sha3 224: ${err}'
		return
	}
	s := result as string
	assert s.len == 56
}

// SHA-3 SHA3-256 variant (line 106-108)
fn test_f4_sha3_256() {
	result := f4_run('sha3("hello", "SHA3-256")') or {
		assert false, 'sha3 256: ${err}'
		return
	}
	s := result as string
	assert s.len == 64
}

// SHA-3 SHA3-384 variant (line 110-112)
fn test_f4_sha3_384() {
	result := f4_run('sha3("hello", "SHA3-384")') or {
		assert false, 'sha3 384: ${err}'
		return
	}
	s := result as string
	assert s.len == 96
}

// SHA-3 unknown variant (line 118-120)
fn test_f4_sha3_bad_variant() {
	f4_run('sha3("hello", "SHA3-999")') or {
		assert err.msg().contains('unknown SHA-3 variant')
		return
	}
	assert false, 'expected error'
}

// xxhash XXH64 variant (line 468-470)
fn test_f4_xxhash_xxh64() {
	result := f4_run('xxhash("hello", "XXH64")') or {
		assert false, 'xxhash xxh64: ${err}'
		return
	}
	_ = result as i64
}

// xxhash XXH3-64 variant (line 472-474)
fn test_f4_xxhash_xxh3_64() {
	result := f4_run('xxhash("hello", "XXH3-64")') or {
		assert false, 'xxhash xxh3-64: ${err}'
		return
	}
	_ = result as i64
}

// xxhash XXH3-128 variant (line 476-481)
fn test_f4_xxhash_xxh3_128() {
	result := f4_run('xxhash("hello", "XXH3-128")') or {
		assert false, 'xxhash xxh3-128: ${err}'
		return
	}
	s := result as string
	assert s.len == 32 // 128 bits = 32 hex chars
}

// xxhash bad variant (line 483-485)
fn test_f4_xxhash_bad_variant() {
	f4_run('xxhash("hello", "XXH999")') or {
		assert err.msg().contains('Variant must be')
		return
	}
	assert false, 'expected error'
}

// CRC with different algorithms (covering crc_get_params paths)
fn test_f4_crc_algorithms() {
	// CRC_3_GSM (line 579)
	r1 := f4_run('crc("123456789", "CRC_3_GSM")') or {
		assert false, 'crc 3 gsm: ${err}'
		return
	}
	_ = r1

	// CRC_8_SMBUS (line 616)
	r2 := f4_run('crc("123456789", "CRC_8_SMBUS")') or {
		assert false, 'crc 8 smbus: ${err}'
		return
	}
	_ = r2

	// CRC_16_USB (line 669)
	r3 := f4_run('crc("123456789", "CRC_16_USB")') or {
		assert false, 'crc 16 usb: ${err}'
		return
	}
	_ = r3

	// CRC_64_XZ (line 709)
	r4 := f4_run('crc("123456789", "CRC_64_XZ")') or {
		assert false, 'crc 64 xz: ${err}'
		return
	}
	_ = r4

	// Invalid algorithm (line 710)
	f4_run('crc("hello", "CRC_INVALID")') or {
		assert err.msg().contains('Invalid CRC algorithm')
		return
	}
	assert false, 'expected error'
}

// CRC_82_DARC (line 528-529, crc82_darc path)
fn test_f4_crc_82_darc() {
	result := f4_run('crc("123456789", "CRC_82_DARC")') or {
		assert false, 'crc 82 darc: ${err}'
		return
	}
	_ = result as string
}

// seahash function (line 344-356)
fn test_f4_seahash() {
	result := f4_run('seahash("hello world")') or {
		assert false, 'seahash: ${err}'
		return
	}
	_ = result as i64
}

// ============================================================
// vrllib_dns.v — reverse_dns
// ============================================================

// reverse_dns with localhost IPv4 (lines 80-109)
fn test_f4_reverse_dns_localhost() {
	result := f4_run('reverse_dns("127.0.0.1")') or {
		// DNS may fail in CI, that's ok - we still cover the code path
		return
	}
	_ = result as string
}

// reverse_dns with IPv6 loopback (lines 61-79)
fn test_f4_reverse_dns_ipv6() {
	result := f4_run('reverse_dns("::1")') or {
		return
	}
	_ = result as string
}

// reverse_dns with invalid input (line 53-54)
fn test_f4_reverse_dns_invalid() {
	f4_run('reverse_dns("not_an_ip")') or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected error'
}

// reverse_dns with invalid IPv4 (line 83-84)
fn test_f4_reverse_dns_bad_ipv4() {
	f4_run('reverse_dns("1.2.3")') or {
		assert err.msg().contains('invalid')
		return
	}
	assert false, 'expected error'
}

// dns_lookup (covers lines 11-40)
fn test_f4_dns_lookup() {
	result := f4_run('dns_lookup("localhost")') or {
		// DNS may fail, that's ok
		return
	}
	_ = result
}

// ============================================================
// vrllib_etld.v — parse_etld
// ============================================================

// Basic parse_etld (covers psl_load and lookup path)
fn test_f4_parse_etld_basic() {
	result := f4_run('parse_etld("www.example.com")') or {
		assert false, 'parse_etld basic: ${err}'
		return
	}
	obj := result as ObjectMap
	etld := obj.get('etld') or {
		assert false, 'no etld key'
		return
	}
	assert (etld as string) == 'com'
}

// parse_etld with plus_parts (line 165-173)
fn test_f4_parse_etld_plus_parts() {
	result := f4_run('parse_etld("www.example.co.uk", plus_parts: 1)') or {
		assert false, 'parse_etld plus_parts: ${err}'
		return
	}
	obj := result as ObjectMap
	ep := obj.get('etld_plus') or {
		assert false, 'no etld_plus key'
		return
	}
	assert (ep as string) == 'example.co.uk'
}

// parse_etld with negative plus_parts (line 171-172, clamped to 0)
fn test_f4_parse_etld_negative_plus() {
	result := f4_run('parse_etld("www.example.com", plus_parts: -1)') or {
		assert false, 'parse_etld neg plus: ${err}'
		return
	}
	obj := result as ObjectMap
	_ = obj.get('etld') or {
		assert false, 'no etld key'
		return
	}
}

// parse_etld with co.uk (multi-label eTLD, covers psl_match_rule wildcard path)
fn test_f4_parse_etld_co_uk() {
	result := f4_run('parse_etld("test.co.uk")') or {
		assert false, 'parse_etld co.uk: ${err}'
		return
	}
	obj := result as ObjectMap
	known := obj.get('known_suffix') or {
		assert false, 'no known_suffix key'
		return
	}
	assert (known as bool) == true
}

// ============================================================
// vrllib_grok.v — parse_grok
// ============================================================

// parse_grok basic (covers lines 63-97)
fn test_f4_parse_grok_basic() {
	result := f4_run('parse_grok("55.3.244.1 GET /index.html 15824 0.043", "%{IP:client} %{WORD:method} %{URIPATHPARAM:request} %{NUMBER:bytes} %{NUMBER:duration}")') or {
		assert false, 'parse_grok basic: ${err}'
		return
	}
	obj := result as ObjectMap
	client := obj.get('client') or {
		assert false, 'no client key'
		return
	}
	assert (client as string) == '55.3.244.1'
}

// parse_grok no match (line 85-86)
fn test_f4_parse_grok_no_match() {
	f4_run('parse_grok("no match here", "%{IP:client}")') or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected error'
}

// parse_grok unknown pattern (line 51)
fn test_f4_parse_grok_unknown() {
	f4_run('parse_grok("test", "%{NONEXISTENT:val}")') or {
		assert err.msg().contains('unknown grok pattern')
		return
	}
	assert false, 'expected error'
}

// ============================================================
// vrllib_ip.v — ip_aton, ip_ntoa, ip_cidr_contains, ip_subnet, ip_to_ipv6, ipv6_to_ipv4, is_ipv4, is_ipv6, ip_version
// ============================================================

// ip_aton (line 4-26)
fn test_f4_ip_aton() {
	result := f4_run('ip_aton("192.168.1.1")') or {
		assert false, 'ip_aton: ${err}'
		return
	}
	n := result as i64
	assert n == 3232235777 // 192*2^24 + 168*2^16 + 1*2^8 + 1
}

// ip_ntoa (line 29-43)
fn test_f4_ip_ntoa() {
	result := f4_run('ip_ntoa(3232235777)') or {
		assert false, 'ip_ntoa: ${err}'
		return
	}
	assert (result as string) == '192.168.1.1'
}

// ip_cidr_contains with array of CIDRs (lines 58-69)
fn test_f4_ip_cidr_contains_array() {
	result := f4_run('ip_cidr_contains(["10.0.0.0/8", "192.168.0.0/16"], "192.168.1.1")') or {
		assert false, 'ip_cidr_contains array: ${err}'
		return
	}
	assert (result as bool) == true
}

// ip_cidr_contains array no match
fn test_f4_ip_cidr_contains_array_no_match() {
	result := f4_run('ip_cidr_contains(["10.0.0.0/8"], "192.168.1.1")') or {
		assert false, 'ip_cidr_contains array no match: ${err}'
		return
	}
	assert (result as bool) == false
}

// ip_subnet with dotted mask (line 138-140)
fn test_f4_ip_subnet_dotted() {
	result := f4_run('ip_subnet("192.168.1.100", "255.255.255.0")') or {
		assert false, 'ip_subnet dotted: ${err}'
		return
	}
	assert (result as string) == '192.168.1.0'
}

// ip_subnet with CIDR prefix (line 131-137)
fn test_f4_ip_subnet_cidr() {
	result := f4_run('ip_subnet("192.168.1.100", "/24")') or {
		assert false, 'ip_subnet cidr: ${err}'
		return
	}
	assert (result as string) == '192.168.1.0'
}

// ip_subnet with invalid subnet format (line 141-142)
fn test_f4_ip_subnet_invalid() {
	f4_run('ip_subnet("192.168.1.100", "invalid")') or {
		assert err.msg().contains('invalid subnet')
		return
	}
	assert false, 'expected error'
}

// ip_to_ipv6 with already IPv6 (line 164-165)
fn test_f4_ip_to_ipv6_already() {
	result := f4_run('ip_to_ipv6("::1")') or {
		assert false, 'ip_to_ipv6 already: ${err}'
		return
	}
	assert (result as string) == '::1'
}

// ipv6_to_ipv4 non-mapped (line 184)
fn test_f4_ipv6_to_ipv4_not_mapped() {
	f4_run('ipv6_to_ipv4("::1")') or {
		assert err.msg().contains('not an IPv4-mapped')
		return
	}
	assert false, 'expected error'
}

// is_ipv4 with non-string (line 195)
fn test_f4_is_ipv4_non_string() {
	result := f4_run('is_ipv4(42)') or {
		assert false, 'is_ipv4 non-string: ${err}'
		return
	}
	assert (result as bool) == false
}

// is_ipv4 with bad format (lines 198-213)
fn test_f4_is_ipv4_bad_format() {
	result := f4_run('is_ipv4("1.2.3")') or {
		assert false, 'is_ipv4 bad: ${err}'
		return
	}
	assert (result as bool) == false
}

// is_ipv4 with non-digit chars (line 207)
fn test_f4_is_ipv4_non_digit() {
	result := f4_run('is_ipv4("1.2.3.abc")') or {
		assert false, 'is_ipv4 non-digit: ${err}'
		return
	}
	assert (result as bool) == false
}

// is_ipv6 non-string (line 225)
fn test_f4_is_ipv6_non_string() {
	result := f4_run('is_ipv6(42)') or {
		assert false, 'is_ipv6 non-string: ${err}'
		return
	}
	assert (result as bool) == false
}

// is_ipv6 with no colons (line 229)
fn test_f4_is_ipv6_no_colons() {
	result := f4_run('is_ipv6("192.168.1.1")') or {
		assert false, 'is_ipv6 no colons: ${err}'
		return
	}
	assert (result as bool) == false
}

// ip_version with IPv6 (line 250)
fn test_f4_ip_version_v6() {
	result := f4_run('ip_version("::1")') or {
		assert false, 'ip_version v6: ${err}'
		return
	}
	assert (result as string) == 'IPv6'
}

// ip_version with invalid (line 256)
fn test_f4_ip_version_invalid() {
	f4_run('ip_version("not_ip")') or {
		assert err.msg().contains('not a valid IP')
		return
	}
	assert false, 'expected error'
}

// ============================================================
// vrllib_ip2.v — ip_ntop, ip_pton, ipv6_compress
// ============================================================

// ip_pton IPv4 (line 91-111)
fn test_f4_ip_pton_ipv4() {
	result := f4_run('encode_base16(ip_pton("192.168.1.1"))') or {
		assert false, 'ip_pton ipv4: ${err}'
		return
	}
	assert (result as string) == 'c0a80101'
}

// ip_pton IPv6 (line 87-90)
fn test_f4_ip_pton_ipv6() {
	result := f4_run('encode_base16(ip_pton("::1"))') or {
		assert false, 'ip_pton ipv6: ${err}'
		return
	}
	assert (result as string) == '00000000000000000000000000000001'
}

// ip_pton invalid (line 113)
fn test_f4_ip_pton_invalid() {
	f4_run('ip_pton("not_ip")') or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected error'
}

// ip_ntop with 4 bytes -> IPv4 (line 15-17)
fn test_f4_ip_ntop_ipv4() {
	// Use ip_pton to create 4 bytes, then ip_ntop to convert back
	result := f4_run('ip_ntop(ip_pton("10.0.0.1"))') or {
		assert false, 'ip_ntop ipv4: ${err}'
		return
	}
	assert (result as string) == '10.0.0.1'
}

// ip_ntop with 16 bytes -> IPv6 (line 18-27)
fn test_f4_ip_ntop_ipv6() {
	result := f4_run('ip_ntop(ip_pton("2001:db8::1"))') or {
		assert false, 'ip_ntop ipv6: ${err}'
		return
	}
	s := result as string
	assert s.contains('2001')
}

// ip_ntop with invalid length (line 28)
fn test_f4_ip_ntop_invalid_len() {
	f4_run('ip_ntop("abc")') or {
		assert err.msg().contains('length 4 or 16')
		return
	}
	assert false, 'expected error'
}

// ipv6_compress no compression needed (line 55-57)
fn test_f4_ipv6_compress_no_compress() {
	result := f4_run('ip_ntop(ip_pton("1:2:3:4:5:6:7:8"))') or {
		assert false, 'ipv6 no compress: ${err}'
		return
	}
	s := result as string
	assert s == '1:2:3:4:5:6:7:8'
}

// ipv6_compress with trailing zeros (line 70-71)
fn test_f4_ipv6_compress_trailing() {
	result := f4_run('ip_ntop(ip_pton("2001:db8::"))') or {
		assert false, 'ipv6 trailing: ${err}'
		return
	}
	s := result as string
	assert s == '2001:db8::'
}

// ============================================================
// vrllib_object.v — unnest, object_from_array, zip, remove
// ============================================================

// object_from_array with key-value pairs (lines 256-273)
fn test_f4_object_from_array_pairs() {
	result := f4_run('object_from_array([["a", 1], ["b", 2]])') or {
		assert false, 'object_from_array pairs: ${err}'
		return
	}
	obj := result as ObjectMap
	a_val := obj.get('a') or {
		assert false, 'no a key'
		return
	}
	assert (a_val as i64) == 1
}

// object_from_array with keys argument (lines 236-253)
fn test_f4_object_from_array_keys() {
	result := f4_run('object_from_array(["val1", "val2"], ["key1", "key2"])') or {
		assert false, 'object_from_array keys: ${err}'
		return
	}
	obj := result as ObjectMap
	v := obj.get('key1') or {
		assert false, 'no key1'
		return
	}
	assert (v as string) == 'val1'
}

// zip with multiple args (lines 297-306)
fn test_f4_zip_multi() {
	result := f4_run('zip(["a", "b"], [1, 2])') or {
		assert false, 'zip multi: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 2
}

// zip with single array of arrays (lines 282-296)
fn test_f4_zip_single() {
	result := f4_run('zip([["a", "b"], [1, 2]])') or {
		assert false, 'zip single: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 2
}

// remove from object (lines 329-342, 344-408)
fn test_f4_remove_object() {
	result := f4_run('. = {"a": 1, "b": {"c": 2}}; remove(., ["b", "c"])') or {
		assert false, 'remove object: ${err}'
		return
	}
	_ = result
}

// remove with compact (line 338-340)
fn test_f4_remove_compact() {
	result := f4_run('. = {"a": 1, "b": {"c": 2}}; remove(., ["b", "c"], compact: true)') or {
		assert false, 'remove compact: ${err}'
		return
	}
	_ = result
}

// remove from array (lines 370-402)
fn test_f4_remove_array() {
	result := f4_run('. = [1, 2, 3]; remove(., [1])') or {
		assert false, 'remove array: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 2
}

// unnest basic (lines 4-15)
fn test_f4_unnest_basic() {
	mut obj := map[string]VrlValue{}
	obj['items'] = VrlValue([VrlValue(i64(1)), VrlValue(i64(2))])
	result := f4_run_obj('. = unnest(.items)', obj) or {
		assert false, 'unnest basic: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 2
}

// ============================================================
// vrllib_string.v — case conversion, basename, dirname, strip_ansi, shannon_entropy, sieve
// ============================================================

// screaming_snakecase (line 88)
fn test_f4_screamingsnakecase() {
	result := f4_run('screamingsnakecase("hello world")') or {
		assert false, 'screamingsnakecase: ${err}'
		return
	}
	assert (result as string) == 'HELLO_WORLD'
}

// kebabcase (line 87)
fn test_f4_kebabcase() {
	result := f4_run('kebabcase("hello world")') or {
		assert false, 'kebabcase: ${err}'
		return
	}
	assert (result as string) == 'hello-world'
}

// pascalcase (line 85)
fn test_f4_pascalcase() {
	result := f4_run('pascalcase("hello_world")') or {
		assert false, 'pascalcase: ${err}'
		return
	}
	assert (result as string) == 'HelloWorld'
}

// Case conversion with original_case parameter (line 93-112, split_words_by_case)
fn test_f4_camelcase_from_snake() {
	result := f4_run('camelcase("hello_world", "snakeCase")') or {
		assert false, 'camelcase from snake: ${err}'
		return
	}
	assert (result as string) == 'helloWorld'
}

fn test_f4_camelcase_from_kebab() {
	result := f4_run('camelcase("hello-world", "kebabCase")') or {
		assert false, 'camelcase from kebab: ${err}'
		return
	}
	assert (result as string) == 'helloWorld'
}

fn test_f4_camelcase_from_camel() {
	result := f4_run('snakecase("helloWorld", "camelCase")') or {
		assert false, 'snakecase from camel: ${err}'
		return
	}
	assert (result as string) == 'hello_world'
}

// basename with extension removal (lines 215-225)
fn test_f4_basename_with_ext() {
	result := f4_run('basename("/path/to/file.txt", ".txt")') or {
		assert false, 'basename ext: ${err}'
		return
	}
	assert (result as string) == 'file'
}

// basename with root path (line 203-204)
fn test_f4_basename_root() {
	result := f4_run('basename("/")') or {
		assert false, 'basename root: ${err}'
		return
	}
	_ = result
}

// dirname with root (line 244-245)
fn test_f4_dirname_root() {
	result := f4_run('dirname("/file")') or {
		assert false, 'dirname root: ${err}'
		return
	}
	assert (result as string) == '/'
}

// dirname with no slash (line 243)
fn test_f4_dirname_no_slash() {
	result := f4_run('dirname("file")') or {
		assert false, 'dirname no slash: ${err}'
		return
	}
	assert (result as string) == '.'
}

// dirname with trailing slashes (line 239-240)
fn test_f4_dirname_trailing_slash() {
	result := f4_run('dirname("///")') or {
		assert false, 'dirname trailing: ${err}'
		return
	}
	assert (result as string) == '/'
}

// split_path (lines 251-271)
fn test_f4_split_path() {
	result := f4_run('split_path("/usr/local/bin")') or {
		assert false, 'split_path: ${err}'
		return
	}
	arr := result as []VrlValue
	assert arr.len == 4 // "/", "usr", "local", "bin"
}

// strip_ansi_escape_codes (lines 274-319)
fn test_f4_strip_ansi() {
	// Use raw bytes to create ANSI escape sequences
	ansi_str := '\x1b[31mhello\x1b[0m'
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue(ansi_str)
	result := f4_run_obj('strip_ansi_escape_codes(.msg)', obj) or {
		assert false, 'strip_ansi: ${err}'
		return
	}
	assert (result as string) == 'hello'
}

// strip_ansi with OSC sequences (lines 300-314)
fn test_f4_strip_ansi_osc() {
	// OSC sequence: ESC ] ... BEL
	osc_str := '\x1b]0;title\x07hello'
	mut obj := map[string]VrlValue{}
	obj['msg'] = VrlValue(osc_str)
	result := f4_run_obj('strip_ansi_escape_codes(.msg)', obj) or {
		assert false, 'strip_ansi osc: ${err}'
		return
	}
	assert (result as string) == 'hello'
}

// shannon_entropy codepoint mode (lines 345-362)
fn test_f4_shannon_entropy_codepoint() {
	result := f4_run('shannon_entropy("hello", "codepoint")') or {
		assert false, 'entropy codepoint: ${err}'
		return
	}
	f := result as f64
	assert f > 0.0
}

// shannon_entropy grapheme mode (lines 366-410)
fn test_f4_shannon_entropy_grapheme() {
	result := f4_run('shannon_entropy("hello", "grapheme")') or {
		assert false, 'entropy grapheme: ${err}'
		return
	}
	f := result as f64
	assert f > 0.0
}

// shannon_entropy empty string (line 341-342)
fn test_f4_shannon_entropy_empty() {
	result := f4_run('shannon_entropy("")') or {
		assert false, 'entropy empty: ${err}'
		return
	}
	f := result as f64
	assert f == 0.0
}

// sieve function (lines 459-541)
fn test_f4_sieve_basic() {
	result := f4_run('sieve("abc123def", r\'[a-z]\')') or {
		assert false, 'sieve basic: ${err}'
		return
	}
	assert (result as string) == 'abcdef'
}

// sieve with replace_single (line 524-530)
fn test_f4_sieve_replace_single() {
	result := f4_run('sieve("abc123def", r\'[a-z]\', replace_single: "?")') or {
		assert false, 'sieve replace single: ${err}'
		return
	}
	assert (result as string) == 'abc???def'
}

// sieve with replace_repeated (line 519-523)
fn test_f4_sieve_replace_repeated() {
	result := f4_run('sieve("abc123def", r\'[a-z]\', replace_repeated: "*")') or {
		assert false, 'sieve replace repeated: ${err}'
		return
	}
	assert (result as string) == 'abc*def'
}

// ============================================================
// vrllib_enumerate.v — for_each, filter, map_values, tally, tally_value, match_array
// ============================================================

// tally (lines 6-33)
fn test_f4_tally() {
	result := f4_run('tally(["a", "b", "a", "c", "b", "a"])') or {
		assert false, 'tally: ${err}'
		return
	}
	obj := result as ObjectMap
	a_count := obj.get('a') or {
		assert false, 'no a'
		return
	}
	assert (a_count as i64) == 3
}

// tally_value (lines 36-53)
fn test_f4_tally_value() {
	result := f4_run('tally_value(["a", "b", "a", "c"], "a")') or {
		assert false, 'tally_value: ${err}'
		return
	}
	assert (result as i64) == 2
}

// match_array with any match (lines 56-92)
fn test_f4_match_array_any() {
	result := f4_run('match_array(["hello", "world"], r\'hel\')') or {
		assert false, 'match_array any: ${err}'
		return
	}
	assert (result as bool) == true
}

// match_array with all mode (line 66, 81-83)
fn test_f4_match_array_all() {
	result := f4_run('match_array(["hello", "help"], r\'hel\', all: true)') or {
		assert false, 'match_array all: ${err}'
		return
	}
	assert (result as bool) == true
}

// match_array all mode with non-match (line 82-83)
fn test_f4_match_array_all_fail() {
	result := f4_run('match_array(["hello", "world"], r\'hel\', all: true)') or {
		assert false, 'match_array all fail: ${err}'
		return
	}
	assert (result as bool) == false
}

// ============================================================
// vrllib_codec.v — encode_base64, decode_mime_q, encode_csv, encode_key_value, snappy, lz4, zstd
// ============================================================

// encode_base64 url_safe with padding (lines 29-37)
fn test_f4_encode_base64_urlsafe() {
	result := f4_run('encode_base64("hello+world", padding: true, charset: "url_safe")') or {
		assert false, 'base64 urlsafe: ${err}'
		return
	}
	s := result as string
	assert s.len > 0
	assert !s.contains('+')
}

// encode_base64 no padding (line 40)
fn test_f4_encode_base64_no_padding() {
	result := f4_run('encode_base64("hi", padding: false)') or {
		assert false, 'base64 no padding: ${err}'
		return
	}
	s := result as string
	assert !s.ends_with('=')
}

// decode_base64 url_safe (line 70-71)
fn test_f4_decode_base64_urlsafe() {
	result := f4_run('decode_base64("aGVsbG8", charset: "url_safe")') or {
		assert false, 'decode base64 urlsafe: ${err}'
		return
	}
	assert (result as string) == 'hello'
}

// encode_percent with CONTROLS set (line 155-156)
fn test_f4_encode_percent_controls() {
	result := f4_run('encode_percent("hello\\nworld", ascii_set: "CONTROLS")') or {
		assert false, 'encode_percent controls: ${err}'
		return
	}
	s := result as string
	assert s.contains('%0A')
}

// encode_key_value with fields ordering and flatten_boolean (lines 260-342)
fn test_f4_encode_key_value_ordered() {
	// positional: encode_key_value(obj, fields_ordering, kv_delim, field_delim, flatten_bool)
	result := f4_run('encode_key_value({"b": 2, "a": 1, "c": true}, ["b", "a"], "=", " ", true)') or {
		assert false, 'encode_key_value ordered: ${err}'
		return
	}
	s := result as string
	assert s.contains('b=2')
	assert s.contains('a=1')
}

// encode_csv (lines 215-240)
fn test_f4_encode_csv() {
	result := f4_run('encode_csv(["a", "b,c", "d"])') or {
		assert false, 'encode_csv: ${err}'
		return
	}
	s := result as string
	assert s.contains('"b,c"')
}

// decode_mime_q delimited (lines 408-444)
fn test_f4_decode_mime_q() {
	result := f4_run('decode_mime_q("=?UTF-8?Q?hello_world?=")') or {
		assert false, 'decode_mime_q: ${err}'
		return
	}
	assert (result as string) == 'hello world'
}

// decode_mime_q base64 encoding (line 538-544)
fn test_f4_decode_mime_q_base64() {
	result := f4_run('decode_mime_q("=?UTF-8?B?aGVsbG8=?=")') or {
		assert false, 'decode_mime_q b64: ${err}'
		return
	}
	assert (result as string) == 'hello'
}

// decode_mime_q internal format (line 440-442, 497-531)
fn test_f4_decode_mime_q_internal() {
	result := f4_run('decode_mime_q("?Q?hello_world")') or {
		assert false, 'decode_mime_q internal: ${err}'
		return
	}
	assert (result as string) == 'hello world'
}

// encode/decode snappy roundtrip (lines 692-733)
fn test_f4_snappy_roundtrip() {
	result := f4_run('decode_snappy(encode_snappy("hello world"))') or {
		assert false, 'snappy roundtrip: ${err}'
		return
	}
	assert (result as string) == 'hello world'
}

// encode/decode lz4 roundtrip (lines 738-802)
fn test_f4_lz4_roundtrip() {
	result := f4_run('decode_lz4(encode_lz4("hello world"))') or {
		assert false, 'lz4 roundtrip: ${err}'
		return
	}
	assert (result as string) == 'hello world'
}

// encode/decode zstd roundtrip (lines 639-672)
fn test_f4_zstd_roundtrip() {
	result := f4_run('decode_zstd(encode_zstd("hello world"))') or {
		assert false, 'zstd roundtrip: ${err}'
		return
	}
	assert (result as string) == 'hello world'
}

// encode/decode zlib roundtrip (lines 577-604)
fn test_f4_zlib_roundtrip() {
	result := f4_run('decode_zlib(encode_zlib("hello world"))') or {
		assert false, 'zlib roundtrip: ${err}'
		return
	}
	assert (result as string) == 'hello world'
}

// encode/decode gzip roundtrip (lines 607-637)
fn test_f4_gzip_roundtrip() {
	result := f4_run('decode_gzip(encode_gzip("hello world"))') or {
		assert false, 'gzip roundtrip: ${err}'
		return
	}
	assert (result as string) == 'hello world'
}

// encode_logfmt (lines 363-401)
fn test_f4_encode_logfmt() {
	result := f4_run('encode_logfmt({"level": "info", "msg": "hello world"})') or {
		assert false, 'encode_logfmt: ${err}'
		return
	}
	s := result as string
	assert s.contains('level=info')
	assert s.contains('msg="hello world"')
}

// encode_logfmt with boolean values (line 392-393)
fn test_f4_encode_logfmt_bool() {
	result := f4_run('encode_logfmt({"active": true, "name": "test"})') or {
		assert false, 'encode_logfmt bool: ${err}'
		return
	}
	s := result as string
	assert s.contains('active=true')
}

// crc32 function (line 329-340)
fn test_f4_crc32() {
	result := f4_run('crc32("hello")') or {
		assert false, 'crc32: ${err}'
		return
	}
	_ = result as i64
}

// md5 function (line 262-272)
fn test_f4_md5() {
	result := f4_run('md5("hello")') or {
		assert false, 'md5: ${err}'
		return
	}
	s := result as string
	assert s == '5d41402abc4b2a76b9719d911017c592'
}
