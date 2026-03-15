module sources

fn test_new_socket_defaults() {
	s := new_socket(map[string]string{})
	assert s.mode == .tcp
	assert s.address == '0.0.0.0:9000'
	assert s.max_length == 102400
	assert s.host_key == 'host'
}

fn test_new_socket_tcp() {
	s := new_socket({
		'mode':    'tcp'
		'address': '127.0.0.1:5000'
	})
	assert s.mode == .tcp
	assert s.address == '127.0.0.1:5000'
}

fn test_new_socket_udp() {
	s := new_socket({
		'mode':    'udp'
		'address': '0.0.0.0:5514'
	})
	assert s.mode == .udp
	assert s.address == '0.0.0.0:5514'
}

fn test_new_socket_custom_max_length() {
	s := new_socket({
		'max_length': '8192'
	})
	assert s.max_length == 8192
}

fn test_new_socket_invalid_max_length() {
	s := new_socket({
		'max_length': '-1'
	})
	assert s.max_length == 102400
}

fn test_new_socket_custom_host_key() {
	s := new_socket({
		'host_key': 'remote_host'
	})
	assert s.host_key == 'remote_host'
}
