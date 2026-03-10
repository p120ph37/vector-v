module event

fn test_event_log_to_json() {
	ev := Event(new_log('hello'))
	json_str := ev.to_json_string()
	assert json_str.contains('hello')
}

fn test_event_wraps_log() {
	log := new_log('test')
	ev := Event(log)
	match ev {
		LogEvent {
			assert ev.message() == 'test'
		}
		else {
			assert false
		}
	}
}
