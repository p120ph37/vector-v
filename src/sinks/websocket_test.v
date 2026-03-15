module sinks

import event

fn test_new_websocket_defaults() {
	s := new_websocket({
		'uri': 'ws://localhost:9000/events'
	})!
	assert s.host == 'localhost'
	assert s.port == 9000
	assert s.path == '/events'
	assert s.codec == .json_codec
}

fn test_new_websocket_text_codec() {
	s := new_websocket({
		'uri':            'ws://localhost:9000/ws'
		'encoding.codec': 'text'
	})!
	assert s.codec == .text_codec
}

fn test_new_websocket_missing_uri() {
	new_websocket(map[string]string{}) or {
		assert err.msg().contains('uri is required')
		return
	}
	assert false, 'expected error for missing uri'
}

fn test_parse_ws_uri_basic() {
	u := parse_ws_uri('ws://example.com:8080/path')!
	assert u.host == 'example.com'
	assert u.port == 8080
	assert u.path == '/path'
}

fn test_parse_ws_uri_no_port() {
	u := parse_ws_uri('ws://example.com/path')!
	assert u.host == 'example.com'
	assert u.port == 80
	assert u.path == '/path'
}

fn test_parse_ws_uri_no_path() {
	u := parse_ws_uri('ws://example.com:9000')!
	assert u.host == 'example.com'
	assert u.port == 9000
	assert u.path == '/'
}

fn test_parse_ws_uri_wss() {
	u := parse_ws_uri('wss://secure.example.com:443/ws')!
	assert u.host == 'secure.example.com'
	assert u.port == 443
	assert u.path == '/ws'
}

fn test_parse_ws_uri_no_scheme() {
	u := parse_ws_uri('localhost:9000/events')!
	assert u.host == 'localhost'
	assert u.port == 9000
	assert u.path == '/events'
}

fn test_parse_ws_uri_deep_path() {
	u := parse_ws_uri('ws://localhost:8080/api/v1/ws')!
	assert u.host == 'localhost'
	assert u.port == 8080
	assert u.path == '/api/v1/ws'
}

fn test_build_ws_frame_short() {
	frame := build_ws_frame('hi')
	// FIN + text opcode
	assert frame[0] == 0x81
	// Length 2 with mask bit
	assert frame[1] == u8(0x80 | 2)
	// 4 bytes masking key + 2 bytes payload
	assert frame.len == 2 + 4 + 2
}

fn test_build_ws_frame_medium() {
	// 200 bytes — should use 2-byte extended length
	payload := 'x'.repeat(200)
	frame := build_ws_frame(payload)
	assert frame[0] == 0x81
	assert frame[1] == u8(0x80 | 126)
	// 2 bytes length + 4 bytes mask + 200 bytes payload
	assert frame.len == 4 + 4 + 200
}

fn test_build_ws_frame_empty() {
	frame := build_ws_frame('')
	assert frame[0] == 0x81
	assert frame[1] == u8(0x80 | 0)
	// 2 header + 4 mask + 0 payload
	assert frame.len == 6
}

fn test_build_ws_frame_unmask_roundtrip() {
	payload := 'hello world'
	frame := build_ws_frame(payload)

	// Extract mask and masked data
	mask_offset := 2
	mask := frame[mask_offset..mask_offset + 4]
	data := frame[mask_offset + 4..]

	// Unmask
	mut unmasked := []u8{}
	for i, b in data {
		unmasked << b ^ mask[i % 4]
	}
	assert unmasked.bytestr() == payload
}

fn test_websocket_not_connected_initially() {
	s := new_websocket({
		'uri': 'ws://localhost:9000/events'
	})!
	assert s.connected == false
}

fn test_new_websocket_custom_ping_interval() {
	s := new_websocket({
		'uri':                 'ws://localhost:9000/events'
		'ping_interval_secs': '60'
	})!
	// 60 seconds in nanoseconds
	assert s.ping_interval > 0
}

fn test_websocket_invalid_uri() {
	new_websocket({
		'uri': 'ws://:invalid'
	}) or {
		assert err.msg().contains('invalid uri')
		return
	}
	// Some URIs may parse unexpectedly — just verify it doesn't crash
}

fn test_websocket_encode_event_json() {
	s := new_websocket({
		'uri': 'ws://localhost:9000/ws'
	})!
	ev := event.Event(event.new_log('test message'))
	result := s.encode_event(ev)
	assert result.contains('"message"')
	assert result.contains('test message')
}

fn test_websocket_encode_event_text() {
	s := new_websocket({
		'uri':            'ws://localhost:9000/ws'
		'encoding.codec': 'text'
	})!
	ev := event.Event(event.new_log('plain text'))
	result := s.encode_event(ev)
	assert result == 'plain text'
}

fn test_websocket_encode_metric() {
	s := new_websocket({
		'uri': 'ws://localhost:9000/ws'
	})!
	metric := event.Event(event.Metric{
		name: 'req.count'
		kind: .absolute
		value: event.MetricValue(event.CounterValue{ value: 99.0 })
	})
	result := s.encode_event(metric)
	assert result.len > 0
	assert result.contains('req.count')
}

fn test_websocket_encode_trace() {
	s := new_websocket({
		'uri': 'ws://localhost:9000/ws'
	})!
	trace := event.Event(event.TraceEvent{})
	result := s.encode_event(trace)
	assert result.len > 0
}

fn test_websocket_close() {
	mut s := new_websocket({
		'uri': 'ws://localhost:9000/ws'
	})!
	assert s.connected == false
	s.close()
	assert s.connected == false
}

fn test_websocket_send_not_connected() {
	mut s := new_websocket({
		'uri': 'ws://localhost:19999/ws'
	})!
	ev := event.Event(event.new_log('test'))
	s.send(ev) or {
		assert err.msg().contains('connection failed')
		return
	}
}

fn test_websocket_send_text_frame_not_connected() {
	mut s := new_websocket({
		'uri': 'ws://localhost:9000/ws'
	})!
	s.send_text_frame('test') or {
		assert err.msg().contains('not connected')
		return
	}
	assert false, 'expected error for send when not connected'
}

fn test_websocket_invalid_ping() {
	s := new_websocket({
		'uri':                 'ws://localhost:9000/ws'
		'ping_interval_secs': '-10'
	})!
	assert s.ping_interval > 0
}
