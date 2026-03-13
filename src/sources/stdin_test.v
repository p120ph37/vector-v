module sources

fn test_new_stdin_defaults() {
	s := new_stdin(map[string]string{})
	assert s.max_length == 102400
	assert s.host_key == 'host'
}

fn test_new_stdin_custom_max_length() {
	s := new_stdin({
		'max_length': '1024'
	})
	assert s.max_length == 1024
}

fn test_new_stdin_invalid_max_length_uses_default() {
	s := new_stdin({
		'max_length': '-1'
	})
	assert s.max_length == 102400
}

fn test_new_stdin_zero_max_length_uses_default() {
	s := new_stdin({
		'max_length': '0'
	})
	assert s.max_length == 102400
}
