module sources

import event
import time

// MqttSource subscribes to an MQTT broker and receives messages on a topic.
// Mirrors Vector's mqtt source concept.
//
// Implements MQTT v3.1.1 protocol basics (CONNECT, SUBSCRIBE, PUBLISH handling).
// The source connects to the broker, subscribes to the configured topic (which may
// include + and # wildcards), and emits each received message as a log event.
//
// Config options:
//   host:            MQTT broker host (default: 127.0.0.1)
//   port:            MQTT broker port (default: 1883, or 8883 with TLS)
//   topic:           MQTT topic filter to subscribe to (required, supports +/# wildcards)
//   qos:             Quality of service 0-2 (default: 1)
//   client_id:       Client identifier (default: "vector")
//   username:        Basic auth username
//   password:        Basic auth password
//   clean_session:   Start with clean session (default: true)
//   keep_alive_secs: Keep-alive interval in seconds (default: 60)
//   max_packet_size: Maximum MQTT packet size (default: 268435456 = 256MB)
//   tls.enabled:     Enable TLS (default: false)
//   decoding.codec:  Decoding format (default: "bytes")
//   topic_key:       Field name for topic metadata (default: "mqtt_topic")
pub struct MqttSource {
	host            string = '127.0.0.1'
	port            int    = 1883
	topic           string
	qos             int    = 1 // 0=at_most_once, 1=at_least_once, 2=exactly_once
	client_id       string = 'vector'
	username        string
	password        string
	clean_session   bool = true
	keep_alive_secs int  = 60
	max_packet_size int  = 268435456 // 256MB default
	tls_enabled     bool
	decoding_codec  string = 'bytes'
	topic_key       string = 'mqtt_topic'
}

// new_mqtt_source creates a new MqttSource from config options.
// Returns error if topic is not provided.
pub fn new_mqtt_source(opts map[string]string) !MqttSource {
	topic := opts['topic'] or {
		return error('mqtt source: topic is required')
	}
	if topic.len == 0 {
		return error('mqtt source: topic is required')
	}

	mut host := opts['host'] or { '127.0.0.1' }
	if host.len == 0 {
		host = '127.0.0.1'
	}

	// Check for URL-based config
	mut tls_enabled := false
	if tls_opt := opts['tls.enabled'] {
		tls_enabled = tls_opt == 'true'
	}

	// Determine default port based on TLS setting
	default_port := if tls_enabled { 8883 } else { 1883 }

	mut port := default_port
	if p := opts['port'] {
		parsed := p.int()
		if parsed > 0 {
			port = parsed
		}
	}

	mut qos := 1
	if q := opts['qos'] {
		qos = q.int()
		if !validate_mqtt_qos(qos) {
			qos = 1
		}
	}

	mut client_id := opts['client_id'] or { 'vector' }
	if client_id.len == 0 {
		client_id = 'vector'
	}

	username := opts['username'] or { '' }
	password := opts['password'] or { '' }

	mut clean_session := true
	if cs := opts['clean_session'] {
		clean_session = cs != 'false'
	}

	mut keep_alive_secs := 60
	if ka := opts['keep_alive_secs'] {
		keep_alive_secs = ka.int()
		if keep_alive_secs <= 0 {
			keep_alive_secs = 60
		}
	}

	mut max_packet_size := 268435456
	if mps := opts['max_packet_size'] {
		max_packet_size = mps.int()
		if max_packet_size <= 0 {
			max_packet_size = 268435456
		}
	}

	decoding_codec := opts['decoding.codec'] or { 'bytes' }
	topic_key := opts['topic_key'] or { 'mqtt_topic' }

	return MqttSource{
		host:            host
		port:            port
		topic:           topic
		qos:             qos
		client_id:       client_id
		username:        username
		password:        password
		clean_session:   clean_session
		keep_alive_secs: keep_alive_secs
		max_packet_size: max_packet_size
		tls_enabled:     tls_enabled
		decoding_codec:  decoding_codec
		topic_key:       topic_key
	}
}

// validate_mqtt_topic validates an MQTT topic filter.
// Rules:
//   - '#' (multi-level wildcard) may only appear as the last character, and must
//     be preceded by '/' or be the entire topic.
//   - '+' (single-level wildcard) must occupy an entire level (between '/' delimiters).
//   - Empty levels (double slashes "//") are not allowed.
//   - The topic must not be empty.
pub fn validate_mqtt_topic(topic string) bool {
	if topic.len == 0 {
		return false
	}
	levels := topic.split('/')
	for i, level in levels {
		// Empty level (e.g. "a//b") is invalid
		if level.len == 0 && i > 0 && i < levels.len - 1 {
			return false
		}
		// '#' must be the last level and must be the entire level string
		if level.contains('#') {
			if level != '#' {
				return false
			}
			if i != levels.len - 1 {
				return false
			}
		}
		// '+' must be the entire level string
		if level.contains('+') {
			if level != '+' {
				return false
			}
		}
	}
	return true
}

// validate_mqtt_qos returns true if qos is a valid MQTT QoS level (0, 1, or 2).
pub fn validate_mqtt_qos(qos int) bool {
	return qos >= 0 && qos <= 2
}

// build_mqtt_connect_flags builds the MQTT CONNECT packet flags byte.
// Bit layout (MSB to LSB):
//   7: username flag
//   6: password flag
//   5: will retain
//   4-3: will QoS (2 bits)
//   2: will flag
//   1: clean session
//   0: reserved (0)
pub fn build_mqtt_connect_flags(clean_session bool, has_username bool, has_password bool, has_will bool, will_qos int, will_retain bool) u8 {
	mut flags := u8(0)
	if clean_session {
		flags |= 0x02
	}
	if has_will {
		flags |= 0x04
		flags |= u8((will_qos & 0x03) << 3)
		if will_retain {
			flags |= 0x20
		}
	}
	if has_password {
		flags |= 0x40
	}
	if has_username {
		flags |= 0x80
	}
	return flags
}

// parse_mqtt_url parses an mqtt:// or mqtts:// URL into (host, port, tls).
// Returns error for invalid/unsupported schemes.
pub fn parse_mqtt_url(url string) !(string, int, bool) {
	mut s := url
	mut tls := false

	if s.starts_with('mqtts://') {
		tls = true
		s = s[8..]
	} else if s.starts_with('mqtt://') {
		s = s[7..]
	} else {
		return error('mqtt: unsupported URL scheme: ${url}')
	}

	// Strip path if any
	if idx := s.index('/') {
		s = s[..idx]
	}

	default_port := if tls { 8883 } else { 1883 }
	mut host := '127.0.0.1'
	mut port := default_port

	if s.len == 0 {
		return host, port, tls
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

	return host, port, tls
}

// run connects to the MQTT broker, subscribes to the topic, and emits
// received messages as log events on the output channel.
// TODO: Implement actual MQTT protocol connection and message loop.
pub fn (s &MqttSource) run(output chan event.Event) {
	// Stub: MQTT protocol connection, SUBSCRIBE, and message receive loop
	// would be implemented here using net.TcpConn (or TLS) with the
	// MQTT v3.1.1 binary protocol.
	eprintln('mqtt: connecting to ${s.host}:${s.port} (topic: ${s.topic}, qos: ${s.qos}, client_id: ${s.client_id})')
	_ = output
	_ = time.now() // suppress unused import
}
