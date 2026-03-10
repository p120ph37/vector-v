module transforms

import event

fn test_remap_set_field() {
	mut opts := map[string]string{}
	opts['source'] = '.environment = "production"'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('hello'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('environment') or { panic('expected field') }
			assert event.value_to_string(val) == 'production'
			assert first.message() == 'hello'
		}
		else {
			assert false
		}
	}
}

fn test_remap_delete_field() {
	mut opts := map[string]string{}
	opts['source'] = 'del(.host)'
	t := new_remap(opts) or { panic(err) }

	mut log := event.new_log('hello')
	log.set('host', event.Value('myhost'))

	ev := event.Event(log)
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			if _ := first.get('host') {
				assert false, 'host field should have been deleted'
			}
			assert first.message() == 'hello'
		}
		else {
			assert false
		}
	}
}

fn test_remap_copy_field() {
	mut opts := map[string]string{}
	opts['source'] = '.msg_copy = .message'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('hello'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('msg_copy') or { panic('expected field') }
			assert event.value_to_string(val) == 'hello'
		}
		else {
			assert false
		}
	}
}

fn test_remap_requires_source() {
	opts := map[string]string{}
	if _ := new_remap(opts) {
		assert false, 'expected error for missing source'
	}
}
