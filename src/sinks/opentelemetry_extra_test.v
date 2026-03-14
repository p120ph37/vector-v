module sinks

import event

fn test_otlp_severity_from_severity_field() {
	mut s := new_opentelemetry({
		'endpoint':         'http://localhost:4318'
		'batch.max_events': '1000'
	})

	mut log := event.new_log('test message')
	log.set('severity', event.Value('ERROR'))
	ev := event.Event(log)
	s.send(ev) or {}
	assert s.buffer.len == 1
	assert s.buffer[0].severity_text == 'ERROR'
	assert s.buffer[0].body == 'test message'
}

fn test_otlp_severity_from_level_field() {
	mut s := new_opentelemetry({
		'endpoint':         'http://localhost:4318'
		'batch.max_events': '1000'
	})

	mut log := event.new_log('test message')
	log.set('level', event.Value('WARN'))
	ev := event.Event(log)
	s.send(ev) or {}
	assert s.buffer.len == 1
	assert s.buffer[0].severity_text == 'WARN'
}

fn test_otlp_severity_fallback_to_info() {
	mut s := new_opentelemetry({
		'endpoint':         'http://localhost:4318'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('plain message'))
	s.send(ev) or {}
	assert s.buffer.len == 1
	assert s.buffer[0].severity_text == 'INFO'
}

fn test_otlp_empty_resource_attributes() {
	s := new_opentelemetry({
		'endpoint': 'http://localhost:4318'
	})
	assert s.resource_attrs.len == 0

	mut sink := s
	sink.buffer << OtlpLogRecord{
		timestamp_ns: '1710000000000000000'
		severity_text: 'INFO'
		body: 'test'
		attributes: {}
	}
	payload := sink.build_otlp_payload()
	assert payload.contains('"attributes":[]')
}

fn test_otlp_batch_size_defaults_on_invalid() {
	s := new_opentelemetry({
		'endpoint':         'http://localhost:4318'
		'batch.max_events': '0'
	})
	assert s.batch_max == 100

	s2 := new_opentelemetry({
		'endpoint':         'http://localhost:4318'
		'batch.max_events': '-10'
	})
	assert s2.batch_max == 100
}

fn test_otlp_batch_timeout_defaults_on_invalid() {
	s := new_opentelemetry({
		'endpoint':            'http://localhost:4318'
		'batch.timeout_secs':  '-1'
	})
	assert s.batch_timeout > 0
}

fn test_otlp_payload_structure_validation() {
	s := new_opentelemetry({
		'endpoint':              'http://localhost:4318'
		'resource.service.name': 'test-svc'
		'resource.env':          'staging'
	})
	mut sink := s
	sink.buffer << OtlpLogRecord{
		timestamp_ns: '1710000000000000000'
		severity_text: 'WARN'
		body: 'something happened'
		attributes: {
			'host': 'node1'
			'pid':  '1234'
		}
	}
	payload := sink.build_otlp_payload()
	assert payload.starts_with('{"resourceLogs":[')
	assert payload.contains('"resource":')
	assert payload.contains('"scopeLogs":')
	assert payload.contains('"scope":{}')
	assert payload.contains('"logRecords":')
	assert payload.contains('"timeUnixNano":"1710000000000000000"')
	assert payload.contains('"severityText":"WARN"')
	assert payload.contains('"body":{"stringValue":"something happened"}')
	assert payload.contains('"service.name"')
	assert payload.contains('"env"')
}

fn test_otlp_attributes_exclude_message_severity_level() {
	mut s := new_opentelemetry({
		'endpoint':         'http://localhost:4318'
		'batch.max_events': '1000'
	})

	mut log := event.new_log('hello')
	log.set('severity', event.Value('DEBUG'))
	log.set('level', event.Value('debug'))
	log.set('host', event.Value('server1'))
	ev := event.Event(log)
	s.send(ev) or {}
	assert s.buffer.len == 1
	assert 'message' !in s.buffer[0].attributes
	assert 'severity' !in s.buffer[0].attributes
	assert 'level' !in s.buffer[0].attributes
	assert s.buffer[0].attributes['host'] == 'server1'
}

fn test_otlp_multiple_records_payload() {
	s := new_opentelemetry({
		'endpoint': 'http://localhost:4318'
	})
	mut sink := s
	sink.buffer << OtlpLogRecord{
		timestamp_ns: '1000000000000000000'
		severity_text: 'INFO'
		body: 'first'
		attributes: {}
	}
	sink.buffer << OtlpLogRecord{
		timestamp_ns: '2000000000000000000'
		severity_text: 'ERROR'
		body: 'second'
		attributes: {}
	}
	payload := sink.build_otlp_payload()
	assert payload.contains('"first"')
	assert payload.contains('"second"')
	assert payload.contains('"INFO"')
	assert payload.contains('"ERROR"')
}
