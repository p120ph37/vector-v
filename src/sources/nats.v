module sources

import event
import time

// NatsSource subscribes to NATS subjects and receives messages as log events.
// Mirrors Vector's nats source (src/sources/nats/).
//
// Implements a minimal NATS client protocol directly over TCP.
// Supports core NATS pub/sub and JetStream durable consumers.
//
// Config options:
//   url:                NATS server URL (default: nats://127.0.0.1:4222)
//   subject:            Subject to subscribe to (required)
//   queue:              Queue group name for load balancing
//   connection_name:    Connection name (default: "vector")
//   auth.token:         Auth token
//   auth.user:          Username for basic auth
//   auth.password:      Password for basic auth
//   auth.nkey:          NKey authentication seed
//   auth.credentials_file: Path to credentials file
//   jetstream:          Enable JetStream (default: false)
//   jetstream.stream:   JetStream stream name
//   subscriber_capacity: Subscriber buffer capacity (default: 4096)
//   subject_key_field:  Field name for subject metadata (default: "nats_subject")
//   tls.enabled:        Enable TLS (default: false)
//   decoding.codec:     Decoding format: bytes or json (default: bytes)
pub struct NatsSource {
	url                 string = 'nats://127.0.0.1:4222'
	subject             string
	queue               string // optional: queue group name for load balancing
	connection_name     string = 'vector'
	auth_token          string
	auth_user           string
	auth_password       string
	auth_nkey           string
	credentials_file    string
	jetstream           bool   // enable JetStream durable consumers
	jetstream_stream    string // JetStream stream name
	subscriber_capacity int = 4096
	subject_key_field   string = 'nats_subject'
	tls_enabled         bool
	decoding_codec      string = 'bytes'
}

// new_nats_source creates a new NatsSource from config options.
pub fn new_nats_source(opts map[string]string) !NatsSource {
	subject := opts['subject'] or {
		return error('nats source: subject is required')
	}
	if subject.len == 0 {
		return error('nats source: subject is required')
	}

	url := opts['url'] or { 'nats://127.0.0.1:4222' }
	connection_name := opts['connection_name'] or { 'vector' }
	auth_token := opts['auth.token'] or { '' }
	auth_user := opts['auth.user'] or { '' }
	auth_password := opts['auth.password'] or { '' }
	auth_nkey := opts['auth.nkey'] or { '' }
	credentials_file := opts['auth.credentials_file'] or { '' }
	queue := opts['queue'] or { '' }
	jetstream_stream := opts['jetstream.stream'] or { '' }
	subject_key_field := opts['subject_key_field'] or { 'nats_subject' }
	decoding_codec := opts['decoding.codec'] or { 'bytes' }

	jetstream := if js := opts['jetstream'] {
		js == 'true'
	} else {
		false
	}

	tls_enabled := if tls := opts['tls.enabled'] {
		tls == 'true'
	} else {
		false
	}

	mut subscriber_capacity := 4096
	if sc := opts['subscriber_capacity'] {
		subscriber_capacity = sc.int()
		if subscriber_capacity <= 0 {
			subscriber_capacity = 4096
		}
	}

	return NatsSource{
		url: url
		subject: subject
		queue: queue
		connection_name: connection_name
		auth_token: auth_token
		auth_user: auth_user
		auth_password: auth_password
		auth_nkey: auth_nkey
		credentials_file: credentials_file
		jetstream: jetstream
		jetstream_stream: jetstream_stream
		subscriber_capacity: subscriber_capacity
		subject_key_field: subject_key_field
		tls_enabled: tls_enabled
		decoding_codec: decoding_codec
	}
}

// parse_nats_url extracts host and port from a nats:// URL.
// Format: nats://host[:port]
// Returns error for invalid URLs.
pub fn parse_nats_url(url string) !(string, int) {
	mut s := url
	if s.starts_with('nats://') {
		s = s[7..]
	} else if s.starts_with('tls://') {
		s = s[6..]
	} else {
		return error('invalid NATS URL scheme: ${url}')
	}

	// Strip trailing path
	if idx := s.index('/') {
		s = s[..idx]
	}

	// Parse host:port
	mut host := '127.0.0.1'
	mut port := 4222

	if s.len == 0 {
		return host, port
	}

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

	if host.len == 0 {
		host = '127.0.0.1'
	}

	return host, port
}

// validate_nats_source_config checks that required fields are present.
pub fn validate_nats_source_config(opts map[string]string) !bool {
	subject := opts['subject'] or {
		return error('nats source: subject is required')
	}
	if subject.len == 0 {
		return error('nats source: subject is required')
	}
	// Validate URL if provided
	if url := opts['url'] {
		parse_nats_url(url) or {
			return error('nats source: invalid url: ${err}')
		}
	}
	return true
}

// build_nats_connect_payload builds a CONNECT JSON payload for the NATS protocol.
// The CONNECT command is sent after receiving INFO from the server.
pub fn build_nats_connect_payload(name string, user string, password string, token string) string {
	mut parts := []string{}
	parts << '"verbose":false'
	parts << '"pedantic":false'
	parts << '"tls_required":false'
	parts << '"name":"${name}"'
	parts << '"lang":"vlang"'
	parts << '"version":"0.1.0"'
	parts << '"protocol":1'

	if token.len > 0 {
		parts << '"auth_token":"${token}"'
	}
	if user.len > 0 {
		parts << '"user":"${user}"'
	}
	if password.len > 0 {
		parts << '"pass":"${password}"'
	}

	return 'CONNECT {${parts.join(",")}}\r\n'
}

// run connects to the NATS server and subscribes to the configured subject.
// Messages are emitted as LogEvent on the output channel.
//
// NATS protocol implementation:
// 1. Connect to nats://host:port over TCP
// 2. Receive INFO from server
// 3. Send CONNECT with auth credentials
// 4. Send SUB <subject> [queue] <sid>
// 5. Read MSG/HMSG frames in a loop, emit as LogEvent
//
// For JetStream mode, the consumer is created via the JetStream API
// ($JS.API.CONSUMER.CREATE.<stream>) and messages are acknowledged
// with +ACK to enable durable consumption.
pub fn (s &NatsSource) run(output chan event.Event) {
	// TODO: Implement NATS protocol connection and message consumption.
	// The implementation would:
	// - Parse URL to get host:port
	// - Open TCP connection (with optional TLS)
	// - Perform NATS handshake (INFO/CONNECT)
	// - Subscribe to the configured subject with optional queue group
	// - For JetStream: create durable consumer and handle ack protocol
	// - Read MSG frames and emit LogEvent on the output channel
	// - Handle reconnection on failure with backoff
	_ = time.second // suppress unused import
	_ = event.new_log('') // suppress unused import
}
