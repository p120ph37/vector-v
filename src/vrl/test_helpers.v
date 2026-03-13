module vrl

// uses_unimplemented_fn checks if source code calls functions we haven't implemented yet.
fn uses_unimplemented_fn(src string) bool {
	unimplemented := [
		// Codec (require external libs)
		'encode_charset', 'decode_charset',
		// Other unimplemented
		'community_id',
		'murmur3',
		'mezmo_patterns',
		'reverse_dns',
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
