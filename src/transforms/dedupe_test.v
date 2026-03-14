module transforms

import event

fn test_dedupe_drops_duplicate() {
	mut opts := map[string]string{}
	opts['fields.match'] = '.host, .message'
	mut t := new_dedupe(opts) or { panic(err) }

	mut log1 := event.new_log('hello')
	log1.set('host', event.Value('server1'))
	ev1 := event.Event(log1)

	result1 := t.transform(ev1) or { panic(err) }
	assert result1.len == 1, 'first event should pass through'

	// Same fields — duplicate
	mut log2 := event.new_log('hello')
	log2.set('host', event.Value('server1'))
	ev2 := event.Event(log2)

	result2 := t.transform(ev2) or { panic(err) }
	assert result2.len == 0, 'duplicate event should be dropped'
}

fn test_dedupe_unique_events_pass() {
	mut opts := map[string]string{}
	opts['fields.match'] = '.host'
	mut t := new_dedupe(opts) or { panic(err) }

	mut log1 := event.new_log('hello')
	log1.set('host', event.Value('server1'))
	result1 := t.transform(event.Event(log1)) or { panic(err) }
	assert result1.len == 1

	mut log2 := event.new_log('hello')
	log2.set('host', event.Value('server2'))
	result2 := t.transform(event.Event(log2)) or { panic(err) }
	assert result2.len == 1, 'different field value should pass through'
}

fn test_dedupe_match_mode() {
	mut opts := map[string]string{}
	opts['fields.match'] = '.level'
	mut t := new_dedupe(opts) or { panic(err) }

	mut log1 := event.new_log('first message')
	log1.set('level', event.Value('error'))
	result1 := t.transform(event.Event(log1)) or { panic(err) }
	assert result1.len == 1

	// Different message but same level — duplicate in match mode
	mut log2 := event.new_log('second message')
	log2.set('level', event.Value('error'))
	result2 := t.transform(event.Event(log2)) or { panic(err) }
	assert result2.len == 0, 'same matched field should be detected as duplicate'
}

fn test_dedupe_ignore_mode() {
	mut opts := map[string]string{}
	opts['fields.ignore'] = '.timestamp, .extra'
	mut t := new_dedupe(opts) or { panic(err) }

	mut log1 := event.new_log('hello')
	log1.set('extra', event.Value('value1'))
	result1 := t.transform(event.Event(log1)) or { panic(err) }
	assert result1.len == 1

	// Same message, different ignored field — duplicate
	mut log2 := event.new_log('hello')
	log2.set('extra', event.Value('value2'))
	result2 := t.transform(event.Event(log2)) or { panic(err) }
	assert result2.len == 0, 'events differing only in ignored fields should be duplicates'
}

fn test_dedupe_lru_cache_eviction() {
	mut opts := map[string]string{}
	opts['fields.match'] = '.id'
	opts['cache.num_events'] = '3'
	mut t := new_dedupe(opts) or { panic(err) }

	// Fill cache with 3 unique events
	for i in 0 .. 3 {
		mut log := event.new_log('msg')
		log.set('id', event.Value('${i}'))
		result := t.transform(event.Event(log)) or { panic(err) }
		assert result.len == 1
	}

	// Add a 4th event to evict the oldest (id=0)
	mut log4 := event.new_log('msg')
	log4.set('id', event.Value('new'))
	t.transform(event.Event(log4)) or { panic(err) }

	// id=0 should have been evicted, so it passes through again
	mut log_reinsert := event.new_log('msg')
	log_reinsert.set('id', event.Value('0'))
	result := t.transform(event.Event(log_reinsert)) or { panic(err) }
	assert result.len == 1, 'evicted event should pass through again'
}

fn test_dedupe_non_log_passthrough() {
	mut opts := map[string]string{}
	mut t := new_dedupe(opts) or { panic(err) }

	ev := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.5})
	})
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1, 'non-log events should pass through'
}

fn test_dedupe_default_config() {
	// Default config: ignore only timestamp
	opts := map[string]string{}
	t := new_dedupe(opts) or { panic(err) }
	assert t.ignore_fields == ['timestamp']
	assert t.match_fields.len == 0
	assert t.cache_size == 5000
}

fn test_dedupe_custom_cache_size() {
	mut opts := map[string]string{}
	opts['cache.num_events'] = '100'
	t := new_dedupe(opts) or { panic(err) }
	assert t.cache_size == 100
}
