module sinks

import event
import mockserver

// Integration tests for VectorSink using mockserver TCP server.

fn test_vector_sink_flush_to_mock() {
	mut mock := mockserver.start_tcp_with_config(mockserver.TcpServerConfig{
		close_after_read: true
	})!
	defer { mock.stop() }

	mut s := new_vector({
		'address':          mock.address()
		'batch.max_events': '1000'
	})

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('vector msg ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 3

	s.flush()!
	assert s.total_buffered() == 0
	s.close()

	msgs := mock.wait_for_messages(1, 5000)
	assert msgs.len >= 1
	data := mock.all_data()
	assert data.contains('vector msg 0')
	assert data.contains('vector msg 1')
	assert data.contains('vector msg 2')

	// Data should be newline-delimited JSON
	lines := data.trim_right('\n').split('\n')
	assert lines.len == 3
}

fn test_vector_sink_auto_flush_mock() {
	mut mock := mockserver.start_tcp_with_config(mockserver.TcpServerConfig{
		close_after_read: true
	})!
	defer { mock.stop() }

	mut s := new_vector({
		'address':          mock.address()
		'batch.max_events': '2'
	})

	ev1 := event.Event(event.new_log('batch1'))
	ev2 := event.Event(event.new_log('batch2'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	// Should have auto-flushed
	assert s.total_buffered() == 0
	s.close()

	msgs := mock.wait_for_messages(1, 5000)
	assert msgs.len >= 1
}

fn test_vector_sink_connection_refused() {
	mut s := new_vector({
		'address':          '127.0.0.1:1'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('will fail'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('connection failed') || err.msg().contains('connect')
		return
	}
	s.close()
}

fn test_vector_sink_newline_delimited_json() {
	mut mock := mockserver.start_tcp_with_config(mockserver.TcpServerConfig{
		close_after_read: true
	})!
	defer { mock.stop() }

	mut s := new_vector({
		'address':          mock.address()
		'batch.max_events': '1000'
	})

	// Send events with special characters
	mut log1 := event.new_log('line with "quotes"')
	log1.set('key', event.Value('value'))
	s.send(event.Event(log1)) or {}

	s.flush()!
	s.close()

	msgs := mock.wait_for_messages(1, 5000)
	assert msgs.len >= 1
	data := mock.all_data()
	// Each event should end with newline
	assert data.ends_with('\n')
	// Should be valid JSON-ish
	assert data.contains('"message"')
}

fn test_vector_sink_empty_flush_noop() {
	mut mock := mockserver.start_tcp()!
	defer { mock.stop() }

	mut s := new_vector({
		'address':          mock.address()
		'batch.max_events': '1000'
	})

	// Flushing with no buffered data should be a no-op
	s.flush()!
	assert s.total_buffered() == 0

	// No messages should be captured
	assert mock.message_count() == 0

	s.close()
}
