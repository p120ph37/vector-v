module sinks

import event

fn test_new_socket_sink_tcp_defaults() {
	s := new_socket_sink({
		'address': '127.0.0.1:9000'
	})!
	assert s.mode == .tcp
	assert s.address == '127.0.0.1:9000'
	assert s.codec == .json_codec
	assert s.connected == false
}

fn test_new_socket_sink_udp() {
	s := new_socket_sink({
		'address': '127.0.0.1:5514'
		'mode':    'udp'
	})!
	assert s.mode == .udp
}

fn test_new_socket_sink_missing_address() {
	new_socket_sink(map[string]string{}) or {
		assert err.msg().contains('address is required')
		return
	}
	assert false, 'expected error for missing address'
}

fn test_new_socket_sink_text_codec() {
	s := new_socket_sink({
		'address':        '127.0.0.1:9000'
		'encoding.codec': 'text'
	})!
	assert s.codec == .text_codec
}

fn test_socket_sink_not_connected() {
	s := new_socket_sink({
		'address': '127.0.0.1:9000'
	})!
	assert s.connected == false
}

fn test_new_socket_sink_default_tcp() {
	s := new_socket_sink({
		'address': '127.0.0.1:9000'
		'mode':    'tcp'
	})!
	assert s.mode == .tcp
}

fn test_socket_sink_encode_event_json() {
	s := new_socket_sink({
		'address': '127.0.0.1:9000'
	})!
	ev := event.Event(event.new_log('hello world'))
	result := s.encode_event(ev)
	assert result.contains('"message"')
	assert result.contains('hello world')
}

fn test_socket_sink_encode_event_text() {
	s := new_socket_sink({
		'address':        '127.0.0.1:9000'
		'encoding.codec': 'text'
	})!
	ev := event.Event(event.new_log('hello text'))
	result := s.encode_event(ev)
	assert result == 'hello text'
}

fn test_socket_sink_encode_metric() {
	s := new_socket_sink({
		'address': '127.0.0.1:9000'
	})!
	metric := event.Event(event.Metric{
		name: 'cpu.usage'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{ value: 42.0 })
	})
	result := s.encode_event(metric)
	assert result.len > 0
}

fn test_socket_sink_close() {
	mut s := new_socket_sink({
		'address': '127.0.0.1:9000'
	})!
	assert s.connected == false
	s.close()
	assert s.connected == false
}

fn test_socket_sink_send_not_connected() {
	mut s := new_socket_sink({
		'address': '127.0.0.1:19999'
	})!
	ev := event.Event(event.new_log('test'))
	s.send(ev) or {
		assert err.msg().contains('connection failed')
		return
	}
	// Connection to non-listening port should fail
}

fn test_socket_sink_udp_mode_encode() {
	s := new_socket_sink({
		'address':        '127.0.0.1:9000'
		'mode':           'udp'
		'encoding.codec': 'text'
	})!
	ev := event.Event(event.new_log('udp message'))
	result := s.encode_event(ev)
	assert result == 'udp message'
}

fn test_socket_sink_write_tcp_not_connected() {
	mut s := new_socket_sink({
		'address': '127.0.0.1:9000'
	})!
	s.write_tcp('test') or {
		assert err.msg().contains('not connected')
		return
	}
	assert false, 'expected error for write when not connected'
}
