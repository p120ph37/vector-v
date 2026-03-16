module sinks

import event

fn test_websocket_wss_default_port() {
	u := parse_ws_uri('wss://secure.example.com/ws')!
	assert u.host == 'secure.example.com'
	assert u.port == 80 // Default port when not specified
	assert u.path == '/ws'
}

fn test_websocket_empty_host_error() {
	parse_ws_uri('ws://:9000/ws') or {
		assert err.msg().contains('empty host')
		return
	}
	assert false, 'expected error for empty host'
}

fn test_websocket_invalid_port_error() {
	parse_ws_uri('ws://host:notaport/ws') or {
		assert err.msg().contains('invalid port')
		return
	}
	assert false, 'expected error for invalid port'
}

fn test_build_ws_frame_large() {
	// 70000 bytes — should use 8-byte extended length
	payload := 'x'.repeat(70000)
	frame := build_ws_frame(payload)
	assert frame[0] == 0x81
	assert frame[1] == u8(0x80 | 127)
	// 2 bytes opcode+len + 8 bytes extended len + 4 bytes mask + 70000 bytes payload
	assert frame.len == 10 + 4 + 70000
}

fn test_build_ws_frame_exact_126() {
	payload := 'x'.repeat(126)
	frame := build_ws_frame(payload)
	assert frame[0] == 0x81
	// 126 bytes requires 2-byte extended length
	assert frame[1] == u8(0x80 | 126)
	assert frame.len == 4 + 4 + 126
}

fn test_build_ws_frame_125() {
	payload := 'x'.repeat(125)
	frame := build_ws_frame(payload)
	assert frame[0] == 0x81
	assert frame[1] == u8(0x80 | 125)
	assert frame.len == 2 + 4 + 125
}

fn test_websocket_encode_log_json_contains_fields() {
	s := new_websocket({
		'uri': 'ws://localhost:9000/ws'
	})!
	mut log := event.new_log('test')
	log.set('host', 'server1')
	result := s.encode_event(event.Event(log))
	assert result.contains('"message"')
}

fn test_websocket_encode_trace_fields() {
	s := new_websocket({
		'uri': 'ws://localhost:9000/ws'
	})!
	trace := event.TraceEvent{
		fields: {'key': 'value', 'service': 'test'}
	}
	result := s.encode_event(event.Event(trace))
	assert result.len > 0
}

fn test_websocket_parse_ws_uri_with_query() {
	u := parse_ws_uri('ws://localhost:9000/ws?auth=token')!
	assert u.host == 'localhost'
	assert u.port == 9000
	assert u.path == '/ws?auth=token'
}

fn test_websocket_parse_ws_uri_root() {
	u := parse_ws_uri('ws://localhost:9000')!
	assert u.host == 'localhost'
	assert u.port == 9000
	assert u.path == '/'
}

fn test_websocket_codec_default() {
	s := new_websocket({
		'uri':            'ws://localhost:9000/ws'
		'encoding.codec': 'unknown'
	})!
	assert s.codec == .json_codec
}

fn test_websocket_close_not_connected() {
	mut s := new_websocket({
		'uri': 'ws://localhost:9000/ws'
	})!
	assert !s.connected
	s.close()
	assert !s.connected
	assert s.tcp_fd == -1
}

fn test_websocket_encode_metric_text_codec() {
	s := new_websocket({
		'uri':            'ws://localhost:9000/ws'
		'encoding.codec': 'text'
	})!
	m := event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.GaugeValue{value: 50.0}
	}
	result := s.encode_event(event.Event(m))
	// Metrics always use JSON encoding regardless of codec
	assert result.len > 0
}

fn test_build_ws_frame_unmask_medium() {
	payload := 'x'.repeat(200)
	frame := build_ws_frame(payload)

	// Extract mask and masked data for medium frame
	mask_offset := 4 // 2 header + 2 extended len
	mask := frame[mask_offset..mask_offset + 4]
	data := frame[mask_offset + 4..]

	mut unmasked := []u8{}
	for i, b in data {
		unmasked << b ^ mask[i % 4]
	}
	assert unmasked.bytestr() == payload
}

fn test_websocket_ping_interval_default() {
	s := new_websocket({
		'uri': 'ws://localhost:9000/ws'
	})!
	// Default 30 seconds
	assert s.ping_interval == 30_000_000_000
}

fn test_websocket_ping_interval_zero() {
	s := new_websocket({
		'uri':                 'ws://localhost:9000/ws'
		'ping_interval_secs': '0'
	})!
	assert s.ping_interval > 0
}
