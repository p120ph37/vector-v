module transforms

import event

fn test_filter_matches() {
	mut opts := map[string]string{}
	opts['condition'] = '.level == "error"'
	t := new_filter(opts) or { panic(err) }

	mut log := event.new_log('something broke')
	log.set('level', event.Value('error'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1, 'matching event should pass through'
}

fn test_filter_drops_non_matching() {
	mut opts := map[string]string{}
	opts['condition'] = '.level == "error"'
	t := new_filter(opts) or { panic(err) }

	mut log := event.new_log('all good')
	log.set('level', event.Value('info'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 0, 'non-matching event should be dropped'
}

fn test_filter_missing_field_drops() {
	mut opts := map[string]string{}
	opts['condition'] = '.level == "error"'
	t := new_filter(opts) or { panic(err) }

	ev := event.Event(event.new_log('no level field'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 0, 'event without field should be dropped'
}

fn test_filter_requires_condition() {
	opts := map[string]string{}
	if _ := new_filter(opts) {
		assert false, 'expected error for missing condition'
	}
}

fn test_filter_passes_metrics() {
	mut opts := map[string]string{}
	opts['condition'] = '.level == "error"'
	t := new_filter(opts) or { panic(err) }

	ev := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.5})
	})
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1, 'metric events should pass through'
}
