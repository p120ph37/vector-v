module sinks

import event

fn test_new_blackhole() {
	s := new_blackhole(map[string]string{})
	assert s.count == 0
}

fn test_blackhole_send_increments_count() {
	mut s := new_blackhole(map[string]string{})
	ev := event.Event(event.new_log('test'))
	s.send(ev) or { panic(err) }
	assert s.count == 1
	s.send(ev) or { panic(err) }
	assert s.count == 2
}

fn test_blackhole_send_multiple() {
	mut s := new_blackhole(map[string]string{})
	for i in 0 .. 100 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or { panic(err) }
	}
	assert s.count == 100
}

fn test_blackhole_ignores_options() {
	s := new_blackhole({
		'anything': 'value'
		'other':    'option'
	})
	assert s.count == 0
}
