module transforms

import event

fn test_aggregate_counter_sum() {
	mut t := new_aggregate({'interval_ms': '999999'})!

	t.transform(event.Event(event.new_counter('requests', 5.0, .incremental)))!
	t.transform(event.Event(event.new_counter('requests', 3.0, .incremental)))!
	t.transform(event.Event(event.new_counter('requests', 2.0, .incremental)))!

	result := t.flush_all()
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			assert m.name == 'requests'
			v := m.value
			match v {
				event.CounterValue { assert v.value == 10.0 }
				else { assert false, 'expected CounterValue' }
			}
		}
		else { assert false }
	}
}

fn test_aggregate_gauge_latest() {
	mut t := new_aggregate({'interval_ms': '999999'})!

	t.transform(event.Event(event.new_gauge('cpu', 0.5)))!
	t.transform(event.Event(event.new_gauge('cpu', 0.8)))!
	t.transform(event.Event(event.new_gauge('cpu', 0.3)))!

	result := t.flush_all()
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			v := m.value
			match v {
				event.GaugeValue { assert v.value == 0.3 }
				else { assert false }
			}
		}
		else { assert false }
	}
}

fn test_aggregate_set_union() {
	mut t := new_aggregate({'interval_ms': '999999'})!

	t.transform(event.Event(event.Metric{
		name: 'users'
		kind: .incremental
		value: event.MetricValue(event.SetValue{values: ['a', 'b']})
	}))!
	t.transform(event.Event(event.Metric{
		name: 'users'
		kind: .incremental
		value: event.MetricValue(event.SetValue{values: ['b', 'c']})
	}))!

	result := t.flush_all()
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			v := m.value
			match v {
				event.SetValue { assert v.values.len == 3 }
				else { assert false }
			}
		}
		else { assert false }
	}
}

fn test_aggregate_separate_metrics() {
	mut t := new_aggregate({'interval_ms': '999999'})!

	t.transform(event.Event(event.new_counter('requests', 5.0, .incremental)))!
	t.transform(event.Event(event.new_gauge('cpu', 0.5)))!
	t.transform(event.Event(event.new_counter('requests', 3.0, .incremental)))!

	result := t.flush_all()
	assert result.len == 2
}

fn test_aggregate_with_tags() {
	mut t := new_aggregate({'interval_ms': '999999'})!

	mut m1 := event.new_counter('requests', 1.0, .incremental)
	m1.tags = {'host': 'a'}
	mut m2 := event.new_counter('requests', 2.0, .incremental)
	m2.tags = {'host': 'b'}
	mut m3 := event.new_counter('requests', 3.0, .incremental)
	m3.tags = {'host': 'a'}

	t.transform(event.Event(m1))!
	t.transform(event.Event(m2))!
	t.transform(event.Event(m3))!

	result := t.flush_all()
	assert result.len == 2
}

fn test_aggregate_non_metric_passthrough() {
	mut t := new_aggregate({'interval_ms': '999999'})!

	log := event.Event(event.new_log('hello'))
	result := t.transform(log)!
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent { assert first.message() == 'hello' }
		else { assert false }
	}
}

fn test_aggregate_absolute_counter_replace() {
	mut t := new_aggregate({'interval_ms': '999999'})!

	t.transform(event.Event(event.new_counter('total', 100.0, .absolute)))!
	t.transform(event.Event(event.new_counter('total', 200.0, .absolute)))!

	result := t.flush_all()
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			v := m.value
			match v {
				event.CounterValue { assert v.value == 200.0 }
				else { assert false }
			}
		}
		else { assert false }
	}
}

fn test_aggregate_default_interval() {
	t := new_aggregate({})!
	assert t.interval == 10_000_000_000
}

fn test_aggregate_invalid_interval_defaults() {
	t := new_aggregate({'interval_ms': '-5'})!
	assert t.interval == 10_000_000_000
}

fn test_aggregate_flush_all_clears_state() {
	mut t := new_aggregate({'interval_ms': '999999'})!

	t.transform(event.Event(event.new_counter('test', 1.0, .incremental)))!

	r1 := t.flush_all()
	assert r1.len == 1

	r2 := t.flush_all()
	assert r2.len == 0
}

fn test_aggregate_histogram() {
	mut t := new_aggregate({'interval_ms': '999999'})!

	t.transform(event.Event(event.Metric{
		name: 'duration'
		kind: .incremental
		value: event.MetricValue(event.HistogramValue{
			buckets: [event.Bucket{upper_limit: 1.0, count: 5}]
			count: 5
			sum: 3.0
		})
	}))!
	t.transform(event.Event(event.Metric{
		name: 'duration'
		kind: .incremental
		value: event.MetricValue(event.HistogramValue{
			buckets: [event.Bucket{upper_limit: 1.0, count: 3}]
			count: 3
			sum: 2.0
		})
	}))!

	result := t.flush_all()
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			v := m.value
			match v {
				event.HistogramValue {
					assert v.count == 8
					assert v.sum == 5.0
				}
				else { assert false }
			}
		}
		else { assert false }
	}
}

fn test_aggregate_via_registry() {
	mut t := build_transform('aggregate', {'interval_ms': '999999'})!

	m := event.Event(event.new_counter('test', 1.0, .incremental))
	result := apply_transform(mut t, m)!
	assert result.len == 0
}
