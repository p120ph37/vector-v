module sinks

import event

fn test_datadog_default_api_key_fallback() {
	s := new_datadog({
		'default_api_key': 'fallback-key'
	}) or { panic(err.str()) }
	assert s.api_key == 'fallback-key'
}

fn test_datadog_site_custom() {
	s := new_datadog({
		'api_key': 'key'
		'site':    'datadoghq.eu'
	}) or { panic(err.str()) }
	assert s.endpoint == 'https://http-intake.logs.datadoghq.eu'
}

fn test_datadog_endpoint_overrides_site() {
	s := new_datadog({
		'api_key':  'key'
		'site':     'datadoghq.eu'
		'endpoint': 'https://custom.endpoint.com'
	}) or { panic(err.str()) }
	assert s.endpoint == 'https://custom.endpoint.com'
}

fn test_datadog_batch_invalid() {
	s := new_datadog({
		'api_key':            'key'
		'batch.max_events':   '-1'
		'batch.timeout_secs': '-5'
	}) or { panic(err.str()) }
	assert s.batch_max == 100
}

fn test_datadog_encode_log_with_hostname() {
	s := new_datadog({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	mut log := event.new_log('test')
	log.set('hostname', 'web1')
	encoded := s.encode_event(event.Event(log))
	assert encoded.contains('"hostname":"web1"')
}

fn test_datadog_encode_log_with_host() {
	s := new_datadog({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	mut log := event.new_log('test')
	log.set('host', 'web2')
	encoded := s.encode_event(event.Event(log))
	assert encoded.contains('"hostname":"web2"')
}

fn test_datadog_encode_log_with_service() {
	s := new_datadog({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	mut log := event.new_log('test')
	log.set('service', 'api-server')
	encoded := s.encode_event(event.Event(log))
	assert encoded.contains('"service":"api-server"')
}

fn test_datadog_encode_log_with_ddtags() {
	s := new_datadog({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	mut log := event.new_log('test')
	log.set('ddtags', 'env:prod,version:1.0')
	encoded := s.encode_event(event.Event(log))
	assert encoded.contains('"ddtags"')
	assert encoded.contains('env:prod')
}

fn test_datadog_encode_metric() {
	s := new_datadog({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'test_metric'
		kind: .absolute
		value: event.GaugeValue{value: 42.0}
	}
	encoded := s.encode_event(event.Event(m))
	assert encoded.len > 0
	assert encoded.contains('test_metric')
}

fn test_datadog_encode_trace() {
	s := new_datadog({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	trace := event.TraceEvent{
		fields: {'key': 'value'}
	}
	encoded := s.encode_event(event.Event(trace))
	assert encoded.len > 0
}

fn test_datadog_ddsource_field() {
	s := new_datadog({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('test'))
	encoded := s.encode_event(ev)
	assert encoded.contains('"ddsource":"vector"')
}

fn test_datadog_registry_logs_alias() {
	sink := build_sink('datadog_logs', {
		'api_key': 'test-key'
	}) or { panic(err.str()) }
	assert sink is DatadogSink
}

fn test_datadog_json_codec_message() {
	s := new_datadog({
		'api_key':          'key'
		'encoding.codec':   'json'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	encoded := s.encode_event(event.Event(event.new_log('json message')))
	assert encoded.contains('"message"')
	assert encoded.contains('"ddsource"')
}
