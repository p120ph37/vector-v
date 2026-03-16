module sources

fn test_new_pulsar_source_defaults() {
	s := new_pulsar_source({
		'topics': 'my-topic'
	}) or { panic(err.str()) }
	assert s.endpoint == 'pulsar://127.0.0.1:6650'
	assert s.topics == ['my-topic']
	assert s.subscription == 'vector'
	assert s.consumer_name == 'vector'
	assert s.batch_size == 1000
	assert s.decoding_codec == 'bytes'
	assert s.auth_token == ''
	assert s.tls_enabled == false
	assert s.dead_letter_topic == ''
	assert s.topic_key == 'pulsar_topic'
	assert s.producer_key == 'pulsar_producer'
}

fn test_new_pulsar_source_missing_topics() {
	new_pulsar_source(map[string]string{}) or {
		assert err.msg().contains('topics is required')
		return
	}
	assert false, 'expected error for missing topics'
}

fn test_new_pulsar_source_custom() {
	s := new_pulsar_source({
		'topics':        'events,logs,traces'
		'endpoint':      'pulsar://pulsar.local:6651'
		'subscription':  'my-sub'
		'consumer_name': 'my-consumer'
		'batch_size':    '500'
		'decoding.codec': 'json'
		'topic_key':     'custom_topic'
		'producer_key':  'custom_producer'
	}) or { panic(err.str()) }
	assert s.endpoint == 'pulsar://pulsar.local:6651'
	assert s.topics == ['events', 'logs', 'traces']
	assert s.subscription == 'my-sub'
	assert s.consumer_name == 'my-consumer'
	assert s.batch_size == 500
	assert s.decoding_codec == 'json'
	assert s.topic_key == 'custom_topic'
	assert s.producer_key == 'custom_producer'
}

fn test_parse_pulsar_url() {
	// Standard pulsar:// URL
	host1, port1, tls1 := parse_pulsar_url('pulsar://localhost:6650') or { panic(err.str()) }
	assert host1 == 'localhost'
	assert port1 == 6650
	assert tls1 == false

	// pulsar+ssl:// URL
	host2, port2, tls2 := parse_pulsar_url('pulsar+ssl://secure.pulsar.io:6651') or {
		panic(err.str())
	}
	assert host2 == 'secure.pulsar.io'
	assert port2 == 6651
	assert tls2 == true

	// Default port
	host3, port3, tls3 := parse_pulsar_url('pulsar://myhost') or { panic(err.str()) }
	assert host3 == 'myhost'
	assert port3 == 6650
	assert tls3 == false

	// With trailing path
	host4, port4, _ := parse_pulsar_url('pulsar://broker:6650/tenant/namespace') or {
		panic(err.str())
	}
	assert host4 == 'broker'
	assert port4 == 6650
}

fn test_parse_pulsar_url_invalid() {
	// Invalid scheme
	parse_pulsar_url('http://localhost:6650') or {
		assert err.msg().contains('invalid URL scheme')
		return
	}
	assert false, 'expected error for invalid URL scheme'
}

fn test_validate_pulsar_source_config() {
	// Valid config
	result := validate_pulsar_source_config({
		'topics':   'my-topic'
		'endpoint': 'pulsar://localhost:6650'
	}) or { panic(err.str()) }
	assert result == true

	// Missing topics
	validate_pulsar_source_config(map[string]string{}) or {
		assert err.msg().contains('topics is required')
		return
	}
	assert false, 'expected error for missing topics'
}

fn test_build_pulsar_metadata() {
	meta := build_pulsar_metadata('persistent://tenant/ns/topic', 'producer-1', 1700000000000,
		'1:2:3')
	assert meta['topic'] == 'persistent://tenant/ns/topic'
	assert meta['producer_name'] == 'producer-1'
	assert meta['publish_time_ms'] == '1700000000000'
	assert meta['message_id'] == '1:2:3'
}

fn test_pulsar_source_oauth2_config() {
	s := new_pulsar_source({
		'topics':                     'my-topic'
		'auth.oauth2.issuer_url':     'https://auth.example.com'
		'auth.oauth2.audience':       'urn:pulsar:cluster'
		'auth.oauth2.credentials_url': 'file:///path/to/creds.json'
	}) or { panic(err.str()) }
	assert s.auth_oauth2_url == 'https://auth.example.com'
	assert s.auth_oauth2_audience == 'urn:pulsar:cluster'
	assert s.auth_oauth2_credentials_url == 'file:///path/to/creds.json'
	assert s.auth_token == ''
}

fn test_pulsar_source_dead_letter_topic() {
	s := new_pulsar_source({
		'topics':            'my-topic'
		'dead_letter_topic': 'persistent://tenant/ns/dlq'
	}) or { panic(err.str()) }
	assert s.dead_letter_topic == 'persistent://tenant/ns/dlq'
}

fn test_pulsar_source_batch_config() {
	// Custom batch size
	s1 := new_pulsar_source({
		'topics':     'my-topic'
		'batch_size': '2000'
	}) or { panic(err.str()) }
	assert s1.batch_size == 2000

	// Invalid batch size falls back to default
	s2 := new_pulsar_source({
		'topics':     'my-topic'
		'batch_size': '-5'
	}) or { panic(err.str()) }
	assert s2.batch_size == 1000

	// Zero batch size falls back to default
	s3 := new_pulsar_source({
		'topics':     'my-topic'
		'batch_size': '0'
	}) or { panic(err.str()) }
	assert s3.batch_size == 1000
}
