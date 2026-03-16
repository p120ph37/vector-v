module sources

import event
import json
import net
import time

// HttpServerSource provides an HTTP endpoint that receives events via POST.
// Mirrors Vector's http_server source (previously http).
//
// Accepts POST requests, parses the body based on the configured encoding,
// and emits each event as a log event.
//
// Config options:
//   address:    Listen address (default: 0.0.0.0:80)
//   path:       URL path to accept (default: /)
//   encoding:   Body encoding: json, text, ndjson (default: json)
//   auth.token: Optional bearer token for authentication
pub struct HttpServerSource {
	address  string = '0.0.0.0:80'
	path     string = '/'
	encoding HttpServerEncoding = .json_enc
	token    string
}

enum HttpServerEncoding {
	json_enc
	text
	ndjson
}

// new_http_server creates a new HttpServerSource from config options.
pub fn new_http_server(opts map[string]string) HttpServerSource {
	address := opts['address'] or { '0.0.0.0:80' }
	path := opts['path'] or { '/' }
	token := opts['auth.token'] or { '' }

	encoding := match opts['encoding'] or { 'json' } {
		'text' { HttpServerEncoding.text }
		'ndjson' { HttpServerEncoding.ndjson }
		else { HttpServerEncoding.json_enc }
	}

	return HttpServerSource{
		address: address
		path: path
		encoding: encoding
		token: token
	}
}

// run starts the HTTP server and processes incoming events.
pub fn (s &HttpServerSource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('http_server: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('http_server: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		path := s.path
		encoding := s.encoding
		token := s.token
		spawn handle_http_server_conn(mut conn, output, path, encoding, token)
	}
}

fn handle_http_server_conn(mut conn net.TcpConn, output chan event.Event, path string, encoding HttpServerEncoding, token string) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	req := read_http_server_request(mut conn) or {
		send_http_server_response(mut conn, 400, '{"error":"bad request"}')
		return
	}

	// Only accept POST on configured path
	if req.method != 'POST' || req.path != path {
		send_http_server_response(mut conn, 404, '{"error":"not found"}')
		return
	}

	// Validate bearer token if configured
	if token.len > 0 {
		auth := req.headers['authorization'] or { '' }
		expected := 'Bearer ${token}'
		if auth != expected {
			send_http_server_response(mut conn, 401, '{"error":"unauthorized"}')
			return
		}
	}

	// Parse body based on encoding
	events := parse_http_server_body(req.body, encoding)
	for ev in events {
		output <- event.Event(ev)
	}

	send_http_server_response(mut conn, 200, '{"status":"ok"}')
}

// parse_http_server_body parses the request body based on encoding.
fn parse_http_server_body(body string, encoding HttpServerEncoding) []event.LogEvent {
	mut result := []event.LogEvent{}

	match encoding {
		.json_enc {
			// Try as JSON array first
			arr := json.decode([]string, body) or { []string{} }
			if arr.len > 0 {
				for item in arr {
					mut ev := event.new_log(item)
					ev.meta.source_type = 'http_server'
					result << ev
				}
			} else {
				// Single JSON object or string - emit as-is
				if body.trim_space().len > 0 {
					mut ev := event.new_log(body.trim_space())
					ev.meta.source_type = 'http_server'
					result << ev
				}
			}
		}
		.text {
			for line in body.split('\n') {
				trimmed := line.trim_right('\r')
				if trimmed.len > 0 {
					mut ev := event.new_log(trimmed)
					ev.meta.source_type = 'http_server'
					result << ev
				}
			}
		}
		.ndjson {
			for line in body.split('\n') {
				trimmed := line.trim_right('\r').trim_space()
				if trimmed.len > 0 {
					mut ev := event.new_log(trimmed)
					ev.meta.source_type = 'http_server'
					result << ev
				}
			}
		}
	}

	return result
}

// HttpServerRequest holds a parsed HTTP request.
struct HttpServerRequest {
	method  string
	path    string
	headers map[string]string
	body    string
}

// read_http_server_request reads and parses an HTTP request from a TCP connection.
fn read_http_server_request(mut conn net.TcpConn) !HttpServerRequest {
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
	method := if request_line.len > 0 { request_line[0] } else { 'GET' }
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

	return HttpServerRequest{
		method: method
		path: path
		headers: headers
		body: body_str
	}
}

fn send_http_server_response(mut conn net.TcpConn, status int, body string) {
	status_text := match status {
		200 { 'OK' }
		400 { 'Bad Request' }
		401 { 'Unauthorized' }
		404 { 'Not Found' }
		else { 'Error' }
	}
	response := 'HTTP/1.1 ${status} ${status_text}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
	conn.write(response.bytes()) or {}
}
