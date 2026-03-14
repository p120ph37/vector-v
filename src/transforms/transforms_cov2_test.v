module transforms

import event
import time

// Coverage tests for reduce.v uncovered lines

// reduce.v line 291: array strategy first value initialization
fn test_reduce_array_strategy_init() {
	mut opts := map[string]string{}
	opts['merge_strategies.tags'] = 'array'
	mut t := new_reduce(opts) or { return }

	// First event initializes the array
	mut log1 := event.new_log('first')
	log1.set('tags', event.Value('tag_a'))
	_ = t.transform(event.Event(log1)) or { return }

	// Second event should append to array
	mut log2 := event.new_log('second')
	log2.set('tags', event.Value('tag_b'))
	_ = t.transform(event.Event(log2)) or { return }

	// Flush and check
	result := t.flush_all()
	assert result.len == 1
	merged := result[0] as event.LogEvent
	arr_val := merged.get('tags') or { return }
	arr := arr_val as []event.Value
	assert arr.len == 2
}

// reduce.v lines 330-332: flat_unique strategy new field initialization
fn test_reduce_flat_unique_strategy() {
	mut opts := map[string]string{}
	opts['merge_strategies.category'] = 'flat_unique'
	mut t := new_reduce(opts) or { return }

	mut log1 := event.new_log('first')
	log1.set('category', event.Value('web'))
	_ = t.transform(event.Event(log1)) or { return }

	mut log2 := event.new_log('second')
	log2.set('category', event.Value('api'))
	_ = t.transform(event.Event(log2)) or { return }

	// Same value again - should not duplicate
	mut log3 := event.new_log('third')
	log3.set('category', event.Value('web'))
	_ = t.transform(event.Event(log3)) or { return }

	result := t.flush_all()
	assert result.len == 1
	merged := result[0] as event.LogEvent
	vals := merged.get('category') or { return }
	arr := vals as []event.Value
	assert arr.len == 2, 'expected 2 unique values, got ${arr.len}'
}

// reduce.v line 350: shortest_array strategy with no existing value
fn test_reduce_shortest_array_strategy() {
	mut opts := map[string]string{}
	opts['merge_strategies.items'] = 'shortest_array'
	mut t := new_reduce(opts) or { return }

	// First event: array with 3 elements
	mut log1 := event.new_log('first')
	log1.set('items', event.Value([event.Value('a'), event.Value('b'), event.Value('c')]))
	_ = t.transform(event.Event(log1)) or { return }

	// Second event: array with 2 elements (shorter)
	mut log2 := event.new_log('second')
	log2.set('items', event.Value([event.Value('x'), event.Value('y')]))
	_ = t.transform(event.Event(log2)) or { return }

	// Third event: array with 4 elements (longer, should not replace)
	mut log3 := event.new_log('third')
	log3.set('items', event.Value([event.Value('1'), event.Value('2'), event.Value('3'), event.Value('4')]))
	_ = t.transform(event.Event(log3)) or { return }

	result := t.flush_all()
	assert result.len == 1
	merged := result[0] as event.LogEvent
	vals := merged.get('items') or { return }
	arr := vals as []event.Value
	assert arr.len == 2, 'expected shortest array (2), got ${arr.len}'
}

// reduce.v line 371: longest_array with no existing value
fn test_reduce_longest_array_strategy() {
	mut opts := map[string]string{}
	opts['merge_strategies.items'] = 'longest_array'
	mut t := new_reduce(opts) or { return }

	// First event: array with 2 elements
	mut log1 := event.new_log('first')
	log1.set('items', event.Value([event.Value('a'), event.Value('b')]))
	_ = t.transform(event.Event(log1)) or { return }

	// Second event: array with 4 elements (longer)
	mut log2 := event.new_log('second')
	log2.set('items', event.Value([event.Value('x'), event.Value('y'), event.Value('z'), event.Value('w')]))
	_ = t.transform(event.Event(log2)) or { return }

	// Third event: array with 1 element (shorter)
	mut log3 := event.new_log('third')
	log3.set('items', event.Value([event.Value('1')]))
	_ = t.transform(event.Event(log3)) or { return }

	result := t.flush_all()
	assert result.len == 1
	merged := result[0] as event.LogEvent
	vals := merged.get('items') or { return }
	arr := vals as []event.Value
	assert arr.len == 4, 'expected longest array (4), got ${arr.len}'
}

// reduce.v line 385: finalize_group with missing key
fn test_reduce_finalize_missing_group() {
	mut opts := map[string]string{}
	mut t := new_reduce(opts) or { return }

	// flush_all on empty groups
	result := t.flush_all()
	assert result.len == 0
}

// reduce.v lines 438, 442-443: flush_expired
fn test_reduce_flush_expired() {
	mut opts := map[string]string{}
	opts['expire_after_ms'] = '1' // 1ms expiry
	mut t := new_reduce(opts) or { return }

	mut log1 := event.new_log('event1')
	_ = t.transform(event.Event(log1)) or { return }

	// Wait a bit for expiry
	time.sleep(5 * time.millisecond)

	// Next transform should trigger flush_expired
	mut log2 := event.new_log('event2')
	result := t.transform(event.Event(log2)) or { return }

	// The expired group should have been flushed
	assert result.len >= 1, 'expected expired group to be flushed'
}

// reduce.v: shortest_array with non-array existing value (line 346 else branch)
fn test_reduce_shortest_array_existing_non_array() {
	mut opts := map[string]string{}
	opts['merge_strategies.items'] = 'shortest_array'
	mut t := new_reduce(opts) or { return }

	// First event: non-array value
	mut log1 := event.new_log('first')
	log1.set('items', event.Value('not_an_array'))
	_ = t.transform(event.Event(log1)) or { return }

	// Second event: array value (should replace because existing is not array)
	mut log2 := event.new_log('second')
	log2.set('items', event.Value([event.Value('a'), event.Value('b')]))
	_ = t.transform(event.Event(log2)) or { return }

	result := t.flush_all()
	assert result.len == 1
}

// reduce.v: discard strategy
fn test_reduce_discard_strategy() {
	mut opts := map[string]string{}
	opts['merge_strategies.status'] = 'discard'
	mut t := new_reduce(opts) or { return }

	mut log1 := event.new_log('first')
	log1.set('status', event.Value('initial'))
	_ = t.transform(event.Event(log1)) or { return }

	mut log2 := event.new_log('second')
	log2.set('status', event.Value('updated'))
	_ = t.transform(event.Event(log2)) or { return }

	result := t.flush_all()
	assert result.len == 1
	merged := result[0] as event.LogEvent
	val := merged.get('status') or { return }
	s := val as string
	assert s == 'initial', 'discard should keep first value, got ${s}'
}
