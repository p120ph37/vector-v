module sources

import event
import time

// PulsarSource consumes messages from Apache Pulsar topics.
// Mirrors Vector's pulsar source configuration.
//
// Implements a Pulsar consumer that subscribes to one or more topics
// and converts messages to Vector log events with metadata enrichment.
//
// Config options:
//   endpoint:                      Pulsar broker URL (default: pulsar://127.0.0.1:6650)
//   topics:                        Comma-separated topic list (required)
//   subscription:                  Subscription name (default: "vector")
//   consumer_name:                 Consumer name (default: "vector")
//   auth.token:                    Bearer token auth
//   auth.oauth2.issuer_url:        OAuth2 issuer URL
//   auth.oauth2.audience:          OAuth2 audience
//   auth.oauth2.credentials_url:   OAuth2 credentials URL
//   batch_size:                    Consumer batch size (default: 1000)
//   decoding.codec:                Decoding format (default: "bytes")
//   dead_letter_topic:             Dead letter queue topic
//   tls.enabled:                   Enable TLS
//   topic_key:                     Metadata key for topic name (default: "pulsar_topic")
//   producer_key:                  Metadata key for producer name (default: "pulsar_producer")
pub struct PulsarSource {
	endpoint                    string = 'pulsar://127.0.0.1:6650'
	topics                      []string
	subscription                string = 'vector'
	consumer_name               string = 'vector'
	auth_token                  string
	auth_oauth2_url             string
	auth_oauth2_audience        string
	auth_oauth2_credentials_url string
	batch_size                  int = 1000
	decoding_codec              string = 'bytes'
	dead_letter_topic           string
	topic_key                   string = 'pulsar_topic'
	producer_key                string = 'pulsar_producer'
	tls_enabled                 bool
}

// parse_pulsar_url extracts host, port, and TLS flag from a pulsar:// or pulsar+ssl:// URL.
// Returns (host, port, tls).
pub fn parse_pulsar_url(url string) !(string, int, bool) {
	mut s := url
	mut tls := false

	if s.starts_with('pulsar+ssl://') {
		tls = true
		s = s[13..]
	} else if s.starts_with('pulsar://') {
		s = s[9..]
	} else {
		return error('pulsar: invalid URL scheme, expected pulsar:// or pulsar+ssl://')
	}

	// Strip trailing path
	if idx := s.index('/') {
		s = s[..idx]
	}

	// Parse host:port
	mut host := '127.0.0.1'
	mut port := 6650

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

	return host, port, tls
}

// validate_pulsar_source_config checks that required config options are present.
pub fn validate_pulsar_source_config(opts map[string]string) !bool {
	_ := opts['topics'] or {
		return error('pulsar source: topics is required')
	}
	// Validate endpoint URL if provided
	if ep := opts['endpoint'] {
		if !ep.starts_with('pulsar://') && !ep.starts_with('pulsar+ssl://') {
			return error('pulsar source: endpoint must start with pulsar:// or pulsar+ssl://')
		}
	}
	// Validate batch_size if provided
	if bs := opts['batch_size'] {
		if bs.int() <= 0 {
			return error('pulsar source: batch_size must be positive')
		}
	}
	return true
}

// build_pulsar_metadata creates a metadata map from Pulsar message properties.
pub fn build_pulsar_metadata(topic string, producer_name string, publish_time_ms i64, message_id string) map[string]string {
	mut meta := map[string]string{}
	meta['topic'] = topic
	meta['producer_name'] = producer_name
	meta['publish_time_ms'] = '${publish_time_ms}'
	meta['message_id'] = message_id
	return meta
}

// new_pulsar_source creates a new PulsarSource from config options.
pub fn new_pulsar_source(opts map[string]string) !PulsarSource {
	topics_str := opts['topics'] or {
		return error('pulsar source: topics is required')
	}
	topics := topics_str.split(',').map(it.trim_space()).filter(it.len > 0)
	if topics.len == 0 {
		return error('pulsar source: topics is required')
	}

	endpoint := opts['endpoint'] or { 'pulsar://127.0.0.1:6650' }

	// Validate endpoint
	if !endpoint.starts_with('pulsar://') && !endpoint.starts_with('pulsar+ssl://') {
		return error('pulsar source: endpoint must start with pulsar:// or pulsar+ssl://')
	}

	subscription := opts['subscription'] or { 'vector' }
	consumer_name := opts['consumer_name'] or { 'vector' }
	auth_token := opts['auth.token'] or { '' }
	auth_oauth2_url := opts['auth.oauth2.issuer_url'] or { '' }
	auth_oauth2_audience := opts['auth.oauth2.audience'] or { '' }
	auth_oauth2_credentials_url := opts['auth.oauth2.credentials_url'] or { '' }
	decoding_codec := opts['decoding.codec'] or { 'bytes' }
	dead_letter_topic := opts['dead_letter_topic'] or { '' }
	topic_key := opts['topic_key'] or { 'pulsar_topic' }
	producer_key := opts['producer_key'] or { 'pulsar_producer' }

	mut batch_size := 1000
	if bs := opts['batch_size'] {
		batch_size = bs.int()
		if batch_size <= 0 {
			batch_size = 1000
		}
	}

	mut tls_enabled := false
	if tls_opt := opts['tls.enabled'] {
		tls_enabled = tls_opt == 'true'
	}
	if endpoint.starts_with('pulsar+ssl://') {
		tls_enabled = true
	}

	return PulsarSource{
		endpoint: endpoint
		topics: topics
		subscription: subscription
		consumer_name: consumer_name
		auth_token: auth_token
		auth_oauth2_url: auth_oauth2_url
		auth_oauth2_audience: auth_oauth2_audience
		auth_oauth2_credentials_url: auth_oauth2_credentials_url
		batch_size: batch_size
		decoding_codec: decoding_codec
		dead_letter_topic: dead_letter_topic
		topic_key: topic_key
		producer_key: producer_key
		tls_enabled: tls_enabled
	}
}

// run connects to Pulsar and begins consuming messages.
// TODO: Implement Pulsar binary protocol consumer.
// This will connect to the broker, send CommandConnect, subscribe to
// configured topics, and convert received messages into Vector log events.
pub fn (s &PulsarSource) run(output chan event.Event) {
	// Stub: Pulsar binary protocol consumer not yet implemented.
	// When implemented, this method will:
	// 1. Connect to the Pulsar broker via TCP (with optional TLS)
	// 2. Send CommandConnect with auth credentials
	// 3. Create a subscription on each topic
	// 4. Receive messages, decode them with the configured codec
	// 5. Enrich events with Pulsar metadata (topic, producer, publish time)
	// 6. Send events to the output channel
	// 7. Acknowledge messages (or route to dead letter topic on failure)
	eprintln('pulsar source: not yet implemented')
	_ = time.now() // avoid unused import
}
