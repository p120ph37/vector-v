module sources

import encoding.base64
import event
import json
import net
import time

// KinesisFirehoseSource provides an HTTP endpoint for receiving data from
// AWS Kinesis Data Firehose delivery streams. Mirrors Vector's
// aws_kinesis_firehose source.
//
// Firehose sends batches of records via HTTP POST with a JSON body
// containing base64-encoded data records. The source decodes each record
// and emits it as a log event.
//
// Config options:
//   address:          Listen address (default: 0.0.0.0:443)
//   access_key:       Expected value of X-Amz-Firehose-Access-Key header (optional)
//   store_access_key: Whether to store the access key in event metadata (default: false)
pub struct KinesisFirehoseSource {
	address          string = '0.0.0.0:443'
	access_key       string
	store_access_key bool
}

// new_kinesis_firehose creates a new KinesisFirehoseSource from config options.
pub fn new_kinesis_firehose(opts map[string]string) KinesisFirehoseSource {
	address := opts['address'] or { '0.0.0.0:443' }
	access_key := opts['access_key'] or { '' }
	store_val := opts['store_access_key'] or { 'false' }

	return KinesisFirehoseSource{
		address: address
		access_key: access_key
		store_access_key: store_val == 'true'
	}
}

// run starts the HTTP server and processes Firehose delivery requests.
pub fn (s &KinesisFirehoseSource) run(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('kinesis_firehose: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('kinesis_firehose: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		access_key := s.access_key
		store_key := s.store_access_key
		spawn handle_firehose_conn(mut conn, output, access_key, store_key)
	}
}

fn handle_firehose_conn(mut conn net.TcpConn, output chan event.Event, access_key string, store_access_key bool) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	// Read HTTP request
	req := read_firehose_request(mut conn) or {
		send_firehose_error(mut conn, '', 'failed to read request: ${err}')
		return
	}

	// Validate access key if configured
	if access_key.len > 0 {
		req_key := req.headers['x-amz-firehose-access-key'] or { '' }
		if req_key != access_key {
			send_firehose_error(mut conn, req.request_id, 'invalid access key')
			return
		}
	}

	// Parse JSON body
	payload := json.decode(FirehosePayload, req.body) or {
		send_firehose_error(mut conn, req.request_id, 'invalid JSON: ${err}')
		return
	}

	request_id := payload.request_id

	// Process each record
	for record in payload.records {
		decoded := base64.decode_str(record.data)
		if decoded.len == 0 {
			continue
		}

		mut ev := event.new_log(decoded)
		ev.meta.source_type = 'aws_kinesis_firehose'
		ev.set('request_id', event.Value(request_id))
		if store_access_key {
			req_key := req.headers['x-amz-firehose-access-key'] or { '' }
			if req_key.len > 0 {
				ev.set('access_key', event.Value(req_key))
			}
		}
		output <- event.Event(ev)
	}

	// Send success response
	send_firehose_response(mut conn, request_id)
}

// FirehosePayload represents the JSON body sent by Kinesis Firehose.
struct FirehosePayload {
	request_id string           @[json: 'requestId']
	records    []FirehoseRecord
}

struct FirehoseRecord {
	data string
}

// FirehoseRequest holds a parsed HTTP request from Firehose.
struct FirehoseRequest {
	method     string
	path       string
	headers    map[string]string
	body       string
	request_id string
}

// read_firehose_request reads and parses an HTTP request from a TCP connection.
fn read_firehose_request(mut conn net.TcpConn) !FirehoseRequest {
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
	mut body := body_start
	content_length_str := headers['content-length'] or { '0' }
	content_length := content_length_str.int()
	if content_length > 0 && body.len < content_length {
		remaining := content_length - body.len
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
		body += body_buf[..total_read].bytestr()
	}

	return FirehoseRequest{
		method: method
		path: path
		headers: headers
		body: body
		request_id: headers['x-amz-firehose-request-id'] or { '' }
	}
}

fn send_firehose_response(mut conn net.TcpConn, request_id string) {
	ts := time.now().unix()
	body := '{"requestId":"${request_id}","timestamp":${ts},"errorMessage":""}'
	response := 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
	conn.write(response.bytes()) or {}
}

fn send_firehose_error(mut conn net.TcpConn, request_id string, error_msg string) {
	ts := time.now().unix()
	body := '{"requestId":"${request_id}","timestamp":${ts},"errorMessage":"${error_msg}"}'
	response := 'HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\n\r\n${body}'
	conn.write(response.bytes()) or {}
}
