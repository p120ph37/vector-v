module sinks

import event

fn test_new_mqtt_sink_defaults() {
	s := new_mqtt_sink({
		'topic': 'output/events'
	}) or { panic(err.str()) }
	assert s.host == '127.0.0.1'
	assert s.port == 1883
	assert s.topic == 'output/events'
	assert s.qos == 0
	assert s.client_id == 'vector'
	assert s.username == ''
	assert s.password == ''
	assert s.clean_session == true
	assert s.keep_alive_secs == 60
	assert s.retain == false
	assert s.encoding_codec == 'json'
	assert s.tls_enabled == false
	assert s.batch_max_events == 100
	assert s.buffer.len == 0
}

fn test_new_mqtt_sink_missing_topic() {
	new_mqtt_sink(map[string]string{}) or {
		assert err.msg().contains('topic is required')
		return
	}
	assert false, 'expected error for missing topic'
}

fn test_new_mqtt_sink_custom() {
	s := new_mqtt_sink({
		'topic':            'devices/{{device_id}}/status'
		'host':             'mqtt.example.com'
		'port':             '1884'
		'qos':              '2'
		'client_id':        'vector-sink'
		'username':         'admin'
		'password':         'secret'
		'clean_session':    'false'
		'keep_alive_secs':  '120'
		'retain':           'true'
		'encoding.codec':   'text'
		'tls.enabled':      'true'
		'batch.max_events': '50'
	}) or { panic(err.str()) }
	assert s.host == 'mqtt.example.com'
	assert s.port == 1884
	assert s.topic == 'devices/{{device_id}}/status'
	assert s.qos == 2
	assert s.client_id == 'vector-sink'
	assert s.username == 'admin'
	assert s.password == 'secret'
	assert s.clean_session == false
	assert s.keep_alive_secs == 120
	assert s.retain == true
	assert s.encoding_codec == 'text'
	assert s.tls_enabled == true
	assert s.batch_max_events == 50
}

fn test_mqtt_sink_send_buffers() {
	mut s := new_mqtt_sink({
		'topic':            'test/events'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_mqtt_sink_total_buffered() {
	mut s := new_mqtt_sink({
		'topic':            'test/events'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	s.send(ev) or {}
	assert s.total_buffered() == 2
}

fn test_mqtt_sink_flush_empty() {
	mut s := new_mqtt_sink({
		'topic': 'test/events'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_mqtt_sink_retain_config() {
	// Default: retain is false
	s1 := new_mqtt_sink({
		'topic': 'test/events'
	}) or { panic(err.str()) }
	assert s1.retain == false

	// Explicit retain true
	s2 := new_mqtt_sink({
		'topic':  'test/events'
		'retain': 'true'
	}) or { panic(err.str()) }
	assert s2.retain == true

	// Explicit retain false
	s3 := new_mqtt_sink({
		'topic':  'test/events'
		'retain': 'false'
	}) or { panic(err.str()) }
	assert s3.retain == false
}

fn test_mqtt_sink_qos_config() {
	// Default QoS for sink is 0
	s0 := new_mqtt_sink({
		'topic': 'test'
	}) or { panic(err.str()) }
	assert s0.qos == 0

	// QoS 1
	s1 := new_mqtt_sink({
		'topic': 'test'
		'qos':   '1'
	}) or { panic(err.str()) }
	assert s1.qos == 1

	// QoS 2
	s2 := new_mqtt_sink({
		'topic': 'test'
		'qos':   '2'
	}) or { panic(err.str()) }
	assert s2.qos == 2

	// Invalid QoS falls back to 0
	s3 := new_mqtt_sink({
		'topic': 'test'
		'qos':   '5'
	}) or { panic(err.str()) }
	assert s3.qos == 0
}

fn test_encode_mqtt_payload_json() {
	ev := event.Event(event.new_log('hello world'))
	result := encode_mqtt_payload(ev, 'json')
	assert result.contains('hello world')
	// JSON output should have braces
	assert result.contains('{')
	assert result.contains('}')
}

fn test_encode_mqtt_payload_text() {
	ev := event.Event(event.new_log('hello world'))
	result := encode_mqtt_payload(ev, 'text')
	assert result == 'hello world'
}
