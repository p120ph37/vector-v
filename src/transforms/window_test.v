module transforms

import event
import time

fn test_window_accumulates_events() {
	mut t := new_window({
		'window_ms': '999999' // large window to prevent auto-flush
	})!

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('msg ${i}'))
		result := t.transform(ev)!
		assert result.len == 0, 'events should be accumulated, not emitted'
	}

	// Flush all
	result := t.flush_all()
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert json_str.contains('5 events')
}

fn test_window_group_by() {
	mut t := new_window({
		'window_ms': '999999'
		'group_by':  'host'
	})!

	mut log1 := event.new_log('msg1')
	log1.set('host', event.Value('a'))
	mut log2 := event.new_log('msg2')
	log2.set('host', event.Value('b'))
	mut log3 := event.new_log('msg3')
	log3.set('host', event.Value('a'))

	t.transform(event.Event(log1))!
	t.transform(event.Event(log2))!
	t.transform(event.Event(log3))!

	result := t.flush_all()
	assert result.len == 2 // two groups: a, b
}

fn test_window_flush_all_clears() {
	mut t := new_window({
		'window_ms': '999999'
	})!

	ev := event.Event(event.new_log('msg'))
	t.transform(ev)!

	r1 := t.flush_all()
	assert r1.len == 1

	r2 := t.flush_all()
	assert r2.len == 0
}

fn test_window_non_log_passthrough() {
	mut t := new_window({
		'window_ms': '999999'
	})!

	metric := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.5})
	})
	result := t.transform(metric)!
	assert result.len == 1 // metrics pass through
}

fn test_window_custom_merge_into() {
	mut t := new_window({
		'window_ms':  '999999'
		'merge_into': 'logs'
	})!

	ev := event.Event(event.new_log('test'))
	t.transform(ev)!

	result := t.flush_all()
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert json_str.contains('"logs"')
}

fn test_window_default_config() {
	t := new_window({})!
	assert t.window_ms == 5000
	assert t.merge_into == 'events'
	assert t.group_by.len == 0
}

fn test_window_invalid_ms_defaults() {
	t := new_window({
		'window_ms': '-5'
	})!
	assert t.window_ms == 5000
}

fn test_window_events_field_contains_data() {
	mut t := new_window({
		'window_ms': '999999'
	})!

	mut log := event.new_log('hello')
	log.set('level', event.Value('info'))
	t.transform(event.Event(log))!

	result := t.flush_all()
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert json_str.contains('"events"')
	assert json_str.contains('hello')
	assert json_str.contains('info')
}

fn test_window_group_by_preserves_group_field() {
	mut t := new_window({
		'window_ms': '999999'
		'group_by':  'service'
	})!

	mut log := event.new_log('test')
	log.set('service', event.Value('web'))
	t.transform(event.Event(log))!

	result := t.flush_all()
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert json_str.contains('web')
}

fn test_window_message_field() {
	mut t := new_window({
		'window_ms': '999999'
	})!

	for _ in 0 .. 3 {
		ev := event.Event(event.new_log('test'))
		t.transform(ev)!
	}

	result := t.flush_all()
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert json_str.contains('3 events')
}

fn test_window_window_start_field() {
	mut t := new_window({
		'window_ms': '999999'
	})!

	ev := event.Event(event.new_log('test'))
	t.transform(ev)!

	result := t.flush_all()
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert json_str.contains('window_start')
}

fn test_window_via_registry() {
	mut t := build_transform('window', {
		'window_ms': '999999'
	})!

	ev := event.Event(event.new_log('test'))
	result := apply_transform(mut t, ev)!
	assert result.len == 0 // accumulated
}

fn test_window_multiple_group_by_fields() {
	mut t := new_window({
		'window_ms': '999999'
		'group_by':  'host,service'
	})!

	mut log1 := event.new_log('m1')
	log1.set('host', event.Value('a'))
	log1.set('service', event.Value('web'))
	mut log2 := event.new_log('m2')
	log2.set('host', event.Value('a'))
	log2.set('service', event.Value('api'))
	mut log3 := event.new_log('m3')
	log3.set('host', event.Value('a'))
	log3.set('service', event.Value('web'))

	t.transform(event.Event(log1))!
	t.transform(event.Event(log2))!
	t.transform(event.Event(log3))!

	result := t.flush_all()
	assert result.len == 2 // (a,web) and (a,api)
}
