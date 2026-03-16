module sources

import event
import time

// KafkaSource consumes messages from Apache Kafka topics.
// Mirrors Vector's kafka source (src/sources/kafka/).
//
// This implements configuration parsing and event construction.
// The actual Kafka wire protocol consumer is stubbed — in production
// this would use librdkafka via C interop or implement the Kafka
// binary protocol directly.
//
// Config options:
//   bootstrap_servers:  Comma-separated broker list (required)
//   group_id:           Consumer group ID (required)
//   topics:             Comma-separated topic list (required)
//   auto_offset_reset:  Starting offset — "latest" or "earliest" (default: "latest")
//   commit_interval_ms: Auto-commit interval in ms (default: 5000)
//   session_timeout_ms: Session timeout in ms (default: 10000)
//   sasl.mechanism:     SASL auth mechanism (PLAIN, SCRAM-SHA-256, SCRAM-SHA-512)
//   sasl.username:      SASL username
//   sasl.password:      SASL password
//   tls.enabled:        Enable TLS (default: false)
//   decoding.codec:     Message decoding — "bytes", "json", "text" (default: "bytes")
pub struct KafkaSource {
	bootstrap_servers []string
	group_id          string
	topics            []string
	auto_offset_reset string = 'latest'
	commit_interval_ms int    = 5000
	session_timeout_ms int    = 10000
	sasl_mechanism    string
	sasl_username     string
	sasl_password     string
	tls_enabled       bool
	decoding_codec    string = 'bytes'
	headers_key       string = 'kafka_headers'
	topic_key         string = 'kafka_topic'
	partition_key     string = 'kafka_partition'
	offset_key        string = 'kafka_offset'
}

// new_kafka_source creates a new KafkaSource from config options.
pub fn new_kafka_source(opts map[string]string) !KafkaSource {
	servers_str := opts['bootstrap_servers'] or {
		return error('kafka: bootstrap_servers is required')
	}
	if servers_str.len == 0 {
		return error('kafka: bootstrap_servers is required')
	}

	group_id := opts['group_id'] or {
		return error('kafka: group_id is required')
	}
	if group_id.len == 0 {
		return error('kafka: group_id is required')
	}

	topics_str := opts['topics'] or {
		return error('kafka: topics is required')
	}
	if topics_str.len == 0 {
		return error('kafka: topics is required')
	}

	servers := parse_kafka_bootstrap_servers(servers_str)
	topics := topics_str.split(',').map(it.trim_space()).filter(it.len > 0)

	mut auto_offset_reset := 'latest'
	if v := opts['auto_offset_reset'] {
		if v == 'earliest' || v == 'latest' {
			auto_offset_reset = v
		}
	}

	mut commit_interval_ms := 5000
	if v := opts['commit_interval_ms'] {
		parsed := v.int()
		if parsed > 0 {
			commit_interval_ms = parsed
		}
	}

	mut session_timeout_ms := 10000
	if v := opts['session_timeout_ms'] {
		parsed := v.int()
		if parsed > 0 {
			session_timeout_ms = parsed
		}
	}

	sasl_mechanism := opts['sasl.mechanism'] or { '' }
	sasl_username := opts['sasl.username'] or { '' }
	sasl_password := opts['sasl.password'] or { '' }

	mut tls_enabled := false
	if v := opts['tls.enabled'] {
		tls_enabled = v == 'true'
	}

	decoding_codec := opts['decoding.codec'] or { 'bytes' }

	return KafkaSource{
		bootstrap_servers: servers
		group_id: group_id
		topics: topics
		auto_offset_reset: auto_offset_reset
		commit_interval_ms: commit_interval_ms
		session_timeout_ms: session_timeout_ms
		sasl_mechanism: sasl_mechanism
		sasl_username: sasl_username
		sasl_password: sasl_password
		tls_enabled: tls_enabled
		decoding_codec: decoding_codec
	}
}

// run starts the Kafka consumer loop.
// Kafka wire protocol consumer — connects to bootstrap_servers,
// joins consumer group, fetches from assigned topic-partitions.
// In production, this would implement the Kafka binary protocol
// or use librdkafka via C interop.
pub fn (s &KafkaSource) run(output chan event.Event) {
	for {
		// Poll cycle: fetch messages from assigned partitions
		// For each message:
		//   mut ev := event.new_log(message_value)
		//   ev.meta.source_type = 'kafka'
		//   ev.set(s.topic_key, event.Value(topic))
		//   ev.set(s.partition_key, event.Value(partition))
		//   ev.set(s.offset_key, event.Value(offset))
		//   output <- event.Event(ev)
		time.sleep(1 * time.second)
	}
}

// parse_kafka_bootstrap_servers parses a comma-separated list of Kafka broker
// addresses into individual server strings, trimming whitespace.
pub fn parse_kafka_bootstrap_servers(servers_str string) []string {
	return servers_str.split(',').map(it.trim_space()).filter(it.len > 0)
}

// validate_kafka_source_config validates that all required fields are present
// in the Kafka source configuration.
pub fn validate_kafka_source_config(opts map[string]string) !bool {
	if 'bootstrap_servers' !in opts || opts['bootstrap_servers'].len == 0 {
		return error('kafka: bootstrap_servers is required')
	}
	if 'group_id' !in opts || opts['group_id'].len == 0 {
		return error('kafka: group_id is required')
	}
	if 'topics' !in opts || opts['topics'].len == 0 {
		return error('kafka: topics is required')
	}
	return true
}

// build_kafka_metadata builds a metadata map for enriching log events with
// Kafka message metadata (topic, partition, offset, timestamp).
pub fn build_kafka_metadata(topic string, partition int, offset i64, timestamp_ms i64) map[string]event.Value {
	mut meta := map[string]event.Value{}
	meta['topic'] = event.Value(topic)
	meta['partition'] = event.Value(partition)
	meta['offset'] = event.Value(int(offset))
	meta['timestamp_ms'] = event.Value(int(timestamp_ms))
	return meta
}
