module sinks

import event
import json
import time

// PulsarSink publishes events to an Apache Pulsar topic.
// Mirrors Vector's pulsar sink configuration.
//
// Events are encoded and buffered, then flushed as Pulsar messages.
// Supports JSON and text encoding, multiple compression algorithms,
// and optional partition key routing.
//
// Config options:
//   endpoint:            Pulsar broker URL (default: pulsar://127.0.0.1:6650)
//   topic:               Target topic (required, can contain {{field}} templates)
//   producer_name:       Producer name (default: "vector")
//   encoding.codec:      json or text (default: json)
//   compression:         none, lz4, zlib, zstd, snappy (default: none)
//   partition_key_field: Field for partition key routing
//   batch.max_events:    Max batch size (default: 1000)
//   batch.timeout_ms:    Flush timeout in ms (default: 1000)
//   auth.token:          Bearer token auth
//   tls.enabled:         Enable TLS
pub struct PulsarSink {
pub mut:
	endpoint           string = 'pulsar://127.0.0.1:6650'
	topic              string
	producer_name      string = 'vector'
	encoding_codec     string = 'json'
	compression        string = 'none'
	partition_key_field string
	batch_max_events   int = 1000
	batch_timeout_ms   int = 1000
	auth_token         string
	tls_enabled        bool
	buffer             []string
}

// encode_pulsar_payload encodes an event as a string using the specified codec.
pub fn encode_pulsar_payload(e event.Event, codec string) string {
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

// new_pulsar_sink creates a new PulsarSink from config options.
pub fn new_pulsar_sink(opts map[string]string) !PulsarSink {
	topic := opts['topic'] or {
		return error('pulsar sink: topic is required')
	}
	if topic.len == 0 {
		return error('pulsar sink: topic is required')
	}

	endpoint := opts['endpoint'] or { 'pulsar://127.0.0.1:6650' }
	producer_name := opts['producer_name'] or { 'vector' }
	encoding_codec := opts['encoding.codec'] or { 'json' }
	auth_token := opts['auth.token'] or { '' }
	partition_key_field := opts['partition_key_field'] or { '' }

	compression := match opts['compression'] or { 'none' } {
		'lz4' { 'lz4' }
		'zlib' { 'zlib' }
		'zstd' { 'zstd' }
		'snappy' { 'snappy' }
		else { 'none' }
	}

	mut batch_max_events := 1000
	if bm := opts['batch.max_events'] {
		batch_max_events = bm.int()
		if batch_max_events <= 0 {
			batch_max_events = 1000
		}
	}

	mut batch_timeout_ms := 1000
	if bt := opts['batch.timeout_ms'] {
		batch_timeout_ms = bt.int()
		if batch_timeout_ms <= 0 {
			batch_timeout_ms = 1000
		}
	}

	mut tls_enabled := false
	if tls_opt := opts['tls.enabled'] {
		tls_enabled = tls_opt == 'true'
	}
	if endpoint.starts_with('pulsar+ssl://') {
		tls_enabled = true
	}

	return PulsarSink{
		endpoint: endpoint
		topic: topic
		producer_name: producer_name
		encoding_codec: encoding_codec
		compression: compression
		partition_key_field: partition_key_field
		batch_max_events: batch_max_events
		batch_timeout_ms: batch_timeout_ms
		auth_token: auth_token
		tls_enabled: tls_enabled
	}
}

// send buffers an event for later flushing to Pulsar.
pub fn (mut s PulsarSink) send(e event.Event) ! {
	encoded := encode_pulsar_payload(e, s.encoding_codec)
	if encoded.len > 0 {
		s.buffer << encoded
	}

	if s.buffer.len >= s.batch_max_events {
		s.flush()!
	}
}

// flush sends all buffered events to Pulsar.
// TODO: Implement Pulsar binary protocol producer.
pub fn (mut s PulsarSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	// Stub: Pulsar binary protocol producer not yet implemented.
	// When implemented, this method will:
	// 1. Connect to the Pulsar broker via TCP (with optional TLS)
	// 2. Send CommandConnect with auth credentials
	// 3. Create a producer on the configured topic
	// 4. Send each buffered message with optional partition key and compression
	// 5. Wait for acknowledgements
	// 6. Clear the buffer on success
	eprintln('pulsar sink: flush not yet implemented (${s.buffer.len} events buffered for topic ${s.topic})')

	s.buffer.clear()
	_ = time.now() // avoid unused import
}

// total_buffered returns the number of events currently buffered.
pub fn (s &PulsarSink) total_buffered() int {
	return s.buffer.len
}
