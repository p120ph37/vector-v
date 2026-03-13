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
