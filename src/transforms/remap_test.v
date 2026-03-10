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

fn test_remap_string_concat() {
	mut opts := map[string]string{}
	opts['source'] = '.greeting = "hello" + " " + "world"'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { panic(err) }
	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('greeting') or { panic('expected field') }
			assert event.value_to_string(val) == 'hello world'
		}
		else { assert false }
	}
}

fn test_remap_conditional() {
	mut opts := map[string]string{}
	opts['source'] = '
if .message == "error" {
	.level = "error"
} else {
	.level = "info"
}
'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('error'))
	result := t.transform(ev) or { panic(err) }
	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('level') or { panic('expected field') }
			assert event.value_to_string(val) == 'error'
		}
		else { assert false }
	}

	ev2 := event.Event(event.new_log('hello'))
	result2 := t.transform(ev2) or { panic(err) }
	first2 := result2[0]
	match first2 {
		event.LogEvent {
			val := first2.get('level') or { panic('expected field') }
			assert event.value_to_string(val) == 'info'
		}
		else { assert false }
	}
}

fn test_remap_downcase() {
	mut opts := map[string]string{}
	opts['source'] = '.message = downcase(.message)'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('HELLO WORLD'))
	result := t.transform(ev) or { panic(err) }
	first := result[0]
	match first {
		event.LogEvent {
			assert first.message() == 'hello world'
		}
		else { assert false }
	}
}

fn test_remap_multiline() {
	mut opts := map[string]string{}
	opts['source'] = '
.env = "prod"
.host = "server01"
del(.message)
'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { panic(err) }
	first := result[0]
	match first {
		event.LogEvent {
			env := first.get('env') or { panic('expected env') }
			assert event.value_to_string(env) == 'prod'
			host := first.get('host') or { panic('expected host') }
			assert event.value_to_string(host) == 'server01'
			if _ := first.get('message') {
				assert false, 'message should have been deleted'
			}
		}
		else { assert false }
	}
}

fn test_remap_contains_check() {
	mut opts := map[string]string{}
	opts['source'] = '
if contains(.message, "error") {
	.is_error = true
} else {
	.is_error = false
}
'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('an error occurred'))
	result := t.transform(ev) or { panic(err) }
	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('is_error') or { panic('expected field') }
			assert event.value_to_string(val) == 'true'
		}
		else { assert false }
	}
}

fn test_remap_pass_through_non_log() {
	mut opts := map[string]string{}
	opts['source'] = '.foo = "bar"'
	t := new_remap(opts) or { panic(err) }

	// Metric events should pass through unchanged
	ev := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.5})
	})
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
}
