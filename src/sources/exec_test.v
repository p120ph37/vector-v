module sources

import event

fn test_new_exec_defaults() {
	s := new_exec({
		'command': 'echo hello'
	})!
	assert s.command == ['echo', 'hello']
	assert s.mode == .scheduled
	assert s.respawn_on_exit == true
	assert s.max_length == 102400
}

fn test_new_exec_missing_command() {
	new_exec(map[string]string{}) or {
		assert err.msg().contains('command is required')
		return
	}
	assert false, 'expected error for missing command'
}

fn test_new_exec_empty_command() {
	new_exec({
		'command': ''
	}) or {
		assert err.msg().contains('command is empty')
		return
	}
	assert false, 'expected error for empty command'
}

fn test_new_exec_streaming_mode() {
	s := new_exec({
		'command': 'tail -f /var/log/syslog'
		'mode':    'streaming'
	})!
	assert s.mode == .streaming
}

fn test_new_exec_custom_interval() {
	s := new_exec({
		'command':                       'date'
		'scheduled.exec_interval_secs': '30'
	})!
	assert s.exec_interval > 0
}

fn test_new_exec_no_respawn() {
	s := new_exec({
		'command':                     'echo test'
		'mode':                        'streaming'
		'streaming.respawn_on_exit':   'false'
	})!
	assert s.respawn_on_exit == false
}

fn test_new_exec_include_stderr() {
	s := new_exec({
		'command':        'ls -la'
		'include_stderr': 'true'
	})!
	assert s.include_stderr == true
}

fn test_exec_get_command() {
	s := new_exec({
		'command': 'ls -la /tmp'
	})!
	assert s.get_command() == 'ls -la /tmp'
}

fn test_exec_custom_max_length() {
	s := new_exec({
		'command':    'echo hello'
		'max_length': '50'
	})!
	assert s.max_length == 50
}

fn test_exec_run_once() {
	s := new_exec({
		'command': 'echo test_output_123'
		'mode':    'streaming'
		'streaming.respawn_on_exit': 'false'
	})!
	output := chan event.Event{cap: 100}
	s.exec_once(output)

	mut ev := event.Event(event.new_log(''))
	assert output.try_pop(mut ev) == .success, 'expected at least one event'
	log_ev := ev as event.LogEvent
	msg := log_ev.message()
	assert msg.contains('test_output_123')
	assert log_ev.meta.source_type == 'exec'
}

fn test_exec_multiline_output() {
	s := new_exec({
		'command': 'printf "line1\nline2\nline3"'
		'mode':    'streaming'
		'streaming.respawn_on_exit': 'false'
	})!
	output := chan event.Event{cap: 100}
	s.exec_once(output)

	mut count := 0
	for {
		mut ev := event.Event(event.new_log(''))
		if output.try_pop(mut ev) == .success {
			count++
		} else {
			break
		}
	}
	assert count == 3
}

fn test_new_exec_invalid_interval() {
	s := new_exec({
		'command':                       'date'
		'scheduled.exec_interval_secs': '-5'
	})!
	assert s.exec_interval > 0
}

fn test_new_exec_invalid_respawn_interval() {
	s := new_exec({
		'command':                           'date'
		'mode':                             'streaming'
		'streaming.respawn_interval_secs': '-5'
	})!
	assert s.respawn_interval > 0
}

fn test_new_exec_working_directory() {
	s := new_exec({
		'command':           'ls'
		'working_directory': '/tmp'
	})!
	assert s.working_dir == '/tmp'
}

fn test_new_exec_invalid_max_length() {
	s := new_exec({
		'command':    'echo hello'
		'max_length': '-1'
	})!
	assert s.max_length == 102400
}

fn test_exec_event_metadata() {
	s := new_exec({
		'command': 'echo metadata_test'
		'mode':    'streaming'
		'streaming.respawn_on_exit': 'false'
	})!
	output := chan event.Event{cap: 100}
	s.exec_once(output)

	mut ev := event.Event(event.new_log(''))
	assert output.try_pop(mut ev) == .success
	log_ev := ev as event.LogEvent
	assert log_ev.meta.source_type == 'exec'
	cmd_val := log_ev.get('command') or { panic('expected command field') }
	assert event.value_to_string(cmd_val) == 'echo metadata_test'
}

fn test_exec_run_streaming_no_respawn() {
	s := new_exec({
		'command':                   'echo done'
		'mode':                     'streaming'
		'streaming.respawn_on_exit': 'false'
	})!
	output := chan event.Event{cap: 100}
	s.run_streaming(output)
	// Should return after single execution since respawn_on_exit is false
	mut ev := event.Event(event.new_log(''))
	assert output.try_pop(mut ev) == .success
}
