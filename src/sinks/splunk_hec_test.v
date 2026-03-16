module sinks

import event

fn test_new_splunk_hec_defaults() {
	s := new_splunk_hec({
		'endpoint': 'https://splunk:8088'
		'token':    'my-token'
	}) or { panic(err.str()) }
	assert s.endpoint == 'https://splunk:8088'
	assert s.token == 'my-token'
	assert s.codec == .json_codec
	assert s.index == ''
	assert s.source == ''
	assert s.sourcetype == ''
	assert s.host_key == 'host'
	assert s.batch_max == 100
}

fn test_new_splunk_hec_missing_endpoint() {
	new_splunk_hec({
		'token': 'my-token'
	}) or {
		assert err.msg().contains('endpoint is required')
		return
	}
	assert false, 'expected error for missing endpoint'
}

fn test_new_splunk_hec_missing_token() {
	new_splunk_hec({
		'endpoint': 'https://splunk:8088'
	}) or {
		assert err.msg().contains('token is required')
		return
	}
	assert false, 'expected error for missing token'
}

fn test_new_splunk_hec_custom() {
	s := new_splunk_hec({
		'endpoint':          'https://splunk.example.com:8088/'
		'token':             'custom-token'
		'encoding.codec':    'text'
		'index':             'main'
		'source':            'vector'
		'sourcetype':        '_json'
		'host_key':          'hostname'
		'batch.max_events':  '50'
		'batch.timeout_secs': '10'
	}) or { panic(err.str()) }
	assert s.endpoint == 'https://splunk.example.com:8088'
	assert s.token == 'custom-token'
	assert s.codec == .text_codec
	assert s.index == 'main'
	assert s.source == 'vector'
	assert s.sourcetype == '_json'
	assert s.host_key == 'hostname'
	assert s.batch_max == 50
}

fn test_splunk_hec_send_buffers() {
	mut s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 3
}

fn test_splunk_hec_total_buffered() {
	mut s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	s.send(ev) or {}
	assert s.total_buffered() == 2
}

fn test_splunk_hec_flush_empty() {
	mut s := new_splunk_hec({
		'endpoint': 'https://splunk:8088'
		'token':    'tok'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_splunk_hec_drops_non_log() {
	mut s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	// Metric events should still be encoded (as JSON)
	metric := event.Event(event.Metric{
		name:  'test.counter'
		kind:  .incremental
		value: event.MetricValue(event.CounterValue{ value: 1.0 })
	})
	s.send(metric) or {}
	assert s.total_buffered() == 1

	// TraceEvent should also be encoded
	trace := event.Event(event.TraceEvent{})
	s.send(trace) or {}
	assert s.total_buffered() == 2
}

fn test_splunk_hec_registry() {
	sink := build_sink('splunk_hec', {
		'endpoint': 'https://splunk:8088'
		'token':    'tok'
	}) or { panic(err.str()) }
	match sink {
		SplunkHecSink {
			assert sink.endpoint == 'https://splunk:8088'
			assert sink.token == 'tok'
		}
		else {
			assert false, 'expected SplunkHecSink'
		}
	}
}
