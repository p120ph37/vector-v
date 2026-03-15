module sinks

import event
import mockserver

// Integration tests for WebSocketSink using mockserver TCP server with WS upgrade.

fn test_websocket_sink_send_via_mock() {
	mut mock := mockserver.start_tcp_with_config(mockserver.TcpServerConfig{
		ws_upgrade: true
	})!
	defer { mock.stop() }

	mut s := new_websocket({
		'uri': 'ws://127.0.0.1:${mock.port}/ws'
	})!

	ev := event.Event(event.new_log('ws mock message'))
	s.send(ev)!
	assert s.connected == true

	// Wait for the frame data to be captured
	msgs := mock.wait_for_messages(1, 3000)
	assert msgs.len >= 1
	// The captured data should contain the message (decoded from WS frame)
	assert msgs[0].data.contains('ws mock message')

	s.close()
	assert s.connected == false
}

fn test_websocket_sink_multiple_events_mock() {
	mut mock := mockserver.start_tcp_with_config(mockserver.TcpServerConfig{
		ws_upgrade: true
	})!
	defer { mock.stop() }

	mut s := new_websocket({
		'uri': 'ws://127.0.0.1:${mock.port}/events'
	})!

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('ws msg ${i}'))
		s.send(ev)!
	}

	msgs := mock.wait_for_messages(3, 3000)
	assert msgs.len >= 3

	mut found := [false, false, false]
	for m in msgs {
		if m.data.contains('ws msg 0') { found[0] = true }
		if m.data.contains('ws msg 1') { found[1] = true }
		if m.data.contains('ws msg 2') { found[2] = true }
	}
	assert found[0]
	assert found[1]
	assert found[2]

	s.close()
}

fn test_websocket_sink_text_codec_mock() {
	mut mock := mockserver.start_tcp_with_config(mockserver.TcpServerConfig{
		ws_upgrade: true
	})!
	defer { mock.stop() }

	mut s := new_websocket({
		'uri':            'ws://127.0.0.1:${mock.port}/ws'
		'encoding.codec': 'text'
	})!

	ev := event.Event(event.new_log('plain text ws'))
	s.send(ev)!

	msgs := mock.wait_for_messages(1, 3000)
	assert msgs.len >= 1
	// Text codec should send just the message, not JSON
	assert msgs[0].data.contains('plain text ws')
	assert !msgs[0].data.contains('"message"')

	s.close()
}

fn test_websocket_sink_connection_refused() {
	mut s := new_websocket({
		'uri': 'ws://127.0.0.1:1/ws'
	})!

	ev := event.Event(event.new_log('no server'))
	s.send(ev) or {
		assert err.msg().contains('connection failed') || err.msg().contains('connect')
		return
	}
	s.close()
}
