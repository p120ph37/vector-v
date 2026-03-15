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

fn test_vector_flush_empty() {
	mut s := new_vector(map[string]string{})
	// Flush with empty buffer should be a no-op
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_vector_close() {
	mut s := new_vector(map[string]string{})
	assert s.connected == false
	s.close()
	assert s.connected == false
}

fn test_vector_send_no_connection() {
	mut s := new_vector({
		'address':          '127.0.0.1:19999'
		'batch.max_events': '1'
	})
	ev := event.Event(event.new_log('test'))
	s.send(ev) or {
		assert err.msg().contains('connection failed')
		return
	}
	// Connection to non-listening port should fail on flush
}

fn test_vector_write_data_not_connected() {
	mut s := new_vector(map[string]string{})
	s.write_data('test') or {
		assert err.msg().contains('not connected')
		return
	}
	assert false, 'expected error for write when not connected'
}

fn test_vector_multiple_buffers() {
	mut s := new_vector({
		'batch.max_events': '10000'
	})
	for i in 0 .. 10 {
		ev := event.Event(event.new_log('event ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 10
}
