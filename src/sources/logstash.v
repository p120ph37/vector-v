module sources

import event
import json
import net
import time

// LogstashSource listens on a TCP socket for newline-delimited JSON messages,
// providing compatibility with Logstash's beats/lumberjack output protocol
// (simplified to JSON-over-TCP). Mirrors upstream Vector's logstash source.
//
// Each JSON line received on the TCP connection becomes a log event.
// Fields from the JSON object are mapped directly into the log event.
//
// Config options:
//   address: Listen address (default: 0.0.0.0:5044)
pub struct LogstashSource {
	address string = '0.0.0.0:5044'
}

// new_logstash creates a new LogstashSource from config options.
pub fn new_logstash(opts map[string]string) LogstashSource {
	address := opts['address'] or { '0.0.0.0:5044' }

	return LogstashSource{
		address: address
	}
}

// run starts the TCP listener and processes incoming JSON lines.
pub fn (s &LogstashSource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('logstash: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('logstash: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		spawn handle_logstash_conn(mut conn, output)
	}
}

fn handle_logstash_conn(mut conn net.TcpConn, output chan event.Event) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	mut sb := new_socket_buffer(102400)

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
			ev := parse_logstash_line(line) or {
				eprintln('logstash: parse error: ${err}')
				continue
			}
			output <- event.Event(ev)
		}
	}

	// Flush remaining data
	remaining := sb.remaining()
	if remaining.len > 0 {
		ev := parse_logstash_line(remaining) or { return }
		output <- event.Event(ev)
	}
}

// parse_logstash_line parses a single JSON line from a Logstash client
// into a LogEvent with mapped fields.
fn parse_logstash_line(line string) !event.LogEvent {
	trimmed := line.trim_space()
	if trimmed.len == 0 {
		return error('empty line')
	}

	obj := json.decode(map[string]string, trimmed) or {
		return error('invalid JSON: ${err}')
	}

	// Extract message field, or use empty string
	message := obj['message'] or { '' }

	mut ev := event.new_log(message)
	ev.meta.source_type = 'logstash'

	// Map all other fields into the log event
	for key, val in obj {
		if key == 'message' {
			continue
		}
		ev.set(key, event.Value(val))
	}

	return ev
}
