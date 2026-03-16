module sinks

import event
import time

fn test_splunk_hec_encode_log_json() {
	s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('test message'))
	encoded := s.encode_event(ev)
	assert encoded.contains('"event"')
	assert encoded.contains('"time"')
	// JSON codec: event body should be the full JSON
	assert encoded.contains('message')
}

fn test_splunk_hec_encode_log_text() {
	s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'encoding.codec':   'text'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('text message'))
	encoded := s.encode_event(ev)
	assert encoded.contains('"event"')
	assert encoded.contains('text message')
}

fn test_splunk_hec_encode_with_metadata() {
	s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'index':            'main'
		'source':           'vector'
		'sourcetype':       '_json'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('test'))
	encoded := s.encode_event(ev)
	assert encoded.contains('"index":"main"')
	assert encoded.contains('"source":"vector"')
	assert encoded.contains('"sourcetype":"_json"')
}

fn test_splunk_hec_extract_host_from_log() {
	s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	mut log := event.new_log('test')
	log.set('host', 'web-server-1')
	ev := event.Event(log)
	encoded := s.encode_event(ev)
	assert encoded.contains('"host":"web-server-1"')
}

fn test_splunk_hec_extract_host_custom_key() {
	s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'host_key':         'hostname'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	mut log := event.new_log('test')
	log.set('hostname', 'custom-host')
	ev := event.Event(log)
	encoded := s.encode_event(ev)
	assert encoded.contains('"host":"custom-host"')
}

fn test_splunk_hec_no_host_field() {
	s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('test'))
	encoded := s.encode_event(ev)
	// Should not contain host key when field is missing
	assert !encoded.contains('"host"')
}

fn test_splunk_hec_encode_metric() {
	s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.GaugeValue{value: 50.0}
	}
	encoded := s.encode_event(event.Event(m))
	assert encoded.len > 0
	assert encoded.contains('"event"')
}

fn test_splunk_hec_encode_trace() {
	s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	trace := event.TraceEvent{
		fields: {'key': 'value'}
	}
	encoded := s.encode_event(event.Event(trace))
	assert encoded.len > 0
	assert encoded.contains('"event"')
}

fn test_splunk_hec_registry_logs_alias() {
	sink := build_sink('splunk_hec_logs', {
		'endpoint': 'https://splunk:8088'
		'token':    'tok'
	}) or { panic(err.str()) }
	assert sink is SplunkHecSink
}

fn test_splunk_hec_extract_host_metric() {
	s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'test'
		kind: .absolute
		value: event.GaugeValue{value: 1.0}
	}
	host := s.extract_host(event.Event(m))
	assert host == ''
}

fn test_splunk_hec_timestamp_format() {
	s := new_splunk_hec({
		'endpoint':         'https://splunk:8088'
		'token':            'tok'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('test'))
	encoded := s.encode_event(ev)
	// Should contain a time field with a decimal
	assert encoded.contains('"time":')
}

fn test_splunk_hec_batch_config_defaults() {
	s := new_splunk_hec({
		'endpoint':           'https://splunk:8088'
		'token':              'tok'
		'batch.max_events':   '0'
		'batch.timeout_secs': '0'
	}) or { panic(err.str()) }
	assert s.batch_max == 100
}

fn test_splunk_hec_endpoint_trailing_slash() {
	s := new_splunk_hec({
		'endpoint': 'https://splunk:8088/'
		'token':    'tok'
	}) or { panic(err.str()) }
	assert s.endpoint == 'https://splunk:8088'
}
