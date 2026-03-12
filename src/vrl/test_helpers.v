module vrl

// uses_unimplemented_fn checks if source code calls functions we haven't implemented yet.
fn uses_unimplemented_fn(src string) bool {
	unimplemented := [
		// Crypto (not available in V stdlib)
		'sha3', 'seahash', 'xxhash',
		// Complex parsing (require specialized formats)
		'parse_common_log', 'parse_syslog', 'parse_logfmt', 'parse_xml',
		'parse_klog', 'parse_linux_authorization',
		'parse_nginx_log', 'parse_apache_log', 'parse_aws_alb_log',
		'parse_aws_cloudwatch_log_subscription_message', 'parse_aws_vpc_flow_log',
		'parse_cef', 'parse_user_agent', 'parse_etld',
		'parse_ruby_hash', 'parse_glog', 'parse_grok', 'parse_groks',
		'parse_influxdb', 'parse_yaml', 'parse_proto',
		// Codec (require external libs)
		'encode_punycode', 'decode_punycode',
		'encode_snappy', 'decode_snappy',
		'encode_zlib', 'decode_zlib',
		'encode_gzip', 'decode_gzip',
		'encode_zstd', 'decode_zstd',
		'encode_proto', 'decode_proto',
		'encode_charset', 'decode_charset',
		'decode_mime_q',
		// Other unimplemented
		'match_datadog_query',
		'redact', 'community_id', 'decrypt', 'encrypt',
		'crc32', 'murmur3', 'crc',
		'mezmo_patterns', 'punycode',
		'reverse_dns',
		'decrypt_ip', 'encrypt_ip',
		'get_timezone_name', 'haversine', 'http_request',
		'uuid_from_friendly_id',
	]
	for fn_name in unimplemented {
		if src.contains('${fn_name}(') || src.contains('${fn_name}!(') {
			return true
		}
	}
	return false
}
