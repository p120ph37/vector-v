module sinks

import event

fn test_new_pulsar_sink_defaults() {
	s := new_pulsar_sink({
		'topic': 'my-topic'
	}) or { panic(err.str()) }
	assert s.endpoint == 'pulsar://127.0.0.1:6650'
	assert s.topic == 'my-topic'
	assert s.producer_name == 'vector'
	assert s.encoding_codec == 'json'
	assert s.compression == 'none'
	assert s.partition_key_field == ''
	assert s.batch_max_events == 1000
	assert s.batch_timeout_ms == 1000
	assert s.auth_token == ''
	assert s.tls_enabled == false
	assert s.buffer.len == 0
}

fn test_new_pulsar_sink_missing_topic() {
	new_pulsar_sink(map[string]string{}) or {
		assert err.msg().contains('topic is required')
		return
	}
	assert false, 'expected error for missing topic'
}

fn test_new_pulsar_sink_custom() {
	s := new_pulsar_sink({
		'topic':              'events'
		'endpoint':           'pulsar://pulsar.local:6651'
		'producer_name':      'my-producer'
		'encoding.codec':     'text'
		'compression':        'lz4'
		'partition_key_field': 'host'
		'batch.max_events':   '500'
		'batch.timeout_ms':   '2000'
		'auth.token':         'my-token'
	}) or { panic(err.str()) }
	assert s.endpoint == 'pulsar://pulsar.local:6651'
	assert s.topic == 'events'
	assert s.producer_name == 'my-producer'
	assert s.encoding_codec == 'text'
	assert s.compression == 'lz4'
	assert s.partition_key_field == 'host'
	assert s.batch_max_events == 500
	assert s.batch_timeout_ms == 2000
	assert s.auth_token == 'my-token'
}

fn test_pulsar_sink_send_buffers() {
	mut s := new_pulsar_sink({
		'topic':            'my-topic'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_pulsar_sink_total_buffered() {
	mut s := new_pulsar_sink({
		'topic':            'my-topic'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	s.send(ev) or {}
	assert s.total_buffered() == 2
}

fn test_pulsar_sink_flush_empty() {
	mut s := new_pulsar_sink({
		'topic': 'my-topic'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_pulsar_sink_compression_config() {
	// lz4
	s1 := new_pulsar_sink({
		'topic':       't'
		'compression': 'lz4'
	}) or { panic(err.str()) }
	assert s1.compression == 'lz4'

	// zlib
	s2 := new_pulsar_sink({
		'topic':       't'
		'compression': 'zlib'
	}) or { panic(err.str()) }
	assert s2.compression == 'zlib'

	// zstd
	s3 := new_pulsar_sink({
		'topic':       't'
		'compression': 'zstd'
	}) or { panic(err.str()) }
	assert s3.compression == 'zstd'

	// snappy
	s4 := new_pulsar_sink({
		'topic':       't'
		'compression': 'snappy'
	}) or { panic(err.str()) }
	assert s4.compression == 'snappy'

	// unknown falls back to none
	s5 := new_pulsar_sink({
		'topic':       't'
		'compression': 'brotli'
	}) or { panic(err.str()) }
	assert s5.compression == 'none'
}

fn test_encode_pulsar_payload_json() {
	ev := event.Event(event.new_log('test message'))
	result := encode_pulsar_payload(ev, 'json')
	assert result.contains('message')
	assert result.contains('test message')
}

fn test_encode_pulsar_payload_text() {
	ev := event.Event(event.new_log('test message'))
	result := encode_pulsar_payload(ev, 'text')
	assert result == 'test message'
}

fn test_pulsar_sink_partition_key() {
	s := new_pulsar_sink({
		'topic':              'my-topic'
		'partition_key_field': 'hostname'
	}) or { panic(err.str()) }
	assert s.partition_key_field == 'hostname'

	// Without partition key field
	s2 := new_pulsar_sink({
		'topic': 'my-topic'
	}) or { panic(err.str()) }
	assert s2.partition_key_field == ''
}
