module sinks

import event
import os

fn test_new_azure_monitor_logs_defaults() {
	s := new_azure_monitor_logs({
		'customer_id':    'workspace-123'
		'log_type':       'MyApp'
		'auth.shared_key': 'dGVzdGtleQ=='
	})!
	assert s.customer_id == 'workspace-123'
	assert s.log_type == 'MyApp'
	assert s.shared_key == 'dGVzdGtleQ=='
	assert s.endpoint == 'https://workspace-123.ods.opinsights.azure.com'
	assert s.codec == .json_codec
	assert s.batch_max == 100
	assert s.azure_resource_id == ''
	assert s.time_generated_key == ''
	assert s.buffer.len == 0
}

fn test_new_azure_monitor_logs_missing_customer_id() {
	new_azure_monitor_logs({
		'log_type': 'MyApp'
	}) or {
		assert err.msg().contains('customer_id is required')
		return
	}
	assert false, 'expected error for missing customer_id'
}

fn test_new_azure_monitor_logs_empty_customer_id() {
	new_azure_monitor_logs({
		'customer_id': ''
		'log_type':    'MyApp'
	}) or {
		assert err.msg().contains('customer_id is required')
		return
	}
	assert false, 'expected error for empty customer_id'
}

fn test_new_azure_monitor_logs_missing_log_type() {
	new_azure_monitor_logs({
		'customer_id': 'ws-1'
	}) or {
		assert err.msg().contains('log_type is required')
		return
	}
	assert false, 'expected error for missing log_type'
}

fn test_new_azure_monitor_logs_empty_log_type() {
	new_azure_monitor_logs({
		'customer_id': 'ws-1'
		'log_type':    ''
	}) or {
		assert err.msg().contains('log_type is required')
		return
	}
	assert false, 'expected error for empty log_type'
}

fn test_new_azure_monitor_logs_custom_config() {
	s := new_azure_monitor_logs({
		'customer_id':        'ws-custom'
		'log_type':           'CustomLog'
		'auth.shared_key':    'c2hhcmVk'
		'endpoint':           'http://localhost:8080'
		'azure_resource_id':  '/subscriptions/sub-1/resourceGroups/rg-1'
		'time_generated_key': 'event_time'
		'encoding.codec':     'text'
		'batch.max_events':   '50'
	})!
	assert s.customer_id == 'ws-custom'
	assert s.log_type == 'CustomLog'
	assert s.endpoint == 'http://localhost:8080'
	assert s.azure_resource_id == '/subscriptions/sub-1/resourceGroups/rg-1'
	assert s.time_generated_key == 'event_time'
	assert s.codec == .text_codec
	assert s.batch_max == 50
}

fn test_new_azure_monitor_logs_text_codec() {
	s := new_azure_monitor_logs({
		'customer_id':    'ws-1'
		'log_type':       'Test'
		'encoding.codec': 'text'
	})!
	assert s.codec == .text_codec
}

fn test_new_azure_monitor_logs_env_shared_key() {
	os.setenv('AZURE_MONITOR_SHARED_KEY', 'ZW52a2V5', true)
	defer { os.unsetenv('AZURE_MONITOR_SHARED_KEY') }

	s := new_azure_monitor_logs({
		'customer_id': 'ws-1'
		'log_type':    'Test'
	})!
	assert s.shared_key == 'ZW52a2V5'
}

fn test_new_azure_monitor_logs_explicit_key_overrides_env() {
	os.setenv('AZURE_MONITOR_SHARED_KEY', 'ZW52a2V5', true)
	defer { os.unsetenv('AZURE_MONITOR_SHARED_KEY') }

	s := new_azure_monitor_logs({
		'customer_id':    'ws-1'
		'log_type':       'Test'
		'auth.shared_key': 'ZXhwbGljaXQ='
	})!
	assert s.shared_key == 'ZXhwbGljaXQ='
}

fn test_azure_monitor_logs_buffering() {
	mut s := new_azure_monitor_logs({
		'customer_id':      'ws-1'
		'log_type':         'Test'
		'batch.max_events': '1000'
	})!

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_azure_monitor_logs_total_buffered() {
	mut s := new_azure_monitor_logs({
		'customer_id':      'ws-1'
		'log_type':         'Test'
		'batch.max_events': '1000'
	})!

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
}

fn test_azure_monitor_logs_flush_empty() {
	mut s := new_azure_monitor_logs({
		'customer_id': 'ws-1'
		'log_type':    'Test'
	})!

	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_azure_monitor_logs_build_payload() {
	mut s := new_azure_monitor_logs({
		'customer_id':      'ws-1'
		'log_type':         'Test'
		'batch.max_events': '1000'
	})!

	ev1 := event.Event(event.new_log('hello'))
	ev2 := event.Event(event.new_log('world'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	payload := s.build_payload()
	assert payload.starts_with('[')
	assert payload.ends_with(']')
	assert payload.contains('hello')
	assert payload.contains('world')
}

fn test_azure_monitor_logs_text_codec_wraps_message() {
	mut s := new_azure_monitor_logs({
		'customer_id':      'ws-1'
		'log_type':         'Test'
		'encoding.codec':   'text'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('plain text msg'))
	s.send(ev) or {}

	assert s.buffer.len == 1
	assert s.buffer[0].contains('"message"')
	assert s.buffer[0].contains('plain text msg')
}

fn test_azure_monitor_logs_drops_non_log() {
	mut s := new_azure_monitor_logs({
		'customer_id':      'ws-1'
		'log_type':         'Test'
		'batch.max_events': '1000'
	})!

	metric := event.Event(event.Metric{
		name: 'test.gauge'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 42.0})
	})
	s.send(metric) or {}
	assert s.total_buffered() == 0
}

fn test_azure_monitor_logs_invalid_batch_max() {
	s := new_azure_monitor_logs({
		'customer_id':      'ws-1'
		'log_type':         'Test'
		'batch.max_events': '-5'
	})!
	assert s.batch_max == 100
}

fn test_azure_monitor_logs_invalid_batch_timeout() {
	s := new_azure_monitor_logs({
		'customer_id':         'ws-1'
		'log_type':            'Test'
		'batch.timeout_secs': '0'
	})!
	assert s.batch_timeout > 0
}

fn test_build_monitor_url() {
	url := build_monitor_url('https://ws-123.ods.opinsights.azure.com')
	assert url == 'https://ws-123.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'

	url2 := build_monitor_url('http://localhost:8080')
	assert url2 == 'http://localhost:8080/api/logs?api-version=2016-04-01'
}

fn test_azure_monitor_logs_json_codec_format() {
	mut s := new_azure_monitor_logs({
		'customer_id':      'ws-1'
		'log_type':         'Test'
		'encoding.codec':   'json'
		'batch.max_events': '1000'
	})!

	mut log := event.new_log('hello world')
	log.set('level', event.Value('info'))
	ev := event.Event(log)
	s.send(ev) or {}
	assert s.buffer.len == 1
	assert s.buffer[0].contains('"message"')
	assert s.buffer[0].contains('hello world')
}

fn test_azure_monitor_logs_no_shared_key() {
	os.unsetenv('AZURE_MONITOR_SHARED_KEY')

	s := new_azure_monitor_logs({
		'customer_id': 'ws-1'
		'log_type':    'Test'
	})!
	// Should succeed but with empty shared_key (auth will fail at flush time)
	assert s.shared_key == ''
}

fn test_azure_monitor_logs_azure_resource_id() {
	s := new_azure_monitor_logs({
		'customer_id':       'ws-1'
		'log_type':          'Test'
		'azure_resource_id': '/subscriptions/abc/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm1'
	})!
	assert s.azure_resource_id.contains('/subscriptions/')
	assert s.azure_resource_id.contains('virtualMachines/vm1')
}

fn test_azure_monitor_logs_time_generated_key() {
	s := new_azure_monitor_logs({
		'customer_id':        'ws-1'
		'log_type':           'Test'
		'time_generated_key': 'event_timestamp'
	})!
	assert s.time_generated_key == 'event_timestamp'
}
