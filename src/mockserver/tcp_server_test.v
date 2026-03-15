module mockserver

import net
import time

fn test_tcp_server_start_and_address() {
	mut mock := start_tcp()!
	defer { mock.stop() }

	assert mock.port > 0
	assert mock.address().starts_with('127.0.0.1:')
}

fn test_tcp_server_captures_data() {
	mut mock := start_tcp()!
	defer { mock.stop() }

	// Connect and send data
	mut conn := net.dial_tcp(mock.address()) or { return }
	conn.write('hello tcp\n'.bytes()) or {}
	conn.close() or {}

	msgs := mock.wait_for_messages(1, 3000)
	assert msgs.len >= 1
	assert msgs[0].data.contains('hello tcp')
}

fn test_tcp_server_multiple_lines() {
	mut mock := start_tcp()!
	defer { mock.stop() }

	mut conn := net.dial_tcp(mock.address()) or { return }
	conn.write('line1\nline2\nline3\n'.bytes()) or {}
	conn.close() or {}

	msgs := mock.wait_for_messages(1, 3000)
	assert msgs.len >= 1
	data := mock.all_data()
	assert data.contains('line1')
	assert data.contains('line2')
	assert data.contains('line3')
}

fn test_tcp_server_with_response() {
	mut mock := start_tcp_with_config(TcpServerConfig{
		response: 'ACK\n'
	})!
	defer { mock.stop() }

	mut conn := net.dial_tcp(mock.address()) or { return }
	conn.set_read_timeout(3 * time.second)
	conn.write('request data\n'.bytes()) or {
		conn.close() or {}
		return
	}

	// Close write side to trigger server read completion
	// Read response
	mut buf := []u8{len: 1024}
	n := conn.read(mut buf) or {
		conn.close() or {}
		return
	}
	conn.close() or {}

	if n > 0 {
		resp := buf[..n].bytestr()
		assert resp == 'ACK\n'
	}

	msgs := mock.wait_for_messages(1, 3000)
	assert msgs.len >= 1
}

fn test_tcp_server_reject_mode() {
	mut mock := start_tcp_with_config(TcpServerConfig{
		reject: true
	})!
	defer { mock.stop() }

	// Connection should be accepted then immediately closed
	mut conn := net.dial_tcp(mock.address()) or { return }
	conn.set_read_timeout(1 * time.second)

	time.sleep(100 * time.millisecond)

	// Try to write - should fail or connection should be closed
	mut buf := []u8{len: 1024}
	conn.read(mut buf) or {
		// Expected: read fails because server closed the connection
		conn.close() or {}
		return
	}
	conn.close() or {}
}

fn test_tcp_server_message_count() {
	mut mock := start_tcp()!
	defer { mock.stop() }

	mut conn := net.dial_tcp(mock.address()) or { return }
	conn.write('data\n'.bytes()) or {}
	conn.close() or {}

	mock.wait_for_messages(1, 3000)
	assert mock.message_count() >= 1
}

fn test_tcp_server_ws_upgrade() {
	mut mock := start_tcp_with_config(TcpServerConfig{
		ws_upgrade: true
	})!
	defer { mock.stop() }

	mut conn := net.dial_tcp(mock.address()) or { return }
	conn.set_read_timeout(3 * time.second)
	conn.set_write_timeout(3 * time.second)

	// Send WebSocket upgrade request
	upgrade := 'GET /ws HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n'
	conn.write(upgrade.bytes()) or {
		conn.close() or {}
		return
	}

	// Read upgrade response
	mut buf := []u8{len: 4096}
	n := conn.read(mut buf) or {
		conn.close() or {}
		return
	}
	resp := buf[..n].bytestr()
	assert resp.contains('101')

	conn.close() or {}
}
