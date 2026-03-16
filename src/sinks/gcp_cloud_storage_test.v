module sinks

import event
import os

fn test_new_gcp_cloud_storage_defaults() {
	s := new_gcp_cloud_storage({
		'bucket': 'my-bucket'
	})!
	assert s.bucket == 'my-bucket'
	assert s.key_prefix == 'date=%Y-%m-%d/'
	assert s.endpoint == 'https://storage.googleapis.com'
	assert s.codec == .ndjson_codec
	assert s.content_type == 'application/x-ndjson'
	assert s.batch_max == 1000
	assert s.api_key == ''
	assert s.acl == ''
	assert s.storage_class == ''
	assert s.buffer.len == 0
}

fn test_new_gcp_cloud_storage_missing_bucket() {
	new_gcp_cloud_storage(map[string]string{}) or {
		assert err.msg().contains('bucket is required')
		return
	}
	assert false, 'expected error for missing bucket'
}

fn test_new_gcp_cloud_storage_empty_bucket() {
	new_gcp_cloud_storage({
		'bucket': ''
	}) or {
		assert err.msg().contains('bucket is required')
		return
	}
	assert false, 'expected error for empty bucket'
}

fn test_new_gcp_cloud_storage_custom_config() {
	s := new_gcp_cloud_storage({
		'bucket':          'custom-bucket'
		'key_prefix':      'logs/%Y/%m/'
		'endpoint':        'http://localhost:4443'
		'auth.api_key':    'my-api-key'
		'encoding.codec':  'json'
		'batch.max_events': '500'
		'content_type':    'application/json'
		'acl':             'private'
		'storage_class':   'NEARLINE'
	})!
	assert s.bucket == 'custom-bucket'
	assert s.key_prefix == 'logs/%Y/%m/'
	assert s.endpoint == 'http://localhost:4443'
	assert s.api_key == 'my-api-key'
	assert s.codec == .json_codec
	assert s.batch_max == 500
	assert s.content_type == 'application/json'
	assert s.acl == 'private'
	assert s.storage_class == 'NEARLINE'
}

fn test_new_gcp_cloud_storage_text_codec() {
	s := new_gcp_cloud_storage({
		'bucket':         'b1'
		'encoding.codec': 'text'
	})!
	assert s.codec == .text_codec
	assert s.content_type == 'text/plain'
}

fn test_new_gcp_cloud_storage_credentials() {
	os.setenv('GOOGLE_APPLICATION_CREDENTIALS', '/path/to/sa.json', true)
	defer { os.unsetenv('GOOGLE_APPLICATION_CREDENTIALS') }

	s := new_gcp_cloud_storage({
		'bucket': 'b1'
	})!
	assert s.credentials_file == '/path/to/sa.json'
}

fn test_new_gcp_cloud_storage_credentials_explicit() {
	os.setenv('GOOGLE_APPLICATION_CREDENTIALS', '/env/creds.json', true)
	defer { os.unsetenv('GOOGLE_APPLICATION_CREDENTIALS') }

	s := new_gcp_cloud_storage({
		'bucket':               'b1'
		'auth.credentials_file': '/explicit/creds.json'
	})!
	assert s.credentials_file == '/explicit/creds.json'
}

fn test_new_gcp_cloud_storage_metadata() {
	s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'metadata.env':    'production'
		'metadata.region': 'us-central1'
	})!
	assert s.metadata['env'] == 'production'
	assert s.metadata['region'] == 'us-central1'
}

fn test_gcp_cloud_storage_buffering() {
	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'batch.max_events': '10000'
	})!

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_gcp_cloud_storage_total_buffered() {
	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'batch.max_events': '10000'
	})!

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
}

fn test_gcp_cloud_storage_build_payload_ndjson() {
	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
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

fn test_gcp_cloud_storage_build_payload_json() {
	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'encoding.codec':  'json'
		'batch.max_events': '10000'
	})!

	ev := event.Event(event.new_log('json test'))
	s.send(ev) or {}

	payload := s.build_payload()
	assert payload.starts_with('[')
	assert payload.ends_with(']')
}

fn test_gcp_cloud_storage_build_payload_text() {
	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'encoding.codec':  'text'
		'batch.max_events': '10000'
	})!

	ev1 := event.Event(event.new_log('hello'))
	ev2 := event.Event(event.new_log('world'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	payload := s.build_payload()
	assert payload == 'hello\nworld'
}

fn test_gcp_cloud_storage_generate_object_name() {
	mut s := new_gcp_cloud_storage({
		'bucket':     'b1'
		'key_prefix': 'logs/'
	})!

	name := s.generate_object_name()
	assert name.starts_with('logs/')
	assert name.ends_with('.log')
	assert s.seq == 1

	name2 := s.generate_object_name()
	assert name2 != name
	assert s.seq == 2
}

fn test_gcp_cloud_storage_flush_empty() {
	mut s := new_gcp_cloud_storage({
		'bucket': 'b1'
	})!
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_gcp_cloud_storage_encode_metric() {
	s := new_gcp_cloud_storage({
		'bucket': 'b1'
	})!
	metric := event.Event(event.Metric{
		name: 'test.counter'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	result := s.encode_event(metric)
	assert result.contains('test.counter')
}

fn test_gcp_cloud_storage_encode_trace() {
	s := new_gcp_cloud_storage({
		'bucket': 'b1'
	})!
	trace := event.Event(event.TraceEvent{})
	result := s.encode_event(trace)
	assert result.len > 0
}

fn test_gcp_cloud_storage_encode_text() {
	s := new_gcp_cloud_storage({
		'bucket':         'b1'
		'encoding.codec': 'text'
	})!
	ev := event.Event(event.new_log('plain text'))
	result := s.encode_event(ev)
	assert result == 'plain text'
}

fn test_gcp_cloud_storage_invalid_batch_max() {
	s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'batch.max_events': '-1'
	})!
	assert s.batch_max == 1000
}

fn test_gcp_cloud_storage_invalid_batch_timeout() {
	s := new_gcp_cloud_storage({
		'bucket':             'b1'
		'batch.timeout_secs': '-10'
	})!
	assert s.batch_timeout > 0
}

fn test_gcp_cloud_storage_json_content_type() {
	s := new_gcp_cloud_storage({
		'bucket':         'b1'
		'encoding.codec': 'json'
	})!
	assert s.content_type == 'application/json'
}

fn test_build_gcs_upload_url() {
	url := build_gcs_upload_url('https://storage.googleapis.com', 'my-bucket', 'path/to/object.log')
	assert url == 'https://storage.googleapis.com/upload/storage/v1/b/my-bucket/o?uploadType=media&name=path/to/object.log'

	url2 := build_gcs_upload_url('http://localhost:4443', 'b1', 'test.log')
	assert url2 == 'http://localhost:4443/upload/storage/v1/b/b1/o?uploadType=media&name=test.log'
}

fn test_gcp_cloud_storage_sends_all_event_types() {
	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'batch.max_events': '10000'
	})!

	// Log event
	s.send(event.Event(event.new_log('log msg'))) or {}
	assert s.total_buffered() == 1

	// Metric event
	s.send(event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 50.0})
	})) or {}
	assert s.total_buffered() == 2

	// Trace event
	s.send(event.Event(event.TraceEvent{})) or {}
	assert s.total_buffered() == 3
}

fn test_gcp_cloud_storage_acl_and_storage_class() {
	s := new_gcp_cloud_storage({
		'bucket':        'b1'
		'acl':           'publicRead'
		'storage_class': 'COLDLINE'
	})!
	assert s.acl == 'publicRead'
	assert s.storage_class == 'COLDLINE'
}
