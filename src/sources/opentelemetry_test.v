module sources

fn test_parse_otlp_logs_basic() {
	body := '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"stringValue":"hello world"},"severityText":"INFO","attributes":[]}]}]}]}'
	logs := parse_otlp_logs(body)
	assert logs.len == 1
	assert logs[0].message == 'hello world'
	assert logs[0].severity == 'INFO'
}

fn test_parse_otlp_logs_multiple() {
	body := '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"stringValue":"first"},"severityText":"INFO","attributes":[]},{"body":{"stringValue":"second"},"severityText":"WARN","attributes":[]}]}]}]}'
	logs := parse_otlp_logs(body)
	assert logs.len == 2
	assert logs[0].message == 'first'
	assert logs[0].severity == 'INFO'
	assert logs[1].message == 'second'
	assert logs[1].severity == 'WARN'
}

fn test_parse_otlp_logs_with_attributes() {
	body := '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"stringValue":"with attrs"},"severityText":"DEBUG","attributes":[{"key":"service","value":{"stringValue":"web"}},{"key":"count","value":{"intValue":"42"}}]}]}]}]}'
	logs := parse_otlp_logs(body)
	assert logs.len == 1
	assert logs[0].message == 'with attrs'
	assert logs[0].attributes['service'] == 'web'
	assert logs[0].attributes['count'] == '42'
}

fn test_parse_otlp_logs_severity() {
	body := '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"stringValue":"err msg"},"severityText":"ERROR","attributes":[]}]}]}]}'
	logs := parse_otlp_logs(body)
	assert logs.len == 1
	assert logs[0].severity == 'ERROR'
}

fn test_parse_otlp_logs_empty() {
	// Empty string
	logs1 := parse_otlp_logs('')
	assert logs1.len == 0

	// Invalid JSON
	logs2 := parse_otlp_logs('not json')
	assert logs2.len == 0

	// Valid JSON but wrong structure
	logs3 := parse_otlp_logs('{"foo":"bar"}')
	assert logs3.len == 0
}

fn test_parse_otlp_logs_no_body() {
	body := '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"severityText":"INFO","attributes":[]}]}]}]}'
	logs := parse_otlp_logs(body)
	assert logs.len == 1
	// No body means empty message (all body fields are empty strings)
	assert logs[0].message == ''
	assert logs[0].severity == 'INFO'
}

fn test_new_opentelemetry_source_defaults() {
	s := new_opentelemetry_source(map[string]string{})
	assert s.address == '0.0.0.0:4318'
	assert s.path == '/v1/logs'
}

fn test_new_opentelemetry_source_custom() {
	s := new_opentelemetry_source({
		'address': '127.0.0.1:9000'
		'path':    '/custom/logs'
	})
	assert s.address == '127.0.0.1:9000'
	assert s.path == '/custom/logs'
}

fn test_opentelemetry_source_registry() {
	s := build_source('opentelemetry', map[string]string{}) or { panic(err.str()) }
	assert s is OpenTelemetrySource
}
