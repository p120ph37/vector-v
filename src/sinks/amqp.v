module sinks

import event
import json

// AmqpSink publishes events to an AMQP 0-9-1 exchange (e.g. RabbitMQ).
// Mirrors Vector's amqp sink (src/sinks/amqp/).
//
// Events are encoded (json or text), buffered, and flushed as AMQP
// Basic.Publish messages. Actual network I/O is stubbed — this module
// provides configuration parsing, encoding, and buffer management that
// are exercised by unit tests.
//
// Config options:
//   connection:                AMQP connection URL (default: amqp://guest:guest@127.0.0.1:5672/%2f)
//   exchange:                  Target exchange (required)
//   routing_key:               Routing key (supports {{field}} templates)
//   encoding.codec:            json or text (default: json)
//   properties.content_type:   AMQP content type (default: application/json)
//   properties.delivery_mode:  1=transient, 2=persistent (default: 2)
//   max_channels:              Max AMQP channels (default: 10)
//   tls.enabled:               Enable TLS (default: false)
//   batch.max_events:          Max events per batch (default: 100)
pub struct AmqpSink {
pub mut:
	connection_string string = 'amqp://guest:guest@127.0.0.1:5672/%2f'
	exchange          string
	routing_key       string
	encoding_codec    string = 'json'
	content_type      string = 'application/json'
	delivery_mode     int    = 2
	max_channels      int    = 10
	tls_enabled       bool
	buffer            []string
	batch_max_events  int = 100
}

// new_amqp_sink creates a new AmqpSink from config options.
// Returns error if exchange is missing.
pub fn new_amqp_sink(opts map[string]string) !AmqpSink {
	exchange := opts['exchange'] or {
		return error('amqp sink: exchange is required')
	}
	if exchange.len == 0 {
		return error('amqp sink: exchange is required')
	}

	mut delivery_mode := 2
	if dm := opts['properties.delivery_mode'] {
		delivery_mode = dm.int()
		if delivery_mode != 1 && delivery_mode != 2 {
			delivery_mode = 2
		}
	}

	mut max_channels := 10
	if mc := opts['max_channels'] {
		max_channels = mc.int()
		if max_channels <= 0 {
			max_channels = 10
		}
	}

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
	}

	codec := opts['encoding.codec'] or { 'json' }
	content_type := if codec == 'text' { 'text/plain' } else { 'application/json' }

	mut tls_enabled := false
	if tls_opt := opts['tls.enabled'] {
		tls_enabled = tls_opt == 'true'
	}

	return AmqpSink{
		connection_string: opts['connection'] or { 'amqp://guest:guest@127.0.0.1:5672/%2f' }
		exchange:          exchange
		routing_key:       opts['routing_key'] or { '' }
		encoding_codec:    codec
		content_type:      opts['properties.content_type'] or { content_type }
		delivery_mode:     delivery_mode
		max_channels:      max_channels
		tls_enabled:       tls_enabled
		batch_max_events:  batch_max
	}
}

// send buffers an event for publishing. Encodes the event according to the
// configured codec and appends it to the internal buffer.
pub fn (mut s AmqpSink) send(e event.Event) ! {
	encoded := encode_amqp_payload(e, s.encoding_codec)
	if encoded.len > 0 {
		s.buffer << encoded
	}
}

// flush publishes all buffered events to the AMQP exchange.
// Currently a stub — actual AMQP publishing requires protocol implementation.
pub fn (mut s AmqpSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	// TODO: Implement actual AMQP Basic.Publish for each buffered message.
	// The sink would:
	// 1. Open TCP connection (with optional TLS)
	// 2. Perform AMQP handshake
	// 3. Open channel, declare exchange
	// 4. For each buffered message, publish with routing_key and properties
	// 5. Wait for publisher confirms if enabled

	eprintln('amqp sink: would publish ${s.buffer.len} messages to exchange "${s.exchange}"')
	s.buffer.clear()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &AmqpSink) total_buffered() int {
	return s.buffer.len
}

// encode_amqp_payload encodes a single event as a string for AMQP publishing.
pub fn encode_amqp_payload(e event.Event, codec string) string {
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
