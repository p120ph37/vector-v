module sources

fn test_new_file_descriptor_defaults() {
	s := new_file_descriptor(map[string]string{})
	assert s.fd == 0
	assert s.max_length == 102400
	assert s.host_key == 'host'
}

fn test_new_file_descriptor_custom_fd() {
	s := new_file_descriptor({
		'fd': '3'
	})
	assert s.fd == 3
}

fn test_new_file_descriptor_custom_max_length() {
	s := new_file_descriptor({
		'max_length': '500'
	})
	assert s.max_length == 500
}

fn test_new_file_descriptor_invalid_max_length() {
	s := new_file_descriptor({
		'max_length': '-1'
	})
	assert s.max_length == 102400
}

fn test_new_file_descriptor_negative_fd() {
	s := new_file_descriptor({
		'fd': '-1'
	})
	assert s.fd == 0
}

fn test_new_file_descriptor_custom_host_key() {
	s := new_file_descriptor({
		'host_key': 'hostname'
	})
	assert s.host_key == 'hostname'
}
