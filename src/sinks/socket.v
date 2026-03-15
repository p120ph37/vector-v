module sinks

import event
import net
import time

// SocketSink sends events over a TCP or UDP socket.
// Mirrors Vector's socket sink (src/sinks/socket/).
//
// Uses the same TCP connection management and buffering patterns as VectorSink.
// Both socket-based sinks (SocketSink and VectorSink) share the reconnect-on-
// failure approach, paralleling how upstream Vector's socket source and sink
// share a common framing/buffering layer.
//
// Config options:
//   mode:              "tcp" or "udp" (default: tcp)
//   address:           Target address (required), e.g. 127.0.0.1:9000
//   encoding.codec:    json, text, or ndjson (default: json)
pub struct SocketSink {
	mode    SocketSinkMode
	address string
	codec   SocketCodec
mut:
	tcp_fd    int = -1
	connected bool
}

enum SocketSinkMode {
	tcp
	udp
}

enum SocketCodec {
	json_codec
	text_codec
}

// new_socket_sink creates a new SocketSink from config options.
pub fn new_socket_sink(opts map[string]string) !SocketSink {
	address := opts['address'] or {
		return error('socket sink: address is required')
	}

	mode := match opts['mode'] or { 'tcp' } {
		'udp' { SocketSinkMode.udp }
		else { SocketSinkMode.tcp }
	}

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { SocketCodec.text_codec }
		else { SocketCodec.json_codec }
	}

	return SocketSink{
		mode: mode
		address: address
		codec: codec
	}
}

// send encodes and sends an event over the socket.
pub fn (mut s SocketSink) send(e event.Event) ! {
	line := s.encode_event(e)
	if line.len == 0 {
		return
	}

	match s.mode {
		.tcp { s.send_tcp(line)! }
		.udp { s.send_udp(line)! }
	}
}

pub fn (s &SocketSink) encode_event(e event.Event) string {
	match e {
		event.LogEvent {
			return match s.codec {
				.json_codec { e.to_json() }
				.text_codec { e.message() }
			}
		}
		else {
			return e.to_json_string()
		}
	}
}

fn (mut s SocketSink) send_tcp(line string) ! {
	if !s.connected {
		s.connect_tcp() or {
			return error('socket sink: connection failed: ${err}')
		}
	}

	payload := line + '\n'
	s.write_tcp(payload) or {
		// Try reconnect once
		s.connected = false
		s.connect_tcp() or {
			return error('socket sink: reconnection failed: ${err}')
		}
		s.write_tcp(payload) or {
			s.connected = false
			return error('socket sink: send failed after reconnect: ${err}')
		}
	}
}

fn (mut s SocketSink) connect_tcp() ! {
	if s.tcp_fd >= 0 {
		C.close(s.tcp_fd)
		s.tcp_fd = -1
	}

	mut conn := net.dial_tcp(s.address) or {
		return error('tcp connect to ${s.address} failed: ${err}')
	}
	conn.set_write_timeout(5 * time.second)
	s.tcp_fd = conn.sock.handle
	s.connected = true
}

pub fn (mut s SocketSink) write_tcp(data string) ! {
	if s.tcp_fd < 0 {
		return error('not connected')
	}
	bytes := data.bytes()
	sent := C.send(s.tcp_fd, bytes.data, bytes.len, 0)
	if sent < 0 {
		return error('write failed: socket error')
	}
}

fn (s &SocketSink) send_udp(line string) ! {
	mut conn := net.dial_udp(s.address) or {
		return error('socket sink: UDP dial failed: ${err}')
	}
	defer { conn.close() or {} }

	conn.write(line.bytes()) or {
		return error('socket sink: UDP send failed: ${err}')
	}
}

// close closes the TCP connection (no-op for UDP).
pub fn (mut s SocketSink) close() {
	if s.tcp_fd >= 0 {
		C.close(s.tcp_fd)
		s.tcp_fd = -1
	}
	s.connected = false
}
