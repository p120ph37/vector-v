module api

import net
import time

// ApiServer provides health and readiness endpoints.
// Mirrors Vector's GraphQL API (simplified to REST).
//
// Endpoints:
//   GET /health  - Returns 200 if the process is alive
//   GET /ready   - Returns 200 if the pipeline is running
//
// Config:
//   enabled:  true/false (default: false)
//   address:  bind address (default: 0.0.0.0:8686)
pub struct ApiServer {
	address  string = '0.0.0.0:8686'
	is_ready bool
}

// new_api creates a new ApiServer from config options.
pub fn new_api(opts map[string]string) ApiServer {
	address := opts['api.address'] or { '0.0.0.0:8686' }
	return ApiServer{
		address: address
	}
}

// new_api_ready creates an ApiServer that is already in the ready state.
pub fn new_api_ready(opts map[string]string) ApiServer {
	address := opts['api.address'] or { '0.0.0.0:8686' }
	return ApiServer{
		address: address
		is_ready: true
	}
}

// run_server is a free function to start the API server in a spawn.
pub fn run_server(address string) {
	s := ApiServer{
		address: address
		is_ready: true
	}
	s.run()
}

// run starts the API server. Blocks forever.
pub fn (s &ApiServer) run() {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('api: failed to bind ${s.address}: ${err}')
		return
	}
	eprintln('api: listening on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		is_ready := s.is_ready
		spawn handle_api_request(mut conn, is_ready)
	}
}

fn handle_api_request(mut conn net.TcpConn, is_ready bool) {
	defer {
		conn.close() or {}
	}
	conn.set_read_timeout(5 * time.second)

	mut buf := []u8{len: 4096}
	bytes_read := conn.read(mut buf) or { return }
	if bytes_read == 0 {
		return
	}

	request := buf[..bytes_read].bytestr()
	first_line := request.split('\n')[0] or { '' }
	parts := first_line.split(' ')
	if parts.len < 2 {
		send_response(mut conn, 400, '{"error":"bad request"}')
		return
	}

	method := parts[0]
	path := parts[1]

	if method != 'GET' {
		send_response(mut conn, 405, '{"error":"method not allowed"}')
		return
	}

	match path {
		'/health' {
			send_response(mut conn, 200, '{"status":"ok"}')
		}
		'/ready' {
			if is_ready {
				send_response(mut conn, 200, '{"status":"ready"}')
			} else {
				send_response(mut conn, 503, '{"status":"not ready"}')
			}
		}
		'/' {
			body := '{"version":"0.1.0","name":"vector-v"}'
			send_response(mut conn, 200, body)
		}
		else {
			send_response(mut conn, 404, '{"error":"not found"}')
		}
	}
}

fn send_response(mut conn net.TcpConn, status int, body string) {
	status_text := match status {
		200 { 'OK' }
		400 { 'Bad Request' }
		404 { 'Not Found' }
		405 { 'Method Not Allowed' }
		503 { 'Service Unavailable' }
		else { 'Unknown' }
	}
	response := 'HTTP/1.1 ${status} ${status_text}\r\nContent-Type: application/json\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
	conn.write(response.bytes()) or {}
}
