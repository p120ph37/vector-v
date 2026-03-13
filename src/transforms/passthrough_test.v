module transforms

import event

fn test_passthrough_returns_same_event() {
	ev := event.Event(event.new_log('hello'))
	result := passthrough(ev) or { panic(err) }
	assert result.len == 1
	first := result[0]
	match first {
		event.LogEvent {
			assert first.message() == 'hello'
		}
		else {
			assert false, 'expected LogEvent'
		}
	}
}

fn test_passthrough_metric() {
	ev := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	result := passthrough(ev) or { panic(err) }
	assert result.len == 1
}

fn test_passthrough_trace() {
	mut t := event.new_trace()
	t.set('span', event.Value('abc'))
	ev := event.Event(t)
	result := passthrough(ev) or { panic(err) }
	assert result.len == 1
}
