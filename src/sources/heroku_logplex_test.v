module sources

fn test_parse_logplex_line_basic() {
	msg := parse_logplex_line('<190>1 2023-01-01T00:00:00+00:00 host heroku web.1 - State changed from starting to up')
	assert msg.priority == 190
	assert msg.version == 1
	assert msg.timestamp == '2023-01-01T00:00:00+00:00'
	assert msg.hostname == 'host'
	assert msg.app_name == 'heroku'
	assert msg.proc_id == 'web.1'
	assert msg.msg_id == '-'
	assert msg.message == 'State changed from starting to up'
}

fn test_parse_logplex_line_router() {
	msg := parse_logplex_line('<158>1 2023-06-15T12:34:56.789012+00:00 d.abc123 heroku router - at=info method=GET path="/" host=myapp.herokuapp.com fwd="1.2.3.4" dyno=web.1 connect=1ms service=5ms status=200 bytes=512')
	assert msg.priority == 158
	assert msg.version == 1
	assert msg.hostname == 'd.abc123'
	assert msg.app_name == 'heroku'
	assert msg.proc_id == 'router'
	assert msg.msg_id == '-'
	assert msg.message.contains('at=info')
	assert msg.message.contains('status=200')
}

fn test_parse_logplex_line_app_log() {
	msg := parse_logplex_line('<134>1 2023-06-15T12:00:00+00:00 d.host myapp web.2 - Starting process with command `bundle exec puma`')
	assert msg.priority == 134
	assert msg.app_name == 'myapp'
	assert msg.proc_id == 'web.2'
	assert msg.message == 'Starting process with command `bundle exec puma`'
}

fn test_parse_logplex_line_no_priority() {
	msg := parse_logplex_line('plain text message without syslog format')
	assert msg.message == 'plain text message without syslog format'
	assert msg.priority == -1
}

fn test_parse_logplex_line_empty_message() {
	msg := parse_logplex_line('<190>1 2023-01-01T00:00:00+00:00 host app proc -')
	assert msg.priority == 190
	assert msg.app_name == 'app'
	assert msg.proc_id == 'proc'
	assert msg.msg_id == '-'
	assert msg.message == ''
}

fn test_parse_logplex_line_different_priorities() {
	// Emergency (0) * 8 + local7 (23) = 184
	msg := parse_logplex_line('<184>1 2023-01-01T00:00:00Z host app web.1 - critical error')
	assert msg.priority == 184

	// Notice (5) * 8 + local0 (16) = 133
	msg2 := parse_logplex_line('<133>1 2023-01-01T00:00:00Z host app web.1 - notice msg')
	assert msg2.priority == 133
}

fn test_parse_logplex_line_nilvalue_fields() {
	// RFC 5424 uses "-" for nil values
	msg := parse_logplex_line('<190>1 - - - - - no structured data')
	assert msg.priority == 190
	assert msg.timestamp == '-'
	assert msg.hostname == '-'
	assert msg.app_name == '-'
	assert msg.proc_id == '-'
	assert msg.msg_id == '-'
	assert msg.message == 'no structured data'
}

fn test_parse_logplex_line_long_message() {
	long_body := 'a]'.repeat(500)
	line := '<190>1 2023-01-01T00:00:00Z host app web.1 - ${long_body}'
	msg := parse_logplex_line(line)
	assert msg.message == long_body
	assert msg.app_name == 'app'
}

fn test_new_heroku_logplex_defaults() {
	s := new_heroku_logplex(map[string]string{})
	assert s.address == '0.0.0.0:80'
	assert s.auth_token == ''
}

fn test_new_heroku_logplex_custom() {
	s := new_heroku_logplex({
		'address':    '127.0.0.1:8080'
		'auth.token': 'd.my-drain-token'
	})
	assert s.address == '127.0.0.1:8080'
	assert s.auth_token == 'd.my-drain-token'
}

fn test_new_heroku_logplex_partial_config() {
	s := new_heroku_logplex({
		'address': '0.0.0.0:3000'
	})
	assert s.address == '0.0.0.0:3000'
	assert s.auth_token == ''
}

fn test_parse_logplex_line_version_zero() {
	msg := parse_logplex_line('<190>0 2023-01-01T00:00:00Z host app web.1 - test')
	assert msg.version == 0
}

fn test_parse_logplex_line_multiword_message() {
	msg := parse_logplex_line('<134>1 2023-06-15T12:00:00Z host app worker.1 - Processing job id=123 type=email status=completed duration=1.5s')
	assert msg.proc_id == 'worker.1'
	assert msg.message.contains('Processing job')
	assert msg.message.contains('duration=1.5s')
}

fn test_heroku_logplex_source_registry() {
	s := build_source('heroku_logplex', map[string]string{}) or { panic(err.str()) }
	assert s is HerokuLogplexSource
}
