module sinks

import event
import os

fn test_new_gcp_stackdriver_defaults() {
	s := new_gcp_stackdriver({
		'project_id': 'my-project'
		'log_id':     'my-app-logs'
	})!
	assert s.project_id == 'my-project'
	assert s.log_id == 'my-app-logs'
	assert s.endpoint == 'https://logging.googleapis.com'
	assert s.api_key == ''
	assert s.credentials_file == ''
	assert s.resource_type == 'global'
	assert s.encoding_codec == 'json'
	assert s.batch_max_events == 1000
	assert s.batch_timeout_ms == 1000
	assert s.severity_key == ''
	assert s.resource_labels.len == 0
	assert s.labels.len == 0
	assert s.buffer.len == 0
}

fn test_new_gcp_stackdriver_missing_project_id() {
	new_gcp_stackdriver({
		'log_id': 'logs'
	}) or {
		assert err.msg().contains('project_id is required')
		return
	}
	assert false, 'expected error for missing project_id'
}

fn test_new_gcp_stackdriver_empty_project_id() {
	new_gcp_stackdriver({
		'project_id': ''
		'log_id':     'logs'
	}) or {
		assert err.msg().contains('project_id is required')
		return
	}
	assert false, 'expected error for empty project_id'
}

fn test_new_gcp_stackdriver_missing_log_id() {
	new_gcp_stackdriver({
		'project_id': 'proj'
	}) or {
		assert err.msg().contains('log_id is required')
		return
	}
	assert false, 'expected error for missing log_id'
}

fn test_new_gcp_stackdriver_empty_log_id() {
	new_gcp_stackdriver({
		'project_id': 'proj'
		'log_id':     ''
	}) or {
		assert err.msg().contains('log_id is required')
		return
	}
	assert false, 'expected error for empty log_id'
}

fn test_new_gcp_stackdriver_custom_config() {
	s := new_gcp_stackdriver({
		'project_id':       'custom-proj'
		'log_id':           'custom-logs'
		'endpoint':         'http://localhost:8080'
		'auth.api_key':     'my-api-key'
		'resource.type':    'gce_instance'
		'encoding.codec':   'text'
		'batch.max_events': '500'
		'batch.timeout_ms': '2000'
		'severity_key':     'level'
	})!
	assert s.project_id == 'custom-proj'
	assert s.log_id == 'custom-logs'
	assert s.endpoint == 'http://localhost:8080'
	assert s.api_key == 'my-api-key'
	assert s.resource_type == 'gce_instance'
	assert s.encoding_codec == 'text'
	assert s.batch_max_events == 500
	assert s.batch_timeout_ms == 2000
	assert s.severity_key == 'level'
}

fn test_new_gcp_stackdriver_resource_labels() {
	s := new_gcp_stackdriver({
		'project_id':               'proj'
		'log_id':                   'logs'
		'resource.labels.zone':     'us-central1-a'
		'resource.labels.instance': 'vm-123'
	})!
	assert s.resource_labels['zone'] == 'us-central1-a'
	assert s.resource_labels['instance'] == 'vm-123'
}

fn test_new_gcp_stackdriver_labels() {
	s := new_gcp_stackdriver({
		'project_id':  'proj'
		'log_id':      'logs'
		'labels.env':  'production'
		'labels.team': 'platform'
	})!
	assert s.labels['env'] == 'production'
	assert s.labels['team'] == 'platform'
}

fn test_new_gcp_stackdriver_credentials() {
	os.setenv('GOOGLE_APPLICATION_CREDENTIALS', '/path/to/sa.json', true)
	defer { os.unsetenv('GOOGLE_APPLICATION_CREDENTIALS') }

	s := new_gcp_stackdriver({
		'project_id': 'proj'
		'log_id':     'logs'
	})!
	assert s.credentials_file == '/path/to/sa.json'
}

fn test_new_gcp_stackdriver_credentials_explicit() {
	os.setenv('GOOGLE_APPLICATION_CREDENTIALS', '/env/creds.json', true)
	defer { os.unsetenv('GOOGLE_APPLICATION_CREDENTIALS') }

	s := new_gcp_stackdriver({
		'project_id':            'proj'
		'log_id':                'logs'
		'auth.credentials_file': '/explicit/creds.json'
	})!
	assert s.credentials_file == '/explicit/creds.json'
}

fn test_build_stackdriver_url() {
	url := build_stackdriver_url('https://logging.googleapis.com')
	assert url == 'https://logging.googleapis.com/v2/entries:write'

	url2 := build_stackdriver_url('http://localhost:8080')
	assert url2 == 'http://localhost:8080/v2/entries:write'
}

fn test_gcp_stackdriver_send_buffers() {
	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('hello stackdriver'))
	s.send(ev) or {}
	assert s.total_buffered() == 1

	ev2 := event.Event(event.new_log('second message'))
	s.send(ev2) or {}
	assert s.total_buffered() == 2
}

fn test_gcp_stackdriver_total_buffered() {
	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	assert s.total_buffered() == 0
	for i in 0 .. 5 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_gcp_stackdriver_flush_empty() {
	mut s := new_gcp_stackdriver({
		'project_id': 'proj'
		'log_id':     'logs'
	})!

	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_gcp_stackdriver_drops_non_log() {
	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	metric := event.Event(event.Metric{
		name: 'test.gauge'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 42.0})
	})
	s.send(metric) or {}
	assert s.total_buffered() == 0
}

fn test_gcp_stackdriver_negative_batch_max() {
	s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'batch.max_events': '-1'
	})!
	assert s.batch_max_events == 1000
}

fn test_gcp_stackdriver_negative_batch_timeout() {
	s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'batch.timeout_ms': '0'
	})!
	assert s.batch_timeout_ms == 1000
}

fn test_gcp_stackdriver_build_entries_payload() {
	mut s := new_gcp_stackdriver({
		'project_id':       'my-project'
		'log_id':           'my-logs'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('test message'))
	s.send(ev) or {}

	payload := s.build_entries_payload()
	assert payload.contains('"entries":[')
	assert payload.contains('"logName":"projects/my-project/logs/my-logs"')
	assert payload.contains('"resource":{"type":"global"}')
	assert payload.contains('"timestamp"')
	assert payload.contains('"jsonPayload"')
}

fn test_gcp_stackdriver_build_entries_text() {
	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'encoding.codec':   'text'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('plain text'))
	s.send(ev) or {}

	payload := s.build_entries_payload()
	assert payload.contains('"textPayload"')
	assert payload.contains('plain text')
}

fn test_gcp_stackdriver_build_entries_with_resource_labels() {
	mut s := new_gcp_stackdriver({
		'project_id':           'proj'
		'log_id':               'logs'
		'resource.type':        'gce_instance'
		'resource.labels.zone': 'us-east1-b'
		'batch.max_events':     '1000'
		'batch.timeout_ms':     '3600000'
	})!

	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}

	payload := s.build_entries_payload()
	assert payload.contains('"type":"gce_instance"')
	assert payload.contains('"zone"')
	assert payload.contains('us-east1-b')
}

fn test_gcp_stackdriver_build_entries_with_labels() {
	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'labels.env':       'staging'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}

	payload := s.build_entries_payload()
	assert payload.contains('"labels":{')
	assert payload.contains('"env"')
	assert payload.contains('staging')
}

fn test_gcp_stackdriver_severity_key() {
	s := new_gcp_stackdriver({
		'project_id':   'proj'
		'log_id':       'logs'
		'severity_key': 'level'
	})!
	assert s.severity_key == 'level'
}

fn test_gcp_stackdriver_multiple_entries() {
	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or {}
	}

	payload := s.build_entries_payload()
	assert payload.contains('msg 0')
	assert payload.contains('msg 1')
	assert payload.contains('msg 2')
}
