module sinks

import event
import json

// KafkaSink sends events to Apache Kafka topics.
// Mirrors Vector's kafka sink (src/sinks/kafka/).
//
// Events are buffered and flushed as batches. The actual Kafka wire
// protocol producer is stubbed — in production this would use
// librdkafka via C interop or implement the Kafka binary protocol.
//
// Config options:
//   bootstrap_servers:  Comma-separated broker list (required)
//   topic:              Target topic, can contain {{field}} templates (required)
//   key_field:          Event field to use as Kafka partition key
//   encoding.codec:     Encoding format — "json", "text", "raw" (default: "json")
//   compression:        Compression — "none", "gzip", "snappy", "lz4", "zstd" (default: "none")
//   batch.max_events:   Max batch size (default: 1000)
//   batch.timeout_ms:   Flush timeout in ms (default: 1000)
//   sasl.mechanism:     SASL auth mechanism
//   sasl.username:      SASL username
//   sasl.password:      SASL password
//   tls.enabled:        Enable TLS (default: false)
//   headers_key:        Event field containing headers map
pub struct KafkaSink {
pub mut:
	bootstrap_servers []string
	topic             string
	key_field         string
	encoding_codec    string = 'json'
	compression       string = 'none'
	batch_max_events  int    = 1000
	batch_timeout_ms  int    = 1000
	sasl_mechanism    string
	sasl_username     string
	sasl_password     string
	tls_enabled       bool
	headers_key       string
	buffer            []string
}

// new_kafka_sink creates a new KafkaSink from config options.
pub fn new_kafka_sink(opts map[string]string) !KafkaSink {
	servers_str := opts['bootstrap_servers'] or {
		return error('kafka: bootstrap_servers is required')
	}
	if servers_str.len == 0 {
		return error('kafka: bootstrap_servers is required')
	}

	topic := opts['topic'] or {
		return error('kafka: topic is required')
	}
	if topic.len == 0 {
		return error('kafka: topic is required')
	}

	servers := servers_str.split(',').map(it.trim_space()).filter(it.len > 0)

	key_field := opts['key_field'] or { '' }

	encoding_codec := opts['encoding.codec'] or { 'json' }

	mut compression := 'none'
	if v := opts['compression'] {
		if v in ['none', 'gzip', 'snappy', 'lz4', 'zstd'] {
			compression = v
		}
	}

	mut batch_max_events := 1000
	if v := opts['batch.max_events'] {
		parsed := v.int()
		if parsed > 0 {
			batch_max_events = parsed
		}
	}

	mut batch_timeout_ms := 1000
	if v := opts['batch.timeout_ms'] {
		parsed := v.int()
		if parsed > 0 {
			batch_timeout_ms = parsed
		}
	}

	sasl_mechanism := opts['sasl.mechanism'] or { '' }
	sasl_username := opts['sasl.username'] or { '' }
	sasl_password := opts['sasl.password'] or { '' }

	mut tls_enabled := false
	if v := opts['tls.enabled'] {
		tls_enabled = v == 'true'
	}

	headers_key := opts['headers_key'] or { '' }

	return KafkaSink{
		bootstrap_servers: servers
		topic: topic
		key_field: key_field
		encoding_codec: encoding_codec
		compression: compression
		batch_max_events: batch_max_events
		batch_timeout_ms: batch_timeout_ms
		sasl_mechanism: sasl_mechanism
		sasl_username: sasl_username
		sasl_password: sasl_password
		tls_enabled: tls_enabled
		headers_key: headers_key
	}
}

// send encodes an event and adds it to the buffer, flushing if the batch is full.
pub fn (mut s KafkaSink) send(e event.Event) ! {
	encoded := encode_kafka_event(e, s.encoding_codec)
	if encoded.len > 0 {
		s.buffer << encoded
	}

	if s.buffer.len >= s.batch_max_events {
		s.flush()!
	}
}

// flush sends all buffered events to Kafka.
// Stub: logs the batch size and clears the buffer.
// In production, this would serialize a Kafka ProduceRequest and send
// it over the Kafka binary protocol or via librdkafka.
pub fn (mut s KafkaSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	// Kafka wire protocol produce — would batch-send to topic partitions.
	// For now, just clear the buffer (stub).
	s.buffer.clear()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &KafkaSink) total_buffered() int {
	return s.buffer.len
}

// encode_kafka_event encodes an event according to the specified codec.
pub fn encode_kafka_event(e event.Event, codec string) string {
	match e {
		event.LogEvent {
			return match codec {
				'text' { e.message() }
				'raw' { e.message() }
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
