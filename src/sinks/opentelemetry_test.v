module sinks

import event

fn test_new_opentelemetry_defaults() {
	s := new_opentelemetry({
		'endpoint': 'http://localhost:4318'
	})
	assert s.http.endpoint == 'http://localhost:4318'
	assert s.http.path == '/v1/logs'
	assert s.batch_max == 100
}

fn test_new_opentelemetry_with_resource() {
	s := new_opentelemetry({
		'endpoint':             'http://localhost:4318'
		'resource.service.name': 'my-service'
		'resource.env':          'prod'
	})
	assert s.resource_attrs['service.name'] == 'my-service'
	assert s.resource_attrs['env'] == 'prod'
}

fn test_otlp_payload_format() {
	s := new_opentelemetry({
		'endpoint':              'http://localhost:4318'
		'resource.service.name': 'test-svc'
	})
	// Manually add a record to check payload format
	mut sink := s
	sink.buffer << OtlpLogRecord{
		timestamp_ns: '1710000000000000000'
		severity_text: 'INFO'
		body: 'test message'
		attributes: {
			'host': 'server1'
		}
	}
	payload := sink.build_otlp_payload()
	assert payload.contains('"resourceLogs"')
	assert payload.contains('"scopeLogs"')
	assert payload.contains('"logRecords"')
	assert payload.contains('"test message"')
	assert payload.contains('"INFO"')
	assert payload.contains('"service.name"')
}

fn test_opentelemetry_buffering() {
	mut s := new_opentelemetry({
		'endpoint':         'http://localhost:4318'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('hello world'))
	s.send(ev) or {}
	assert s.buffer.len == 1
	assert s.buffer[0].body == 'hello world'
}
