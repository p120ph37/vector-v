module sinks

fn test_new_socket_sink_tcp_defaults() {
	s := new_socket_sink({
		'address': '127.0.0.1:9000'
	})!
	assert s.mode == .tcp
	assert s.address == '127.0.0.1:9000'
	assert s.codec == .json_codec
	assert s.connected == false
}

fn test_new_socket_sink_udp() {
	s := new_socket_sink({
		'address': '127.0.0.1:5514'
		'mode':    'udp'
	})!
	assert s.mode == .udp
}

fn test_new_socket_sink_missing_address() {
	new_socket_sink(map[string]string{}) or {
		assert err.msg().contains('address is required')
		return
	}
	assert false, 'expected error for missing address'
}

fn test_new_socket_sink_text_codec() {
	s := new_socket_sink({
		'address':        '127.0.0.1:9000'
		'encoding.codec': 'text'
	})!
	assert s.codec == .text_codec
}

fn test_socket_sink_not_connected() {
	s := new_socket_sink({
		'address': '127.0.0.1:9000'
	})!
	assert s.connected == false
}

fn test_new_socket_sink_default_tcp() {
	s := new_socket_sink({
		'address': '127.0.0.1:9000'
		'mode':    'tcp'
	})!
	assert s.mode == .tcp
}
