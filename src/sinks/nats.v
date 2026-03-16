module sinks

import event
import json
import time

// NatsSink publishes events to a NATS subject.
// Mirrors Vector's nats sink (src/sinks/nats/).
//
// Events are encoded and buffered, then published as NATS PUB messages
// over a raw TCP connection using the NATS protocol.
//
// Config options:
//   url:              NATS server URL (default: nats://127.0.0.1:4222)
//   subject:          Target subject — can contain {{field}} templates (required)
//   connection_name:  Connection name (default: "vector")
//   auth.token:       Auth token
//   auth.user:        Username for basic auth
//   auth.password:    Password for basic auth
//   jetstream:        Enable JetStream (default: false)
//   encoding.codec:   json or text (default: json)
//   tls.enabled:      Enable TLS (default: false)
//   batch.max_events: Max events per batch (default: 100)
pub struct NatsSink {
pub mut:
	url              string = 'nats://127.0.0.1:4222'
	subject          string // can contain {{field}} templates
	connection_name  string = 'vector'
	auth_token       string
	auth_user        string
	auth_password    string
	jetstream        bool
	encoding_codec   string = 'json'
	tls_enabled      bool
	buffer           []string
	batch_max_events int = 100
}

// new_nats_sink creates a new NatsSink from config options.
pub fn new_nats_sink(opts map[string]string) !NatsSink {
	subject := opts['subject'] or {
		return error('nats sink: subject is required')
	}
	if subject.len == 0 {
		return error('nats sink: subject is required')
	}

	url := opts['url'] or { 'nats://127.0.0.1:4222' }
	connection_name := opts['connection_name'] or { 'vector' }
	auth_token := opts['auth.token'] or { '' }
	auth_user := opts['auth.user'] or { '' }
	auth_password := opts['auth.password'] or { '' }
	encoding_codec := opts['encoding.codec'] or { 'json' }

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

	mut batch_max_events := 100
	if bm := opts['batch.max_events'] {
		batch_max_events = bm.int()
		if batch_max_events <= 0 {
			batch_max_events = 100
		}
	}

	return NatsSink{
		url: url
		subject: subject
		connection_name: connection_name
		auth_token: auth_token
		auth_user: auth_user
		auth_password: auth_password
		jetstream: jetstream
		encoding_codec: encoding_codec
		tls_enabled: tls_enabled
		batch_max_events: batch_max_events
	}
}

// send encodes an event and adds it to the internal buffer.
// When the buffer reaches batch_max_events, flush is called automatically.
pub fn (mut s NatsSink) send(e event.Event) ! {
	encoded := encode_nats_payload(e, s.encoding_codec)
	if encoded.len > 0 {
		s.buffer << encoded
	}

	if s.buffer.len >= s.batch_max_events {
		s.flush()!
	}
}

// flush publishes all buffered events to the NATS subject.
// Each event is sent as a PUB command: PUB <subject> <length>\r\n<payload>\r\n
//
// TODO: Implement actual NATS protocol connection and publishing.
// The implementation would:
// - Connect to the NATS server (with optional TLS)
// - Perform NATS handshake (INFO/CONNECT with auth)
// - For each buffered message, send PUB <subject> <len>\r\n<payload>\r\n
// - For JetStream: use JPUB and wait for +OK acknowledgement
// - Handle reconnection on failure
pub fn (mut s NatsSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	// Stub: In a full implementation, this would connect to NATS and publish.
	// For now, clear the buffer to indicate the flush was processed.
	s.buffer.clear()

	_ = time.second // suppress unused import
}

// total_buffered returns the number of events currently in the buffer.
pub fn (s &NatsSink) total_buffered() int {
	return s.buffer.len
}

// encode_nats_payload encodes an event as a string for NATS publishing.
// Supports "json" and "text" codecs.
pub fn encode_nats_payload(e event.Event, codec string) string {
	match e {
		event.LogEvent {
			return match codec {
				'text' { e.message() }
				else { e.to_json() }
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
