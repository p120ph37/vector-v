module sources

fn test_new_demo_logs_defaults() {
	s := new_demo_logs(map[string]string{})
	assert s.format == 'text'
	assert s.count == 10
	assert s.interval == 1.0
}

fn test_new_demo_logs_custom_format() {
	s := new_demo_logs({
		'format': 'json'
	})
	assert s.format == 'json'
}

fn test_new_demo_logs_syslog_format() {
	s := new_demo_logs({
		'format': 'syslog'
	})
	assert s.format == 'syslog'
}

fn test_new_demo_logs_custom_count() {
	s := new_demo_logs({
		'count': '5'
	})
	assert s.count == 5
}

fn test_new_demo_logs_invalid_count_uses_default() {
	s := new_demo_logs({
		'count': '-1'
	})
	assert s.count == 10
}

fn test_new_demo_logs_zero_count_uses_default() {
	s := new_demo_logs({
		'count': '0'
	})
	assert s.count == 10
}

fn test_new_demo_logs_custom_interval() {
	s := new_demo_logs({
		'interval': '0.5'
	})
	assert s.interval == 0.5
}

fn test_new_demo_logs_invalid_interval_uses_default() {
	s := new_demo_logs({
		'interval': '-1'
	})
	assert s.interval == 1.0
}

fn test_new_demo_logs_all_options() {
	s := new_demo_logs({
		'format':   'json'
		'count':    '3'
		'interval': '2.5'
	})
	assert s.format == 'json'
	assert s.count == 3
	assert s.interval == 2.5
}
