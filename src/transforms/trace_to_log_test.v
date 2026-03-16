module transforms

import event

fn test_trace_to_log_basic() {
	t := new_trace_to_log(map[string]string{}) or { panic(err) }

	mut trace := event.new_trace()
	trace.set('trace_id', event.Value('abc123'))
	trace.set('span_id', event.Value('span-1'))
	trace.set('service', event.Value('web'))
	ev := event.Event(trace)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	if result[0] is event.LogEvent {
		le := result[0] as event.LogEvent
		assert le.meta.source_type == 'trace'
		tid := le.get('trace_id') or { panic('expected trace_id') }
		assert event.value_to_string(tid) == 'abc123'
		sid := le.get('span_id') or { panic('expected span_id') }
		assert event.value_to_string(sid) == 'span-1'
		svc := le.get('service') or { panic('expected service') }
		assert event.value_to_string(svc) == 'web'
	} else {
		assert false, 'expected LogEvent'
	}
}

fn test_trace_to_log_with_fields_filter() {
	t := new_trace_to_log({
		'fields': 'trace_id,service'
	}) or { panic(err) }

	mut trace := event.new_trace()
	trace.set('trace_id', event.Value('abc123'))
	trace.set('span_id', event.Value('span-1'))
	trace.set('service', event.Value('web'))
	ev := event.Event(trace)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	if result[0] is event.LogEvent {
		le := result[0] as event.LogEvent
		// Only trace_id and service should be included
		tid := le.get('trace_id') or { panic('expected trace_id') }
		assert event.value_to_string(tid) == 'abc123'
		svc := le.get('service') or { panic('expected service') }
		assert event.value_to_string(svc) == 'web'
		// span_id should NOT be included (only 2 fields)
		assert le.fields.len == 2
	} else {
		assert false, 'expected LogEvent'
	}
}

fn test_trace_to_log_empty_trace() {
	t := new_trace_to_log(map[string]string{}) or { panic(err) }

	trace := event.new_trace()
	ev := event.Event(trace)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	if result[0] is event.LogEvent {
		le := result[0] as event.LogEvent
		assert le.meta.source_type == 'trace'
		assert le.fields.len == 0
	} else {
		assert false, 'expected LogEvent'
	}
}

fn test_trace_to_log_source_type_metadata() {
	t := new_trace_to_log(map[string]string{}) or { panic(err) }

	mut trace := event.new_trace()
	trace.set('service', event.Value('api'))
	ev := event.Event(trace)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	if result[0] is event.LogEvent {
		le := result[0] as event.LogEvent
		assert le.meta.source_type == 'trace'
	} else {
		assert false, 'expected LogEvent'
	}
}

fn test_trace_to_log_passthrough_log_event() {
	t := new_trace_to_log(map[string]string{}) or { panic(err) }

	log := event.new_log('hello log')
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	if result[0] is event.LogEvent {
		le := result[0] as event.LogEvent
		assert le.message() == 'hello log'
	} else {
		assert false, 'expected LogEvent passthrough'
	}
}

fn test_trace_to_log_passthrough_metric() {
	t := new_trace_to_log(map[string]string{}) or { panic(err) }

	ev := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.5})
	})

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1, 'metric should pass through unchanged'
}

fn test_trace_to_log_fields_filter_missing_field() {
	t := new_trace_to_log({
		'fields': 'trace_id,nonexistent'
	}) or { panic(err) }

	mut trace := event.new_trace()
	trace.set('trace_id', event.Value('abc'))
	ev := event.Event(trace)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	if result[0] is event.LogEvent {
		le := result[0] as event.LogEvent
		tid := le.get('trace_id') or { panic('expected trace_id') }
		assert event.value_to_string(tid) == 'abc'
		// nonexistent field should just be absent — only trace_id included
		assert le.fields.len == 1
	} else {
		assert false, 'expected LogEvent'
	}
}

fn test_trace_to_log_fields_whitespace_handling() {
	t := new_trace_to_log({
		'fields': '  trace_id , span_id  '
	}) or { panic(err) }

	assert t.fields.len == 2
	assert t.fields[0] == 'trace_id'
	assert t.fields[1] == 'span_id'
}

fn test_trace_to_log_empty_fields_string() {
	t := new_trace_to_log({
		'fields': ''
	}) or { panic(err) }

	// Empty fields string means include all
	assert t.fields.len == 0
}

fn test_trace_to_log_upstream_metadata_carried() {
	t := new_trace_to_log(map[string]string{}) or { panic(err) }

	mut trace := event.new_trace()
	trace.set('service', event.Value('web'))
	trace.meta.upstream['_source'] = event.Value('otlp')
	ev := event.Event(trace)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	if result[0] is event.LogEvent {
		le := result[0] as event.LogEvent
		src := le.meta.upstream['_source'] or { panic('expected _source') }
		assert event.value_to_string(src) == 'otlp'
	} else {
		assert false, 'expected LogEvent'
	}
}

fn test_trace_to_log_no_opts() {
	t := new_trace_to_log(map[string]string{}) or { panic(err) }
	assert t.fields.len == 0
}
