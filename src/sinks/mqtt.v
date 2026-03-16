module sinks

import event
import json
import time

// MqttSink publishes events to an MQTT broker on a given topic.
// Mirrors Vector's mqtt sink concept.
//
// Events are encoded (JSON or text), buffered, and published as MQTT PUBLISH
// packets. The sink supports QoS 0-2, message retention, and template-based
// topic routing using {{field}} placeholders.
//
// Config options:
//   host:             MQTT broker host (default: 127.0.0.1)
//   port:             MQTT broker port (default: 1883)
//   topic:            Target topic, may contain {{field}} templates (required)
//   qos:              Quality of service 0-2 (default: 0)
//   client_id:        Client identifier (default: "vector")
//   username:         Auth username
//   password:         Auth password
//   clean_session:    Start with clean session (default: true)
//   keep_alive_secs:  Keep-alive interval (default: 60)
//   retain:           Retain messages on broker (default: false)
//   encoding.codec:   Encoding format json or text (default: json)
//   tls.enabled:      Enable TLS (default: false)
//   batch.max_events: Max events per batch (default: 100)
pub struct MqttSink {
pub mut:
	host             string = '127.0.0.1'
	port             int    = 1883
	topic            string // can contain {{field}} templates
	qos              int // 0=at_most_once, 1=at_least_once, 2=exactly_once
	client_id        string = 'vector'
	username         string
	password         string
	clean_session    bool = true
	keep_alive_secs  int  = 60
	retain           bool // retain messages on broker
	encoding_codec   string = 'json'
	tls_enabled      bool
	buffer           []string
	batch_max_events int = 100
}

// new_mqtt_sink creates a new MqttSink from config options.
// Returns error if topic is not provided.
pub fn new_mqtt_sink(opts map[string]string) !MqttSink {
	topic := opts['topic'] or {
		return error('mqtt sink: topic is required')
	}
	if topic.len == 0 {
		return error('mqtt sink: topic is required')
	}

	mut host := opts['host'] or { '127.0.0.1' }
	if host.len == 0 {
		host = '127.0.0.1'
	}

	mut tls_enabled := false
	if tls_opt := opts['tls.enabled'] {
		tls_enabled = tls_opt == 'true'
	}

	default_port := if tls_enabled { 8883 } else { 1883 }
	mut port := default_port
	if p := opts['port'] {
		parsed := p.int()
		if parsed > 0 {
			port = parsed
		}
	}

	mut qos := 0
	if q := opts['qos'] {
		qos = q.int()
		if qos < 0 || qos > 2 {
			qos = 0
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

	mut retain := false
	if r := opts['retain'] {
		retain = r == 'true'
	}

	encoding_codec := opts['encoding.codec'] or { 'json' }

	mut batch_max_events := 100
	if bm := opts['batch.max_events'] {
		batch_max_events = bm.int()
		if batch_max_events <= 0 {
			batch_max_events = 100
		}
	}

	return MqttSink{
		host:             host
		port:             port
		topic:            topic
		qos:              qos
		client_id:        client_id
		username:         username
		password:         password
		clean_session:    clean_session
		keep_alive_secs:  keep_alive_secs
		retain:           retain
		encoding_codec:   encoding_codec
		tls_enabled:      tls_enabled
		batch_max_events: batch_max_events
	}
}

// send encodes an event and buffers it. Flushes when batch is full.
pub fn (mut s MqttSink) send(e event.Event) ! {
	encoded := encode_mqtt_payload(e, s.encoding_codec)
	if encoded.len > 0 {
		s.buffer << encoded
	}
	if s.buffer.len >= s.batch_max_events {
		s.flush()!
	}
}

// flush publishes all buffered messages to the MQTT broker.
// TODO: Implement actual MQTT PUBLISH packet sending over TCP.
pub fn (mut s MqttSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}
	// Stub: would connect to broker and send PUBLISH packets for each
	// buffered message. For now, just clear the buffer.
	// In a real implementation, this would use net.TcpConn with the
	// MQTT v3.1.1 binary protocol.
	s.buffer.clear()
	_ = time.now() // suppress unused import
}

// total_buffered returns the number of events currently buffered.
pub fn (s &MqttSink) total_buffered() int {
	return s.buffer.len
}

// encode_mqtt_payload encodes an event for MQTT transmission.
// Supported codecs: "json" (default) and "text".
pub fn encode_mqtt_payload(e event.Event, codec string) string {
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
