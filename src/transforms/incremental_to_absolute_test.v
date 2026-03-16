module transforms

import event

fn test_incremental_to_absolute_counter_basic() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	m := event.Event(event.Metric{
		name: 'requests'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 5.0})
	})

	result := t.transform(m) or { panic(err) }
	assert result.len == 1
	if result[0] is event.Metric {
		metric := result[0] as event.Metric
		assert metric.kind == .absolute
		assert metric.name == 'requests'
		if metric.value is event.CounterValue {
			cv := metric.value as event.CounterValue
			assert cv.value == 5.0
		} else {
			assert false, 'expected CounterValue'
		}
	} else {
		assert false, 'expected Metric'
	}
}

fn test_incremental_to_absolute_counter_accumulates() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	for _ in 0 .. 3 {
		m := event.Event(event.Metric{
			name: 'requests'
			kind: .incremental
			value: event.MetricValue(event.CounterValue{value: 10.0})
		})
		t.transform(m) or { panic(err) }
	}

	assert t.state_counter('requests') == 30.0
}

fn test_incremental_to_absolute_counter_multiple_metrics() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	m1 := event.Event(event.Metric{
		name: 'requests'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 5.0})
	})
	m2 := event.Event(event.Metric{
		name: 'errors'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	m3 := event.Event(event.Metric{
		name: 'requests'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 3.0})
	})

	t.transform(m1) or { panic(err) }
	t.transform(m2) or { panic(err) }
	t.transform(m3) or { panic(err) }

	assert t.state_counter('requests') == 8.0
	assert t.state_counter('errors') == 1.0
}

fn test_incremental_to_absolute_gauge() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	m := event.Event(event.Metric{
		name: 'temperature'
		kind: .incremental
		value: event.MetricValue(event.GaugeValue{value: 72.5})
	})

	result := t.transform(m) or { panic(err) }
	assert result.len == 1
	if result[0] is event.Metric {
		metric := result[0] as event.Metric
		assert metric.kind == .absolute
		if metric.value is event.GaugeValue {
			gv := metric.value as event.GaugeValue
			assert gv.value == 72.5
		} else {
			assert false, 'expected GaugeValue'
		}
	} else {
		assert false, 'expected Metric'
	}
}

fn test_incremental_to_absolute_gauge_latest_wins() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	m1 := event.Event(event.Metric{
		name: 'temperature'
		kind: .incremental
		value: event.MetricValue(event.GaugeValue{value: 72.5})
	})
	m2 := event.Event(event.Metric{
		name: 'temperature'
		kind: .incremental
		value: event.MetricValue(event.GaugeValue{value: 80.0})
	})

	t.transform(m1) or { panic(err) }
	t.transform(m2) or { panic(err) }

	assert t.state_gauge('temperature') == 80.0
}

fn test_incremental_to_absolute_set_union() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	m1 := event.Event(event.Metric{
		name: 'users'
		kind: .incremental
		value: event.MetricValue(event.SetValue{values: ['alice', 'bob']})
	})
	m2 := event.Event(event.Metric{
		name: 'users'
		kind: .incremental
		value: event.MetricValue(event.SetValue{values: ['bob', 'charlie']})
	})

	t.transform(m1) or { panic(err) }
	result := t.transform(m2) or { panic(err) }

	assert result.len == 1
	if result[0] is event.Metric {
		metric := result[0] as event.Metric
		assert metric.kind == .absolute
		if metric.value is event.SetValue {
			sv := metric.value as event.SetValue
			assert sv.values.len == 3
			assert 'alice' in sv.values
			assert 'bob' in sv.values
			assert 'charlie' in sv.values
		} else {
			assert false, 'expected SetValue'
		}
	} else {
		assert false, 'expected Metric'
	}
}

fn test_incremental_to_absolute_set_state() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	m1 := event.Event(event.Metric{
		name: 'users'
		kind: .incremental
		value: event.MetricValue(event.SetValue{values: ['alice', 'bob']})
	})
	m2 := event.Event(event.Metric{
		name: 'users'
		kind: .incremental
		value: event.MetricValue(event.SetValue{values: ['charlie']})
	})

	t.transform(m1) or { panic(err) }
	t.transform(m2) or { panic(err) }

	vals := t.state_set_values('users')
	assert vals.len == 3
	assert 'alice' in vals
	assert 'bob' in vals
	assert 'charlie' in vals
}

fn test_incremental_to_absolute_passthrough_absolute() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	m := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.85})
	})

	result := t.transform(m) or { panic(err) }
	assert result.len == 1
	if result[0] is event.Metric {
		metric := result[0] as event.Metric
		assert metric.kind == .absolute
		assert metric.name == 'cpu'
	} else {
		assert false, 'expected Metric'
	}
}

fn test_incremental_to_absolute_passthrough_log() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	ev := event.Event(event.new_log('hello'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	if result[0] is event.LogEvent {
		log_ev := result[0] as event.LogEvent
		assert log_ev.message() == 'hello'
	} else {
		assert false, 'expected LogEvent'
	}
}

fn test_incremental_to_absolute_passthrough_trace() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	mut trace := event.new_trace()
	trace.set('span_id', event.Value('xyz'))
	ev := event.Event(trace)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
}

fn test_incremental_to_absolute_preserves_tags() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	m := event.Event(event.Metric{
		name: 'requests'
		kind: .incremental
		tags: {
			'host': 'web-01'
			'env':  'prod'
		}
		value: event.MetricValue(event.CounterValue{value: 5.0})
	})

	result := t.transform(m) or { panic(err) }
	assert result.len == 1
	if result[0] is event.Metric {
		metric := result[0] as event.Metric
		assert metric.tags['host'] == 'web-01'
		assert metric.tags['env'] == 'prod'
	} else {
		assert false, 'expected Metric'
	}
}

fn test_incremental_to_absolute_preserves_namespace() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	m := event.Event(event.Metric{
		name: 'requests'
		namespace: 'myapp'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})

	result := t.transform(m) or { panic(err) }
	assert result.len == 1
	if result[0] is event.Metric {
		metric := result[0] as event.Metric
		assert metric.namespace == 'myapp'
	} else {
		assert false, 'expected Metric'
	}
}

fn test_incremental_to_absolute_tags_separate_state() {
	mut t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }

	// Same metric name but different tags should be tracked separately
	m1 := event.Event(event.Metric{
		name: 'requests'
		kind: .incremental
		tags: {'host': 'web-01'}
		value: event.MetricValue(event.CounterValue{value: 10.0})
	})
	m2 := event.Event(event.Metric{
		name: 'requests'
		kind: .incremental
		tags: {'host': 'web-02'}
		value: event.MetricValue(event.CounterValue{value: 20.0})
	})

	r1 := t.transform(m1) or { panic(err) }
	r2 := t.transform(m2) or { panic(err) }

	if r1[0] is event.Metric {
		metric := r1[0] as event.Metric
		if metric.value is event.CounterValue {
			cv := metric.value as event.CounterValue
			assert cv.value == 10.0
		} else {
			assert false, 'expected CounterValue'
		}
	} else {
		assert false, 'expected Metric'
	}
	if r2[0] is event.Metric {
		metric := r2[0] as event.Metric
		if metric.value is event.CounterValue {
			cv := metric.value as event.CounterValue
			assert cv.value == 20.0
		} else {
			assert false, 'expected CounterValue'
		}
	} else {
		assert false, 'expected Metric'
	}
}

fn test_incremental_to_absolute_no_opts() {
	t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }
	assert t.counters.len == 0
	assert t.gauges.len == 0
	assert t.sets.len == 0
}

fn test_incremental_to_absolute_state_counter_default() {
	t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }
	assert t.state_counter('nonexistent') == 0.0
}

fn test_incremental_to_absolute_state_set_default() {
	t := new_incremental_to_absolute(map[string]string{}) or { panic(err) }
	vals := t.state_set_values('nonexistent')
	assert vals.len == 0
}
