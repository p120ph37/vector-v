module vrl

// uses_unimplemented_fn checks if source code calls functions we haven't implemented yet.
fn uses_unimplemented_fn(src string) bool {
	unimplemented := [
		'sha1', 'sha2', 'sha3', 'md5', 'hmac', 'seahash', 'xxhash',
		'parse_common_log', 'parse_syslog', 'parse_regex', 'parse_key_value',
		'parse_grok', 'parse_groks', 'parse_csv', 'parse_logfmt', 'parse_xml',
		'parse_url', 'parse_query_string', 'parse_klog', 'parse_linux_authorization',
		'parse_nginx_log', 'parse_apache_log', 'parse_aws_alb_log',
		'parse_aws_cloudwatch_log_subscription_message', 'parse_aws_vpc_flow_log',
		'parse_cef', 'parse_user_agent', 'parse_etld', 'parse_float',
		'parse_duration', 'parse_bytes', 'parse_timestamp', 'parse_tokens',
		'parse_int', 'parse_regex_all', 'parse_ruby_hash', 'parse_glog',
		'match_datadog_query',
		'encode_base64', 'decode_base64', 'encode_base16', 'decode_base16',
		'encode_percent', 'decode_percent',
		'encode_punycode', 'decode_punycode',
		'encode_csv', 'encode_logfmt', 'encode_key_value',
		'encode_snappy', 'decode_snappy',
		'encode_zlib', 'decode_zlib',
		'encode_gzip', 'decode_gzip',
		'encode_zstd', 'decode_zstd',
		'encode_proto', 'decode_proto',
		'format_timestamp',
		'ip_aton', 'ip_ntoa', 'ip_cidr_contains', 'ip_subnet', 'ip_to_ipv6',
		'ipv6_to_ipv4', 'ip_version',
		'tally', 'tally_value',
		'redact', 'community_id', 'decrypt', 'encrypt',
		'tag_types_externally', 'get_hostname',
		'chunks', 'sieve',
		'remove', 'parse_proto',
		'random_bytes', 'random_int', 'random_float',
		'uuid_v7',
		'replace_with', 'strip_ansi_escape_codes',
		'to_syslog_facility', 'to_syslog_level', 'to_syslog_severity',
		'shannon_entropy',
		'encode_charset', 'decode_charset',
		'decode_mime_q',
		'crc32', 'murmur3',
		'mezmo_patterns',
		'punycode',
		'reverse_dns',
		'format_int',
		'unnest',
		'basename', 'dirname', 'split_path',
		'camelcase', 'kebabcase', 'pascalcase', 'screamingsnakecase', 'snakecase',
		'crc', 'decrypt_ip', 'encrypt_ip',
		'get_timezone_name', 'haversine', 'http_request',
		'is_empty', 'is_ipv4', 'is_ipv6', 'is_json', 'is_regex', 'is_timestamp',
		'match_array', 'object_from_array', 'parse_influxdb', 'parse_yaml',
		'random_bool', 'timestamp', 'to_syslog_facility_code',
		'uuid_from_friendly_id', 'zip',
	]
	for fn_name in unimplemented {
		if src.contains('${fn_name}(') || src.contains('${fn_name}!(') {
			return true
		}
	}
	return false
}
