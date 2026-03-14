module transforms

import event

fn test_build_transform_filter() {
	t := build_transform('filter', {
		'condition': '.level == "error"'
	}) or { panic(err) }
	assert t is FilterTransform
}

fn test_build_transform_reduce() {
	t := build_transform('reduce', map[string]string{}) or { panic(err) }
	assert t is ReduceTransform
}

fn test_build_transform_unknown_errors() {
	if _ := build_transform('nonexistent', map[string]string{}) {
		assert false, 'expected error for unknown transform type'
	}
}

fn test_apply_transform_filter() {
	mut t := build_transform('filter', {
		'condition': '.level == "error"'
	}) or { panic(err) }

	mut log := event.new_log('test')
	log.set('level', event.Value('error'))
	ev := event.Event(log)

	result := apply_transform(mut t, ev) or { panic(err) }
	assert result.len == 1
}

fn test_apply_transform_filter_drops() {
	mut t := build_transform('filter', {
		'condition': '.level == "error"'
	}) or { panic(err) }

	mut log := event.new_log('test')
	log.set('level', event.Value('info'))
	ev := event.Event(log)

	result := apply_transform(mut t, ev) or { panic(err) }
	assert result.len == 0
}

fn test_apply_transform_reduce() {
	mut t := build_transform('reduce', map[string]string{}) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := apply_transform(mut t, ev) or { panic(err) }
	// Reduce accumulates, so first event is not emitted
	assert result.len == 0
}

fn test_build_transform_dedupe() {
	t := build_transform('dedupe', map[string]string{}) or { panic(err) }
	assert t is DedupeTransform
}

fn test_build_transform_sample() {
	t := build_transform('sample', {
		'rate': '10'
	}) or { panic(err) }
	assert t is SampleTransform
}

fn test_build_transform_throttle() {
	t := build_transform('throttle', {
		'threshold': '5'
	}) or { panic(err) }
	assert t is ThrottleTransform
}

fn test_build_transform_exclusive_route() {
	t := build_transform('exclusive_route', {
		'routes.errors.condition': '.level == "error"'
	}) or { panic(err) }
	assert t is ExclusiveRouteTransform
}

fn test_build_transform_remap() {
	t := build_transform('remap', {
		'source': '.env = "prod"'
	}) or { panic(err) }
	assert t is RemapTransform
}

fn test_apply_transform_dedupe() {
	mut t := build_transform('dedupe', {
		'fields.match': '.message'
	}) or { panic(err) }

	ev := event.Event(event.new_log('hello'))
	result := apply_transform(mut t, ev) or { panic(err) }
	assert result.len == 1, 'first event should pass through dedupe'

	// Duplicate should be dropped
	ev2 := event.Event(event.new_log('hello'))
	result2 := apply_transform(mut t, ev2) or { panic(err) }
	assert result2.len == 0, 'duplicate should be dropped by dedupe'
}

fn test_apply_transform_sample() {
	mut t := build_transform('sample', {
		'rate': '1'
	}) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := apply_transform(mut t, ev) or { panic(err) }
	assert result.len == 1, 'rate=1 should pass all events'
}

fn test_apply_transform_throttle() {
	mut t := build_transform('throttle', {
		'threshold': '1'
		'window_secs': '60'
	}) or { panic(err) }

	ev1 := event.Event(event.new_log('first'))
	result1 := apply_transform(mut t, ev1) or { panic(err) }
	assert result1.len == 1, 'first event should pass throttle'

	ev2 := event.Event(event.new_log('second'))
	result2 := apply_transform(mut t, ev2) or { panic(err) }
	assert result2.len == 0, 'second event should be throttled'
}

fn test_apply_transform_exclusive_route() {
	mut t := build_transform('exclusive_route', {
		'routes.errors.condition': '.level == "error"'
	}) or { panic(err) }

	mut log := event.new_log('test')
	log.set('level', event.Value('error'))
	ev := event.Event(log)

	result := apply_transform(mut t, ev) or { panic(err) }
	assert result.len == 1
}

fn test_apply_transform_remap() {
	mut t := build_transform('remap', {
		'source': '.env = "prod"'
	}) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := apply_transform(mut t, ev) or { panic(err) }
	assert result.len == 1
}
