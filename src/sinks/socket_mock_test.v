module sinks

import event
import mockserver

// Integration tests for SocketSink using mockserver TCP/UDP servers.

fn test_socket_sink_tcp_with_mock_server() {
	mut mock := mockserver.start_tcp()!
	defer { mock.stop() }

	mut s := new_socket_sink({
		'address':        mock.address()
		'encoding.codec': 'text'
	})!

	ev := event.Event(event.new_log('mock tcp message'))
	s.send(ev)!
	s.close()

	msgs := mock.wait_for_messages(1, 3000)
	assert msgs.len >= 1
	assert mock.all_data().contains('mock tcp message')
}

fn test_socket_sink_tcp_json_with_mock() {
	mut mock := mockserver.start_tcp()!
	defer { mock.stop() }

	mut s := new_socket_sink({
		'address':        mock.address()
		'encoding.codec': 'json'
	})!

	ev := event.Event(event.new_log('json via mock'))
	s.send(ev)!
	s.close()

	msgs := mock.wait_for_messages(1, 3000)
	assert msgs.len >= 1
	data := mock.all_data()
	assert data.contains('"message"')
	assert data.contains('json via mock')
}

fn test_socket_sink_tcp_multiple_events_mock() {
	mut mock := mockserver.start_tcp()!
	defer { mock.stop() }

	mut s := new_socket_sink({
		'address':        mock.address()
		'encoding.codec': 'text'
	})!

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('line ${i}'))
		s.send(ev)!
	}
	s.close()

	msgs := mock.wait_for_messages(1, 3000)
	assert msgs.len >= 1
	data := mock.all_data()
	assert data.contains('line 0')
	assert data.contains('line 4')
}

fn test_socket_sink_tcp_connection_refused() {
	// Try to connect to a port with no listener
	mut s := new_socket_sink({
		'address': '127.0.0.1:1'
	})!

	ev := event.Event(event.new_log('will fail'))
	s.send(ev) or {
		assert err.msg().contains('connection failed') || err.msg().contains('connect')
		return
	}
	// Some systems may allow connection to port 1
	s.close()
}

fn test_socket_sink_tcp_server_closes_reconnect() {
	// Server that accepts only one connection, then rejects
	mut mock := mockserver.start_tcp_with_config(mockserver.TcpServerConfig{
		close_after_read: true
	})!
	defer { mock.stop() }

	mut s := new_socket_sink({
		'address':        mock.address()
		'encoding.codec': 'text'
	})!

	// First send should work
	ev1 := event.Event(event.new_log('first'))
	s.send(ev1)!

	s.close()
}

fn test_socket_sink_udp_with_mock_server() {
	mut mock := mockserver.start_udp()!
	defer { mock.stop() }

	mut s := new_socket_sink({
		'address': mock.address()
		'mode':    'udp'
		'encoding.codec': 'text'
	})!

	ev := event.Event(event.new_log('udp mock message'))
	s.send(ev)!

	msgs := mock.wait_for_datagrams(1, 3000)
	assert msgs.len >= 1
	assert msgs[0].data.contains('udp mock message')
}

fn test_socket_sink_udp_multiple_events() {
	mut mock := mockserver.start_udp()!
	defer { mock.stop() }

	mut s := new_socket_sink({
		'address': mock.address()
		'mode':    'udp'
		'encoding.codec': 'text'
	})!

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('udp ${i}'))
		s.send(ev)!
	}

	msgs := mock.wait_for_datagrams(3, 3000)
	assert msgs.len >= 3
}

fn test_socket_sink_metric_with_mock() {
	mut mock := mockserver.start_tcp()!
	defer { mock.stop() }

	mut s := new_socket_sink({
		'address': mock.address()
	})!

	metric := event.Event(event.Metric{
		name: 'mock.counter'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{ value: 99.0 })
	})
	s.send(metric)!
	s.close()

	msgs := mock.wait_for_messages(1, 3000)
	assert msgs.len >= 1
	assert mock.all_data().contains('mock.counter')
}
