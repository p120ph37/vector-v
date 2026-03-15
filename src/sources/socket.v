module sources

import event
import net
import time

// SocketSource listens on a TCP or UDP socket and emits received data as
// log events. Mirrors Vector's socket source (src/sources/socket/).
//
// Uses the shared SocketBuffer for line-delimited framing over TCP. This
// same buffering infrastructure is reused by VectorSource and can be used
// for any line-oriented TCP protocol.
//
// Config options:
//   mode:           "tcp" or "udp" (default: tcp)
//   address:        Listen address (default: 0.0.0.0:9000)
//   max_length:     Max line length in bytes (default: 102400)
//   host_key:       Field name to store remote host (default: "host")
pub struct SocketSource {
	mode       SocketMode
	address    string = '0.0.0.0:9000'
	max_length int    = 102400
	host_key   string = 'host'
}

pub enum SocketMode {
	tcp
	udp
}

// new_socket creates a new SocketSource from config options.
pub fn new_socket(opts map[string]string) SocketSource {
	mode := match opts['mode'] or { 'tcp' } {
		'udp' { SocketMode.udp }
		else { SocketMode.tcp }
	}

	address := opts['address'] or { '0.0.0.0:9000' }

	mut max_length := 102400
	if ml := opts['max_length'] {
		max_length = ml.int()
		if max_length <= 0 {
			max_length = 102400
		}
	}

	host_key := opts['host_key'] or { 'host' }

	return SocketSource{
		mode: mode
		address: address
		max_length: max_length
		host_key: host_key
	}
}

// run starts listening and emitting events.
pub fn (s &SocketSource) run(output chan event.Event) {
	match s.mode {
		.tcp { s.run_tcp(output) }
		.udp { s.run_udp(output) }
	}
}

fn (s &SocketSource) run_tcp(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('socket: failed to bind TCP ${s.address}: ${err}')
		return
	}
	eprintln('socket: listening TCP on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		max_len := s.max_length
		host_key := s.host_key
		spawn handle_socket_tcp(mut conn, output, max_len, host_key)
	}
}

fn handle_socket_tcp(mut conn net.TcpConn, output chan event.Event, max_length int, host_key string) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	peer := (conn.peer_addr() or { net.Addr{} }).str()
	mut sb := new_socket_buffer(max_length)

	for {
		mut buf := []u8{len: 8192}
		n := conn.read(mut buf) or { break }
		if n == 0 {
			break
		}
		sb.feed(buf[..n])
		for line in sb.read_lines() {
			if line.len == 0 {
				continue
			}
			mut ev := event.new_log(line)
			ev.meta.source_type = 'socket'
			ev.set(host_key, event.Value(peer))
			ev.set('source_type', event.Value('tcp'))
			output <- event.Event(ev)
		}
	}

	// Flush remaining
	remaining := sb.remaining()
	if remaining.len > 0 {
		mut ev := event.new_log(remaining)
		ev.meta.source_type = 'socket'
		ev.set(host_key, event.Value(peer))
		ev.set('source_type', event.Value('tcp'))
		output <- event.Event(ev)
	}
}

fn (s &SocketSource) run_udp(output chan event.Event) {
	mut conn := net.listen_udp(s.address) or {
		eprintln('socket: failed to bind UDP ${s.address}: ${err}')
		return
	}
	eprintln('socket: listening UDP on ${s.address}')

	for {
		mut buf := []u8{len: 65536}
		n, addr := conn.read(mut buf) or {
			time.sleep(10 * time.millisecond)
			continue
		}
		if n == 0 {
			continue
		}
		msg := buf[..n].bytestr().trim_right('\r\n')
		if msg.len == 0 {
			continue
		}
		line := if msg.len > s.max_length {
			msg[..s.max_length]
		} else {
			msg
		}
		mut ev := event.new_log(line)
		ev.meta.source_type = 'socket'
		ev.set(s.host_key, event.Value(addr.str()))
		ev.set('source_type', event.Value('udp'))
		output <- event.Event(ev)
	}
}
