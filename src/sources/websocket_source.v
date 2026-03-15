module sources

import event
import net
import time

// WebSocketSource connects to a WebSocket server and emits received messages
// as log events. Mirrors Vector's websocket source.
//
// Performs a WebSocket upgrade handshake over TCP and reads text frames,
// emitting each complete message as a log event.
//
// Config options:
//   url:                WebSocket URL (required), e.g. ws://localhost:9000/feed
//   max_length:         Max message length (default: 1048576)
//   reconnect_secs:     Seconds before reconnect on disconnect (default: 5)
pub struct WebSocketSource {
	host       string
	port       int
	path       string
	max_length int = 1048576
	reconnect  time.Duration = 5 * time.second
}

// new_websocket_source creates a new WebSocketSource from config options.
pub fn new_websocket_source(opts map[string]string) !WebSocketSource {
	url := opts['url'] or {
		return error('websocket source: url is required')
	}

	parsed := parse_ws_source_uri(url) or {
		return error('websocket source: invalid url "${url}": ${err}')
	}

	mut max_length := 1048576
	if ml := opts['max_length'] {
		max_length = ml.int()
		if max_length <= 0 {
			max_length = 1048576
		}
	}

	mut reconnect_secs := 5.0
	if r := opts['reconnect_secs'] {
		reconnect_secs = r.f64()
		if reconnect_secs <= 0 {
			reconnect_secs = 5.0
		}
	}

	return WebSocketSource{
		host: parsed.host
		port: parsed.port
		path: parsed.path
		max_length: max_length
		reconnect: time.Duration(i64(reconnect_secs * 1_000_000_000))
	}
}

// run connects to the WebSocket server and emits received messages.
pub fn (s &WebSocketSource) run(output chan event.Event) {
	for {
		s.connect_and_read(output)
		eprintln('websocket source: disconnected, reconnecting in ${s.reconnect / time.second}s')
		time.sleep(s.reconnect)
	}
}

fn (s &WebSocketSource) connect_and_read(output chan event.Event) {
	mut conn := net.dial_tcp('${s.host}:${s.port}') or {
		eprintln('websocket source: connect failed: ${err}')
		return
	}
	defer { conn.close() or {} }
	conn.set_read_timeout(60 * time.second)
	conn.set_write_timeout(5 * time.second)

	// WebSocket upgrade handshake
	upgrade := 'GET ${s.path} HTTP/1.1\r\nHost: ${s.host}:${s.port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n'
	conn.write(upgrade.bytes()) or { return }

	mut buf := []u8{len: 4096}
	n := conn.read(mut buf) or { return }
	resp := buf[..n].bytestr()
	if !resp.contains('101') {
		eprintln('websocket source: upgrade rejected')
		return
	}

	// Read WebSocket frames
	for {
		payload := read_ws_text_frame(mut conn, s.max_length) or { break }
		if payload.len == 0 {
			continue
		}
		mut ev := event.new_log(payload)
		ev.meta.source_type = 'websocket'
		ev.set('host', event.Value('${s.host}:${s.port}'))
		output <- event.Event(ev)
	}
}

// read_ws_text_frame reads a single WebSocket text frame from a TCP connection.
fn read_ws_text_frame(mut conn net.TcpConn, max_length int) !string {
	// Read frame header (2 bytes minimum)
	mut header := []u8{len: 2}
	n := conn.read(mut header) or { return error('read failed') }
	if n < 2 {
		return error('incomplete frame header')
	}

	opcode := header[0] & 0x0F
	// 0x8 = close, 0x9 = ping, 0xA = pong
	if opcode == 0x8 {
		return error('connection closed by server')
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

	// Limit payload
	if payload_len > u64(max_length) {
		payload_len = u64(max_length)
	}

	// Read mask if present
	mut mask := []u8{}
	if masked {
		mask = []u8{len: 4}
		conn.read(mut mask) or { return error('read failed') }
	}

	// Read payload
	if payload_len == 0 {
		// Handle ping: send pong
		if opcode == 0x9 {
			pong := [u8(0x8A), 0x00] // FIN + pong, 0 length
			conn.write(pong) or {}
		}
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

	// Unmask if needed
	if masked {
		for i in 0 .. total_read {
			payload[i] = payload[i] ^ mask[i % 4]
		}
	}

	// Handle ping
	if opcode == 0x9 {
		pong := [u8(0x8A), 0x00]
		conn.write(pong) or {}
		return ''
	}

	return payload[..total_read].bytestr()
}

// --- URI parsing ---

struct WsSourceUri {
	host string
	port int
	path string
}

fn parse_ws_source_uri(uri string) !WsSourceUri {
	mut remainder := uri
	if remainder.starts_with('ws://') {
		remainder = remainder[5..]
	} else if remainder.starts_with('wss://') {
		remainder = remainder[6..]
	}

	mut path := '/'
	slash_idx := remainder.index('/') or { -1 }
	mut host_port := remainder
	if slash_idx >= 0 {
		host_port = remainder[..slash_idx]
		path = remainder[slash_idx..]
	}

	mut host := host_port
	mut port := 80
	colon_idx := host_port.last_index(':') or { -1 }
	if colon_idx >= 0 {
		host = host_port[..colon_idx]
		port = host_port[colon_idx + 1..].int()
		if port <= 0 {
			return error('invalid port')
		}
	}

	if host.len == 0 {
		return error('empty host')
	}

	return WsSourceUri{
		host: host
		port: port
		path: path
	}
}
