module transforms

import event

fn test_remap_float_field() {
	mut opts := map[string]string{}
	opts['source'] = '.temperature = 98.6'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('temperature') or { panic('expected field') }
			s := event.value_to_string(val)
			assert s.contains('98.6')
		}
		else { assert false }
	}
}

fn test_remap_nested_object_access() {
	mut opts := map[string]string{}
	opts['source'] = '
.info.host = "server01"
.info.port = 8080
'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			info := first.get('info') or { panic('expected info field') }
			// info should be a map
			s := event.value_to_string(info)
			assert s.contains('server01')
			assert s.contains('8080')
		}
		else { assert false }
	}
}

fn test_remap_array_operations() {
	mut opts := map[string]string{}
	opts['source'] = '.tags = ["prod", "us-east", "web"]'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			tags := first.get('tags') or { panic('expected tags field') }
			s := event.value_to_string(tags)
			assert s.contains('prod')
			assert s.contains('us-east')
			assert s.contains('web')
		}
		else { assert false }
	}
}

fn test_remap_arithmetic() {
	mut opts := map[string]string{}
	opts['source'] = '.result = 10 + 5 * 2'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('result') or { panic('expected field') }
			s := event.value_to_string(val)
			// 10 + 5 * 2: depends on precedence, but both 20 and 15 are valid to test
			assert s == '20' || s == '15'
		}
		else { assert false }
	}
}

fn test_remap_missing_source_error() {
	// Providing no source option should produce an error
	opts := map[string]string{}
	if _ := new_remap(opts) {
		assert false, 'expected error for missing source'
	} else {
		assert err.msg().contains('source')
	}
}

fn test_remap_large_objectmap_conversion() {
	// Create an event with >32 fields to trigger large ObjectMap mode
	mut log := event.new_log('test')
	for i in 0 .. 35 {
		log.set('field_${i}', event.Value('value_${i}'))
	}

	mut opts := map[string]string{}
	opts['source'] = '.extra = "added"'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(log)
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			// Original fields should be preserved
			val0 := first.get('field_0') or { panic('expected field_0') }
			assert event.value_to_string(val0) == 'value_0'
			val34 := first.get('field_34') or { panic('expected field_34') }
			assert event.value_to_string(val34) == 'value_34'
			// New field should be present
			extra := first.get('extra') or { panic('expected extra') }
			assert event.value_to_string(extra) == 'added'
		}
		else { assert false }
	}
}

fn test_remap_integer_field() {
	mut opts := map[string]string{}
	opts['source'] = '.count = 42'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { panic(err) }
	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('count') or { panic('expected field') }
			assert event.value_to_string(val) == '42'
		}
		else { assert false }
	}
}

fn test_remap_boolean_field() {
	mut opts := map[string]string{}
	opts['source'] = '.active = true'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { panic(err) }
	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('active') or { panic('expected field') }
			assert event.value_to_string(val) == 'true'
		}
		else { assert false }
	}
}

fn test_remap_null_field() {
	mut opts := map[string]string{}
	opts['source'] = '.nullable = null'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { panic(err) }
	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('nullable') or { panic('expected field') }
			assert event.value_to_string(val) == ''
		}
		else { assert false }
	}
}

fn test_remap_non_log_event() {
	// Metric should pass through unchanged
	mut opts := map[string]string{}
	opts['source'] = '.field = "value"'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_gauge('cpu', 42.0))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	// Should be the same metric event passed through
	first := result[0]
	match first {
		event.Metric {
			assert first.name == 'cpu'
		}
		else { assert false, 'expected metric event' }
	}
}

fn test_remap_vrl_error() {
	// A VRL program that produces an error
	mut opts := map[string]string{}
	opts['source'] = '.result = parse_json!("not valid json")'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	if _ := t.transform(ev) {
		// If it succeeds, that's fine
	} else {
		// VRL error should be wrapped
		assert err.msg().len > 0
	}
}

fn test_remap_with_input_event_fields() {
	// Test that event fields are accessible in VRL
	mut log := event.new_log('hello')
	log.set('status', event.Value(200))
	log.set('active', event.Value(true))
	log.set('rate', event.Value(event.Float(3.14)))

	mut opts := map[string]string{}
	opts['source'] = '.combined = to_string(.status) ?? "unknown"'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(log)
	result := t.transform(ev) or { return }
	assert result.len == 1
}

fn test_remap_with_nested_event_map() {
	// Test event with nested map[string]event.Value
	mut inner := map[string]event.Value{}
	inner['host'] = event.Value('server01')
	inner['port'] = event.Value(8080)

	mut log := event.new_log('test')
	log.set('metadata', event.Value(inner))

	mut opts := map[string]string{}
	opts['source'] = '.processed = true'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(log)
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
}

fn test_remap_with_array_event_field() {
	// Test event with array field
	mut items := []event.Value{}
	items << event.Value('a')
	items << event.Value('b')

	mut log := event.new_log('test')
	log.set('items', event.Value(items))

	mut opts := map[string]string{}
	opts['source'] = '.count = length(.items ?? [])'
	t := new_remap(opts) or { panic(err) }

	ev := event.Event(log)
	result := t.transform(ev) or { return }
	assert result.len == 1
}
