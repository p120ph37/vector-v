module sinks

import event

fn test_new_kafka_sink_defaults() {
	s := new_kafka_sink({
		'bootstrap_servers': 'localhost:9092'
		'topic':             'my-topic'
	}) or { panic(err.str()) }
	assert s.bootstrap_servers == ['localhost:9092']
	assert s.topic == 'my-topic'
	assert s.key_field == ''
	assert s.encoding_codec == 'json'
	assert s.compression == 'none'
	assert s.batch_max_events == 1000
	assert s.batch_timeout_ms == 1000
	assert s.sasl_mechanism == ''
	assert s.sasl_username == ''
	assert s.sasl_password == ''
	assert s.tls_enabled == false
	assert s.headers_key == ''
	assert s.buffer.len == 0
}

fn test_new_kafka_sink_missing_servers() {
	new_kafka_sink({
		'topic': 'my-topic'
	}) or {
		assert err.msg().contains('bootstrap_servers is required')
		return
	}
	assert false, 'expected error for missing bootstrap_servers'
}

fn test_new_kafka_sink_missing_topic() {
	new_kafka_sink({
		'bootstrap_servers': 'localhost:9092'
	}) or {
		assert err.msg().contains('topic is required')
		return
	}
	assert false, 'expected error for missing topic'
}

fn test_new_kafka_sink_custom() {
	s := new_kafka_sink({
		'bootstrap_servers': 'broker1:9092,broker2:9093'
		'topic':             'events-{{env}}'
		'key_field':         'user_id'
		'encoding.codec':    'text'
		'compression':       'snappy'
		'batch.max_events':  '500'
		'batch.timeout_ms':  '2000'
		'sasl.mechanism':    'PLAIN'
		'sasl.username':     'producer'
		'sasl.password':     'secret'
		'tls.enabled':       'true'
		'headers_key':       'kafka_headers'
	}) or { panic(err.str()) }
	assert s.bootstrap_servers == ['broker1:9092', 'broker2:9093']
	assert s.topic == 'events-{{env}}'
	assert s.key_field == 'user_id'
	assert s.encoding_codec == 'text'
	assert s.compression == 'snappy'
	assert s.batch_max_events == 500
	assert s.batch_timeout_ms == 2000
	assert s.sasl_mechanism == 'PLAIN'
	assert s.sasl_username == 'producer'
	assert s.sasl_password == 'secret'
	assert s.tls_enabled == true
	assert s.headers_key == 'kafka_headers'
}

fn test_kafka_sink_send_buffers() {
	mut s := new_kafka_sink({
		'bootstrap_servers': 'localhost:9092'
		'topic':             'test'
		'batch.max_events':  '10000'
	}) or { panic(err.str()) }

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_kafka_sink_total_buffered() {
	mut s := new_kafka_sink({
		'bootstrap_servers': 'localhost:9092'
		'topic':             'test'
		'batch.max_events':  '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	s.send(ev) or {}
	assert s.total_buffered() == 2
}

fn test_kafka_sink_flush_empty() {
	mut s := new_kafka_sink({
		'bootstrap_servers': 'localhost:9092'
		'topic':             'test'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_kafka_sink_compression_config() {
	// Valid compressions
	for comp in ['none', 'gzip', 'snappy', 'lz4', 'zstd'] {
		s := new_kafka_sink({
			'bootstrap_servers': 'localhost:9092'
			'topic':             'test'
			'compression':       comp
		}) or { panic(err.str()) }
		assert s.compression == comp
	}

	// Invalid compression falls back to none
	s := new_kafka_sink({
		'bootstrap_servers': 'localhost:9092'
		'topic':             'test'
		'compression':       'invalid'
	}) or { panic(err.str()) }
	assert s.compression == 'none'
}

fn test_kafka_sink_sasl_config() {
	s := new_kafka_sink({
		'bootstrap_servers': 'localhost:9092'
		'topic':             'test'
		'sasl.mechanism':    'SCRAM-SHA-256'
		'sasl.username':     'admin'
		'sasl.password':     'password123'
	}) or { panic(err.str()) }
	assert s.sasl_mechanism == 'SCRAM-SHA-256'
	assert s.sasl_username == 'admin'
	assert s.sasl_password == 'password123'
}

fn test_encode_kafka_event_json() {
	mut log := event.new_log('hello world')
	log.set('level', event.Value('info'))
	ev := event.Event(log)

	encoded := encode_kafka_event(ev, 'json')
	assert encoded.contains('"message"')
	assert encoded.contains('hello world')
	assert encoded.contains('"level"')
}

fn test_encode_kafka_event_text() {
	log := event.new_log('plain text message')
	ev := event.Event(log)

	encoded := encode_kafka_event(ev, 'text')
	assert encoded == 'plain text message'
}

fn test_kafka_sink_registry() {
	// Test that the constructor works correctly without adding to registry.
	// This verifies the KafkaSink can be created with valid config.
	s := new_kafka_sink({
		'bootstrap_servers': 'localhost:9092'
		'topic':             'test-topic'
	}) or { panic(err.str()) }
	assert s.topic == 'test-topic'
	assert s.bootstrap_servers == ['localhost:9092']
	assert s.encoding_codec == 'json'
}
