module sinks

import event
import os

fn test_new_gcp_pubsub_sink_defaults() {
	s := new_gcp_pubsub_sink({
		'project': 'my-project'
		'topic':   'my-topic'
	}) or { panic(err.str()) }
	assert s.project == 'my-project'
	assert s.topic == 'my-topic'
	assert s.endpoint == 'https://pubsub.googleapis.com'
	assert s.api_key == ''
	assert s.credentials_file == ''
	assert s.encoding_codec == 'json'
	assert s.batch_max_events == 1000
	assert s.batch_timeout_ms == 1000
	assert s.ordering_key_field == ''
	assert s.attributes_key == ''
	assert s.buffer.len == 0
}

fn test_new_gcp_pubsub_sink_missing_project() {
	new_gcp_pubsub_sink({
		'topic': 'my-topic'
	}) or {
		assert err.msg().contains('project is required')
		return
	}
	assert false, 'expected error for missing project'
}

fn test_new_gcp_pubsub_sink_missing_topic() {
	new_gcp_pubsub_sink({
		'project': 'my-project'
	}) or {
		assert err.msg().contains('topic is required')
		return
	}
	assert false, 'expected error for missing topic'
}

fn test_new_gcp_pubsub_sink_custom() {
	s := new_gcp_pubsub_sink({
		'project':            'custom-proj'
		'topic':              'custom-topic'
		'endpoint':           'http://localhost:8085'
		'auth.api_key':       'my-api-key'
		'encoding.codec':     'text'
		'batch.max_events':   '500'
		'batch.timeout_ms':   '2000'
		'ordering_key_field': 'order_id'
		'attributes_key':     'attrs'
	}) or { panic(err.str()) }
	assert s.project == 'custom-proj'
	assert s.topic == 'custom-topic'
	assert s.endpoint == 'http://localhost:8085'
	assert s.api_key == 'my-api-key'
	assert s.encoding_codec == 'text'
	assert s.batch_max_events == 500
	assert s.batch_timeout_ms == 2000
	assert s.ordering_key_field == 'order_id'
	assert s.attributes_key == 'attrs'
}

fn test_build_pubsub_publish_url() {
	url := build_pubsub_publish_url('https://pubsub.googleapis.com', 'my-project', 'my-topic')
	assert url == 'https://pubsub.googleapis.com/v1/projects/my-project/topics/my-topic:publish'

	// Custom endpoint
	url2 := build_pubsub_publish_url('http://localhost:8085', 'proj', 'topic')
	assert url2 == 'http://localhost:8085/v1/projects/proj/topics/topic:publish'
}

fn test_gcp_pubsub_sink_send_buffers() {
	mut s := new_gcp_pubsub_sink({
		'project':          'proj'
		'topic':            'topic'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('hello pubsub'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 1

	ev2 := event.Event(event.new_log('second message'))
	s.send(ev2) or { panic(err.str()) }
	assert s.total_buffered() == 2
}

fn test_gcp_pubsub_sink_total_buffered() {
	mut s := new_gcp_pubsub_sink({
		'project':          'proj'
		'topic':            'topic'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	for i in 0 .. 5 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or { panic(err.str()) }
	}
	assert s.total_buffered() == 5
}

fn test_gcp_pubsub_sink_flush_empty() {
	mut s := new_gcp_pubsub_sink({
		'project': 'proj'
		'topic':   'topic'
	}) or { panic(err.str()) }

	// Flushing an empty buffer should not error
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_gcp_pubsub_sink_ordering_key() {
	s := new_gcp_pubsub_sink({
		'project':            'proj'
		'topic':              'topic'
		'ordering_key_field': 'request_id'
	}) or { panic(err.str()) }
	assert s.ordering_key_field == 'request_id'
}

fn test_gcp_pubsub_sink_ordering_key_empty_default() {
	s := new_gcp_pubsub_sink({
		'project': 'proj'
		'topic':   'topic'
	}) or { panic(err.str()) }
	assert s.ordering_key_field == ''
}

fn test_gcp_pubsub_sink_credentials() {
	// Test GOOGLE_APPLICATION_CREDENTIALS env fallback
	os.setenv('GOOGLE_APPLICATION_CREDENTIALS', '/path/to/sa.json', true)
	defer { os.unsetenv('GOOGLE_APPLICATION_CREDENTIALS') }

	s := new_gcp_pubsub_sink({
		'project': 'cred-proj'
		'topic':   'cred-topic'
	}) or { panic(err.str()) }
	assert s.credentials_file == '/path/to/sa.json'
}

fn test_gcp_pubsub_sink_credentials_explicit_override() {
	os.setenv('GOOGLE_APPLICATION_CREDENTIALS', '/env/creds.json', true)
	defer { os.unsetenv('GOOGLE_APPLICATION_CREDENTIALS') }

	s := new_gcp_pubsub_sink({
		'project':              'proj'
		'topic':                'topic'
		'auth.credentials_file': '/explicit/creds.json'
	}) or { panic(err.str()) }
	assert s.credentials_file == '/explicit/creds.json'
}

fn test_gcp_pubsub_sink_negative_batch_max() {
	s := new_gcp_pubsub_sink({
		'project':          'proj'
		'topic':            'topic'
		'batch.max_events': '-1'
	}) or { panic(err.str()) }
	assert s.batch_max_events == 1000
}

fn test_gcp_pubsub_sink_negative_batch_timeout() {
	s := new_gcp_pubsub_sink({
		'project':          'proj'
		'topic':            'topic'
		'batch.timeout_ms': '0'
	}) or { panic(err.str()) }
	assert s.batch_timeout_ms == 1000
}

fn test_gcp_pubsub_sink_drops_non_log() {
	mut s := new_gcp_pubsub_sink({
		'project':          'proj'
		'topic':            'topic'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	}) or { panic(err.str()) }

	// Send a metric event -- should be silently dropped
	metric := event.Event(event.Metric{
		name: 'test.gauge'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 42.0})
	})
	s.send(metric) or { panic(err.str()) }
	assert s.total_buffered() == 0
}
