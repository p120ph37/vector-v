module sources

fn test_parse_datadog_logs_basic() {
	entries := parse_datadog_logs('[{"message":"hello world"}]')
	assert entries.len == 1
	assert entries[0].message == 'hello world'
}

fn test_parse_datadog_logs_multiple() {
	body := '[{"message":"first"},{"message":"second"},{"message":"third"}]'
	entries := parse_datadog_logs(body)
	assert entries.len == 3
	assert entries[0].message == 'first'
	assert entries[1].message == 'second'
	assert entries[2].message == 'third'
}

fn test_parse_datadog_logs_with_fields() {
	body := '[{"message":"app log","hostname":"web-01","service":"nginx","ddsource":"nginx","ddtags":"env:prod,region:us-east","status":"info"}]'
	entries := parse_datadog_logs(body)
	assert entries.len == 1
	e := entries[0]
	assert e.message == 'app log'
	assert e.hostname == 'web-01'
	assert e.service == 'nginx'
	assert e.ddsource == 'nginx'
	assert e.ddtags == 'env:prod,region:us-east'
	assert e.status == 'info'
}

fn test_parse_datadog_logs_empty() {
	entries := parse_datadog_logs('')
	assert entries.len == 0
}

fn test_parse_datadog_logs_whitespace_only() {
	entries := parse_datadog_logs('   ')
	assert entries.len == 0
}

fn test_parse_datadog_logs_single_object() {
	entries := parse_datadog_logs('{"message":"solo entry","hostname":"h1"}')
	assert entries.len == 1
	assert entries[0].message == 'solo entry'
	assert entries[0].hostname == 'h1'
}

fn test_parse_datadog_logs_plain_text() {
	entries := parse_datadog_logs('just a plain log line')
	assert entries.len == 1
	assert entries[0].message == 'just a plain log line'
}

fn test_parse_datadog_logs_invalid_json_array() {
	entries := parse_datadog_logs('[invalid json')
	assert entries.len == 0
}

fn test_parse_datadog_tags() {
	// ddtags are parsed in handle_datadog_conn, but we verify the format
	// is preserved in DatadogLogEntry by parse_datadog_logs.
	body := '[{"message":"test","ddtags":"env:production,version:1.2.3,team:backend"}]'
	entries := parse_datadog_logs(body)
	assert entries.len == 1
	assert entries[0].ddtags == 'env:production,version:1.2.3,team:backend'

	// Verify the tag string can be split as expected by the sink logic
	tags := entries[0].ddtags.split(',')
	assert tags.len == 3
	assert tags[0] == 'env:production'
	assert tags[1] == 'version:1.2.3'
	assert tags[2] == 'team:backend'
}

fn test_parse_content_length_present() {
	headers := 'POST /api/v2/logs HTTP/1.1\r\nHost: localhost\r\nContent-Length: 42\r\nContent-Type: application/json'
	assert parse_content_length(headers) == 42
}

fn test_parse_content_length_missing() {
	headers := 'POST /api/v2/logs HTTP/1.1\r\nHost: localhost'
	assert parse_content_length(headers) == 0
}

fn test_parse_content_length_case_insensitive() {
	headers := 'POST / HTTP/1.1\r\ncontent-length: 100'
	assert parse_content_length(headers) == 100
}

fn test_parse_header_value_found() {
	headers := 'POST /api/v2/logs HTTP/1.1\r\nDD-API-KEY: abc123\r\nContent-Type: application/json'
	assert parse_header_value(headers, 'dd-api-key') == 'abc123'
}

fn test_parse_header_value_not_found() {
	headers := 'POST /api/v2/logs HTTP/1.1\r\nContent-Type: application/json'
	assert parse_header_value(headers, 'dd-api-key') == ''
}

fn test_parse_header_value_case_insensitive() {
	headers := 'POST / HTTP/1.1\r\nDd-Api-Key: mykey'
	assert parse_header_value(headers, 'dd-api-key') == 'mykey'
}

fn test_new_datadog_agent_defaults() {
	s := new_datadog_agent(map[string]string{})
	assert s.address == '0.0.0.0:8282'
	assert s.store_api_key == false
}

fn test_new_datadog_agent_custom() {
	s := new_datadog_agent({
		'address':       '127.0.0.1:9090'
		'store_api_key': 'true'
	})
	assert s.address == '127.0.0.1:9090'
	assert s.store_api_key == true
}

fn test_new_datadog_agent_store_api_key_variants() {
	for val in ['true', '1', 'yes'] {
		s := new_datadog_agent({
			'store_api_key': val
		})
		assert s.store_api_key == true
	}
	for val in ['false', '0', 'no', 'anything'] {
		s := new_datadog_agent({
			'store_api_key': val
		})
		assert s.store_api_key == false
	}
}

fn test_datadog_agent_registry() {
	s := build_source('datadog_agent', map[string]string{}) or { panic(err.str()) }
	assert s is DatadogAgentSource
}

fn test_datadog_agent_registry_custom_address() {
	s := build_source('datadog_agent', {
		'address': '0.0.0.0:9999'
	}) or { panic(err.str()) }
	if s is DatadogAgentSource {
		assert s.address == '0.0.0.0:9999'
	} else {
		assert false, 'expected DatadogAgentSource'
	}
}
