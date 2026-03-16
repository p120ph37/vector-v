module sources

import event
import net
import time

// HerokuLogplexSource provides an HTTP endpoint for receiving events via
// Heroku's Logplex drain protocol. Mirrors upstream Vector's heroku_logplex source.
//
// Heroku sends batches of syslog-framed log lines via HTTP POST with a
// Logplex-Msg-Count header indicating the number of messages in the body.
// Each line follows a syslog-like format:
//   <priority>version timestamp hostname app_name proc_id msg_id msg
//
// Config options:
//   address:    Listen address (default: 0.0.0.0:80)
//   auth.token: Expected drain token in Logplex-Drain-Token header (optional)
pub struct HerokuLogplexSource {
	address    string = '0.0.0.0:80'
	auth_token string
}

// new_heroku_logplex creates a new HerokuLogplexSource from config options.
pub fn new_heroku_logplex(opts map[string]string) HerokuLogplexSource {
	address := opts['address'] or { '0.0.0.0:80' }
	auth_token := opts['auth.token'] or { '' }

	return HerokuLogplexSource{
		address: address
		auth_token: auth_token
	}
}

// run starts the HTTP server and processes Logplex drain submissions.
pub fn (s &HerokuLogplexSource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('heroku_logplex: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('heroku_logplex: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		token := s.auth_token
		spawn handle_logplex_conn(mut conn, output, token)
	}
}

fn handle_logplex_conn(mut conn net.TcpConn, output chan event.Event, token string) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	// Read HTTP request
	req := read_logplex_request(mut conn) or {
		send_logplex_response(mut conn, 400, 'failed to read request: ${err}')
		return
	}

	// Only accept POST
	if req.method != 'POST' {
		send_logplex_response(mut conn, 405, 'method not allowed')
		return
	}

	// Validate drain token if configured
	if token.len > 0 {
		drain_token := req.headers['logplex-drain-token'] or { '' }
		if drain_token != token {
			send_logplex_response(mut conn, 401, 'unauthorized')
			return
		}
	}

	// Parse syslog messages from body
	lines := req.body.split('\n')
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		parsed := parse_logplex_line(trimmed)
		mut ev := event.new_log(parsed.message)
		ev.meta.source_type = 'heroku_logplex'
		if parsed.app_name.len > 0 {
			ev.set('app_name', event.Value(parsed.app_name))
		}
		if parsed.proc_id.len > 0 {
			ev.set('proc_id', event.Value(parsed.proc_id))
		}
		if parsed.hostname.len > 0 {
			ev.set('hostname', event.Value(parsed.hostname))
		}
		if parsed.priority >= 0 {
			ev.set('priority', event.Value(parsed.priority))
		}
		if parsed.version >= 0 {
			ev.set('version', event.Value(parsed.version))
		}
		if parsed.timestamp.len > 0 {
			ev.set('timestamp', event.Value(parsed.timestamp))
		}
		if parsed.msg_id.len > 0 {
			ev.set('msg_id', event.Value(parsed.msg_id))
		}
		output <- event.Event(ev)
	}

	send_logplex_response(mut conn, 200, 'ok')
}

// LogplexMessage holds a parsed Heroku syslog message.
struct LogplexMessage {
	priority  int = -1
	version   int = -1
	timestamp string
	hostname  string
	app_name  string
	proc_id   string
	msg_id    string
	message   string
}

// parse_logplex_line parses a single Heroku syslog-like line.
// Format: <priority>version timestamp hostname app_name proc_id msg_id msg
// Example: <190>1 2023-01-01T00:00:00+00:00 host app web.1 - State changed from starting to up
fn parse_logplex_line(line string) LogplexMessage {
	mut msg := LogplexMessage{}
	mut rest := line

	// Parse priority: <NNN>
	if !rest.starts_with('<') {
		return LogplexMessage{
			message: line
		}
	}

	close := rest.index('>') or {
		return LogplexMessage{
			message: line
		}
	}
	pri_str := rest[1..close]
	msg = LogplexMessage{
		...msg
		priority: pri_str.int()
	}
	rest = rest[close + 1..]

	// Parse version (single digit followed by space)
	space_idx := rest.index(' ') or {
		return LogplexMessage{
			...msg
			message: rest
		}
	}
	version_str := rest[..space_idx]
	msg = LogplexMessage{
		...msg
		version: version_str.int()
	}
	rest = rest[space_idx + 1..]

	// Parse remaining space-delimited fields: timestamp hostname app_name proc_id msg_id msg
	fields := ['timestamp', 'hostname', 'app_name', 'proc_id', 'msg_id']
	mut values := []string{}
	mut remaining := rest

	for _ in 0 .. fields.len {
		sp := remaining.index(' ') or {
			values << remaining
			remaining = ''
			break
		}
		values << remaining[..sp]
		remaining = remaining[sp + 1..]
	}

	if values.len >= 1 {
		msg = LogplexMessage{
			...msg
			timestamp: values[0]
		}
	}
	if values.len >= 2 {
		msg = LogplexMessage{
			...msg
			hostname: values[1]
		}
	}
	if values.len >= 3 {
		msg = LogplexMessage{
			...msg
			app_name: values[2]
		}
	}
	if values.len >= 4 {
		msg = LogplexMessage{
			...msg
			proc_id: values[3]
		}
	}
	if values.len >= 5 {
		msg = LogplexMessage{
			...msg
			msg_id: values[4]
		}
	}

	// The rest is the message body
	message := remaining.trim_space()
	msg = LogplexMessage{
		...msg
		message: if message.len > 0 { message } else { '' }
	}

	return msg
}

// LogplexRequest holds a parsed HTTP request from a Logplex drain.
struct LogplexRequest {
	method  string
	path    string
	headers map[string]string
	body    string
}

// read_logplex_request reads and parses an HTTP request from a TCP connection.
fn read_logplex_request(mut conn net.TcpConn) !LogplexRequest {
	mut raw := []u8{}
	mut buf := []u8{len: 4096}

	mut header_end := -1
	for {
		n := conn.read(mut buf) or { break }
		if n == 0 {
			break
		}
		raw << buf[..n]
		s := raw.bytestr()
		idx := s.index('\r\n\r\n') or { -1 }
		if idx >= 0 {
			header_end = idx
			break
		}
		if raw.len > 65536 {
			return error('request headers too large')
		}
	}

	if header_end < 0 {
		return error('incomplete HTTP request')
	}

	full := raw.bytestr()
	header_section := full[..header_end]
	body_start := full[header_end + 4..]

	lines := header_section.split('\r\n')
	if lines.len == 0 {
		return error('empty request')
	}

	request_line := lines[0].split(' ')
	method := if request_line.len > 0 { request_line[0] } else { 'POST' }
	path := if request_line.len > 1 { request_line[1] } else { '/' }

	mut headers := map[string]string{}
	for i := 1; i < lines.len; i++ {
		colon := lines[i].index(':') or { continue }
		key := lines[i][..colon].trim_space().to_lower()
		val := lines[i][colon + 1..].trim_space()
		headers[key] = val
	}

	mut body_str := body_start
	content_length_str := headers['content-length'] or { '0' }
	content_length := content_length_str.int()
	if content_length > 0 && body_str.len < content_length {
		remaining := content_length - body_str.len
		mut body_buf := []u8{len: remaining}
		mut total_read := 0
		for total_read < remaining {
			mut chunk := unsafe { body_buf[total_read..] }
			n := conn.read(mut chunk) or { break }
			if n == 0 {
				break
			}
			total_read += n
		}
		body_str += body_buf[..total_read].bytestr()
	}

	return LogplexRequest{
		method: method
		path: path
		headers: headers
		body: body_str
	}
}

fn send_logplex_response(mut conn net.TcpConn, status int, message string) {
	status_text := match status {
		200 { 'OK' }
		400 { 'Bad Request' }
		401 { 'Unauthorized' }
		405 { 'Method Not Allowed' }
		else { 'Error' }
	}
	response := 'HTTP/1.1 ${status} ${status_text}\r\nContent-Length: ${message.len}\r\n\r\n${message}'
	conn.write(response.bytes()) or {}
}
