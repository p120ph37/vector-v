module transforms

import event

fn test_throttle_under_threshold_passes() {
	mut opts := map[string]string{}
	opts['threshold'] = '5'
	opts['window_secs'] = '60'
	mut t := new_throttle(opts) or { panic(err) }

	// First 5 events should all pass
	for i in 0 .. 5 {
		ev := event.Event(event.new_log('msg ${i}'))
		result := t.transform(ev) or { panic(err) }
		assert result.len == 1, 'event ${i} should pass (under threshold)'
	}
}

fn test_throttle_over_threshold_drops() {
	mut opts := map[string]string{}
	opts['threshold'] = '3'
	opts['window_secs'] = '60'
	mut t := new_throttle(opts) or { panic(err) }

	// Consume all 3 tokens
	for _ in 0 .. 3 {
		ev := event.Event(event.new_log('msg'))
		result := t.transform(ev) or { panic(err) }
		assert result.len == 1
	}

	// 4th event should be throttled
	ev := event.Event(event.new_log('over limit'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 0, 'event over threshold should be dropped'
}

fn test_throttle_per_key() {
	mut opts := map[string]string{}
	opts['threshold'] = '2'
	opts['window_secs'] = '60'
	opts['key_field'] = 'host'
	mut t := new_throttle(opts) or { panic(err) }

	// Consume both tokens for host=a
	for _ in 0 .. 2 {
		mut log := event.new_log('msg')
		log.set('host', event.Value('a'))
		t.transform(event.Event(log)) or { panic(err) }
	}

	// host=a should be throttled
	mut log_a := event.new_log('msg')
	log_a.set('host', event.Value('a'))
	result_a := t.transform(event.Event(log_a)) or { panic(err) }
	assert result_a.len == 0, 'host=a should be throttled'

	// host=b should still pass (separate bucket)
	mut log_b := event.new_log('msg')
	log_b.set('host', event.Value('b'))
	result_b := t.transform(event.Event(log_b)) or { panic(err) }
	assert result_b.len == 1, 'host=b should pass (separate bucket)'
}

fn test_throttle_missing_key_uses_default() {
	mut opts := map[string]string{}
	opts['threshold'] = '1'
	opts['window_secs'] = '60'
	opts['key_field'] = 'host'
	mut t := new_throttle(opts) or { panic(err) }

	// Event without 'host' field — uses default bucket
	ev1 := event.Event(event.new_log('no host'))
	result1 := t.transform(ev1) or { panic(err) }
	assert result1.len == 1, 'first event without key_field should use default bucket'

	ev2 := event.Event(event.new_log('no host again'))
	result2 := t.transform(ev2) or { panic(err) }
	assert result2.len == 0, 'second event in default bucket should be throttled'
}

fn test_throttle_missing_threshold_errors() {
	opts := map[string]string{}
	if _ := new_throttle(opts) {
		assert false, 'expected error for missing threshold'
	}
}

fn test_throttle_custom_window_secs() {
	mut opts := map[string]string{}
	opts['threshold'] = '10'
	opts['window_secs'] = '30'
	t := new_throttle(opts) or { panic(err) }
	assert t.threshold == 10
	// 30 seconds in nanoseconds
	assert t.window == 30_000_000_000
}

fn test_throttle_non_log_passthrough() {
	mut opts := map[string]string{}
	opts['threshold'] = '1'
	opts['window_secs'] = '60'
	mut t := new_throttle(opts) or { panic(err) }

	ev := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.5})
	})
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1, 'non-log events should pass through'
}
