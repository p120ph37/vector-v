module sinks

import event
import net
import time

// VectorSink sends events to another Vector instance over TCP using
// Vector's native protocol (JSON-over-TCP, newline-delimited).
// Mirrors Vector's vector sink (src/sinks/vector/).
//
// This sink connects to a VectorSource on a remote Vector instance and
// sends events as newline-delimited JSON. It reuses the same TCP buffering
// and connection management patterns as the socket sink.
//
// Config options:
//   address:             Target address (default: 127.0.0.1:6000)
//   batch.max_events:    Max events before flush (default: 100)
//   batch.timeout_secs:  Max seconds before flush (default: 1)
pub struct VectorSink {
	address       string
	batch_max     int = 100
	batch_timeout time.Duration = 1 * time.second
mut:
	tcp_fd     int = -1
	connected  bool
	buffer     []string
	last_flush time.Time
}

// new_vector creates a new VectorSink from config options.
pub fn new_vector(opts map[string]string) VectorSink {
	address := opts['address'] or { '127.0.0.1:6000' }

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return VectorSink{
		address: address
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s VectorSink) send(e event.Event) ! {
	line := e.to_json_string()
	s.buffer << line

	if s.buffer.len >= s.batch_max {
		s.flush()!
	}

	if time.since(s.last_flush) > s.batch_timeout && s.buffer.len > 0 {
		s.flush()!
	}
}

// flush sends all buffered events over TCP.
pub fn (mut s VectorSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	if !s.connected {
		s.connect() or {
			return error('vector sink: connection failed: ${err}')
		}
	}

	// Send each event as a newline-delimited JSON line
	mut payload := s.buffer.join('\n') + '\n'

	s.write_data(payload) or {
		// Try reconnect once
		s.connected = false
		s.connect() or {
			return error('vector sink: reconnection failed: ${err}')
		}
		s.write_data(payload) or {
			s.connected = false
			return error('vector sink: send failed after reconnect: ${err}')
		}
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &VectorSink) total_buffered() int {
	return s.buffer.len
}

fn (mut s VectorSink) connect() ! {
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

pub fn (mut s VectorSink) write_data(data string) ! {
	if s.tcp_fd < 0 {
		return error('not connected')
	}
	bytes := data.bytes()
	sent := C.send(s.tcp_fd, bytes.data, bytes.len, 0)
	if sent < 0 {
		return error('write failed: socket error')
	}
}

// close closes the TCP connection.
pub fn (mut s VectorSink) close() {
	if s.tcp_fd >= 0 {
		C.close(s.tcp_fd)
		s.tcp_fd = -1
	}
	s.connected = false
}
