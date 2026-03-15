module sinks

import event

fn test_new_vector_defaults() {
	s := new_vector(map[string]string{})
	assert s.address == '127.0.0.1:6000'
	assert s.batch_max == 100
	assert s.connected == false
}

fn test_new_vector_custom_address() {
	s := new_vector({
		'address': '10.0.0.1:9000'
	})
	assert s.address == '10.0.0.1:9000'
}

fn test_new_vector_custom_batch() {
	s := new_vector({
		'batch.max_events': '50'
	})
	assert s.batch_max == 50
}

fn test_new_vector_invalid_batch() {
	s := new_vector({
		'batch.max_events': '-1'
	})
	assert s.batch_max == 100
}

fn test_vector_buffering() {
	mut s := new_vector({
		'batch.max_events': '1000'
	})

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_vector_not_connected() {
	s := new_vector(map[string]string{})
	assert s.connected == false
}

fn test_vector_custom_timeout() {
	s := new_vector({
		'batch.timeout_secs': '5'
	})
	assert s.batch_timeout > 0
}

fn test_vector_invalid_timeout() {
	s := new_vector({
		'batch.timeout_secs': '-1'
	})
	assert s.batch_timeout > 0 // falls back to default
}
