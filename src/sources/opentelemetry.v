module sources

import event
import json
import net
import time

// OpenTelemetrySource provides an HTTP endpoint for receiving OTLP logs via
// HTTP POST. Mirrors Vector's opentelemetry source.
//
// Accepts OTLP JSON payloads on a configurable path (default /v1/logs) and
// emits each log record as a log event.
//
// Config options:
//   address: Listen address (default: 0.0.0.0:4318)
//   path:    API path to listen on (default: /v1/logs)
pub struct OpenTelemetrySource {
	address string = '0.0.0.0:4318'
	path    string = '/v1/logs'
}

// new_opentelemetry creates a new OpenTelemetrySource from config options.
pub fn new_opentelemetry_source(opts map[string]string) OpenTelemetrySource {
	address := opts['address'] or { '0.0.0.0:4318' }
	path := opts['path'] or { '/v1/logs' }

	return OpenTelemetrySource{
		address: address
		path: path
	}
}

// run starts the HTTP server and processes OTLP log export requests.
pub fn (s &OpenTelemetrySource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('opentelemetry: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('opentelemetry: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		path := s.path
		spawn handle_otlp_conn(mut conn, output, path)
	}
}

fn handle_otlp_conn(mut conn net.TcpConn, output chan event.Event, path string) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	// Read HTTP request
	req := read_otlp_request(mut conn) or {
		send_otlp_error(mut conn, 400, 'failed to read request: ${err}')
		return
	}

	// Only accept POST on the configured path
	if req.method != 'POST' || req.path != path {
		send_otlp_error(mut conn, 404, 'not found')
		return
	}

	// Parse OTLP log records from JSON body
	logs := parse_otlp_logs(req.body)

	for log_entry in logs {
		mut ev := event.new_log(log_entry.message)
		ev.meta.source_type = 'opentelemetry'
		if log_entry.severity.len > 0 {
			ev.set('level', event.Value(log_entry.severity))
		}
		for key, val in log_entry.attributes {
			ev.set(key, event.Value(val))
		}
		output <- event.Event(ev)
	}

	// Send success response
	body := '{"partialSuccess":{}}'
	response := 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
	conn.write(response.bytes()) or {}
}

// OtlpIncomingLog holds a parsed log record from an OTLP export request.
struct OtlpIncomingLog {
	message    string
	severity   string
	attributes map[string]string
}

// JSON structs for OTLP ExportLogsServiceRequest.
// Structure: resourceLogs[] -> scopeLogs[] -> logRecords[]
struct OtlpExportRequest {
	resource_logs []OtlpResourceLogs @[json: 'resourceLogs']
}

struct OtlpResourceLogs {
	scope_logs []OtlpScopeLogs @[json: 'scopeLogs']
}

struct OtlpScopeLogs {
	log_records []OtlpIncomingRecord @[json: 'logRecords']
}

struct OtlpIncomingRecord {
	body          OtlpAnyValue      @[json: 'body']
	severity_text string             @[json: 'severityText']
	time_unix     string             @[json: 'timeUnixNano']
	attributes    []OtlpKeyValue     @[json: 'attributes']
}

struct OtlpAnyValue {
	string_value string @[json: 'stringValue']
	int_value    string @[json: 'intValue']
	bool_value   string @[json: 'boolValue']
}

struct OtlpKeyValue {
	key   string
	value OtlpAnyValue
}

// parse_otlp_logs extracts log records from an OTLP JSON body.
// The expected structure is:
//   {"resourceLogs":[{"scopeLogs":[{"logRecords":[{
//     "body":{"stringValue":"..."},
//     "severityText":"...",
//     "timeUnixNano":"...",
//     "attributes":[{"key":"k","value":{"stringValue":"v"}}]
//   }]}]}]}
fn parse_otlp_logs(body string) []OtlpIncomingLog {
	mut result := []OtlpIncomingLog{}

	req := json.decode(OtlpExportRequest, body) or { return result }

	for rl in req.resource_logs {
		for sl in rl.scope_logs {
			for lr in sl.log_records {
				message := if lr.body.string_value.len > 0 {
					lr.body.string_value
				} else if lr.body.int_value.len > 0 {
					lr.body.int_value
				} else {
					lr.body.bool_value
				}

				mut attrs := map[string]string{}
				for attr in lr.attributes {
					val := if attr.value.string_value.len > 0 {
						attr.value.string_value
					} else if attr.value.int_value.len > 0 {
						attr.value.int_value
					} else {
						attr.value.bool_value
					}
					if val.len > 0 {
						attrs[attr.key] = val
					}
				}

				result << OtlpIncomingLog{
					message: message
					severity: lr.severity_text
					attributes: attrs
				}
			}
		}
	}

	return result
}

// OtlpRequest holds a parsed HTTP request.
struct OtlpRequest {
	method  string
	path    string
	headers map[string]string
	body    string
}

// read_otlp_request reads and parses an HTTP request from a TCP connection.
fn read_otlp_request(mut conn net.TcpConn) !OtlpRequest {
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

	return OtlpRequest{
		method: method
		path: path
		headers: headers
		body: body_str
	}
}

fn send_otlp_error(mut conn net.TcpConn, status int, message string) {
	status_text := match status {
		400 { 'Bad Request' }
		404 { 'Not Found' }
		else { 'Error' }
	}
	body := '{"error":"${message}"}'
	response := 'HTTP/1.1 ${status} ${status_text}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
	conn.write(response.bytes()) or {}
}
