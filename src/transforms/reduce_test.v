module transforms

import event

fn test_reduce_accumulates_events() {
	mut opts := map[string]string{}
	mut t := new_reduce(opts) or { panic(err) }

	ev1 := event.Event(event.new_log('line 1'))
	result1 := t.transform(ev1) or { panic(err) }
	assert result1.len == 0, 'first event should be accumulated, not emitted'

	ev2 := event.Event(event.new_log('line 2'))
	result2 := t.transform(ev2) or { panic(err) }
	assert result2.len == 0, 'second event should be accumulated'
}

fn test_reduce_flush_all() {
	mut opts := map[string]string{}
	mut t := new_reduce(opts) or { panic(err) }

	ev1 := event.Event(event.new_log('line 1'))
	t.transform(ev1) or { panic(err) }

	ev2 := event.Event(event.new_log('line 2'))
	t.transform(ev2) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1, 'flush_all should emit accumulated group'
}

fn test_reduce_ends_when() {
	mut opts := map[string]string{}
	opts['ends_when'] = '.done == "true"'
	mut t := new_reduce(opts) or { panic(err) }

	ev1 := event.Event(event.new_log('line 1'))
	result1 := t.transform(ev1) or { panic(err) }
	assert result1.len == 0

	// This event ends the group
	mut log2 := event.new_log('line 2')
	log2.set('done', event.Value('true'))
	ev2 := event.Event(log2)
	result2 := t.transform(ev2) or { panic(err) }
	assert result2.len == 1, 'ends_when match should emit accumulated group'
}

fn test_reduce_group_by() {
	mut opts := map[string]string{}
	opts['group_by'] = '.host'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('line 1')
	log1.set('host', event.Value('a'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('line 2')
	log2.set('host', event.Value('b'))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 2, 'different group_by values should create separate groups'
}

fn test_reduce_passes_non_log() {
	mut opts := map[string]string{}
	mut t := new_reduce(opts) or { panic(err) }

	ev := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1, 'non-log events should pass through'
}
