module sources

import event
import net
import time

// RedisSource subscribes to Redis channels (pub/sub) or polls from a list.
// Mirrors Vector's redis source (src/sources/redis/).
//
// Implements a minimal Redis RESP (REdis Serialization Protocol) client
// directly over TCP — no external Redis library is needed.
//
// Config options:
//   url:              Redis connection URL (default: redis://127.0.0.1:6379)
//   mode:             "subscribe" or "list" (default: subscribe)
//   key:              Channel name (subscribe) or list key (list) — required
//   list_option:      "lpop" or "rpop" (default: lpop)
//   poll_interval_ms: Poll interval in ms for list mode (default: 1000)
pub struct RedisSource {
	url              string = 'redis://127.0.0.1:6379'
	mode             RedisMode
	key              string
	list_option      string = 'lpop'
	poll_interval_ms int    = 1000
	host             string = '127.0.0.1'
	port             int    = 6379
	auth             string
}

enum RedisMode {
	subscribe
	list
}

struct RedisAddr {
	host string = '127.0.0.1'
	port int    = 6379
	auth string
}

// parse_redis_url extracts host, port and optional auth from a redis:// URL.
// Format: redis://[:password@]host[:port][/db]
fn parse_redis_url(url string) RedisAddr {
	mut s := url
	// Strip scheme
	if s.starts_with('redis://') {
		s = s[8..]
	} else if s.starts_with('rediss://') {
		s = s[9..]
	}
	// Strip path/db suffix
	slash_idx := s.index('/') or { -1 }
	if slash_idx >= 0 {
		s = s[..slash_idx]
	}
	// Check for auth (password@host)
	mut auth := ''
	at_idx := s.index('@') or { -1 }
	if at_idx >= 0 {
		auth_part := s[..at_idx]
		s = s[at_idx + 1..]
		// auth_part may be ":password" or "user:password"
		if auth_part.starts_with(':') {
			auth = auth_part[1..]
		} else {
			auth = auth_part
		}
	}
	// Parse host:port
	mut host := '127.0.0.1'
	mut port := 6379
	colon_idx := s.last_index(':') or { -1 }
	if colon_idx >= 0 {
		host = s[..colon_idx]
		port = s[colon_idx + 1..].int()
		if port <= 0 {
			port = 6379
		}
	} else if s.len > 0 {
		host = s
	}
	if host.len == 0 {
		host = '127.0.0.1'
	}
	return RedisAddr{
		host: host
		port: port
		auth: auth
	}
}

// new_redis_source creates a new RedisSource from config options.
pub fn new_redis_source(opts map[string]string) !RedisSource {
	key := opts['key'] or {
		return error('redis source: key is required')
	}

	url := opts['url'] or { 'redis://127.0.0.1:6379' }
	addr := parse_redis_url(url)

	mode := match opts['mode'] or { 'subscribe' } {
		'list' { RedisMode.list }
		else { RedisMode.subscribe }
	}

	list_option := match opts['list_option'] or { 'lpop' } {
		'rpop' { 'rpop' }
		else { 'lpop' }
	}

	mut poll_interval_ms := 1000
	if p := opts['poll_interval_ms'] {
		poll_interval_ms = p.int()
		if poll_interval_ms <= 0 {
			poll_interval_ms = 1000
		}
	}

	return RedisSource{
		url: url
		mode: mode
		key: key
		list_option: list_option
		poll_interval_ms: poll_interval_ms
		host: addr.host
		port: addr.port
		auth: addr.auth
	}
}

// send_redis_command encodes args as a RESP array of bulk strings and sends it.
// RESP format: *N\r\n$len\r\narg\r\n...
fn send_redis_command(mut conn net.TcpConn, args []string) {
	mut buf := []u8{}
	buf << '*${args.len}\r\n'.bytes()
	for arg in args {
		buf << '\$${arg.len}\r\n'.bytes()
		buf << arg.bytes()
		buf << '\r\n'.bytes()
	}
	conn.write(buf) or {}
}

// read_redis_resp reads one RESP value from the connection and returns it
// as a string. For bulk strings, returns the data. For simple strings, returns
// the string. For arrays (subscribe messages), returns the last bulk string
// element (the message payload). For integers, returns the numeric string.
// Returns error on connection failure or nil/error RESP types.
fn read_redis_resp(mut conn net.TcpConn) !string {
	line := read_resp_line(mut conn)!
	if line.len == 0 {
		return error('empty RESP response')
	}
	prefix := line[0]
	body := line[1..]
	match prefix {
		`+` {
			// Simple string: +OK\r\n
			return body
		}
		`-` {
			// Error: -ERR message\r\n
			return error('redis error: ${body}')
		}
		`:` {
			// Integer: :N\r\n
			return body
		}
		`\$` {
			// Bulk string: $len\r\ndata\r\n
			length := body.int()
			if length < 0 {
				return error('nil bulk string')
			}
			data := read_resp_bytes(mut conn, length)!
			// consume trailing \r\n
			read_resp_line(mut conn) or {}
			return data
		}
		`*` {
			// Array: *N\r\n...elements...
			count := body.int()
			if count < 0 {
				return error('nil array')
			}
			mut last_val := ''
			for _ in 0 .. count {
				last_val = read_redis_resp(mut conn) or { '' }
			}
			// For subscribe messages, the last element is the payload
			return last_val
		}
		else {
			return error('unknown RESP type: ${[prefix].bytestr()}')
		}
	}
}

// read_resp_line reads bytes until \r\n and returns the line without the delimiter.
fn read_resp_line(mut conn net.TcpConn) !string {
	mut result := []u8{}
	mut buf := []u8{len: 1}
	for {
		n := conn.read(mut buf) or { return error('connection read error: ${err}') }
		if n == 0 {
			return error('connection closed')
		}
		if buf[0] == `\r` {
			// read the \n
			conn.read(mut buf) or {}
			break
		}
		result << buf[0]
	}
	return result.bytestr()
}

// read_resp_bytes reads exactly `count` bytes from the connection.
fn read_resp_bytes(mut conn net.TcpConn, count int) !string {
	if count == 0 {
		return ''
	}
	mut result := []u8{cap: count}
	mut remaining := count
	for remaining > 0 {
		mut buf := []u8{len: remaining}
		n := conn.read(mut buf) or { return error('connection read error: ${err}') }
		if n == 0 {
			return error('connection closed')
		}
		result << buf[..n]
		remaining -= n
	}
	return result.bytestr()
}

// run connects to Redis and begins consuming messages.
pub fn (s &RedisSource) run(output chan event.Event) {
	address := '${s.host}:${s.port}'
	eprintln('redis: connecting to ${address} (mode: ${s.mode}, key: ${s.key})')

	match s.mode {
		.subscribe { s.run_subscribe(output, address) }
		.list { s.run_list(output, address) }
	}
}

fn (s &RedisSource) connect(address string) !net.TcpConn {
	mut conn := net.dial_tcp(address) or {
		return error('redis: failed to connect to ${address}: ${err}')
	}
	conn.set_read_timeout(30 * time.second)

	// Authenticate if password is configured
	if s.auth.len > 0 {
		send_redis_command(mut conn, ['AUTH', s.auth])
		resp := read_redis_resp(mut conn) or {
			conn.close() or {}
			return error('redis: AUTH failed: ${err}')
		}
		if resp != 'OK' {
			conn.close() or {}
			return error('redis: AUTH failed: ${resp}')
		}
	}
	return *conn
}

fn (s &RedisSource) run_subscribe(output chan event.Event, address string) {
	for {
		mut conn := s.connect(address) or {
			eprintln('${err}')
			time.sleep(5 * time.second)
			continue
		}
		eprintln('redis: subscribed to channel "${s.key}"')
		// Set a longer timeout for subscribe — messages may be infrequent
		conn.set_read_timeout(300 * time.second)
		send_redis_command(mut conn, ['SUBSCRIBE', s.key])

		// Read the subscribe confirmation
		_ = read_redis_resp(mut conn) or {
			eprintln('redis: subscribe confirmation failed: ${err}')
			conn.close() or {}
			time.sleep(5 * time.second)
			continue
		}

		// Read messages in a loop
		for {
			// Each message is a 3-element array: ["message", channel, data]
			// read_redis_resp returns the last element (the payload)
			msg := read_redis_resp(mut conn) or {
				eprintln('redis: read error: ${err}')
				break
			}
			if msg.len == 0 {
				continue
			}
			mut ev := event.new_log(msg)
			ev.meta.source_type = 'redis'
			ev.set('channel', event.Value(s.key))
			ev.set('redis_mode', event.Value('subscribe'))
			output <- event.Event(ev)
		}
		conn.close() or {}
		eprintln('redis: connection lost, reconnecting in 5s...')
		time.sleep(5 * time.second)
	}
}

fn (s &RedisSource) run_list(output chan event.Event, address string) {
	cmd := if s.list_option == 'rpop' { 'RPOP' } else { 'LPOP' }
	poll_dur := time.Duration(i64(s.poll_interval_ms) * 1_000_000)

	for {
		mut conn := s.connect(address) or {
			eprintln('${err}')
			time.sleep(5 * time.second)
			continue
		}
		eprintln('redis: polling list "${s.key}" with ${cmd}')

		for {
			send_redis_command(mut conn, [cmd, s.key])
			resp := read_redis_resp(mut conn) or {
				// nil bulk string means empty list, or connection error
				if '${err}'.contains('nil') {
					time.sleep(poll_dur)
					continue
				}
				eprintln('redis: read error: ${err}')
				break
			}
			if resp.len == 0 {
				time.sleep(poll_dur)
				continue
			}
			mut ev := event.new_log(resp)
			ev.meta.source_type = 'redis'
			ev.set('list_key', event.Value(s.key))
			ev.set('redis_mode', event.Value('list'))
			output <- event.Event(ev)
		}
		conn.close() or {}
		eprintln('redis: connection lost, reconnecting in 5s...')
		time.sleep(5 * time.second)
	}
}
