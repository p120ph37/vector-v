module sources

import event
import time

// AmqpSource consumes messages from an AMQP 0-9-1 broker (e.g. RabbitMQ).
// Mirrors Vector's amqp source (src/sources/amqp/).
//
// The source binds a queue to an exchange and consumes messages via the
// AMQP Basic.Consume method. Actual network I/O is stubbed — this module
// provides configuration parsing, URL parsing, metadata construction, and
// validation helpers that are exercised by unit tests.
//
// Config options:
//   connection:           AMQP connection URL (default: amqp://guest:guest@127.0.0.1:5672/%2f)
//   exchange:             Exchange name to bind to
//   exchange_type:        Exchange type — fanout, direct, topic, headers (default: fanout)
//   queue:                Queue name (auto-generated if empty)
//   routing_key:          Binding routing key (default: "#")
//   consumer_tag:         Consumer tag (default: "vector")
//   prefetch_count:       QoS prefetch count (default: 10)
//   exchange_key:         Field name for exchange metadata (default: "amqp_exchange")
//   routing_key_field:    Field name for routing key metadata (default: "amqp_routing_key")
//   decoding.codec:       Decoding format — bytes or json (default: "bytes")
//   tls.enabled:          Enable TLS (default: false)
pub struct AmqpSource {
	connection_string string = 'amqp://guest:guest@127.0.0.1:5672/%2f'
	exchange          string
	exchange_type     string = 'fanout'
	queue             string
	routing_key       string = '#'
	consumer_tag      string = 'vector'
	prefetch_count    int    = 10
	exchange_key      string = 'amqp_exchange'
	routing_key_field string = 'amqp_routing_key'
	offset_key        string = 'amqp_offset'
	decoding_codec    string = 'bytes'
	tls_enabled       bool
}

// new_amqp_source creates a new AmqpSource from config options.
// All fields have defaults so no required options.
pub fn new_amqp_source(opts map[string]string) AmqpSource {
	mut prefetch_count := 10
	if pc := opts['prefetch_count'] {
		prefetch_count = pc.int()
		if prefetch_count <= 0 {
			prefetch_count = 10
		}
	}

	mut tls_enabled := false
	if tls_opt := opts['tls.enabled'] {
		tls_enabled = tls_opt == 'true'
	}

	return AmqpSource{
		connection_string: opts['connection'] or { 'amqp://guest:guest@127.0.0.1:5672/%2f' }
		exchange:          opts['exchange'] or { '' }
		exchange_type:     opts['exchange_type'] or { 'fanout' }
		queue:             opts['queue'] or { '' }
		routing_key:       opts['routing_key'] or { '#' }
		consumer_tag:      opts['consumer_tag'] or { 'vector' }
		prefetch_count:    prefetch_count
		exchange_key:      opts['exchange_key'] or { 'amqp_exchange' }
		routing_key_field: opts['routing_key_field'] or { 'amqp_routing_key' }
		offset_key:        opts['offset_key'] or { 'amqp_offset' }
		decoding_codec:    opts['decoding.codec'] or { 'bytes' }
		tls_enabled:       tls_enabled
	}
}

// parse_amqp_url parses an AMQP connection URL into its components.
// Format: amqp://user:password@host:port/vhost
// Returns (host, port, vhost, user, password) or error on invalid URL.
pub fn parse_amqp_url(url string) !(string, int, string, string, string) {
	mut s := url

	// Strip scheme
	if s.starts_with('amqps://') {
		s = s[8..]
	} else if s.starts_with('amqp://') {
		s = s[7..]
	} else {
		return error('invalid AMQP URL: missing amqp:// or amqps:// scheme')
	}

	// Extract credentials if present (user:pass@...)
	mut user := 'guest'
	mut password := 'guest'
	if at_idx := s.index('@') {
		cred_part := s[..at_idx]
		s = s[at_idx + 1..]
		if colon_idx := cred_part.index(':') {
			user = cred_part[..colon_idx]
			password = cred_part[colon_idx + 1..]
		} else {
			user = cred_part
			password = ''
		}
	}

	// Extract vhost (everything after first /)
	mut vhost := '/'
	if slash_idx := s.index('/') {
		raw_vhost := s[slash_idx + 1..]
		s = s[..slash_idx]
		// Decode %2f -> /
		if raw_vhost == '%2f' || raw_vhost == '%2F' {
			vhost = '/'
		} else if raw_vhost.len > 0 {
			vhost = raw_vhost
		}
	}

	// Parse host:port
	mut host := '127.0.0.1'
	mut port := 5672

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

	return host, port, vhost, user, password
}

// validate_amqp_exchange_type checks if the given exchange type is valid.
// Valid types: fanout, direct, topic, headers.
pub fn validate_amqp_exchange_type(typ string) bool {
	return typ in ['fanout', 'direct', 'topic', 'headers']
}

// build_amqp_metadata constructs metadata fields for a consumed AMQP message.
pub fn build_amqp_metadata(exchange string, routing_key string, delivery_tag u64) map[string]string {
	return {
		'exchange':     exchange
		'routing_key':  routing_key
		'delivery_tag': '${delivery_tag}'
	}
}

// run connects to the AMQP broker and begins consuming messages.
// TODO: Implement actual AMQP 0-9-1 protocol handshake and Basic.Consume.
// Currently a stub — real network I/O requires implementing the AMQP frame
// protocol or linking an external C library.
pub fn (s &AmqpSource) run(output chan event.Event) {
	eprintln('amqp source: connecting to ${s.connection_string} (exchange: ${s.exchange}, queue: ${s.queue})')
	// Stub: actual AMQP protocol implementation would go here.
	// The source would:
	// 1. Open TCP connection (with optional TLS)
	// 2. Perform AMQP handshake (Connection.Start/Tune/Open)
	// 3. Open channel, declare exchange, declare/bind queue
	// 4. Set QoS prefetch_count
	// 5. Basic.Consume and loop reading deliveries
	// 6. For each delivery, create a LogEvent and send to output channel
	for {
		time.sleep(1 * time.second)
	}
}
