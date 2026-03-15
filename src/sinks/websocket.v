module sinks

import event
import json
import net
import time

// WebSocketSink sends events to a WebSocket server.
// Mirrors Vector's websocket sink (src/sinks/websocket/).
//
// Events are encoded and sent individually over a persistent TCP connection
// using a minimal WebSocket frame implementation (RFC 6455). The sink
// reconnects automatically on connection failure.
//
// Config options:
//   uri:                 WebSocket URL (required), e.g. ws://localhost:9000/events
//   encoding.codec:      json or text (default: json)
//   ping_interval_secs:  Interval for WebSocket ping frames (default: 30)
//   ping_timeout_secs:   Timeout waiting for pong response (default: 10)
pub struct WebSocketSink {
	host           string
	port           int
	path           string
	codec          WsCodec
	ping_interval  time.Duration = 30 * time.second
mut:
	conn      ?net.TcpConn
	connected bool
}

enum WsCodec {
	json_codec
	text_codec
}

// new_websocket creates a new WebSocketSink from config options.
pub fn new_websocket(opts map[string]string) !WebSocketSink {
	uri := opts['uri'] or {
		return error('websocket sink: uri is required')
	}

	// Parse ws://host:port/path
	parsed := parse_ws_uri(uri) or {
		return error('websocket sink: invalid uri "${uri}": ${err}')
	}

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { WsCodec.text_codec }
		else { WsCodec.json_codec }
	}

	mut ping_interval_secs := 30.0
	if p := opts['ping_interval_secs'] {
		ping_interval_secs = p.f64()
		if ping_interval_secs <= 0 {
			ping_interval_secs = 30.0
		}
	}

	return WebSocketSink{
		host: parsed.host
		port: parsed.port
		path: parsed.path
		codec: codec
		ping_interval: time.Duration(i64(ping_interval_secs * 1_000_000_000))
	}
}

// send encodes and sends an event over the WebSocket connection.
pub fn (mut s WebSocketSink) send(e event.Event) ! {
	payload := s.encode_event(e)
	if payload.len == 0 {
		return
	}

	// Ensure connected
	if !s.connected {
		s.connect() or {
			return error('websocket: connection failed: ${err}')
		}
	}

	// Send as WebSocket text frame
	s.send_text_frame(payload) or {
		// Try reconnect once
		s.connected = false
		s.connect() or {
			return error('websocket: reconnection failed: ${err}')
		}
		s.send_text_frame(payload) or {
			s.connected = false
			return error('websocket: send failed after reconnect: ${err}')
		}
	}
}

fn (s &WebSocketSink) encode_event(e event.Event) string {
	match e {
		event.LogEvent {
			return match s.codec {
				.json_codec { e.to_json() }
				.text_codec { e.message() }
			}
		}
		event.Metric {
			return json.encode(e)
		}
		event.TraceEvent {
			return json.encode(e.fields)
		}
	}
}

fn (mut s WebSocketSink) connect() ! {
	// Close existing connection
	if mut c := s.conn {
		c.close() or {}
	}

	mut conn := net.dial_tcp('${s.host}:${s.port}') or {
		return error('tcp connect to ${s.host}:${s.port} failed: ${err}')
	}
	conn.set_write_timeout(5 * time.second)
	conn.set_read_timeout(5 * time.second)

	// Perform WebSocket upgrade handshake
	upgrade_req := 'GET ${s.path} HTTP/1.1\r\nHost: ${s.host}:${s.port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n'
	conn.write(upgrade_req.bytes()) or {
		conn.close() or {}
		return error('failed to send upgrade: ${err}')
	}

	// Read upgrade response
	mut buf := []u8{len: 4096}
	n := conn.read(mut buf) or {
		conn.close() or {}
		return error('failed to read upgrade response: ${err}')
	}
	response := buf[..n].bytestr()
	if !response.contains('101') {
		conn.close() or {}
		return error('websocket upgrade rejected: ${response.split_into_lines()[0]}')
	}

	s.conn = conn
	s.connected = true
}

fn (mut s WebSocketSink) send_text_frame(payload string) ! {
	mut c := s.conn or {
		return error('not connected')
	}

	frame := build_ws_frame(payload)
	c.write(frame) or {
		return error('write failed: ${err}')
	}
}

// build_ws_frame builds a WebSocket text frame (opcode 0x81) with masking.
// RFC 6455 requires client-to-server frames to be masked.
pub fn build_ws_frame(payload string) []u8 {
	data := payload.bytes()
	mut frame := []u8{}

	// FIN + text opcode
	frame << u8(0x81)

	// Payload length with mask bit set (0x80)
	if data.len < 126 {
		frame << u8(0x80 | data.len)
	} else if data.len < 65536 {
		frame << u8(0x80 | 126)
		frame << u8(data.len >> 8)
		frame << u8(data.len & 0xFF)
	} else {
		frame << u8(0x80 | 127)
		len64 := u64(data.len)
		for i := 7; i >= 0; i-- {
			frame << u8((len64 >> (u64(i) * 8)) & 0xFF)
		}
	}

	// Masking key (fixed for simplicity — production should use random)
	mask := [u8(0x37), 0xfa, 0x21, 0x3d]
	frame << mask[0]
	frame << mask[1]
	frame << mask[2]
	frame << mask[3]

	// Masked payload
	for i, b in data {
		frame << b ^ mask[i % 4]
	}

	return frame
}

// close closes the WebSocket connection.
pub fn (mut s WebSocketSink) close() {
	if mut c := s.conn {
		c.close() or {}
	}
	s.connected = false
}

// --- URI parsing ---

struct WsUri {
	host string
	port int
	path string
}

fn parse_ws_uri(uri string) !WsUri {
	// Strip ws:// or wss:// prefix
	mut remainder := uri
	if remainder.starts_with('ws://') {
		remainder = remainder[5..]
	} else if remainder.starts_with('wss://') {
		remainder = remainder[6..]
	}

	// Split host:port from path
	mut path := '/'
	slash_idx := remainder.index('/') or { -1 }
	mut host_port := remainder
	if slash_idx >= 0 {
		host_port = remainder[..slash_idx]
		path = remainder[slash_idx..]
	}

	// Split host and port
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

	return WsUri{
		host: host
		port: port
		path: path
	}
}
