module sinks

import event
import json
import net
import time

// RedisSink pushes events to a Redis list or publishes to a Redis channel.
// Mirrors Vector's redis sink (src/sinks/redis/).
//
// Events are buffered and flushed as RESP commands over a raw TCP connection.
// Supports LPUSH, RPUSH (batch) and PUBLISH (per-event) modes.
//
// Config options:
//   url:                 Redis connection URL (default: "redis://127.0.0.1:6379")
//   mode:                "lpush", "rpush", or "publish" (default: "lpush")
//   key:                 Redis key — list key or channel name (required)
//   encoding.codec:      json or text (default: json)
//   batch.max_events:    Max events per batch (default: 100)
//   batch.timeout_secs:  Batch timeout in seconds (default: 1)
pub struct RedisSink {
	addr          RedisSinkAddr
	mode          RedisSinkMode
	key           string
	codec         RedisCodec
	batch_max     int = 100
	batch_timeout time.Duration = 1 * time.second
mut:
	buffer     []string
	last_flush time.Time
}

enum RedisSinkMode {
	lpush
	rpush
	publish
}

enum RedisCodec {
	json_codec
	text_codec
}

struct RedisSinkAddr {
	host     string
	port     int
	password string
}

// parse_redis_sink_url parses a redis:// URL into host, port, and optional password.
// Format: redis://[:password@]host[:port]
fn parse_redis_sink_url(url string) RedisSinkAddr {
	mut s := url
	// Strip scheme
	if s.starts_with('redis://') {
		s = s[8..]
	} else if s.starts_with('rediss://') {
		s = s[9..]
	}

	// Strip trailing slash and path
	if idx := s.index('/') {
		s = s[..idx]
	}

	mut password := ''
	// Check for password: :password@host
	if at_idx := s.index('@') {
		auth_part := s[..at_idx]
		s = s[at_idx + 1..]
		if auth_part.starts_with(':') {
			password = auth_part[1..]
		} else {
			password = auth_part
		}
	}

	// Parse host:port
	mut host := '127.0.0.1'
	mut port := 6379

	if s.len > 0 {
		if colon_idx := s.index(':') {
			host = s[..colon_idx]
			port_str := s[colon_idx + 1..]
			parsed_port := port_str.int()
			if parsed_port > 0 {
				port = parsed_port
			}
		} else {
			host = s
		}
	}

	if host.len == 0 {
		host = '127.0.0.1'
	}

	return RedisSinkAddr{
		host: host
		port: port
		password: password
	}
}

// encode_redis_command encodes a list of arguments as a RESP array command.
// Example: ["LPUSH", "key", "val"] -> "*3\r\n$5\r\nLPUSH\r\n$3\r\nkey\r\n$3\r\nval\r\n"
fn encode_redis_command(args []string) string {
	mut result := '*${args.len}\r\n'
	for arg in args {
		result += '\$${arg.len}\r\n${arg}\r\n'
	}
	return result
}

// new_redis creates a new RedisSink from config options.
pub fn new_redis(opts map[string]string) !RedisSink {
	key := opts['key'] or {
		return error('redis: key is required')
	}

	url := opts['url'] or { 'redis://127.0.0.1:6379' }
	addr := parse_redis_sink_url(url)

	mode := match opts['mode'] or { 'lpush' } {
		'rpush' { RedisSinkMode.rpush }
		'publish' { RedisSinkMode.publish }
		else { RedisSinkMode.lpush }
	}

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { RedisCodec.text_codec }
		else { RedisCodec.json_codec }
	}

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return RedisSink{
		addr: addr
		mode: mode
		key: key
		codec: codec
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s RedisSink) send(e event.Event) ! {
	encoded := s.encode_event(e)
	if encoded.len > 0 {
		s.buffer << encoded
	}

	if s.buffer.len >= s.batch_max {
		s.flush()!
	}

	if time.since(s.last_flush) > s.batch_timeout && s.buffer.len > 0 {
		s.flush()!
	}
}

// flush sends all buffered events to Redis.
pub fn (mut s RedisSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	mut conn := net.dial_tcp('${s.addr.host}:${s.addr.port}') or {
		eprintln('redis: failed to connect to ${s.addr.host}:${s.addr.port}: ${err}')
		return error(err.msg())
	}
	defer {
		conn.close() or {}
	}

	// Authenticate if password is set
	if s.addr.password.len > 0 {
		auth_cmd := encode_redis_command(['AUTH', s.addr.password])
		conn.write_string(auth_cmd) or {
			return error('redis: AUTH failed: ${err}')
		}
		// Read AUTH response
		mut buf := []u8{len: 256}
		conn.read(mut buf) or {}
	}

	match s.mode {
		.lpush, .rpush {
			// Batch: LPUSH/RPUSH key val1 val2 ...
			cmd_name := if s.mode == .lpush { 'LPUSH' } else { 'RPUSH' }
			mut args := [cmd_name, s.key]
			for val in s.buffer {
				args << val
			}
			cmd := encode_redis_command(args)
			conn.write_string(cmd) or {
				eprintln('redis: failed to send ${cmd_name}: ${err}')
				return error(err.msg())
			}
			// Read response
			mut buf := []u8{len: 256}
			conn.read(mut buf) or {}
		}
		.publish {
			// PUBLISH one per event
			for val in s.buffer {
				cmd := encode_redis_command(['PUBLISH', s.key, val])
				conn.write_string(cmd) or {
					eprintln('redis: failed to PUBLISH: ${err}')
					return error(err.msg())
				}
				// Read response
				mut buf := []u8{len: 256}
				conn.read(mut buf) or {}
			}
		}
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &RedisSink) total_buffered() int {
	return s.buffer.len
}

// encode_event encodes a single event as a string for Redis.
fn (s &RedisSink) encode_event(e event.Event) string {
	match e {
		event.LogEvent {
			return match s.codec {
				.json_codec { e.to_json() }
				.text_codec { e.message() }
			}
		}
		event.Metric {
			return json.encode(e)
		}
		event.TraceEvent {
			return json.encode(e.fields)
		}
	}
}
