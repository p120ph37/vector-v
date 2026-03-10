module event

fn test_new_trace() {
	t := new_trace()
	assert t.fields.len == 0
}

fn test_trace_set_get() {
	mut t := new_trace()
	t.set('trace_id', Value('abc123'))
	t.set('span_id', Value('def456'))
	t.set('duration_ms', Value(42))

	trace_id := t.get('trace_id') or { panic('expected value') }
	assert value_to_string(trace_id) == 'abc123'

	span_id := t.get('span_id') or { panic('expected value') }
	assert value_to_string(span_id) == 'def456'
}

fn test_trace_get_missing() {
	t := new_trace()
	result := t.get('nonexistent')
	assert result == none
}

fn test_trace_as_event() {
	mut t := new_trace()
	t.set('service', Value('web'))

	ev := Event(t)
	match ev {
		TraceEvent {
			val := ev.get('service') or { panic('expected value') }
			assert value_to_string(val) == 'web'
		}
		else {
			assert false, 'expected TraceEvent'
		}
	}
}
