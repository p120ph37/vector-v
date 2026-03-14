module event

import json

fn test_metric_event_to_json() {
	m := Metric{
		name: 'cpu_usage'
		kind: .absolute
		value: GaugeValue{value: 0.75}
	}
	ev := Event(m)
	json_str := ev.to_json_string()
	assert json_str.contains('cpu_usage')
	assert json_str.contains('0.75')
}

fn test_counter_metric_to_json() {
	m := new_counter('requests_total', 42.0, .incremental)
	ev := Event(m)
	json_str := ev.to_json_string()
	assert json_str.contains('requests_total')
	assert json_str.contains('42')
}

fn test_gauge_metric_to_json() {
	m := new_gauge('temperature', 23.5)
	ev := Event(m)
	json_str := ev.to_json_string()
	assert json_str.contains('temperature')
}

fn test_trace_event_to_json() {
	mut t := new_trace()
	t.set('trace_id', Value('abc123'))
	t.set('span_id', Value('def456'))
	t.set('service', Value('my-service'))
	ev := Event(t)
	json_str := ev.to_json_string()
	assert json_str.contains('abc123')
	assert json_str.contains('def456')
	assert json_str.contains('my-service')
}

fn test_trace_event_empty_to_json() {
	t := new_trace()
	ev := Event(t)
	json_str := ev.to_json_string()
	assert json_str == '{}'
}

fn test_trace_event_get_set() {
	mut t := new_trace()
	t.set('key', Value('value'))
	val := t.get('key') or { panic('expected value') }
	assert value_to_string(val) == 'value'
}

fn test_trace_event_get_missing() {
	t := new_trace()
	result := t.get('missing')
	assert result == none
}

fn test_value_to_string_float() {
	val := Value(Float(3.14))
	s := value_to_string(val)
	assert s.contains('3.14')
}

fn test_value_to_string_array() {
	arr := Value([]Value{})
	s := value_to_string(arr)
	assert s == '[]'
}

fn test_value_to_string_map() {
	m := Value(map[string]Value{})
	s := value_to_string(m)
	assert s == '{}'
}

fn test_new_log_metadata() {
	ev := new_log('test')
	assert ev.meta.ingest_timestamp.unix() > 0
}
