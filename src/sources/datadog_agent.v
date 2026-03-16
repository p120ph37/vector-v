module sources

import event
import json
import net
import time

// DatadogAgentSource accepts forwarded data from Datadog agents via HTTP.
// Mirrors Vector's datadog_agent source (src/sources/datadog_agent/).
//
// Listens on a TCP port and accepts HTTP POST requests on Datadog-compatible
// endpoints. Uses minimal HTTP parsing directly over TCP (same pattern as
// other TCP-based sources in this project).
//
// Config options:
//   address:       Listen address (default: 0.0.0.0:8282)
//   store_api_key: Whether to store the DD API key in events (default: false)
pub struct DatadogAgentSource {
	address       string = '0.0.0.0:8282'
	store_api_key bool
}

// DatadogLogEntry represents a single log entry from a Datadog agent payload.
struct DatadogLogEntry {
	message  string
	hostname string
	service  string
	ddsource string
	ddtags   string
	status   string
}

// new_datadog_agent creates a new DatadogAgentSource from config options.
pub fn new_datadog_agent(opts map[string]string) DatadogAgentSource {
	address := opts['address'] or { '0.0.0.0:8282' }

	store_api_key := match opts['store_api_key'] or { 'false' } {
		'true', '1', 'yes' { true }
		else { false }
	}

	return DatadogAgentSource{
		address: address
		store_api_key: store_api_key
	}
}

// run listens for HTTP connections from Datadog agents.
pub fn (s &DatadogAgentSource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('datadog_agent: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('datadog_agent: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		store_key := s.store_api_key
		spawn handle_datadog_conn(mut conn, output, store_key)
	}
}

fn handle_datadog_conn(mut conn net.TcpConn, output chan event.Event, store_api_key bool) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	// Read the full HTTP request
	mut raw := []u8{}
	mut buf := []u8{len: 8192}
	for {
		n := conn.read(mut buf) or { break }
		if n == 0 {
			break
		}
		raw << buf[..n]
		// Check if we have the complete request (headers + body)
		raw_str := raw.bytestr()
		header_end := raw_str.index('\r\n\r\n') or { continue }
		headers_part := raw_str[..header_end]
		body_start := header_end + 4
		// Find Content-Length
		content_length := parse_content_length(headers_part)
		if content_length <= 0 {
			break
		}
		if raw_str.len >= body_start + content_length {
			break
		}
	}
	if raw.len == 0 {
		return
	}

	raw_str := raw.bytestr()
	header_end := raw_str.index('\r\n\r\n') or {
		send_http_response(mut conn, 400, '{"error":"bad request"}')
		return
	}

	headers_part := raw_str[..header_end]
	body := raw_str[header_end + 4..]

	// Parse request line
	first_line_end := headers_part.index('\r\n') or { headers_part.len }
	request_line := headers_part[..first_line_end]
	parts := request_line.split(' ')
	if parts.len < 2 {
		send_http_response(mut conn, 400, '{"error":"bad request"}')
		return
	}
	method := parts[0]
	path := parts[1]

	// Only accept POST
	if method != 'POST' {
		send_http_response(mut conn, 405, '{"error":"method not allowed"}')
		return
	}

	// Validate endpoint
	if path != '/api/v2/logs' && path != '/v1/input' {
		send_http_response(mut conn, 404, '{"error":"not found"}')
		return
	}

	// Extract DD-API-KEY header
	api_key := parse_header_value(headers_part, 'dd-api-key')

	// Parse log entries from the body
	entries := parse_datadog_logs(body)

	for entry in entries {
		msg := if entry.message.len > 0 { entry.message } else { body }
		mut ev := event.new_log(msg)
		ev.meta.source_type = 'datadog_agent'

		if entry.hostname.len > 0 {
			ev.set('hostname', event.Value(entry.hostname))
		}
		if entry.service.len > 0 {
			ev.set('service', event.Value(entry.service))
		}
		if entry.ddsource.len > 0 {
			ev.set('ddsource', event.Value(entry.ddsource))
		}
		if entry.status.len > 0 {
			ev.set('status', event.Value(entry.status))
		}
		// Parse ddtags "key:val,key2:val2" into individual fields
		if entry.ddtags.len > 0 {
			ev.set('ddtags', event.Value(entry.ddtags))
			tags := entry.ddtags.split(',')
			for tag in tags {
				tag_trimmed := tag.trim_space()
				if tag_trimmed.len == 0 {
					continue
				}
				colon_idx := tag_trimmed.index(':') or { -1 }
				if colon_idx > 0 {
					tag_key := tag_trimmed[..colon_idx]
					tag_val := tag_trimmed[colon_idx + 1..]
					ev.set('tag.${tag_key}', event.Value(tag_val))
				} else {
					// Tag without value
					ev.set('tag.${tag_trimmed}', event.Value(''))
				}
			}
		}
		if store_api_key && api_key.len > 0 {
			ev.set('dd_api_key', event.Value(api_key))
		}
		output <- event.Event(ev)
	}

	send_http_response(mut conn, 200, '{"status":"ok"}')
}

// parse_datadog_logs parses a JSON body into DatadogLogEntry items.
// Accepts both a JSON array of objects and a single object.
fn parse_datadog_logs(body string) []DatadogLogEntry {
	trimmed := body.trim_space()
	if trimmed.len == 0 {
		return []
	}
	// Try as JSON array first
	if trimmed.starts_with('[') {
		arr := json.decode([]DatadogLogEntry, trimmed) or { return [] }
		return arr
	}
	// Try as single object
	entry := json.decode(DatadogLogEntry, trimmed) or {
		// Treat the whole body as a plain-text message
		return [DatadogLogEntry{
			message: trimmed
		}]
	}
	return [entry]
}

// parse_content_length extracts the Content-Length value from raw headers.
fn parse_content_length(headers string) int {
	for line in headers.split('\r\n') {
		lower := line.to_lower()
		if lower.starts_with('content-length:') {
			val := line[15..].trim_space()
			return val.int()
		}
	}
	return 0
}

// parse_header_value extracts a header value by name (case-insensitive).
fn parse_header_value(headers string, name string) string {
	target := name.to_lower()
	for line in headers.split('\r\n') {
		colon := line.index(':') or { continue }
		key := line[..colon].trim_space().to_lower()
		if key == target {
			return line[colon + 1..].trim_space()
		}
	}
	return ''
}

// send_http_response writes a minimal HTTP/1.1 response.
fn send_http_response(mut conn net.TcpConn, status int, body string) {
	reason := match status {
		200 { 'OK' }
		400 { 'Bad Request' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		else { 'Error' }
	}
	resp := 'HTTP/1.1 ${status} ${reason}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
	conn.write(resp.bytes()) or {}
}
