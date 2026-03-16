module sinks

import event

fn test_new_amqp_sink_defaults() {
	s := new_amqp_sink({
		'exchange': 'my-exchange'
	}) or { panic(err.str()) }
	assert s.connection_string == 'amqp://guest:guest@127.0.0.1:5672/%2f'
	assert s.exchange == 'my-exchange'
	assert s.routing_key == ''
	assert s.encoding_codec == 'json'
	assert s.content_type == 'application/json'
	assert s.delivery_mode == 2
	assert s.max_channels == 10
	assert s.tls_enabled == false
	assert s.batch_max_events == 100
	assert s.buffer.len == 0
}

fn test_new_amqp_sink_missing_exchange() {
	new_amqp_sink(map[string]string{}) or {
		assert err.msg().contains('exchange is required')
		return
	}
	assert false, 'expected error for missing exchange'
}

fn test_new_amqp_sink_custom() {
	s := new_amqp_sink({
		'connection':              'amqp://admin:secret@rabbit:5673/prod'
		'exchange':                'events'
		'routing_key':             'app.logs'
		'encoding.codec':          'text'
		'properties.content_type': 'text/plain'
		'properties.delivery_mode': '1'
		'max_channels':            '20'
		'tls.enabled':             'true'
		'batch.max_events':        '50'
	}) or { panic(err.str()) }
	assert s.connection_string == 'amqp://admin:secret@rabbit:5673/prod'
	assert s.exchange == 'events'
	assert s.routing_key == 'app.logs'
	assert s.encoding_codec == 'text'
	assert s.content_type == 'text/plain'
	assert s.delivery_mode == 1
	assert s.max_channels == 20
	assert s.tls_enabled == true
	assert s.batch_max_events == 50
}

fn test_amqp_sink_send_buffers() {
	mut s := new_amqp_sink({
		'exchange':         'test'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_amqp_sink_total_buffered() {
	mut s := new_amqp_sink({
		'exchange':         'test'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	s.send(ev) or {}
	assert s.total_buffered() == 2
}

fn test_amqp_sink_flush_empty() {
	mut s := new_amqp_sink({
		'exchange': 'test'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_amqp_sink_delivery_mode() {
	// Default: persistent (2)
	s1 := new_amqp_sink({
		'exchange': 'test'
	}) or { panic(err.str()) }
	assert s1.delivery_mode == 2

	// Transient (1)
	s2 := new_amqp_sink({
		'exchange':                 'test'
		'properties.delivery_mode': '1'
	}) or { panic(err.str()) }
	assert s2.delivery_mode == 1

	// Invalid delivery mode falls back to default
	s3 := new_amqp_sink({
		'exchange':                 'test'
		'properties.delivery_mode': '99'
	}) or { panic(err.str()) }
	assert s3.delivery_mode == 2
}

fn test_encode_amqp_payload_json() {
	ev := event.Event(event.new_log('test message'))
	result := encode_amqp_payload(ev, 'json')
	assert result.contains('test message')
	// JSON encoding should produce valid JSON with the message field
	assert result.contains('"message"')
}

fn test_encode_amqp_payload_text() {
	ev := event.Event(event.new_log('plain text message'))
	result := encode_amqp_payload(ev, 'text')
	assert result == 'plain text message'
}

fn test_amqp_sink_routing_key() {
	// No routing key
	s1 := new_amqp_sink({
		'exchange': 'test'
	}) or { panic(err.str()) }
	assert s1.routing_key == ''

	// With routing key
	s2 := new_amqp_sink({
		'exchange':    'test'
		'routing_key': 'app.logs.info'
	}) or { panic(err.str()) }
	assert s2.routing_key == 'app.logs.info'
}
