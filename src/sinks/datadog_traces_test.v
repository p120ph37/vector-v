module sinks

import event

fn test_new_datadog_traces_defaults() {
	s := new_datadog_traces({
		'api_key': 'my-api-key'
	}) or { panic(err.str()) }
	assert s.api_key == 'my-api-key'
	assert s.endpoint == 'https://trace.agent.datadoghq.com'
	assert s.batch_max == 100
}

fn test_new_datadog_traces_missing_api_key() {
	new_datadog_traces(map[string]string{}) or {
		assert err.msg().contains('api_key is required')
		return
	}
	assert false, 'expected error for missing api_key'
}

fn test_new_datadog_traces_default_api_key() {
	s := new_datadog_traces({
		'default_api_key': 'fallback-key'
	}) or { panic(err.str()) }
	assert s.api_key == 'fallback-key'
}

fn test_new_datadog_traces_custom() {
	s := new_datadog_traces({
		'api_key':            'custom-key'
		'site':               'datadoghq.eu'
		'endpoint':           'https://custom.trace.example.com/'
		'batch.max_events':   '200'
		'batch.timeout_secs': '10'
	}) or { panic(err.str()) }
	assert s.api_key == 'custom-key'
	assert s.endpoint == 'https://custom.trace.example.com'
	assert s.batch_max == 200
}

fn test_datadog_traces_batch_invalid() {
	s := new_datadog_traces({
		'api_key':            'k'
		'batch.max_events':   '-1'
		'batch.timeout_secs': '-5'
	}) or { panic(err.str()) }
	assert s.batch_max == 100
}

fn test_datadog_traces_send_buffers_trace() {
	mut s := new_datadog_traces({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	ev := event.Event(event.TraceEvent{
		fields: {
			'name':    'web.request'
			'service': 'api'
		}
	})
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1
}

fn test_datadog_traces_send_buffers_log() {
	mut s := new_datadog_traces({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('test message'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1
}

fn test_datadog_traces_send_buffers_metric() {
	mut s := new_datadog_traces({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'test'
		kind: .absolute
		value: event.GaugeValue{value: 1.0}
	}
	s.send(event.Event(m)) or { panic(err.str()) }
	assert s.total_buffered() == 1
}

fn test_datadog_traces_total_buffered() {
	mut s := new_datadog_traces({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	ev := event.Event(event.TraceEvent{})
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 2
}

fn test_datadog_traces_flush_empty() {
	mut s := new_datadog_traces({
		'api_key': 'key'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_datadog_traces_encode_trace() {
	s := new_datadog_traces({
		'api_key': 'key'
	}) or { panic(err.str()) }

	ev := event.Event(event.TraceEvent{
		fields: {
			'name':     'web.request'
			'service':  'api'
			'resource': '/users'
			'type':     'web'
		}
	})
	encoded := s.encode_event(ev)
	assert encoded.contains('"name":"web.request"')
	assert encoded.contains('"service":"api"')
	assert encoded.contains('"resource":"/users"')
	assert encoded.contains('"type":"web"')
	assert encoded.contains('"meta"')
}

fn test_datadog_traces_encode_trace_minimal() {
	s := new_datadog_traces({
		'api_key': 'key'
	}) or { panic(err.str()) }

	ev := event.Event(event.TraceEvent{})
	encoded := s.encode_event(ev)
	assert encoded.contains('"name":"span"')
	assert encoded.contains('"meta"')
}

fn test_datadog_traces_encode_log_event() {
	s := new_datadog_traces({
		'api_key': 'key'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('hello world'))
	encoded := s.encode_event(ev)
	assert encoded.contains('"name":"log"')
	assert encoded.contains('"resource"')
	assert encoded.contains('hello world')
	assert encoded.contains('"type":"custom"')
}

fn test_datadog_traces_encode_metric_event() {
	s := new_datadog_traces({
		'api_key': 'key'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.GaugeValue{value: 50.0}
	}
	encoded := s.encode_event(event.Event(m))
	assert encoded.len > 0
	assert encoded.contains('cpu')
}

fn test_datadog_traces_registry() {
	sink := build_sink('datadog_traces', {
		'api_key': 'test-key'
	}) or { panic(err.str()) }
	match sink {
		DatadogTracesSink {
			assert sink.api_key == 'test-key'
			assert sink.endpoint == 'https://trace.agent.datadoghq.com'
		}
		else {
			assert false, 'expected DatadogTracesSink'
		}
	}
}

fn test_datadog_traces_site_custom() {
	s := new_datadog_traces({
		'api_key': 'key'
		'site':    'us3.datadoghq.com'
	}) or { panic(err.str()) }
	assert s.endpoint == 'https://trace.agent.us3.datadoghq.com'
}

fn test_datadog_traces_endpoint_overrides_site() {
	s := new_datadog_traces({
		'api_key':  'key'
		'site':     'datadoghq.eu'
		'endpoint': 'https://custom.endpoint.com'
	}) or { panic(err.str()) }
	assert s.endpoint == 'https://custom.endpoint.com'
}

fn test_datadog_traces_encode_trace_with_resource() {
	s := new_datadog_traces({
		'api_key': 'key'
	}) or { panic(err.str()) }

	ev := event.Event(event.TraceEvent{
		fields: {
			'resource': 'GET /api/users'
		}
	})
	encoded := s.encode_event(ev)
	assert encoded.contains('"resource":"GET /api/users"')
}

fn test_datadog_traces_encode_trace_with_service() {
	s := new_datadog_traces({
		'api_key': 'key'
	}) or { panic(err.str()) }

	ev := event.Event(event.TraceEvent{
		fields: {
			'service': 'my-service'
		}
	})
	encoded := s.encode_event(ev)
	assert encoded.contains('"service":"my-service"')
}
