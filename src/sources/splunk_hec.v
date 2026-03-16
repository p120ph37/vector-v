module sources

import event
import json
import net
import time

// SplunkHecSource provides an HTTP endpoint for receiving events via the
// Splunk HTTP Event Collector (HEC) protocol. Mirrors Vector's splunk_hec
// source.
//
// Accepts HEC JSON payloads via HTTP POST on /services/collector/event or
// /services/collector and emits each event as a log event. Also responds
// to health checks on GET /services/collector/health.
//
// Config options:
//   address:         Listen address (default: 0.0.0.0:8088)
//   token:           Expected HEC token in Authorization header (optional)
//   store_hec_token: Store token in event metadata (default: false)
pub struct SplunkHecSource {
	address         string = '0.0.0.0:8088'
	token           string
	store_hec_token bool
}

// new_splunk_hec creates a new SplunkHecSource from config options.
pub fn new_splunk_hec_source(opts map[string]string) SplunkHecSource {
	address := opts['address'] or { '0.0.0.0:8088' }
	token := opts['token'] or { '' }
	store_val := opts['store_hec_token'] or { 'false' }

	return SplunkHecSource{
		address: address
		token: token
		store_hec_token: store_val == 'true'
	}
}

// run starts the HTTP server and processes HEC event submissions.
pub fn (s &SplunkHecSource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('splunk_hec: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('splunk_hec: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		token := s.token
		store_token := s.store_hec_token
		spawn handle_hec_conn(mut conn, output, token, store_token)
	}
}

fn handle_hec_conn(mut conn net.TcpConn, output chan event.Event, token string, store_hec_token bool) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	// Read HTTP request
	req := read_hec_request(mut conn) or {
		send_hec_error(mut conn, 400, 'failed to read request: ${err}')
		return
	}

	// Health check endpoint
	if req.method == 'GET' && req.path == '/services/collector/health' {
		body := '{"text":"HEC is healthy","code":17}'
		response := 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
		conn.write(response.bytes()) or {}
		return
	}

	// Only accept POST on collector paths
	if req.method != 'POST' || (req.path != '/services/collector/event' && req.path != '/services/collector') {
		send_hec_error(mut conn, 404, 'not found')
		return
	}

	// Validate token if configured
	mut req_token := ''
	if token.len > 0 {
		auth := req.headers['authorization'] or { '' }
		if auth.starts_with('Splunk ') {
			req_token = auth[7..]
		}
		if req_token != token {
			body := '{"text":"Invalid token","code":4}'
			response := 'HTTP/1.1 403 Forbidden\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
			conn.write(response.bytes()) or {}
			return
		}
	} else {
		// Still extract token for store_hec_token even if not validating
		auth := req.headers['authorization'] or { '' }
		if auth.starts_with('Splunk ') {
			req_token = auth[7..]
		}
	}

	// Parse HEC events from body
	events := parse_hec_events(req.body)

	for hec_ev in events {
		mut ev := event.new_log(hec_ev.event_text)
		ev.meta.source_type = 'splunk_hec'
		if hec_ev.host.len > 0 {
			ev.set('host', event.Value(hec_ev.host))
		}
		if hec_ev.source.len > 0 {
			ev.set('source', event.Value(hec_ev.source))
		}
		if hec_ev.sourcetype.len > 0 {
			ev.set('sourcetype', event.Value(hec_ev.sourcetype))
		}
		if hec_ev.index.len > 0 {
			ev.set('index', event.Value(hec_ev.index))
		}
		if hec_ev.timestamp > 0 {
			ev.set('timestamp', event.Value(int(hec_ev.timestamp)))
		}
		if store_hec_token && req_token.len > 0 {
			ev.set('splunk_token', event.Value(req_token))
		}
		output <- event.Event(ev)
	}

	// Send success response
	body := '{"text":"Success","code":0}'
	response := 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
	conn.write(response.bytes()) or {}
}

// HecEvent holds a parsed event from a Splunk HEC request body.
struct HecEvent {
	event_text string
	timestamp  i64
	host       string
	source     string
	sourcetype string
	index      string
}

// parse_hec_events extracts events from an HEC JSON body. Supports both single
// JSON objects and batched newline-separated JSON objects.
// Expected format per object:
//   {"event":"message","time":1234,"host":"h","source":"s","sourcetype":"st","index":"i"}
fn parse_hec_events(body string) []HecEvent {
	mut result := []HecEvent{}

	// HEC supports newline-separated JSON objects for batched events
	lines := body.split('\n')
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		ev := parse_single_hec_event(trimmed)
		if ev.event_text.len > 0 {
			result << ev
		}
	}

	return result
}

// HecJsonEvent is the JSON-decodable representation of a single HEC event.
struct HecJsonEvent {
	event_field string @[json: 'event']
	time_field  i64    @[json: 'time']
	host        string
	source      string
	sourcetype  string
	index       string
}

// parse_single_hec_event parses a single HEC JSON object.
fn parse_single_hec_event(body string) HecEvent {
	obj := json.decode(HecJsonEvent, body) or {
		return HecEvent{}
	}

	return HecEvent{
		event_text: obj.event_field
		timestamp: obj.time_field
		host: obj.host
		source: obj.source
		sourcetype: obj.sourcetype
		index: obj.index
	}
}

// HecRequest holds a parsed HTTP request from an HEC client.
struct HecRequest {
	method  string
	path    string
	headers map[string]string
	body    string
}

// read_hec_request reads and parses an HTTP request from a TCP connection.
fn read_hec_request(mut conn net.TcpConn) !HecRequest {
	mut raw := []u8{}
	mut buf := []u8{len: 4096}

	// Read until we have the full headers
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

	// Parse request line
	request_line := lines[0].split(' ')
	method := if request_line.len > 0 { request_line[0] } else { 'POST' }
	path := if request_line.len > 1 { request_line[1] } else { '/' }

	// Parse headers
	mut headers := map[string]string{}
	for i := 1; i < lines.len; i++ {
		colon := lines[i].index(':') or { continue }
		key := lines[i][..colon].trim_space().to_lower()
		val := lines[i][colon + 1..].trim_space()
		headers[key] = val
	}

	// Read remaining body based on Content-Length
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

	return HecRequest{
		method: method
		path: path
		headers: headers
		body: body_str
	}
}

fn send_hec_error(mut conn net.TcpConn, status int, message string) {
	status_text := match status {
		400 { 'Bad Request' }
		404 { 'Not Found' }
		403 { 'Forbidden' }
		else { 'Error' }
	}
	body := '{"text":"${message}","code":${status}}'
	response := 'HTTP/1.1 ${status} ${status_text}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
	conn.write(response.bytes()) or {}
}
