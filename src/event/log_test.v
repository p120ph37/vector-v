module event

fn test_new_log() {
	ev := new_log('hello world')
	assert ev.message() == 'hello world'
	assert ev.fields.len == 1
}

fn test_log_set_get() {
	mut ev := new_log('test')
	ev.set('level', Value('info'))
	val := ev.get('level') or { panic('expected value') }
	assert value_to_string(val) == 'info'
}

fn test_log_remove() {
	mut ev := new_log('test')
	ev.set('extra', Value('data'))
	assert ev.fields.len == 2
	ev.remove('extra')
	assert ev.fields.len == 1
}

fn test_log_get_missing() {
	ev := new_log('test')
	result := ev.get('nonexistent')
	assert result == none
}

fn test_log_to_json() {
	ev := new_log('hello')
	json_str := ev.to_json()
	assert json_str.contains('"message"')
	assert json_str.contains('hello')
}

fn test_value_to_string_types() {
	assert value_to_string(Value('hello')) == 'hello'
	assert value_to_string(Value(42)) == '42'
	assert value_to_string(Value(true)) == 'true'
	assert value_to_string(Value(false)) == 'false'
}
