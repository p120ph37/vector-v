module sources

import event
import net
import time

// PrometheusRemoteWriteSource provides an HTTP endpoint for receiving
// Prometheus remote write requests. Mirrors Vector's prometheus_remote_write
// source.
//
// Accepts POST to /api/v1/write with Prometheus text exposition format in the
// body (simplified: we accept text format rather than protobuf snappy).
// Emits metric events parsed from the body.
//
// Config options:
//   address:    Listen address (default: 0.0.0.0:9090)
//   auth.token: Optional bearer token for authentication
pub struct PrometheusRemoteWriteSource {
	address    string = '0.0.0.0:9090'
	auth_token string
}

// new_prometheus_remote_write creates a new PrometheusRemoteWriteSource from config options.
pub fn new_prometheus_remote_write(opts map[string]string) PrometheusRemoteWriteSource {
	address := opts['address'] or { '0.0.0.0:9090' }
	auth_token := opts['auth.token'] or { '' }

	return PrometheusRemoteWriteSource{
		address: address
		auth_token: auth_token
	}
}

// run starts the HTTP server and processes Prometheus remote write requests.
pub fn (s &PrometheusRemoteWriteSource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('prometheus_remote_write: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('prometheus_remote_write: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		token := s.auth_token
		spawn handle_prom_rw_conn(mut conn, output, token)
	}
}

fn handle_prom_rw_conn(mut conn net.TcpConn, output chan event.Event, auth_token string) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	req := read_prom_rw_request(mut conn) or {
		send_prom_rw_response(mut conn, 400, 'failed to read request: ${err}')
		return
	}

	// Only accept POST on /api/v1/write
	if req.method != 'POST' || req.path != '/api/v1/write' {
		send_prom_rw_response(mut conn, 404, 'not found')
		return
	}

	// Validate bearer token if configured
	if auth_token.len > 0 {
		auth := req.headers['authorization'] or { '' }
		mut token := ''
		if auth.starts_with('Bearer ') {
			token = auth[7..]
		}
		if token != auth_token {
			send_prom_rw_response(mut conn, 401, 'unauthorized')
			return
		}
	}

	// Parse Prometheus text format from body
	metrics := parse_prometheus_text(req.body)
	for m in metrics {
		mut metric := m
		metric.meta.source_type = 'prometheus_remote_write'
		output <- event.Event(metric)
	}

	// Send 204 No Content (standard remote write success response)
	response := 'HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n'
	conn.write(response.bytes()) or {}
}

// PromRwRequest holds a parsed HTTP request for the remote write endpoint.
struct PromRwRequest {
	method  string
	path    string
	headers map[string]string
	body    string
}

// read_prom_rw_request reads and parses an HTTP request from a TCP connection.
fn read_prom_rw_request(mut conn net.TcpConn) !PromRwRequest {
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

	return PromRwRequest{
		method: method
		path: path
		headers: headers
		body: body_str
	}
}

fn send_prom_rw_response(mut conn net.TcpConn, status int, message string) {
	status_text := match status {
		400 { 'Bad Request' }
		401 { 'Unauthorized' }
		404 { 'Not Found' }
		else { 'Error' }
	}
	body := '{"error":"${message}"}'
	response := 'HTTP/1.1 ${status} ${status_text}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
	conn.write(response.bytes()) or {}
}
