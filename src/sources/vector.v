module sources

import event
import net
import time

// VectorSource receives events from other Vector instances over TCP using
// Vector's native protocol (JSON-over-TCP, newline-delimited).
// Mirrors Vector's vector source (src/sources/vector/).
//
// This source listens on a TCP port and accepts connections from VectorSink
// instances. Each line is expected to be a JSON-encoded log event. The source
// reuses the shared SocketBuffer for line-delimited framing, following the
// same buffering pattern as SocketSource.
//
// Config options:
//   address:        Listen address (default: 0.0.0.0:6000)
//   max_length:     Max line length in bytes (default: 1048576)
pub struct VectorSource {
	address    string = '0.0.0.0:6000'
	max_length int    = 1048576
}

// new_vector_source creates a new VectorSource from config options.
pub fn new_vector_source(opts map[string]string) VectorSource {
	address := opts['address'] or { '0.0.0.0:6000' }

	mut max_length := 1048576
	if ml := opts['max_length'] {
		max_length = ml.int()
		if max_length <= 0 {
			max_length = 1048576
		}
	}

	return VectorSource{
		address: address
		max_length: max_length
	}
}

// run listens for TCP connections from other Vector instances.
pub fn (s &VectorSource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('vector source: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('vector source: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		max_len := s.max_length
		spawn handle_vector_conn(mut conn, output, max_len)
	}
}

fn handle_vector_conn(mut conn net.TcpConn, output chan event.Event, max_length int) {
	defer { conn.close() or {} }
	conn.set_read_timeout(60 * time.second)

	peer := (conn.peer_addr() or { net.Addr{} }).str()
	mut sb := new_socket_buffer(max_length)

	for {
		mut buf := []u8{len: 16384}
		n := conn.read(mut buf) or { break }
		if n == 0 {
			break
		}
		sb.feed(buf[..n])
		for line in sb.read_lines() {
			if line.len == 0 {
				continue
			}
			// Parse JSON into a log event
			ev := parse_vector_event(line, peer)
			output <- ev
		}
	}

	remaining := sb.remaining()
	if remaining.trim_space().len > 0 {
		ev := parse_vector_event(remaining, peer)
		output <- ev
	}
}

// parse_vector_event creates a log event from a JSON line received from
// another Vector instance. If the line is valid JSON with a "message" field,
// it's used directly. Otherwise the raw line becomes the message.
fn parse_vector_event(line string, peer string) event.Event {
	mut ev := event.new_log(line)
	ev.meta.source_type = 'vector'
	ev.set('source_peer', event.Value(peer))
	return event.Event(ev)
}
