module transforms

import event

fn test_sample_rate_one_passes_all() {
	mut opts := map[string]string{}
	opts['rate'] = '1'
	t := new_sample(opts) or { panic(err) }

	// With rate=1, every event should pass
	for _ in 0 .. 20 {
		ev := event.Event(event.new_log('test'))
		result := t.transform(ev) or { panic(err) }
		assert result.len == 1, 'rate=1 should pass all events'
	}
}

fn test_sample_deterministic_by_key_field() {
	mut opts := map[string]string{}
	opts['rate'] = '10'
	opts['key_field'] = 'request_id'
	t := new_sample(opts) or { panic(err) }

	mut log1 := event.new_log('req')
	log1.set('request_id', event.Value('abc123'))
	result1 := t.transform(event.Event(log1)) or { panic(err) }

	// Same key should always produce the same result
	mut log2 := event.new_log('req')
	log2.set('request_id', event.Value('abc123'))
	result2 := t.transform(event.Event(log2)) or { panic(err) }

	assert result1.len == result2.len, 'same key_field value should produce deterministic result'
}

fn test_sample_exclude_bypasses_sampling() {
	mut opts := map[string]string{}
	opts['rate'] = '1000000' // very high rate — almost nothing passes randomly
	opts['exclude'] = '.level == "error"'
	t := new_sample(opts) or { panic(err) }

	mut log := event.new_log('critical failure')
	log.set('level', event.Value('error'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1, 'excluded events should always pass through'
}

fn test_sample_missing_rate_errors() {
	opts := map[string]string{}
	if _ := new_sample(opts) {
		assert false, 'expected error for missing rate'
	}
}

fn test_sample_non_log_passthrough() {
	mut opts := map[string]string{}
	opts['rate'] = '1000000'
	t := new_sample(opts) or { panic(err) }

	ev := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.5})
	})
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1, 'non-log events should pass through'
}
