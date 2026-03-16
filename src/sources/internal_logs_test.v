module sources

import event
import os
import time

fn test_new_internal_logs_defaults() {
	s := new_internal_logs({})
	assert s.host_key == 'host'
	assert s.pid_key == 'pid'
}

fn test_new_internal_logs_custom_keys() {
	s := new_internal_logs({
		'host_key': 'hostname'
		'pid_key':  'process_id'
	})
	assert s.host_key == 'hostname'
	assert s.pid_key == 'process_id'
}

fn test_parse_internal_log_message_full() {
	level, module_name, target, message := parse_internal_log_message('info|topology|vector::topology|Pipeline started')
	assert level == 'info'
	assert module_name == 'topology'
	assert target == 'vector::topology'
	assert message == 'Pipeline started'
}

fn test_parse_internal_log_message_with_pipes_in_message() {
	level, module_name, target, message := parse_internal_log_message('warn|source|vector::source|message|with|pipes')
	assert level == 'warn'
	assert module_name == 'source'
	assert target == 'vector::source'
	assert message == 'message|with|pipes'
}

fn test_parse_internal_log_message_plain_text() {
	level, module_name, target, message := parse_internal_log_message('just a plain message')
	assert level == 'just a plain message'
	assert module_name == ''
	assert target == ''
	assert message == 'just a plain message'
}

fn test_build_event_has_message() {
	s := new_internal_logs({})
	ev := s.build_event('info|mymod|mytarget|Hello world', 'testhost', 1234)
	assert ev.message() == 'Hello world'
}

fn test_build_event_has_source_type() {
	s := new_internal_logs({})
	ev := s.build_event('info|mymod|mytarget|test msg', 'testhost', 1234)
	assert ev.meta.source_type == 'internal_logs'
}

fn test_build_event_has_host() {
	s := new_internal_logs({})
	ev := s.build_event('info|mymod|mytarget|test msg', 'myhost', 1234)
	host_val := ev.get('host') or {
		assert false, 'expected host field'
		return
	}
	match host_val {
		string {
			assert host_val == 'myhost'
		}
		else {
			assert false, 'expected string host'
		}
	}
}

fn test_build_event_has_pid() {
	s := new_internal_logs({})
	ev := s.build_event('info|mymod|mytarget|test msg', 'testhost', 42)
	pid_val := ev.get('pid') or {
		assert false, 'expected pid field'
		return
	}
	match pid_val {
		int {
			assert pid_val == 42
		}
		else {
			assert false, 'expected int pid'
		}
	}
}

fn test_build_event_has_metadata_map() {
	s := new_internal_logs({})
	ev := s.build_event('error|vrl|vector::vrl|parse failed', 'h', 1)
	meta_val := ev.get('metadata') or {
		assert false, 'expected metadata field'
		return
	}
	match meta_val {
		map[string]event.Value {
			level := meta_val['level'] or {
				assert false, 'expected level in metadata'
				return
			}
			match level {
				string { assert level == 'error' }
				else { assert false, 'expected string level' }
			}

			mod_val := meta_val['module'] or {
				assert false, 'expected module in metadata'
				return
			}
			match mod_val {
				string { assert mod_val == 'vrl' }
				else { assert false, 'expected string module' }
			}

			target_val := meta_val['target'] or {
				assert false, 'expected target in metadata'
				return
			}
			match target_val {
				string { assert target_val == 'vector::vrl' }
				else { assert false, 'expected string target' }
			}
		}
		else {
			assert false, 'expected map metadata'
		}
	}
}

fn test_build_event_has_timestamp() {
	s := new_internal_logs({})
	before := time.now()
	ev := s.build_event('info|m|t|msg', 'h', 1)
	ts_val := ev.get('timestamp') or {
		assert false, 'expected timestamp field'
		return
	}
	match ts_val {
		time.Time {
			// timestamp should be recent
			assert ts_val.unix_milli() >= before.unix_milli()
		}
		else {
			assert false, 'expected Time timestamp'
		}
	}
}

fn test_build_event_custom_host_key() {
	s := new_internal_logs({
		'host_key': 'hostname'
	})
	ev := s.build_event('info|m|t|msg', 'myhost', 1)
	// Should use custom key
	host_val := ev.get('hostname') or {
		assert false, 'expected hostname field'
		return
	}
	match host_val {
		string {
			assert host_val == 'myhost'
		}
		else {
			assert false, 'expected string'
		}
	}
}

fn test_build_event_custom_pid_key() {
	s := new_internal_logs({
		'pid_key': 'process_id'
	})
	ev := s.build_event('info|m|t|msg', 'h', 99)
	pid_val := ev.get('process_id') or {
		assert false, 'expected process_id field'
		return
	}
	match pid_val {
		int {
			assert pid_val == 99
		}
		else {
			assert false, 'expected int'
		}
	}
}

fn test_build_event_all_levels() {
	s := new_internal_logs({})
	for level in ['trace', 'debug', 'info', 'warn', 'error'] {
		ev := s.build_event('${level}|m|t|msg', 'h', 1)
		meta_val := ev.get('metadata') or { continue }
		match meta_val {
			map[string]event.Value {
				l := meta_val['level'] or { continue }
				match l {
					string { assert l == level }
					else { assert false, 'expected string level' }
				}
			}
			else {}
		}
	}
}

fn test_emit_internal_log_and_consume() {
	// Drain any existing messages from the channel first
	for {
		mut dummy := ''
		if internal_log_chan.try_pop(mut dummy) != .success {
			break
		}
	}

	emit_internal_log('info', 'test_module', 'test_target', 'hello from test')

	mut msg := ''
	result := internal_log_chan.try_pop(mut msg)
	assert result == .success
	assert msg == 'info|test_module|test_target|hello from test'
}
