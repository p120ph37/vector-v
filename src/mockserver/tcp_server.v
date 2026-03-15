module mockserver

import net
import time

// MockTcpServer provides a TCP socket mock server for testing socket-based
// components (SocketSink, VectorSink, SocketSource, VectorSource).
//
// Usage:
//   mut mock := mockserver.start_tcp()!
//   defer { mock.stop() }
//
//   // Connect to mock.address() and send data...
//
//   msgs := mock.wait_for_messages(2, 5000)
//   assert msgs.len == 2
//   assert msgs[0] == 'hello\n'

// CapturedMessage stores raw data received on a TCP connection.
pub struct CapturedMessage {
pub:
	data string
	peer string
}

// MockTcpServer listens on 127.0.0.1 with a kernel-assigned port.
// Accepts TCP connections, captures all received data, and optionally
// sends a configurable response.
pub struct MockTcpServer {
pub:
	port int
mut:
	capture   chan CapturedMessage
	collected []CapturedMessage
}

// TcpServerConfig controls MockTcpServer behavior.
pub struct TcpServerConfig {
pub:
	// response is sent back to each client after reading (empty = no response)
	response string
	// close_after_read closes the connection after first read
	close_after_read bool
	// read_timeout_ms sets the read timeout per connection (default: 3000)
	read_timeout_ms int = 3000
	// accept_count stops accepting after this many connections (0 = unlimited)
	accept_count int
	// reject immediately closes connections without reading (simulates refused)
	reject bool
	// ws_upgrade responds with a WebSocket 101 upgrade before reading frames
	ws_upgrade bool
}

// start_tcp starts a TCP mock server with default config.
pub fn start_tcp() !MockTcpServer {
	return start_tcp_with_config(TcpServerConfig{})
}

// start_tcp_with_config starts a TCP mock server with custom config.
pub fn start_tcp_with_config(config TcpServerConfig) !MockTcpServer {
	ready := chan int{cap: 1}
	capture := chan CapturedMessage{cap: 10000}

	spawn run_tcp_server(config, capture, ready)

	port := <-ready
	if port < 0 {
		return error('mockserver: could not bind TCP to loopback port')
	}

	return MockTcpServer{
		port: port
		capture: capture
	}
}

// address returns the listen address (e.g. "127.0.0.1:34567").
pub fn (s &MockTcpServer) address() string {
	return '127.0.0.1:${s.port}'
}

// wait_for_messages blocks until at least `count` messages have been captured,
// or timeout_ms milliseconds have elapsed.
pub fn (mut s MockTcpServer) wait_for_messages(count int, timeout_ms int) []CapturedMessage {
	deadline := time.now().unix_milli() + timeout_ms
	for s.collected.len < count {
		if time.now().unix_milli() >= deadline {
			break
		}
		mut msg := CapturedMessage{}
		if s.capture.try_pop(mut msg) == .success {
			s.collected << msg
		} else {
			time.sleep(5 * time.millisecond)
		}
	}
	return s.collected
}

// messages non-blocking drains pending messages.
pub fn (mut s MockTcpServer) messages() []CapturedMessage {
	for {
		mut msg := CapturedMessage{}
		if s.capture.try_pop(mut msg) == .success {
			s.collected << msg
		} else {
			break
		}
	}
	return s.collected
}

// message_count returns the total number of messages captured.
pub fn (mut s MockTcpServer) message_count() int {
	_ = s.messages()
	return s.collected.len
}

// all_data returns all captured data concatenated.
pub fn (mut s MockTcpServer) all_data() string {
	_ = s.messages()
	mut result := ''
	for m in s.collected {
		result += m.data
	}
	return result
}

// stop closes the capture channel.
pub fn (mut s MockTcpServer) stop() {
	s.capture.close()
}

// --- Internal TCP server ---

fn run_tcp_server(config TcpServerConfig, capture chan CapturedMessage, ready chan int) {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0') or {
		ready <- -1
		return
	}

	addr_str := (listener.addr() or { net.Addr{} }).str()
	colon := addr_str.last_index(':') or {
		ready <- -1
		return
	}
	port := addr_str[colon + 1..].int()
	if port == 0 {
		ready <- -1
		return
	}
	ready <- port

	mut accepted := 0
	for {
		if config.accept_count > 0 && accepted >= config.accept_count {
			// Keep listener alive but stop accepting
			time.sleep(100 * time.millisecond)
			continue
		}

		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		accepted += 1

		if config.reject {
			conn.close() or {}
			continue
		}

		if config.ws_upgrade {
			handle_ws_mock_conn(mut conn, config, capture)
		} else {
			handle_tcp_mock_conn(mut conn, config, capture)
		}
	}
}

fn handle_tcp_mock_conn(mut conn net.TcpConn, config TcpServerConfig, capture chan CapturedMessage) {
	defer { conn.close() or {} }

	timeout := if config.read_timeout_ms > 0 {
		config.read_timeout_ms
	} else {
		3000
	}
	conn.set_read_timeout(time.Duration(i64(timeout) * time.millisecond))

	peer := (conn.peer_addr() or { net.Addr{} }).str()

	// Read all available data
	mut all_data := []u8{}
	for {
		mut buf := []u8{len: 16384}
		n := conn.read(mut buf) or { break }
		if n == 0 {
			break
		}
		all_data << buf[..n]

		if config.close_after_read {
			break
		}
	}

	if all_data.len > 0 {
		capture.try_push(CapturedMessage{
			data: all_data.bytestr()
			peer: peer
		})
	}

	// Send response if configured
	if config.response.len > 0 {
		conn.write(config.response.bytes()) or {}
	}
}

fn handle_ws_mock_conn(mut conn net.TcpConn, config TcpServerConfig, capture chan CapturedMessage) {
	defer { conn.close() or {} }
	conn.set_read_timeout(5 * time.second)

	peer := (conn.peer_addr() or { net.Addr{} }).str()

	// Read WebSocket upgrade request
	mut buf := []u8{len: 4096}
	n := conn.read(mut buf) or { return }
	if n == 0 {
		return
	}
	req := buf[..n].bytestr()
	if !req.contains('Upgrade: websocket') {
		return
	}

	// Send 101 Switching Protocols
	upgrade_resp := 'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n'
	conn.write(upgrade_resp.bytes()) or { return }

	// Read WebSocket frames and capture payloads
	for {
		payload := read_ws_mock_frame(mut conn) or { break }
		if payload.len > 0 {
			capture.try_push(CapturedMessage{
				data: payload
				peer: peer
			})
		}
	}
}

// read_ws_mock_frame reads a single WebSocket frame from a connection.
fn read_ws_mock_frame(mut conn net.TcpConn) !string {
	mut header := []u8{len: 2}
	n := conn.read(mut header) or { return error('read failed') }
	if n < 2 {
		return error('incomplete header')
	}

	opcode := header[0] & 0x0F
	if opcode == 0x8 {
		return error('close frame')
	}

	mut payload_len := u64(header[1] & 0x7F)
	masked := (header[1] & 0x80) != 0

	if payload_len == 126 {
		mut ext := []u8{len: 2}
		conn.read(mut ext) or { return error('read failed') }
		payload_len = u64(ext[0]) << 8 | u64(ext[1])
	} else if payload_len == 127 {
		mut ext := []u8{len: 8}
		conn.read(mut ext) or { return error('read failed') }
		payload_len = 0
		for i in 0 .. 8 {
			payload_len = (payload_len << 8) | u64(ext[i])
		}
	}

	mut mask := []u8{}
	if masked {
		mask = []u8{len: 4}
		conn.read(mut mask) or { return error('read failed') }
	}

	if payload_len == 0 {
		return ''
	}

	mut payload := []u8{len: int(payload_len)}
	mut total_read := 0
	for total_read < int(payload_len) {
		mut chunk := []u8{len: int(payload_len) - total_read}
		r := conn.read(mut chunk) or { return error('read failed') }
		if r == 0 {
			break
		}
		for i in 0 .. r {
			payload[total_read + i] = chunk[i]
		}
		total_read += r
	}

	if masked {
		for i in 0 .. total_read {
			payload[i] = payload[i] ^ mask[i % 4]
		}
	}

	return payload[..total_read].bytestr()
}
