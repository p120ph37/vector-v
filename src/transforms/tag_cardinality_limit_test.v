module transforms

import event

fn test_tag_cardinality_within_limit() {
	mut t := new_tag_cardinality_limit({'value_limit': '3'})!

	for i in 0 .. 3 {
		m := event.Event(event.Metric{
			name: 'test'
			kind: .incremental
			value: event.MetricValue(event.CounterValue{value: 1.0})
			tags: {'host': 'server-${i}'}
		})
		result := t.transform(m)!
		assert result.len == 1, 'event ${i} should pass'
	}
	assert t.tag_value_count('host') == 3
}

fn test_tag_cardinality_drop_tag() {
	mut t := new_tag_cardinality_limit({
		'value_limit':           '2'
		'limit_exceeded_action': 'drop_tag'
	})!

	for i in 0 .. 2 {
		m := event.Event(event.Metric{
			name: 'test'
			kind: .incremental
			value: event.MetricValue(event.CounterValue{value: 1.0})
			tags: {'region': 'r${i}'}
		})
		t.transform(m)!
	}

	// Third distinct value exceeds limit — tag dropped
	m3 := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
		tags: {'region': 'r2'}
	})
	result3 := t.transform(m3)!
	assert result3.len == 1

	r := result3[0]
	match r {
		event.Metric { assert 'region' !in r.tags }
		else { assert false }
	}
}

fn test_tag_cardinality_drop_event() {
	mut t := new_tag_cardinality_limit({
		'value_limit':           '2'
		'limit_exceeded_action': 'drop_event'
	})!

	for i in 0 .. 2 {
		m := event.Event(event.Metric{
			name: 'test'
			kind: .incremental
			value: event.MetricValue(event.CounterValue{value: 1.0})
			tags: {'host': 'h${i}'}
		})
		t.transform(m)!
	}

	m3 := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
		tags: {'host': 'h2'}
	})
	result3 := t.transform(m3)!
	assert result3.len == 0, 'event should be dropped'
}

fn test_tag_cardinality_seen_values_pass() {
	mut t := new_tag_cardinality_limit({'value_limit': '2'})!

	for i in 0 .. 2 {
		m := event.Event(event.Metric{
			name: 'test'
			kind: .incremental
			value: event.MetricValue(event.CounterValue{value: 1.0})
			tags: {'env': 'e${i}'}
		})
		t.transform(m)!
	}

	// Repeat already-seen value
	m := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
		tags: {'env': 'e0'}
	})
	result := t.transform(m)!
	assert result.len == 1
}

fn test_tag_cardinality_multiple_tags() {
	mut t := new_tag_cardinality_limit({'value_limit': '2'})!

	m := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
		tags: {'host': 'server1', 'region': 'us-east'}
	})
	result := t.transform(m)!
	assert result.len == 1
	assert t.tag_value_count('host') == 1
	assert t.tag_value_count('region') == 1
}

fn test_tag_cardinality_no_tags_passthrough() {
	mut t := new_tag_cardinality_limit({'value_limit': '2'})!

	m := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	result := t.transform(m)!
	assert result.len == 1
}

fn test_tag_cardinality_non_metric_passthrough() {
	mut t := new_tag_cardinality_limit({'value_limit': '2'})!

	log := event.Event(event.new_log('hello'))
	result := t.transform(log)!
	assert result.len == 1
}

fn test_tag_cardinality_default_limit() {
	t := new_tag_cardinality_limit({})!
	assert t.value_limit == 500
}

fn test_tag_cardinality_invalid_limit_defaults() {
	t := new_tag_cardinality_limit({'value_limit': '0'})!
	assert t.value_limit == 500
}

fn test_tag_cardinality_default_action() {
	t := new_tag_cardinality_limit({})!
	assert t.action == .drop_tag
}

fn test_tag_cardinality_only_offending_tag_dropped() {
	mut t := new_tag_cardinality_limit({
		'value_limit':           '1'
		'limit_exceeded_action': 'drop_tag'
	})!

	m1 := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
		tags: {'host': 'server1', 'region': 'us-east'}
	})
	t.transform(m1)!

	m2 := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
		tags: {'host': 'server2', 'region': 'us-east'}
	})
	result := t.transform(m2)!
	assert result.len == 1

	r := result[0]
	match r {
		event.Metric {
			assert 'host' !in r.tags
			assert r.tags['region'] == 'us-east'
		}
		else { assert false }
	}
}

fn test_tag_cardinality_via_registry() {
	mut t := build_transform('tag_cardinality_limit', {'value_limit': '100'})!

	m := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
		tags: {'host': 'server1'}
	})
	result := apply_transform(mut t, m)!
	assert result.len == 1
}
