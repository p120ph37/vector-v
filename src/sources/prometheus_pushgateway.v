module sources

import event
import net
import time

// PrometheusPushgatewaySource provides an HTTP endpoint for receiving
// Prometheus Pushgateway pushes. Mirrors Vector's prometheus_pushgateway source.
//
// Accepts PUT/POST to /metrics/job/{job} with Prometheus text exposition
// format in the body. Emits metric events with the job label extracted
// from the URL path.
//
// Config options:
//   address: Listen address (default: 0.0.0.0:9091)
pub struct PrometheusPushgatewaySource {
	address string = '0.0.0.0:9091'
}

// new_prometheus_pushgateway creates a new PrometheusPushgatewaySource from config options.
pub fn new_prometheus_pushgateway(opts map[string]string) PrometheusPushgatewaySource {
	address := opts['address'] or { '0.0.0.0:9091' }

	return PrometheusPushgatewaySource{
		address: address
	}
}

// run starts the HTTP server and processes Pushgateway push requests.
pub fn (s &PrometheusPushgatewaySource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('prometheus_pushgateway: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('prometheus_pushgateway: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		spawn handle_pushgateway_conn(mut conn, output)
	}
}

fn handle_pushgateway_conn(mut conn net.TcpConn, output chan event.Event) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	req := read_pushgateway_request(mut conn) or {
		send_pushgateway_response(mut conn, 400, 'failed to read request: ${err}')
		return
	}

	// Only accept PUT or POST
	if req.method != 'PUT' && req.method != 'POST' {
		send_pushgateway_response(mut conn, 405, 'method not allowed')
		return
	}

	// Parse job from path: /metrics/job/{job} or /metrics/job/{job}/...
	job := extract_pushgateway_job(req.path)
	if job.len == 0 {
		send_pushgateway_response(mut conn, 404, 'not found: expected /metrics/job/{job}')
		return
	}

	// Extract additional grouping labels from path
	grouping_labels := extract_pushgateway_labels(req.path)

	// Parse Prometheus text format from body
	metrics := parse_prometheus_text(req.body)
	for m in metrics {
		mut metric := m
		metric.meta.source_type = 'prometheus_pushgateway'
		// Add job label from URL path
		metric.tags['job'] = job
		// Add any additional grouping labels
		for k, v in grouping_labels {
			metric.tags[k] = v
		}
		output <- event.Event(metric)
	}

	// Send 200 OK
	response := 'HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n'
	conn.write(response.bytes()) or {}
}

// extract_pushgateway_job extracts the job name from a Pushgateway URL path.
// Expected path format: /metrics/job/{job} or /metrics/job/{job}/label/value/...
fn extract_pushgateway_job(path string) string {
	prefix := '/metrics/job/'
	if !path.starts_with(prefix) {
		return ''
	}
	rest := path[prefix.len..]
	if rest.len == 0 {
		return ''
	}
	// Job name is everything up to the next slash (or end of string)
	slash := rest.index('/') or { return rest }
	return rest[..slash]
}

// extract_pushgateway_labels extracts additional grouping labels from the path.
// Path format after job: /metrics/job/{job}/{label1}/{value1}/{label2}/{value2}/...
fn extract_pushgateway_labels(path string) map[string]string {
	mut labels := map[string]string{}
	prefix := '/metrics/job/'
	if !path.starts_with(prefix) {
		return labels
	}
	rest := path[prefix.len..]
	// Skip past the job name
	slash := rest.index('/') or { return labels }
	label_part := rest[slash + 1..]
	if label_part.len == 0 {
		return labels
	}

	parts := label_part.trim_right('/').split('/')
	mut i := 0
	for i + 1 < parts.len {
		if parts[i].len > 0 && parts[i + 1].len > 0 {
			labels[parts[i]] = parts[i + 1]
		}
		i += 2
	}
	return labels
}

// PushgatewayRequest holds a parsed HTTP request.
struct PushgatewayRequest {
	method  string
	path    string
	headers map[string]string
	body    string
}

// read_pushgateway_request reads and parses an HTTP request from a TCP connection.
fn read_pushgateway_request(mut conn net.TcpConn) !PushgatewayRequest {
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

	return PushgatewayRequest{
		method: method
		path: path
		headers: headers
		body: body_str
	}
}

fn send_pushgateway_response(mut conn net.TcpConn, status int, message string) {
	status_text := match status {
		400 { 'Bad Request' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		else { 'Error' }
	}
	body := '{"error":"${message}"}'
	response := 'HTTP/1.1 ${status} ${status_text}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
	conn.write(response.bytes()) or {}
}
