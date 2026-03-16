module sinks

import event
import os
import time

fn setup_azure_env() {
	os.setenv('AZURE_STORAGE_ACCOUNT', 'teststorage', true)
	os.setenv('AZURE_STORAGE_KEY', 'dGVzdGtleQ==', true) // base64("testkey")
}

fn cleanup_azure_env() {
	os.unsetenv('AZURE_STORAGE_ACCOUNT')
	os.unsetenv('AZURE_STORAGE_KEY')
}

fn test_new_azure_blob_defaults() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	s := new_azure_blob({
		'container_name': 'my-container'
	})!
	assert s.storage_account == 'teststorage'
	assert s.container_name == 'my-container'
	assert s.endpoint == 'https://teststorage.blob.core.windows.net'
	assert s.blob_prefix == 'date=%Y-%m-%d/'
	assert s.codec == .ndjson_codec
	assert s.content_type == 'application/x-ndjson'
	assert s.batch_max == 1000
	assert s.buffer.len == 0
}

fn test_new_azure_blob_missing_container() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	new_azure_blob(map[string]string{}) or {
		assert err.msg().contains('container_name is required')
		return
	}
	assert false, 'expected error for missing container_name'
}

fn test_new_azure_blob_empty_container() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	new_azure_blob({
		'container_name': ''
	}) or {
		assert err.msg().contains('container_name is required')
		return
	}
	assert false, 'expected error for empty container_name'
}

fn test_new_azure_blob_missing_storage_account() {
	os.unsetenv('AZURE_STORAGE_ACCOUNT')
	os.unsetenv('AZURE_STORAGE_KEY')

	new_azure_blob({
		'container_name': 'my-container'
	}) or {
		assert err.msg().contains('storage_account is required')
		return
	}
	assert false, 'expected error for missing storage_account'
}

fn test_new_azure_blob_explicit_account() {
	os.unsetenv('AZURE_STORAGE_ACCOUNT')
	os.unsetenv('AZURE_STORAGE_KEY')

	s := new_azure_blob({
		'container_name':          'c1'
		'storage_account':         'myaccount'
		'auth.storage_access_key': 'dGVzdA=='
	})!
	assert s.storage_account == 'myaccount'
	assert s.access_key == 'dGVzdA=='
}

fn test_new_azure_blob_custom_config() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	s := new_azure_blob({
		'container_name':   'logs'
		'storage_account':  'customaccount'
		'blob_prefix':      'app/%Y/%m/'
		'encoding.codec':   'json'
		'batch.max_events': '500'
		'content_type':     'application/json'
		'endpoint':         'http://localhost:10000/devstoreaccount1'
	})!
	assert s.container_name == 'logs'
	assert s.storage_account == 'customaccount'
	assert s.blob_prefix == 'app/%Y/%m/'
	assert s.codec == .json_codec
	assert s.batch_max == 500
	assert s.content_type == 'application/json'
	assert s.endpoint == 'http://localhost:10000/devstoreaccount1'
}

fn test_new_azure_blob_text_codec() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	s := new_azure_blob({
		'container_name': 'c1'
		'encoding.codec':  'text'
	})!
	assert s.codec == .text_codec
	assert s.content_type == 'text/plain'
}

fn test_new_azure_blob_connection_string() {
	os.unsetenv('AZURE_STORAGE_ACCOUNT')
	os.unsetenv('AZURE_STORAGE_KEY')

	s := new_azure_blob({
		'container_name':    'c1'
		'connection_string': 'DefaultEndpointsProtocol=https;AccountName=connaccount;AccountKey=Y29ubmtleQ==;EndpointSuffix=core.windows.net'
	})!
	assert s.storage_account == 'connaccount'
	assert s.access_key == 'Y29ubmtleQ=='
	assert s.connection_string.len > 0
}

fn test_new_azure_blob_connection_string_explicit_override() {
	os.unsetenv('AZURE_STORAGE_ACCOUNT')
	os.unsetenv('AZURE_STORAGE_KEY')

	s := new_azure_blob({
		'container_name':          'c1'
		'storage_account':         'explicit'
		'auth.storage_access_key': 'ZXhwbGljaXQ='
		'connection_string':       'AccountName=fromconn;AccountKey=Y29ubg=='
	})!
	// Explicit config takes priority over connection string
	assert s.storage_account == 'explicit'
	assert s.access_key == 'ZXhwbGljaXQ='
}

fn test_azure_blob_buffering() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	mut s := new_azure_blob({
		'container_name':   'c1'
		'batch.max_events': '10000'
	})!

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_azure_blob_total_buffered() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	mut s := new_azure_blob({
		'container_name':   'c1'
		'batch.max_events': '10000'
	})!

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
}

fn test_azure_blob_build_payload_ndjson() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	mut s := new_azure_blob({
		'container_name':   'c1'
		'batch.max_events': '10000'
	})!

	ev1 := event.Event(event.new_log('line1'))
	ev2 := event.Event(event.new_log('line2'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	payload := s.build_payload()
	lines := payload.trim_right('\n').split('\n')
	assert lines.len == 2
	assert lines[0].contains('line1')
	assert lines[1].contains('line2')
}

fn test_azure_blob_build_payload_json() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	mut s := new_azure_blob({
		'container_name':   'c1'
		'encoding.codec':   'json'
		'batch.max_events': '10000'
	})!

	ev := event.Event(event.new_log('json test'))
	s.send(ev) or {}

	payload := s.build_payload()
	assert payload.starts_with('[')
	assert payload.ends_with(']')
}

fn test_azure_blob_build_payload_text() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	mut s := new_azure_blob({
		'container_name':   'c1'
		'encoding.codec':   'text'
		'batch.max_events': '10000'
	})!

	ev1 := event.Event(event.new_log('hello'))
	ev2 := event.Event(event.new_log('world'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	payload := s.build_payload()
	assert payload == 'hello\nworld'
}

fn test_azure_blob_generate_name() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	mut s := new_azure_blob({
		'container_name': 'c1'
		'blob_prefix':    'logs/'
	})!

	name := s.generate_blob_name()
	assert name.starts_with('logs/')
	assert name.ends_with('.log')
	assert s.seq == 1

	name2 := s.generate_blob_name()
	assert name2 != name
	assert s.seq == 2
}

fn test_azure_blob_flush_empty() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	mut s := new_azure_blob({
		'container_name': 'c1'
	})!
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_azure_blob_encode_metric() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	s := new_azure_blob({
		'container_name': 'c1'
	})!
	metric := event.Event(event.Metric{
		name: 'test.counter'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	result := s.encode_event(metric)
	assert result.contains('test.counter')
}

fn test_azure_blob_encode_trace() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	s := new_azure_blob({
		'container_name': 'c1'
	})!
	trace := event.Event(event.TraceEvent{})
	result := s.encode_event(trace)
	assert result.len > 0
}

fn test_azure_blob_encode_text() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	s := new_azure_blob({
		'container_name': 'c1'
		'encoding.codec':  'text'
	})!
	ev := event.Event(event.new_log('plain text'))
	result := s.encode_event(ev)
	assert result == 'plain text'
}

fn test_azure_blob_invalid_batch_max() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	s := new_azure_blob({
		'container_name':   'c1'
		'batch.max_events': '-1'
	})!
	assert s.batch_max == 1000
}

fn test_azure_blob_invalid_batch_timeout() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	s := new_azure_blob({
		'container_name':      'c1'
		'batch.timeout_secs': '-10'
	})!
	assert s.batch_timeout > 0
}

fn test_azure_blob_json_content_type() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	s := new_azure_blob({
		'container_name': 'c1'
		'encoding.codec':  'json'
	})!
	assert s.content_type == 'application/json'
}

fn test_azure_blob_drops_non_log_for_text() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	mut s := new_azure_blob({
		'container_name':   'c1'
		'batch.max_events': '10000'
	})!

	// Metrics are encoded (unlike log-only sinks like pubsub)
	metric := event.Event(event.Metric{
		name: 'test.gauge'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 42.0})
	})
	s.send(metric) or {}
	assert s.total_buffered() == 1 // S3-like sinks encode all event types
}

fn test_build_azure_string_to_sign() {
	result := build_azure_string_to_sign('PUT', 'application/x-ndjson', '1234',
		'Mon, 01 Jan 2024 00:00:00 GMT', '/mycontainer/blob.log', 'myaccount')
	assert result.contains('PUT')
	assert result.contains('application/x-ndjson')
	assert result.contains('1234')
	assert result.contains('x-ms-blob-type:BlockBlob')
	assert result.contains('x-ms-date:Mon, 01 Jan 2024 00:00:00 GMT')
	assert result.contains('x-ms-version:2021-12-02')
	assert result.contains('/myaccount/mycontainer/blob.log')
}

fn test_azure_sign() {
	// Verify azure_sign returns a non-empty base64 signature
	sig := azure_sign('dGVzdGtleQ==', 'test string to sign')
	assert sig.len > 0
	// Base64 output should only contain valid characters
	for c in sig.bytes() {
		assert c == `+` || c == `/` || c == `=` || (c >= `A` && c <= `Z`) || (c >= `a`
			&& c <= `z`) || (c >= `0` && c <= `9`)
	}
}

fn test_azure_rfc1123_date() {
	// Create a known UTC time
	t := time.Time{
		year: 2024
		month: 3
		day: 15
		hour: 10
		minute: 30
		second: 45
	}
	result := azure_rfc1123_date(t)
	assert result.contains('2024')
	assert result.contains('Mar')
	assert result.contains('10:30:45 GMT')
}

fn test_parse_connection_string() {
	cs := 'DefaultEndpointsProtocol=https;AccountName=myaccount;AccountKey=mykey;EndpointSuffix=core.windows.net'
	parsed := parse_connection_string(cs)
	assert parsed['DefaultEndpointsProtocol'] == 'https'
	assert parsed['AccountName'] == 'myaccount'
	assert parsed['AccountKey'] == 'mykey'
	assert parsed['EndpointSuffix'] == 'core.windows.net'
}

fn test_parse_connection_string_empty() {
	parsed := parse_connection_string('')
	assert parsed.len == 0
}

fn test_parse_connection_string_with_equals_in_value() {
	// AccountKey values are base64 and may contain '='
	cs := 'AccountName=test;AccountKey=abc123=='
	parsed := parse_connection_string(cs)
	assert parsed['AccountName'] == 'test'
	assert parsed['AccountKey'] == 'abc123=='
}

fn test_azure_blob_env_fallback() {
	os.setenv('AZURE_STORAGE_ACCOUNT', 'envaccount', true)
	os.setenv('AZURE_STORAGE_KEY', 'ZW52a2V5', true)
	defer {
		os.unsetenv('AZURE_STORAGE_ACCOUNT')
		os.unsetenv('AZURE_STORAGE_KEY')
	}

	s := new_azure_blob({
		'container_name': 'c1'
	})!
	assert s.storage_account == 'envaccount'
	assert s.access_key == 'ZW52a2V5'
}

fn test_azure_blob_custom_endpoint() {
	setup_azure_env()
	defer { cleanup_azure_env() }

	s := new_azure_blob({
		'container_name': 'c1'
		'endpoint':       'http://127.0.0.1:10000/devstoreaccount1'
	})!
	assert s.endpoint == 'http://127.0.0.1:10000/devstoreaccount1'
}
