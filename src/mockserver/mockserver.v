module mockserver

import net
import time

// MockServer provides a lightweight, declarative HTTP mock server for testing
// network-dependent components (sinks, sources, transforms).
//
// Usage:
//   mut mock := mockserver.start(
//       mockserver.get('/health', mockserver.respond(200, '{"status":"ok"}')),
//       mockserver.put('/token', mockserver.respond(200, 'my-token')),
//       mockserver.post('/api/push', mockserver.respond(204, '')),
//   )!
//   defer { mock.stop() }
//
//   // Make HTTP requests to mock.url()...
//
//   reqs := mock.wait_for_requests(2, 5000)
//   assert reqs.len == 2
//   assert reqs[0].path == '/health'

// Response defines what the mock server returns for a matched route.
pub struct Response {
pub:
	status  int = 200
	body    string
	headers map[string]string
}

// Route defines a method+path pattern and the responses to cycle through.
pub struct Route {
pub:
	method    string     // HTTP method: GET, POST, PUT, DELETE, etc.
	path      string     // Exact path to match
	responses []Response // Cycles through these on successive hits
}

// CapturedRequest stores the full details of each received HTTP request.
pub struct CapturedRequest {
pub:
	method  string
	path    string
	headers map[string]string
	body    string
}

// MockServer runs an HTTP server on 127.0.0.1 in a background thread.
pub struct MockServer {
pub:
	port int
mut:
	capture   chan CapturedRequest
	collected []CapturedRequest
}

// respond creates a Response with the given status and body.
pub fn respond(status int, body string) Response {
	return Response{
		status: status
		body: body
	}
}

// respond_with_headers creates a Response with custom headers.
pub fn respond_with_headers(status int, body string, headers map[string]string) Response {
	return Response{
		status: status
		body: body
		headers: headers
	}
}

// get creates a GET route with one or more responses.
pub fn get(path string, responses ...Response) Route {
	return Route{
		method: 'GET'
		path: path
		responses: responses
	}
}

// post creates a POST route with one or more responses.
pub fn post(path string, responses ...Response) Route {
	return Route{
		method: 'POST'
		path: path
		responses: responses
	}
}

// put creates a PUT route with one or more responses.
pub fn put(path string, responses ...Response) Route {
	return Route{
		method: 'PUT'
		path: path
		responses: responses
	}
}

// route creates a route with an arbitrary HTTP method.
pub fn route(method string, path string, responses ...Response) Route {
	return Route{
		method: method
		path: path
		responses: responses
	}
}

// sequence creates a route that cycles through multiple responses.
// First request gets responses[0], second gets responses[1], etc., wrapping around.
pub fn sequence(method string, path string, responses []Response) Route {
	return Route{
		method: method
		path: path
		responses: responses
	}
}

// start binds to a free port on 127.0.0.1 and starts the mock server
// in a background thread. The server is ready to accept requests when
// this function returns.
pub fn start(routes ...Route) !MockServer {
	ready := chan int{cap: 1}
	capture := chan CapturedRequest{cap: 10000}

	spawn run_mock_server(routes, capture, ready)

	port := <-ready
	if port < 0 {
		return error('mockserver: could not bind to any port in range 28100-28999')
	}

	return MockServer{
		port: port
		capture: capture
	}
}

// start_with_routes starts a mock server from a pre-built route slice.
pub fn start_with_routes(routes []Route) !MockServer {
	ready := chan int{cap: 1}
	capture := chan CapturedRequest{cap: 10000}

	spawn run_mock_server(routes, capture, ready)

	port := <-ready
	if port < 0 {
		return error('mockserver: could not bind to any port in range 28100-28999')
	}

	return MockServer{
		port: port
		capture: capture
	}
}

// url returns the base URL of the mock server (e.g. "http://127.0.0.1:28105").
pub fn (s &MockServer) url() string {
	return 'http://127.0.0.1:${s.port}'
}

// wait_for_requests blocks until at least `count` requests have been captured,
// or timeout_ms milliseconds have elapsed. Returns all captured requests.
pub fn (mut s MockServer) wait_for_requests(count int, timeout_ms int) []CapturedRequest {
	deadline := time.now().unix_milli() + timeout_ms
	for s.collected.len < count {
		if time.now().unix_milli() >= deadline {
			break
		}
		mut req := CapturedRequest{}
		if s.capture.try_pop(mut req) == .success {
			s.collected << req
		} else {
			time.sleep(5 * time.millisecond)
		}
	}
	return s.collected
}

// requests non-blocking drains any pending captured requests and returns
// all requests captured so far.
pub fn (mut s MockServer) requests() []CapturedRequest {
	for {
		mut req := CapturedRequest{}
		if s.capture.try_pop(mut req) == .success {
			s.collected << req
		} else {
			break
		}
	}
	return s.collected
}

// request_count returns the total number of requests captured.
pub fn (mut s MockServer) request_count() int {
	_ = s.requests()
	return s.collected.len
}

// stop closes the capture channel. The background listener thread will
// continue to exist but captured requests will no longer be recorded.
pub fn (mut s MockServer) stop() {
	s.capture.close()
}

// --- Internal server implementation ---

fn run_mock_server(routes []Route, capture chan CapturedRequest, ready chan int) {
	for p in 28100 .. 29000 {
		mut listener := net.listen_tcp(.ip, '127.0.0.1:${p}') or { continue }
		ready <- p

		mut route_hits := map[string]int{}

		for {
			mut conn := listener.accept() or {
				time.sleep(10 * time.millisecond)
				continue
			}
			handle_mock_conn(mut conn, routes, capture, mut route_hits)
		}
		return
	}
	ready <- -1
}

fn handle_mock_conn(mut conn net.TcpConn, routes []Route, capture chan CapturedRequest, mut route_hits map[string]int) {
	defer {
		conn.close() or {}
	}
	conn.set_read_timeout(5 * time.second)

	mut buf := []u8{len: 65536}
	bytes_read := conn.read(mut buf) or { return }
	if bytes_read == 0 {
		return
	}

	raw := buf[..bytes_read].bytestr()

	// Parse HTTP request: request line + headers + body
	header_end := raw.index('\r\n\r\n') or {
		send_mock_response(mut conn, 400, 'bad request', map[string]string{})
		return
	}

	header_section := raw[..header_end]
	mut body := raw[header_end + 4..]

	lines := header_section.split('\r\n')
	if lines.len == 0 {
		send_mock_response(mut conn, 400, 'bad request', map[string]string{})
		return
	}

	request_line := lines[0]
	parts := request_line.split(' ')
	if parts.len < 2 {
		send_mock_response(mut conn, 400, 'bad request', map[string]string{})
		return
	}

	method := parts[0]
	path := parts[1]

	// Parse headers
	mut headers := map[string]string{}
	for i in 1 .. lines.len {
		colon := lines[i].index(':') or { continue }
		key := lines[i][..colon].trim_space().to_lower()
		val := lines[i][colon + 1..].trim_space()
		headers[key] = val
	}

	// Read remaining body if Content-Length indicates more data
	if cl_str := headers['content-length'] {
		content_length := cl_str.int()
		if content_length > 0 && body.len < content_length {
			mut remaining := content_length - body.len
			mut body_bytes := body.bytes()
			for remaining > 0 {
				mut extra := []u8{len: remaining}
				n := conn.read(mut extra) or { break }
				if n == 0 {
					break
				}
				body_bytes << extra[..n]
				remaining -= n
			}
			body = body_bytes.bytestr()
		}
	}

	// Capture the request
	captured := CapturedRequest{
		method: method
		path: path
		headers: headers
		body: body
	}
	capture.try_push(captured)

	// Find matching route and send response
	route_key := '${method} ${path}'
	for r in routes {
		if r.method == method && r.path == path {
			if r.responses.len == 0 {
				send_mock_response(mut conn, 200, '', map[string]string{})
				route_hits[route_key] = (route_hits[route_key] or { 0 }) + 1
				return
			}
			hit := route_hits[route_key] or { 0 }
			resp_idx := hit % r.responses.len
			resp := r.responses[resp_idx]
			route_hits[route_key] = hit + 1
			send_mock_response(mut conn, resp.status, resp.body, resp.headers)
			return
		}
	}

	// No matching route — return 404
	send_mock_response(mut conn, 404, '{"error":"no matching route for ${method} ${path}"}',
		map[string]string{})
}

fn send_mock_response(mut conn net.TcpConn, status int, body string, headers map[string]string) {
	status_text := match status {
		200 { 'OK' }
		201 { 'Created' }
		204 { 'No Content' }
		400 { 'Bad Request' }
		401 { 'Unauthorized' }
		403 { 'Forbidden' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		429 { 'Too Many Requests' }
		500 { 'Internal Server Error' }
		503 { 'Service Unavailable' }
		else { 'Unknown' }
	}

	mut header_lines := ''
	for k, v in headers {
		header_lines += '${k}: ${v}\r\n'
	}

	response := 'HTTP/1.1 ${status} ${status_text}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\nConnection: close\r\n${header_lines}\r\n${body}'
	conn.write(response.bytes()) or {}
}
