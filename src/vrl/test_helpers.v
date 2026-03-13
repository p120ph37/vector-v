module vrl

// uses_unimplemented_fn checks if source code calls functions we haven't implemented yet.
fn uses_unimplemented_fn(src string) bool {
	unimplemented := [
		// Crypto (not available in V stdlib)
		'seahash', 'xxhash',
		// Complex parsing (require specialized formats)
		'parse_xml',
		'parse_nginx_log', 'parse_apache_log', 'parse_aws_alb_log',
		'parse_aws_vpc_flow_log',
		'parse_cef', 'parse_user_agent',
		'parse_ruby_hash', 'parse_glog', 'parse_groks',
		'parse_influxdb', 'parse_proto',
		// Codec (require external libs)
		'encode_snappy', 'decode_snappy',
		'encode_proto', 'decode_proto',
		'encode_charset', 'decode_charset',
		// Other unimplemented
		'community_id', 'decrypt', 'encrypt',
		'murmur3', 'crc',
		'mezmo_patterns',
		'reverse_dns',
		'decrypt_ip', 'encrypt_ip',
		'http_request',
		'uuid_from_friendly_id',
	]
	for fn_name in unimplemented {
		if src.contains('${fn_name}(') || src.contains('${fn_name}!(') {
			return true
		}
	}
	return false
}
