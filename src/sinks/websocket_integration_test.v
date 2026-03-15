module sinks

import event
import net
import time

fn test_websocket_sink_connect_and_send() {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0') or { return }
	addr := listener.addr() or {
		listener.close() or {}
		return
	}
	port := addr.port() or { return }

	// Accept connection and respond with WS upgrade
	spawn fn (mut listener net.TcpListener) {
		mut conn := listener.accept() or { return }
		conn.set_read_timeout(5 * time.second)

		// Read upgrade request
		mut buf := []u8{len: 4096}
		n := conn.read(mut buf) or {
			conn.close() or {}
			return
		}
		req := buf[..n].bytestr()
		if !req.contains('Upgrade: websocket') {
			conn.close() or {}
			return
		}

		// Send 101 Switching Protocols
		response := 'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n'
		conn.write(response.bytes()) or {
			conn.close() or {}
			return
		}

		// Read WebSocket frames
		for {
			mut frame_buf := []u8{len: 8192}
			conn.read(mut frame_buf) or { break }
		}
		conn.close() or {}
	}(mut listener)
	defer { listener.close() or {} }

	time.sleep(50 * time.millisecond)

	mut s := new_websocket({
		'uri': 'ws://127.0.0.1:${port}/ws'
	})!

	ev := event.Event(event.new_log('ws test message'))
	s.send(ev)!
	assert s.connected == true

	s.close()
	assert s.connected == false
}

fn test_websocket_sink_encode_all_types() {
	s := new_websocket({
		'uri': 'ws://localhost:9000/ws'
	})!

	// Log event — json
	log_ev := event.Event(event.new_log('test'))
	log_result := s.encode_event(log_ev)
	assert log_result.contains('"message"')

	// Metric event
	metric_ev := event.Event(event.Metric{
		name: 'test.metric'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{ value: 1.0 })
	})
	metric_result := s.encode_event(metric_ev)
	assert metric_result.contains('test.metric')

	// Trace event
	trace_ev := event.Event(event.TraceEvent{})
	trace_result := s.encode_event(trace_ev)
	assert trace_result.len > 0
}

fn test_build_ws_frame_large() {
	// Test frame > 65535 bytes which uses 8-byte length encoding
	payload := 'A'.repeat(70000)
	frame := build_ws_frame(payload)
	assert frame[0] == 0x81
	assert frame[1] == u8(0x80 | 127)
	// 2 header + 8 ext length + 4 mask + 70000 payload
	assert frame.len == 2 + 8 + 4 + 70000
}
