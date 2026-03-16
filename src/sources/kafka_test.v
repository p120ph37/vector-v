module sources

import event

fn test_new_kafka_source_defaults() {
	s := new_kafka_source({
		'bootstrap_servers': 'localhost:9092'
		'group_id':          'my-group'
		'topics':            'my-topic'
	}) or { panic(err.str()) }
	assert s.bootstrap_servers == ['localhost:9092']
	assert s.group_id == 'my-group'
	assert s.topics == ['my-topic']
	assert s.auto_offset_reset == 'latest'
	assert s.commit_interval_ms == 5000
	assert s.session_timeout_ms == 10000
	assert s.sasl_mechanism == ''
	assert s.sasl_username == ''
	assert s.sasl_password == ''
	assert s.tls_enabled == false
	assert s.decoding_codec == 'bytes'
	assert s.headers_key == 'kafka_headers'
	assert s.topic_key == 'kafka_topic'
	assert s.partition_key == 'kafka_partition'
	assert s.offset_key == 'kafka_offset'
}

fn test_new_kafka_source_missing_servers() {
	new_kafka_source({
		'group_id': 'my-group'
		'topics':   'my-topic'
	}) or {
		assert err.msg().contains('bootstrap_servers is required')
		return
	}
	assert false, 'expected error for missing bootstrap_servers'
}

fn test_new_kafka_source_missing_group_id() {
	new_kafka_source({
		'bootstrap_servers': 'localhost:9092'
		'topics':            'my-topic'
	}) or {
		assert err.msg().contains('group_id is required')
		return
	}
	assert false, 'expected error for missing group_id'
}

fn test_new_kafka_source_missing_topics() {
	new_kafka_source({
		'bootstrap_servers': 'localhost:9092'
		'group_id':          'my-group'
	}) or {
		assert err.msg().contains('topics is required')
		return
	}
	assert false, 'expected error for missing topics'
}

fn test_new_kafka_source_custom() {
	s := new_kafka_source({
		'bootstrap_servers': 'broker1:9092,broker2:9093,broker3:9094'
		'group_id':          'custom-group'
		'topics':            'topic-a,topic-b,topic-c'
		'auto_offset_reset': 'earliest'
		'commit_interval_ms': '3000'
		'session_timeout_ms': '15000'
		'sasl.mechanism':    'SCRAM-SHA-256'
		'sasl.username':     'user1'
		'sasl.password':     'pass1'
		'tls.enabled':       'true'
		'decoding.codec':    'json'
	}) or { panic(err.str()) }
	assert s.bootstrap_servers == ['broker1:9092', 'broker2:9093', 'broker3:9094']
	assert s.group_id == 'custom-group'
	assert s.topics == ['topic-a', 'topic-b', 'topic-c']
	assert s.auto_offset_reset == 'earliest'
	assert s.commit_interval_ms == 3000
	assert s.session_timeout_ms == 15000
	assert s.sasl_mechanism == 'SCRAM-SHA-256'
	assert s.sasl_username == 'user1'
	assert s.sasl_password == 'pass1'
	assert s.tls_enabled == true
	assert s.decoding_codec == 'json'
}

fn test_parse_kafka_bootstrap_servers() {
	// Single server
	s1 := parse_kafka_bootstrap_servers('localhost:9092')
	assert s1 == ['localhost:9092']

	// Multiple servers
	s2 := parse_kafka_bootstrap_servers('broker1:9092,broker2:9093,broker3:9094')
	assert s2 == ['broker1:9092', 'broker2:9093', 'broker3:9094']

	// With whitespace
	s3 := parse_kafka_bootstrap_servers(' broker1:9092 , broker2:9093 ')
	assert s3 == ['broker1:9092', 'broker2:9093']

	// Empty entries filtered out
	s4 := parse_kafka_bootstrap_servers('broker1:9092,,broker2:9093')
	assert s4 == ['broker1:9092', 'broker2:9093']
}

fn test_validate_kafka_source_config() {
	// Valid config
	result := validate_kafka_source_config({
		'bootstrap_servers': 'localhost:9092'
		'group_id':          'my-group'
		'topics':            'my-topic'
	}) or {
		assert false, 'expected valid config'
		return
	}
	assert result == true

	// Missing bootstrap_servers
	validate_kafka_source_config({
		'group_id': 'my-group'
		'topics':   'my-topic'
	}) or {
		assert err.msg().contains('bootstrap_servers is required')
		return
	}
	assert false, 'expected error for missing bootstrap_servers'
}

fn test_build_kafka_metadata() {
	meta := build_kafka_metadata('events', 3, 12345, 1700000000)
	assert meta.len == 4
	assert 'topic' in meta
	assert 'partition' in meta
	assert 'offset' in meta
	assert 'timestamp_ms' in meta
	// Verify values via event.value_to_string
	assert event.value_to_string(meta['topic'] or { event.Value('') }) == 'events'
	assert event.value_to_string(meta['partition'] or { event.Value(0) }) == '3'
	assert event.value_to_string(meta['offset'] or { event.Value(0) }) == '12345'
	assert event.value_to_string(meta['timestamp_ms'] or { event.Value(0) }) == '1700000000'
}

fn test_kafka_source_sasl_config() {
	// PLAIN
	s1 := new_kafka_source({
		'bootstrap_servers': 'localhost:9092'
		'group_id':          'g1'
		'topics':            't1'
		'sasl.mechanism':    'PLAIN'
		'sasl.username':     'admin'
		'sasl.password':     'secret'
	}) or { panic(err.str()) }
	assert s1.sasl_mechanism == 'PLAIN'
	assert s1.sasl_username == 'admin'
	assert s1.sasl_password == 'secret'

	// SCRAM-SHA-512
	s2 := new_kafka_source({
		'bootstrap_servers': 'localhost:9092'
		'group_id':          'g1'
		'topics':            't1'
		'sasl.mechanism':    'SCRAM-SHA-512'
		'sasl.username':     'user'
		'sasl.password':     'pw'
	}) or { panic(err.str()) }
	assert s2.sasl_mechanism == 'SCRAM-SHA-512'
}

fn test_kafka_source_tls_config() {
	// TLS enabled
	s1 := new_kafka_source({
		'bootstrap_servers': 'localhost:9093'
		'group_id':          'g1'
		'topics':            't1'
		'tls.enabled':       'true'
	}) or { panic(err.str()) }
	assert s1.tls_enabled == true

	// TLS disabled (default)
	s2 := new_kafka_source({
		'bootstrap_servers': 'localhost:9092'
		'group_id':          'g1'
		'topics':            't1'
	}) or { panic(err.str()) }
	assert s2.tls_enabled == false

	// TLS explicitly disabled
	s3 := new_kafka_source({
		'bootstrap_servers': 'localhost:9092'
		'group_id':          'g1'
		'topics':            't1'
		'tls.enabled':       'false'
	}) or { panic(err.str()) }
	assert s3.tls_enabled == false
}
