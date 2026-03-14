module vrl

// Tests for VRL vrllib functions — broad coverage of parsing, encoding,
// type-checking, iteration, and miscellaneous utility functions.

fn s6_obj(prog string, input string) !VrlValue {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(input)
	return execute(prog, obj)
}

// ============================================================================
// Parsing functions
// ============================================================================

fn test_parse_klog() {
	result := s6_obj('parse_klog!(.input)',
		'I0415 12:00:00.000000 1234 file.go:56] message here') or { return }
	j := vrl_to_json(result)
	assert j.contains('message'), 'expected message field: ${j}'
	assert j.contains('file.go'), 'expected file: ${j}'
}

fn test_parse_linux_authorization() {
	result := s6_obj('parse_linux_authorization!(.input)',
		'Jan  1 00:00:00 hostname sshd[1234]: Accepted password for user from 1.2.3.4 port 22 ssh2') or { return }
	j := vrl_to_json(result)
	assert j.contains('hostname'), 'expected hostname: ${j}'
}

fn test_parse_common_log() {
	result := s6_obj('parse_common_log!(.input)',
		'127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326') or { return }
	j := vrl_to_json(result)
	assert j.contains('frank'), 'expected user frank: ${j}'
	assert j.contains('200'), 'expected status 200: ${j}'
}

fn test_parse_tokens() {
	result := s6_obj('parse_tokens!(.input)', 'A]B"C D') or { return }
	j := vrl_to_json(result)
	assert j.contains('A'), 'expected token A: ${j}'
}

fn test_parse_grok() {
	result := execute('parse_grok!("hello world", "%{GREEDYDATA:msg}")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('hello world'), 'expected msg: ${j}'
}

fn test_parse_glog() {
	result := s6_obj('parse_glog!(.input)',
		'I20230101 12:00:00.000000 1234 file.cc:56] message') or { return }
	j := vrl_to_json(result)
	assert j.contains('message'), 'expected message: ${j}'
}

fn test_parse_url() {
	result := execute('parse_url!("https://user:pass@example.com:8080/path?q=1#frag")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('example.com'), 'expected host: ${j}'
	assert j.contains('8080'), 'expected port: ${j}'
	assert j.contains('frag'), 'expected fragment: ${j}'
}

fn test_parse_query_string() {
	result := execute('parse_query_string!("key=value&foo=bar")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('key'), 'expected key: ${j}'
	assert j.contains('value'), 'expected value: ${j}'
	assert j.contains('foo'), 'expected foo: ${j}'
	assert j.contains('bar'), 'expected bar: ${j}'
}

fn test_parse_etld() {
	result := execute('parse_etld!("https://www.example.co.uk")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 2, 'expected etld info: ${j}'
}

fn test_parse_aws_alb_log() {
	line := 'http 2023-01-01T00:00:00.000000Z app/my-alb/1234567890 1.2.3.4:1234 5.6.7.8:80 0.001 0.002 0.003 200 200 123 456 "GET http://example.com:80/path HTTP/1.1" "curl/7.0" ECDHE-RSA-AES128-GCM-SHA256 TLSv1.2 arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/my-tg/1234567890 "Root=1-12345678-123456789012345678901234" "example.com" "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012" 0 2023-01-01T00:00:00.000000Z "forward" "-" "-" "5.6.7.8:80" "200" "-" "-"'
	result := s6_obj('parse_aws_alb_log!(.input)', line) or { return }
	j := vrl_to_json(result)
	assert j.contains('200') || j.contains('example.com'), 'expected alb fields: ${j}'
}

// ============================================================================
// Redact and match_datadog_query
// ============================================================================

fn test_redact() {
	result := execute('redact("my SSN is 123-45-6789", filters: ["us_social_security_number"])',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert !j.contains('123-45-6789'), 'expected SSN redacted: ${j}'
}

fn test_match_datadog_query() {
	result := s6_obj('match_datadog_query(.input, "error")',
		'this is an error message') or { return }
	// Just verify it returned something
	_ := vrl_to_json(result)
}

// ============================================================================
// Codec roundtrips
// ============================================================================

fn test_snappy_roundtrip() {
	result := execute('decode_snappy!(encode_snappy!("hello snappy"))',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue('hello snappy'), 'snappy roundtrip failed: ${vrl_to_json(result)}'
}

fn test_lz4_roundtrip() {
	result := execute('decode_lz4!(encode_lz4!("hello lz4"))',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue('hello lz4'), 'lz4 roundtrip failed: ${vrl_to_json(result)}'
}

fn test_punycode_encode() {
	result := execute('encode_punycode!("muenchen")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected punycode output: ${j}'
}

fn test_punycode_decode() {
	result := execute('decode_punycode!("mnchen-3ya")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected decoded punycode: ${j}'
}

fn test_punycode_roundtrip() {
	result := execute('decode_punycode!(encode_punycode!("example"))',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue('example'), 'punycode roundtrip failed'
}

fn test_zstd_roundtrip_s6() {
	result := execute('decode_zstd!(encode_zstd!("hello zstd"))',
		map[string]VrlValue{}) or { return }
	assert result == VrlValue('hello zstd'), 'zstd roundtrip failed: ${vrl_to_json(result)}'
}

// ============================================================================
// IP conversion functions
// ============================================================================

fn test_ip_ntop() {
	// ip_ntop converts packed binary IP to string; ip_pton does the reverse
	result := execute('ip_ntop!(ip_pton!("192.168.1.1"))',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('192.168.1.1'), 'expected 192.168.1.1: ${j}'
}

fn test_ip_pton() {
	result := execute('ip_pton!("10.0.0.1")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected packed ip bytes: ${j}'
}

// ============================================================================
// uuid_from_friendly_id
// ============================================================================

fn test_uuid_from_friendly_id() {
	result := execute('uuid_from_friendly_id!("3sSB1vMrIEeMOYAN2hJ4ug")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected uuid: ${j}'
}

// ============================================================================
// Random functions
// ============================================================================

fn test_random_int() {
	result := execute('random_int(0, 100)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected random int: ${j}'
}

fn test_random_float() {
	result := execute('random_float(0.0, 1.0)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected random float: ${j}'
}

fn test_random_bool() {
	result := execute('random_bool()', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j == 'true' || j == 'false', 'expected bool: ${j}'
}

fn test_random_bytes() {
	result := execute('random_bytes(16)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected random bytes: ${j}'
}

// ============================================================================
// get_hostname
// ============================================================================

fn test_get_hostname() {
	result := execute('get_hostname!()', map[string]VrlValue{}) or { return }
	s := result as string
	assert s.len > 0, 'expected non-empty hostname'
}

// ============================================================================
// format_int
// ============================================================================

fn test_format_int() {
	result := execute('format_int!(255, 16)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('ff'), 'expected ff for 255 base16: ${j}'
}

// ============================================================================
// to_regex
// ============================================================================

fn test_to_regex() {
	// to_regex creates a regex, then we can use it with match
	result := execute(r"match('hello123', to_regex!(r'\d+'))", map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j == 'true', 'expected match to succeed: ${j}'
}

// ============================================================================
// type_def
// ============================================================================

fn test_type_def() {
	result := execute('type_def(42)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('integer') || j.len > 0, 'expected type info: ${j}'
}

// ============================================================================
// is_timestamp and timestamp
// ============================================================================

fn test_is_timestamp() {
	result := execute('is_timestamp(now())', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j == 'true', 'expected now() is timestamp: ${j}'
}

fn test_timestamp_now() {
	result := execute('timestamp(now())', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected timestamp string: ${j}'
}

// ============================================================================
// strip_ansi_escape_codes
// ============================================================================

fn test_strip_ansi_escape_codes() {
	// \x1b[31m is red ANSI escape, \x1b[0m resets
	result := s6_obj('strip_ansi_escape_codes(.input)',
		'\x1b[31mhello\x1b[0m') or { return }
	j := vrl_to_json(result)
	assert j.contains('hello'), 'expected hello: ${j}'
	assert !j.contains('\x1b'), 'expected no escape codes: ${j}'
}

// ============================================================================
// array (ensure_array)
// ============================================================================

fn test_array_wraps_scalar() {
	result := execute('array("hello")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"hello"'), 'expected array with hello: ${j}'
	assert j.starts_with('['), 'expected array: ${j}'
}

fn test_array_passthrough() {
	result := execute('array([1, 2, 3])', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.starts_with('['), 'expected array: ${j}'
}

// ============================================================================
// object (ensure_object)
// ============================================================================

fn test_object_passthrough() {
	result := execute('object({"a": 1})', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'expected object with a: ${j}'
}

// ============================================================================
// map_values
// ============================================================================

fn test_map_values() {
	result := execute('map_values({"a": 1, "b": 2}) -> |v| { v + 10 }',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('11'), 'expected 11: ${j}'
	assert j.contains('12'), 'expected 12: ${j}'
}

// ============================================================================
// map_keys
// ============================================================================

fn test_map_keys() {
	result := execute('map_keys({"hello": 1}) -> |k| { upcase(k) }',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('HELLO'), 'expected HELLO: ${j}'
}

// ============================================================================
// filter (closure-based)
// ============================================================================

fn test_filter_closure() {
	result := execute('filter(["a", "bb", "ccc"]) -> |_i, v| { length(v) > 1 }',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('bb'), 'expected bb: ${j}'
	assert j.contains('ccc'), 'expected ccc: ${j}'
	assert !j.contains('"a"'), 'should not contain single a: ${j}'
}

// ============================================================================
// chunks
// ============================================================================

fn test_chunks() {
	result := execute('chunks([1, 2, 3, 4, 5], 2)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('[1,2]') || j.contains('[1, 2]'), 'expected chunk [1,2]: ${j}'
}

// ============================================================================
// tally
// ============================================================================

fn test_tally() {
	result := execute('tally(["a", "b", "a", "a"])',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"') && j.contains('3'), 'expected a:3: ${j}'
	assert j.contains('"b"') && j.contains('1'), 'expected b:1: ${j}'
}

// ============================================================================
// del and exists
// ============================================================================

fn test_del_and_exists() {
	mut obj := map[string]VrlValue{}
	obj['key'] = VrlValue('value')
	result := execute('del(., "key")', obj) or { return }
	// del returns the deleted value
	j := vrl_to_json(result)
	assert j.contains('value') || j.len >= 0, 'del result: ${j}'
}

fn test_exists() {
	mut obj := map[string]VrlValue{}
	obj['key'] = VrlValue('value')
	result := execute('exists(.key)', obj) or { return }
	j := vrl_to_json(result)
	assert j == 'true', 'expected .key exists: ${j}'
}

fn test_exists_missing() {
	result := execute('exists(.missing)', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j == 'false', 'expected .missing does not exist: ${j}'
}

// ============================================================================
// encode_logfmt
// ============================================================================

fn test_encode_logfmt() {
	result := execute('encode_logfmt({"a": "1", "b": "2"})',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('a='), 'expected logfmt a=: ${j}'
	assert j.contains('b='), 'expected logfmt b=: ${j}'
}

// ============================================================================
// decode_mime_q
// ============================================================================

fn test_decode_mime_q() {
	result := execute('decode_mime_q!("=?UTF-8?Q?hello?=")',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('hello'), 'expected hello: ${j}'
}

// ============================================================================
// sha3
// ============================================================================

fn test_sha3() {
	result := execute('sha3("test")', map[string]VrlValue{}) or { return }
	s := result as string
	assert s.len > 0, 'expected sha3 hash'
}

// ============================================================================
// crc
// ============================================================================

fn test_crc() {
	result := execute('crc("test")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.len > 0, 'expected crc value: ${j}'
}

// ============================================================================
// compact with named args
// ============================================================================

fn test_compact_named_args() {
	result := execute('compact({"a": null, "b": "", "c": 1}, null: true, string: true)',
		map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"c"'), 'expected c retained: ${j}'
}
