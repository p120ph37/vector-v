module sources

import event

fn test_new_vector_source_defaults() {
	s := new_vector_source(map[string]string{})
	assert s.address == '0.0.0.0:6000'
	assert s.max_length == 1048576
}

fn test_new_vector_source_custom_address() {
	s := new_vector_source({
		'address': '127.0.0.1:9000'
	})
	assert s.address == '127.0.0.1:9000'
}

fn test_new_vector_source_custom_max_length() {
	s := new_vector_source({
		'max_length': '65536'
	})
	assert s.max_length == 65536
}

fn test_new_vector_source_invalid_max_length() {
	s := new_vector_source({
		'max_length': '-1'
	})
	assert s.max_length == 1048576
}

fn test_parse_vector_event_simple() {
	ev := parse_vector_event('hello world', '127.0.0.1:5000')
	match ev {
		event.LogEvent {
			assert ev.message() == 'hello world'
			assert ev.meta.source_type == 'vector'
			val := ev.get('source_peer') or { panic('expected source_peer') }
			assert event.value_to_string(val) == '127.0.0.1:5000'
		}
		else {
			assert false, 'expected LogEvent'
		}
	}
}

fn test_parse_vector_event_json() {
	json_line := '{"message":"test","level":"info"}'
	ev := parse_vector_event(json_line, '10.0.0.1:6000')
	match ev {
		event.LogEvent {
			assert ev.message() == json_line
		}
		else {
			assert false, 'expected LogEvent'
		}
	}
}
