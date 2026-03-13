module transforms

import event

fn test_reduce_merge_strategy_sum() {
	mut opts := map[string]string{}
	opts['merge_strategies.count'] = 'sum'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('count', event.Value(10))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('count', event.Value(20))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	match flushed[0] {
		event.LogEvent {
			val := flushed[0].get('count') or { panic('expected count') }
			assert event.value_to_string(val) == '30'
		}
		else {
			assert false
		}
	}
}

fn test_reduce_merge_strategy_min() {
	mut opts := map[string]string{}
	opts['merge_strategies.val'] = 'min'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('val', event.Value(50))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('val', event.Value(10))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	match flushed[0] {
		event.LogEvent {
			val := flushed[0].get('val') or { panic('expected val') }
			assert event.value_to_string(val) == '10'
		}
		else {
			assert false
		}
	}
}

fn test_reduce_merge_strategy_max() {
	mut opts := map[string]string{}
	opts['merge_strategies.val'] = 'max'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('val', event.Value(50))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('val', event.Value(100))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	match flushed[0] {
		event.LogEvent {
			val := flushed[0].get('val') or { panic('expected val') }
			assert event.value_to_string(val) == '100'
		}
		else {
			assert false
		}
	}
}

fn test_reduce_merge_strategy_concat() {
	mut opts := map[string]string{}
	opts['merge_strategies.msg'] = 'concat'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('msg', event.Value('hello'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('msg', event.Value('world'))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
	match flushed[0] {
		event.LogEvent {
			val := flushed[0].get('msg') or { panic('expected msg') }
			s := event.value_to_string(val)
			assert s.contains('hello')
			assert s.contains('world')
		}
		else {
			assert false
		}
	}
}

fn test_reduce_merge_strategy_array() {
	mut opts := map[string]string{}
	opts['merge_strategies.tag'] = 'array'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('a')
	log1.set('tag', event.Value('t1'))
	t.transform(event.Event(log1)) or { panic(err) }

	mut log2 := event.new_log('b')
	log2.set('tag', event.Value('t2'))
	t.transform(event.Event(log2)) or { panic(err) }

	flushed := t.flush_all()
	assert flushed.len == 1
}

fn test_reduce_max_events() {
	mut opts := map[string]string{}
	opts['max_events'] = '2'
	mut t := new_reduce(opts) or { panic(err) }

	ev1 := event.Event(event.new_log('a'))
	result1 := t.transform(ev1) or { panic(err) }
	assert result1.len == 0

	ev2 := event.Event(event.new_log('b'))
	result2 := t.transform(ev2) or { panic(err) }
	// max_events=2, so after 2nd event the group should be flushed
	assert result2.len == 1
}

fn test_reduce_starts_when() {
	mut opts := map[string]string{}
	opts['starts_when'] = '.type == "start"'
	mut t := new_reduce(opts) or { panic(err) }

	mut log1 := event.new_log('first')
	log1.set('type', event.Value('start'))
	t.transform(event.Event(log1)) or { panic(err) }

	// Accumulate more
	ev2 := event.Event(event.new_log('middle'))
	t.transform(ev2) or { panic(err) }

	// New start should flush previous group
	mut log3 := event.new_log('second start')
	log3.set('type', event.Value('start'))
	result := t.transform(event.Event(log3)) or { panic(err) }
	assert result.len == 1 // flushed the first group
}

fn test_parse_merge_strategy_all() {
	assert parse_merge_strategy('discard') == MergeStrategy.discard
	assert parse_merge_strategy('retain') == MergeStrategy.retain
	assert parse_merge_strategy('array') == MergeStrategy.array_
	assert parse_merge_strategy('concat') == MergeStrategy.concat
	assert parse_merge_strategy('concat_newline') == MergeStrategy.concat_newline
	assert parse_merge_strategy('concat_raw') == MergeStrategy.concat_raw
	assert parse_merge_strategy('sum') == MergeStrategy.sum
	assert parse_merge_strategy('max') == MergeStrategy.max
	assert parse_merge_strategy('min') == MergeStrategy.min
	assert parse_merge_strategy('flat_unique') == MergeStrategy.flat_unique
	assert parse_merge_strategy('shortest_array') == MergeStrategy.shortest_array
	assert parse_merge_strategy('longest_array') == MergeStrategy.longest_array
	assert parse_merge_strategy('unknown') == MergeStrategy.retain
}

fn test_value_to_f64_int() {
	v := event.Value(42)
	assert value_to_f64(v) == 42.0
}

fn test_value_to_f64_float() {
	v := event.Value(event.Float(3.14))
	assert value_to_f64(v) == 3.14
}

fn test_value_to_f64_string() {
	v := event.Value('99.5')
	assert value_to_f64(v) == 99.5
}

fn test_value_to_f64_other() {
	v := event.Value(true)
	assert value_to_f64(v) == 0.0
}

fn test_reduce_compute_group_key_default() {
	mut opts := map[string]string{}
	t := new_reduce(opts) or { panic(err) }
	log := event.new_log('test')
	key := t.compute_group_key(log)
	assert key == '_default_'
}

fn test_reduce_compute_group_key_with_fields() {
	mut opts := map[string]string{}
	opts['group_by'] = '.host,.env'
	t := new_reduce(opts) or { panic(err) }

	mut log := event.new_log('test')
	log.set('host', event.Value('server1'))
	log.set('env', event.Value('prod'))
	key := t.compute_group_key(log)
	assert key == 'server1|prod'
}

fn test_reduce_check_condition_eq() {
	t := new_reduce(map[string]string{}) or { panic(err) }
	mut log := event.new_log('test')
	log.set('level', event.Value('error'))
	assert t.check_condition('.level == "error"', log) == true
	assert t.check_condition('.level == "info"', log) == false
}

fn test_reduce_check_condition_neq() {
	t := new_reduce(map[string]string{}) or { panic(err) }
	mut log := event.new_log('test')
	log.set('level', event.Value('error'))
	assert t.check_condition('.level != "info"', log) == true
	assert t.check_condition('.level != "error"', log) == false
}
