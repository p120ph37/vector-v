module transforms

import event
import time

// --- flat_unique merge strategy ---

fn test_reduce_flat_unique_deduplicates() {
	mut opts := map[string]string{}
	opts['merge_strategies.tag'] = 'flat_unique'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('tag', event.Value('foo'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('tag', event.Value('bar'))
	t.transform(event.Event(log2)) or { panic(err) }

	mut log3 := event.new_log('c')
	log3.set('tag', event.Value('foo')) // duplicate
	t.transform(event.Event(log3)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('tag') or { panic('expected tag') }
			match val {
				[]event.Value {
					// Should have exactly 2 unique values: foo, bar
					assert val.len == 2, 'flat_unique should deduplicate, got ${val.len}'
				}
				else {
					assert false, 'expected array from flat_unique'
				}
			}
		}
		else {
			assert false
		}
	}
}

fn test_reduce_flat_unique_single_value() {
	mut opts := map[string]string{}
	opts['merge_strategies.tag'] = 'flat_unique'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('tag', event.Value('only'))
	t.transform(event.Event(log1)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('tag') or { panic('expected tag') }
			match val {
				[]event.Value {
					assert val.len == 1
				}
				else {
					assert false, 'expected array from flat_unique'
				}
			}
		}
		else {
			assert false
		}
	}
}

// --- shortest_array / longest_array merge strategies ---

fn test_reduce_shortest_array() {
	mut opts := map[string]string{}
	opts['merge_strategies.items'] = 'shortest_array'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('items', event.Value([event.Value('a'), event.Value('b'), event.Value('c')]))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('items', event.Value([event.Value('x')]))
	t.transform(event.Event(log2)) or { panic(err) }

	mut log3 := event.new_log('c')
	log3.set('items', event.Value([event.Value('p'), event.Value('q')]))
	t.transform(event.Event(log3)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('items') or { panic('expected items') }
			match val {
				[]event.Value {
					assert val.len == 1, 'shortest_array should keep array with 1 element, got ${val.len}'
				}
				else {
					assert false, 'expected array'
				}
			}
		}
		else {
			assert false
		}
	}
}

fn test_reduce_longest_array() {
	mut opts := map[string]string{}
	opts['merge_strategies.items'] = 'longest_array'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('items', event.Value([event.Value('a')]))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('items', event.Value([event.Value('x'), event.Value('y'), event.Value('z')]))
	t.transform(event.Event(log2)) or { panic(err) }

	mut log3 := event.new_log('c')
	log3.set('items', event.Value([event.Value('p'), event.Value('q')]))
	t.transform(event.Event(log3)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('items') or { panic('expected items') }
			match val {
				[]event.Value {
					assert val.len == 3, 'longest_array should keep array with 3 elements, got ${val.len}'
				}
				else {
					assert false, 'expected array'
				}
			}
		}
		else {
			assert false
		}
	}
}

fn test_reduce_shortest_array_replaces_non_array() {
	// When existing value is not an array but new value is, it should replace
	mut opts := map[string]string{}
	opts['merge_strategies.items'] = 'shortest_array'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('items', event.Value('not_an_array'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('items', event.Value([event.Value('x'), event.Value('y')]))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('items') or { panic('expected items') }
			match val {
				[]event.Value {
					assert val.len == 2, 'should replace non-array with the array value'
				}
				else {
					assert false, 'expected array after replacing non-array'
				}
			}
		}
		else {
			assert false
		}
	}
}

fn test_reduce_longest_array_replaces_non_array() {
	mut opts := map[string]string{}
	opts['merge_strategies.items'] = 'longest_array'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('items', event.Value('scalar'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('items', event.Value([event.Value('x')]))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('items') or { panic('expected items') }
			match val {
				[]event.Value {
					assert val.len == 1
				}
				else {
					assert false, 'expected array after replacing scalar'
				}
			}
		}
		else {
			assert false
		}
	}
}

fn test_reduce_shortest_array_non_array_input_ignored() {
	// When incoming value is not an array, shortest_array ignores it
	mut opts := map[string]string{}
	opts['merge_strategies.items'] = 'shortest_array'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('items', event.Value([event.Value('a'), event.Value('b')]))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('items', event.Value('not_array')) // non-array, should be ignored
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('items') or { panic('expected items') }
			match val {
				[]event.Value {
					assert val.len == 2, 'non-array merge should not change existing array'
				}
				else {
					// original array stays
				}
			}
		}
		else {
			assert false
		}
	}
}

// --- retain and discard merge strategies ---

fn test_reduce_discard_keeps_first_value() {
	mut opts := map[string]string{}
	opts['merge_strategies.status'] = 'discard'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('status', event.Value('first'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('status', event.Value('second'))
	t.transform(event.Event(log2)) or { panic(err) }

	mut log3 := event.new_log('c')
	log3.set('status', event.Value('third'))
	t.transform(event.Event(log3)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('status') or { panic('expected status') }
			assert event.value_to_string(val) == 'first', 'discard should keep the first value'
		}
		else {
			assert false
		}
	}
}

fn test_reduce_retain_keeps_last_value() {
	mut opts := map[string]string{}
	// retain is the default, but let's be explicit
	opts['merge_strategies.status'] = 'retain'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('status', event.Value('first'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('status', event.Value('second'))
	t.transform(event.Event(log2)) or { panic(err) }

	mut log3 := event.new_log('c')
	log3.set('status', event.Value('third'))
	t.transform(event.Event(log3)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('status') or { panic('expected status') }
			assert event.value_to_string(val) == 'third', 'retain should keep the last value'
		}
		else {
			assert false
		}
	}
}

// --- concat_newline and concat_raw ---

fn test_reduce_concat_newline() {
	mut opts := map[string]string{}
	opts['merge_strategies.msg'] = 'concat_newline'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('msg', event.Value('line1'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('msg', event.Value('line2'))
	t.transform(event.Event(log2)) or { panic(err) }

	mut log3 := event.new_log('c')
	log3.set('msg', event.Value('line3'))
	t.transform(event.Event(log3)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('msg') or { panic('expected msg') }
			s := event.value_to_string(val)
			assert s == 'line1\nline2\nline3', 'concat_newline should join with newlines, got: ${s}'
		}
		else {
			assert false
		}
	}
}

fn test_reduce_concat_raw() {
	mut opts := map[string]string{}
	opts['merge_strategies.msg'] = 'concat_raw'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('msg', event.Value('ab'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('msg', event.Value('cd'))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('msg') or { panic('expected msg') }
			s := event.value_to_string(val)
			assert s == 'abcd', 'concat_raw should join without separator, got: ${s}'
		}
		else {
			assert false
		}
	}
}

// --- sum/min/max with float values (fractional path in finalize) ---

fn test_reduce_sum_float_values() {
	mut opts := map[string]string{}
	opts['merge_strategies.val'] = 'sum'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('val', event.Value(event.Float(1.5)))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('val', event.Value(event.Float(2.3)))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('val') or { panic('expected val') }
			match val {
				event.Float {
					f := f64(val)
					assert f > 3.7 && f < 3.9, 'sum of 1.5+2.3 should be ~3.8, got ${f}'
				}
				else {
					assert false, 'expected Float result for fractional sum'
				}
			}
		}
		else {
			assert false
		}
	}
}

fn test_reduce_min_float_values() {
	mut opts := map[string]string{}
	opts['merge_strategies.val'] = 'min'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('val', event.Value(event.Float(3.7)))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('val', event.Value(event.Float(1.2)))
	t.transform(event.Event(log2)) or { panic(err) }

	mut log3 := event.new_log('c')
	log3.set('val', event.Value(event.Float(5.9)))
	t.transform(event.Event(log3)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('val') or { panic('expected val') }
			match val {
				event.Float {
					f := f64(val)
					assert f > 1.1 && f < 1.3, 'min should be 1.2, got ${f}'
				}
				else {
					assert false, 'expected Float result for fractional min'
				}
			}
		}
		else {
			assert false
		}
	}
}

fn test_reduce_max_float_values() {
	mut opts := map[string]string{}
	opts['merge_strategies.val'] = 'max'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('val', event.Value(event.Float(3.7)))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('val', event.Value(event.Float(9.1)))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('val') or { panic('expected val') }
			match val {
				event.Float {
					f := f64(val)
					assert f > 9.0 && f < 9.2, 'max should be 9.1, got ${f}'
				}
				else {
					assert false, 'expected Float result for fractional max'
				}
			}
		}
		else {
			assert false
		}
	}
}

// --- sum with string numeric values (value_to_f64 string path in merge) ---

fn test_reduce_sum_string_numeric() {
	mut opts := map[string]string{}
	opts['merge_strategies.val'] = 'sum'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('val', event.Value('10'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('val', event.Value('25'))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('val') or { panic('expected val') }
			assert event.value_to_string(val) == '35'
		}
		else {
			assert false
		}
	}
}

// --- sum/min/max with non-numeric types (value_to_f64 returns 0.0) ---

fn test_reduce_sum_bool_yields_zero() {
	mut opts := map[string]string{}
	opts['merge_strategies.flag'] = 'sum'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('flag', event.Value(true))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('flag', event.Value(true))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('flag') or { panic('expected flag') }
			// bool -> value_to_f64 -> 0.0, so sum is 0
			assert event.value_to_string(val) == '0'
		}
		else {
			assert false
		}
	}
}

// --- ends_when with no existing group (pass-through path) ---

fn test_reduce_ends_when_no_existing_group() {
	mut opts := map[string]string{}
	opts['ends_when'] = '.done == "true"'
	mut t := new_reduce(opts) or { panic(err) }

	// Send an event that matches ends_when without a prior group
	mut log1 := event.new_log('immediate')
	log1.set('done', event.Value('true'))
	result := t.transform(event.Event(log1)) or { panic(err) }
	// Should pass through directly since there is no existing group
	assert result.len == 1, 'ends_when with no group should pass event through'
}

// --- check_condition != with missing field (returns true) ---

fn test_reduce_check_condition_neq_missing_field() {
	t := new_reduce(map[string]string{}) or { panic(err) }
	log := event.new_log('test')
	// Field 'level' does not exist; != condition should return true
	assert t.check_condition('.level != "error"', log) == true
}

fn test_reduce_check_condition_eq_missing_field() {
	t := new_reduce(map[string]string{}) or { panic(err) }
	log := event.new_log('test')
	// Field 'level' does not exist; == condition should return false
	assert t.check_condition('.level == "error"', log) == false
}

fn test_reduce_check_condition_no_operator() {
	t := new_reduce(map[string]string{}) or { panic(err) }
	log := event.new_log('test')
	// No == or != operator; should return false
	assert t.check_condition('.level', log) == false
}

// --- group_by with missing field ---

fn test_reduce_group_by_missing_field() {
	mut opts := map[string]string{}
	opts['group_by'] = '.host,.env'
	mut t := new_reduce(opts) or { panic(err) }

	// log1 has host but no env
	mut log1 := event.new_log('a')
	log1.set('host', event.Value('server1'))
	t.transform(event.Event(log1)) or { panic(err) }

	// log2 has both
	mut log2 := event.new_log('b')
	log2.set('host', event.Value('server1'))
	log2.set('env', event.Value('prod'))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	// Different keys: "server1|" vs "server1|prod"
	assert flushed.len == 2, 'missing group_by field should create separate group'
}

// --- group_by with multiple groups ---

fn test_reduce_group_by_multiple_groups_flush() {
	mut opts := map[string]string{}
	opts['group_by'] = '.service'
	opts['merge_strategies.count'] = 'sum'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('service', event.Value('web'))
	log1.set('count', event.Value(1))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('service', event.Value('api'))
	log2.set('count', event.Value(5))
	t.transform(event.Event(log2)) or { panic(err) }

	mut log3 := event.new_log('c')
	log3.set('service', event.Value('web'))
	log3.set('count', event.Value(3))
	t.transform(event.Event(log3)) or { panic(err) }

	mut log4 := event.new_log('d')
	log4.set('service', event.Value('api'))
	log4.set('count', event.Value(7))
	t.transform(event.Event(log4)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 2, 'should have 2 groups: web and api'

	mut web_count := 0
	mut api_count := 0
	for ev in flushed {
		match ev {
			event.LogEvent {
				svc := ev.get('service') or { continue }
				cnt := ev.get('count') or { continue }
				svc_s := event.value_to_string(svc)
				cnt_s := event.value_to_string(cnt)
				if svc_s == 'web' {
					web_count = cnt_s.int()
				} else if svc_s == 'api' {
					api_count = cnt_s.int()
				}
			}
			else {}
		}
	}
	assert web_count == 4, 'web sum should be 4, got ${web_count}'
	assert api_count == 12, 'api sum should be 12, got ${api_count}'
}

// --- expire_after_ms ---

fn test_reduce_expire_after_ms_config() {
	mut opts := map[string]string{}
	opts['expire_after_ms'] = '100'
	t := new_reduce(opts) or { panic(err) }
	// 100ms = 100_000_000 nanoseconds
	assert t.expire_after == time.Duration(i64(100) * 1_000_000)
}

fn test_reduce_expire_after_ms_invalid_uses_default() {
	mut opts := map[string]string{}
	opts['expire_after_ms'] = '-5'
	t := new_reduce(opts) or { panic(err) }
	// Should fall back to 30000ms default
	assert t.expire_after == time.Duration(i64(30000) * 1_000_000)
}

fn test_reduce_expire_after_ms_zero_uses_default() {
	mut opts := map[string]string{}
	opts['expire_after_ms'] = '0'
	t := new_reduce(opts) or { panic(err) }
	assert t.expire_after == time.Duration(i64(30000) * 1_000_000)
}

// --- starts_when with no prior group ---

fn test_reduce_starts_when_no_prior_group() {
	mut opts := map[string]string{}
	opts['starts_when'] = '.type == "start"'
	mut t := new_reduce(opts) or { panic(err) }

	// First event matches starts_when, no prior group to flush
	mut log1 := event.new_log('begin')
	log1.set('type', event.Value('start'))
	result := t.transform(event.Event(log1)) or { panic(err) }
	assert result.len == 0, 'starts_when with no prior group should not emit anything'
}

// --- starts_when flushes and creates new group correctly ---

fn test_reduce_starts_when_preserves_new_group() {
	mut opts := map[string]string{}
	opts['starts_when'] = '.type == "start"'
	opts['merge_strategies.count'] = 'sum'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('type', event.Value('start'))
	log1.set('count', event.Value(1))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('count', event.Value(2))
	t.transform(event.Event(log2)) or { panic(err) }

	// New start flushes old group
	mut log3 := event.new_log('c')
	log3.set('type', event.Value('start'))
	log3.set('count', event.Value(10))
	result := t.transform(event.Event(log3)) or { panic(err) }
	assert result.len == 1, 'starts_when should flush previous group'

	// Verify flushed group has sum of first two events
	first := result[0]
	match first {
		event.LogEvent {
			val := first.get('count') or { panic('expected count') }
			assert event.value_to_string(val) == '3', 'flushed group sum should be 3'
		}
		else {
			assert false
		}
	}

	// The new group should still have the third event
	remaining := t.flush_all()
	assert remaining.len == 1
	second := remaining[0]
	match second {
		event.LogEvent {
			val := second.get('count') or { panic('expected count') }
			assert event.value_to_string(val) == '10', 'new group should start with 10'
		}
		else {
			assert false
		}
	}
}

// --- max_events with group_by ---

fn test_reduce_max_events_per_group() {
	mut opts := map[string]string{}
	opts['group_by'] = '.host'
	opts['max_events'] = '2'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('host', event.Value('A'))
	r1 := t.transform(event.Event(log1)) or { panic(err) }
	assert r1.len == 0

	mut log2 := event.new_log('b')
	log2.set('host', event.Value('B'))
	r2 := t.transform(event.Event(log2)) or { panic(err) }
	assert r2.len == 0

	// Second event for host A triggers flush for A
	mut log3 := event.new_log('c')
	log3.set('host', event.Value('A'))
	r3 := t.transform(event.Event(log3)) or { panic(err) }
	assert r3.len == 1, 'max_events=2 should flush group A after 2 events'

	// Host B still accumulating
	remaining := t.flush_all()
	assert remaining.len == 1, 'host B should still be in accumulator'
}

// --- multiple merge strategies on different fields ---

fn test_reduce_multiple_strategies_combined() {
	mut opts := map[string]string{}
	opts['merge_strategies.total'] = 'sum'
	opts['merge_strategies.name'] = 'discard'
	opts['merge_strategies.tags'] = 'array'
	opts['merge_strategies.level'] = 'retain'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('total', event.Value(10))
	log1.set('name', event.Value('first'))
	log1.set('tags', event.Value('t1'))
	log1.set('level', event.Value('info'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('total', event.Value(20))
	log2.set('name', event.Value('second'))
	log2.set('tags', event.Value('t2'))
	log2.set('level', event.Value('warn'))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			// sum
			total := first.get('total') or { panic('expected total') }
			assert event.value_to_string(total) == '30'

			// discard: keeps first
			name := first.get('name') or { panic('expected name') }
			assert event.value_to_string(name) == 'first'

			// retain: keeps last
			level := first.get('level') or { panic('expected level') }
			assert event.value_to_string(level) == 'warn'

			// array: collected values
			tags := first.get('tags') or { panic('expected tags') }
			match tags {
				[]event.Value {
					assert tags.len == 2
				}
				else {
					assert false, 'expected array for tags'
				}
			}
		}
		else {
			assert false
		}
	}
}

// --- default strategy is retain (no explicit merge_strategies) ---

fn test_reduce_default_strategy_is_retain() {
	mut opts := map[string]string{}
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('field', event.Value('old'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('field', event.Value('new'))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('field') or { panic('expected field') }
			assert event.value_to_string(val) == 'new', 'default strategy should be retain (last value wins)'
		}
		else {
			assert false
		}
	}
}

// --- min keeps existing when new value is larger ---

fn test_reduce_min_keeps_smaller() {
	mut opts := map[string]string{}
	opts['merge_strategies.val'] = 'min'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('val', event.Value(5))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('val', event.Value(10)) // larger, should be ignored
	t.transform(event.Event(log2)) or { panic(err) }

	mut log3 := event.new_log('c')
	log3.set('val', event.Value(3)) // smaller, should replace
	t.transform(event.Event(log3)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('val') or { panic('expected val') }
			assert event.value_to_string(val) == '3'
		}
		else {
			assert false
		}
	}
}

// --- max keeps existing when new value is smaller ---

fn test_reduce_max_keeps_larger() {
	mut opts := map[string]string{}
	opts['merge_strategies.val'] = 'max'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('val', event.Value(50))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('val', event.Value(10)) // smaller, should be ignored
	t.transform(event.Event(log2)) or { panic(err) }

	mut log3 := event.new_log('c')
	log3.set('val', event.Value(70)) // larger, should replace
	t.transform(event.Event(log3)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('val') or { panic('expected val') }
			assert event.value_to_string(val) == '70'
		}
		else {
			assert false
		}
	}
}

// --- longest_array does not replace with shorter ---

fn test_reduce_longest_array_keeps_longer() {
	mut opts := map[string]string{}
	opts['merge_strategies.items'] = 'longest_array'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('items', event.Value([event.Value('a'), event.Value('b'), event.Value('c')]))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('items', event.Value([event.Value('x')])) // shorter, should not replace
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('items') or { panic('expected items') }
			match val {
				[]event.Value {
					assert val.len == 3, 'longest_array should keep the 3-element array'
				}
				else {
					assert false, 'expected array'
				}
			}
		}
		else {
			assert false
		}
	}
}

// --- shortest_array does not replace with longer ---

fn test_reduce_shortest_array_keeps_shorter() {
	mut opts := map[string]string{}
	opts['merge_strategies.items'] = 'shortest_array'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('items', event.Value([event.Value('a')]))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('items', event.Value([event.Value('x'), event.Value('y'), event.Value('z')])) // longer
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('items') or { panic('expected items') }
			match val {
				[]event.Value {
					assert val.len == 1, 'shortest_array should keep the 1-element array'
				}
				else {
					assert false, 'expected array'
				}
			}
		}
		else {
			assert false
		}
	}
}

// --- flush_all on empty transform ---

fn test_reduce_flush_all_empty() {
	mut opts := map[string]string{}
	mut t := new_reduce(opts) or { panic(err) }
	flushed := t.flush_all()
	assert flushed.len == 0, 'flush_all on empty transform should return nothing'
}

// --- array strategy accumulates across many events ---

fn test_reduce_array_accumulates_many() {
	mut opts := map[string]string{}
	opts['merge_strategies.val'] = 'array'
	mut t := new_reduce(opts) or { panic(err) }

	for i in 0 .. 5 {
		mut log := event.new_log('${i}')
		log.set('val', event.Value('item${i}'))
		t.transform(event.Event(log)) or { panic(err) }
	}

	flushed := t.flush_all()
	assert flushed.len == 1
	first := flushed[0]
	match first {
		event.LogEvent {
			val := first.get('val') or { panic('expected val') }
			match val {
				[]event.Value {
					assert val.len == 5, 'array should collect all 5 values'
				}
				else {
					assert false, 'expected array'
				}
			}
		}
		else {
			assert false
		}
	}
}

// --- ends_when flushes mid-stream and allows new accumulation ---

fn test_reduce_ends_when_allows_new_group_after_flush() {
	mut opts := map[string]string{}
	opts['ends_when'] = '.done == "yes"'
	opts['merge_strategies.count'] = 'sum'
	mut t := new_reduce(opts) or { panic(err) }

	// First group
	mut log1 := event.new_log('a')
	log1.set('count', event.Value(1))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('count', event.Value(2))
	log2.set('done', event.Value('yes'))
	result1 := t.transform(event.Event(log2)) or { panic(err) }
	assert result1.len == 1, 'ends_when should flush first group'

	// Second group starts automatically
	mut log3 := event.new_log('c')
	log3.set('count', event.Value(10))
	t.transform(event.Event(log3)) or { panic(err) }

	remaining := t.flush_all()
	assert remaining.len == 1, 'second group should be in accumulator'
	second := remaining[0]
	match second {
		event.LogEvent {
			val := second.get('count') or { panic('expected count') }
			assert event.value_to_string(val) == '10', 'second group should have count=10'
		}
		else {
			assert false
		}
	}
}
