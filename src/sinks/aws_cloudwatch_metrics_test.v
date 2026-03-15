module sinks

import event
import os
import time

fn setup_cwm_test_env() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIATESTKEY', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'testsecretkey', true)
	os.setenv('AWS_REGION', 'us-east-1', true)
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
}

fn cleanup_cwm_test_env() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.unsetenv('AWS_REGION')
	os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
}

fn test_new_cloudwatch_metrics_defaults() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	s := new_cloudwatch_metrics({})!
	assert s.namespace == 'Vector'
	assert s.group_name == '/metrics/vector'
	assert s.stream_name == 'vector-metrics'
	assert s.region == 'us-east-1'
	assert s.batch_max == 100
	assert s.create_missing_group == true
	assert s.create_missing_stream == true
}

fn test_new_cloudwatch_metrics_custom_config() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	s := new_cloudwatch_metrics({
		'namespace':   'MyApp'
		'group_name':  '/custom/metrics'
		'stream_name': 'custom-stream'
		'region':      'eu-west-1'
	})!
	assert s.namespace == 'MyApp'
	assert s.group_name == '/custom/metrics'
	assert s.stream_name == 'custom-stream'
	assert s.region == 'eu-west-1'
	assert s.endpoint == 'https://logs.eu-west-1.amazonaws.com'
}

fn test_new_cloudwatch_metrics_custom_endpoint() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	s := new_cloudwatch_metrics({
		'endpoint': 'http://localhost:4566'
	})!
	assert s.endpoint == 'http://localhost:4566'
}

fn test_cloudwatch_metrics_batch_max_clamped() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	s := new_cloudwatch_metrics({
		'batch.max_events': '50000'
	})!
	assert s.batch_max == 10000
}

fn test_cloudwatch_metrics_batch_max_invalid() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	s := new_cloudwatch_metrics({
		'batch.max_events': '-5'
	})!
	assert s.batch_max == 100
}

fn test_cloudwatch_metrics_disable_auto_create() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	s := new_cloudwatch_metrics({
		'create_missing_group':  'false'
		'create_missing_stream': 'false'
	})!
	assert s.create_missing_group == false
	assert s.create_missing_stream == false
}

fn test_cloudwatch_metrics_counter_buffering() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	mut s := new_cloudwatch_metrics({
		'batch.max_events': '1000'
	})!

	metric := event.Event(event.new_counter('requests.total', 42.0, .incremental))
	s.send(metric) or {}
	assert s.total_buffered() == 1
}

fn test_cloudwatch_metrics_gauge_buffering() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	mut s := new_cloudwatch_metrics({
		'batch.max_events': '1000'
	})!

	metric := event.Event(event.new_gauge('cpu.usage', 72.5))
	s.send(metric) or {}
	assert s.total_buffered() == 1
}

fn test_cloudwatch_metrics_multiple_events() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	mut s := new_cloudwatch_metrics({
		'batch.max_events': '1000'
	})!

	for i in 0 .. 5 {
		metric := event.Event(event.new_counter('metric_${i}', f64(i), .incremental))
		s.send(metric) or {}
	}
	assert s.total_buffered() == 5
}

fn test_cloudwatch_metrics_log_events_ignored() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	mut s := new_cloudwatch_metrics({
		'batch.max_events': '1000'
	})!

	log_ev := event.Event(event.new_log('this is a log'))
	s.send(log_ev) or {}
	assert s.total_buffered() == 0
}

fn test_build_emf_json_counter() {
	emf := build_emf_json('TestNS', 'requests', 42.0, 'Count', 'Count', {}, 1710000000000)
	assert emf.contains('"_aws"')
	assert emf.contains('"Timestamp":1710000000000')
	assert emf.contains('"Namespace":"TestNS"')
	assert emf.contains('"Name":"requests"')
	assert emf.contains('"Unit":"Count"')
	assert emf.contains('"requests":42')
}

fn test_build_emf_json_gauge() {
	emf := build_emf_json('MyApp', 'cpu.usage', 72.5, 'None', 'None', {}, 1710000000000)
	assert emf.contains('"Namespace":"MyApp"')
	assert emf.contains('"Name":"cpu.usage"')
	assert emf.contains('"Unit":"None"')
	assert emf.contains('"cpu.usage":72.5')
}

fn test_build_emf_json_with_dimensions() {
	dims := {
		'host':    'server1'
		'service': 'api'
	}
	emf := build_emf_json('TestNS', 'latency', 150.0, 'None', 'None', dims, 1710000000000)
	assert emf.contains('"_aws"')
	assert emf.contains('"Dimensions"')
	assert emf.contains('"host"')
	assert emf.contains('"service"')
	assert emf.contains('"server1"')
	assert emf.contains('"api"')
	assert emf.contains('"latency":150')
}

fn test_build_emf_json_no_dimensions() {
	emf := build_emf_json('NS', 'count', 1.0, 'Count', 'Count', {}, 1710000000000)
	assert emf.contains('"Dimensions":[[]]')
}

fn test_cloudwatch_metrics_emf_structure() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	mut s := new_cloudwatch_metrics({
		'namespace':        'TestNS'
		'batch.max_events': '1000'
	})!

	mut m := event.new_counter('http.requests', 100.0, .incremental)
	m.tags['host'] = 'web-1'
	m.tags['path'] = '/api'
	metric := event.Event(m)
	s.send(metric) or {}

	assert s.buffer.len == 1
	emf := s.buffer[0].emf_json
	assert emf.contains('"_aws"')
	assert emf.contains('"CloudWatchMetrics"')
	assert emf.contains('"Namespace":"TestNS"')
	assert emf.contains('"Name":"http.requests"')
	assert emf.contains('"http.requests":100')
}

fn test_cloudwatch_metrics_namespaced_metric() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	mut s := new_cloudwatch_metrics({
		'namespace':        'TestNS'
		'batch.max_events': '1000'
	})!

	mut m := event.new_counter('requests', 10.0, .incremental)
	m.namespace = 'http'
	metric := event.Event(m)
	s.send(metric) or {}

	assert s.buffer.len == 1
	emf := s.buffer[0].emf_json
	assert emf.contains('"Name":"http.requests"')
}

fn test_cloudwatch_metrics_payload_structure() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	mut s := new_cloudwatch_metrics({
		'group_name':       '/metrics/test'
		'stream_name':      'test-stream'
		'batch.max_events': '1000'
	})!

	s.buffer << EmfEntry{
		timestamp_ms: 1710000000000
		emf_json: '{"_aws":{},"test":1}'
	}

	payload := s.build_put_log_events_payload()
	assert payload.contains('"logGroupName":"/metrics/test"')
	assert payload.contains('"logStreamName":"test-stream"')
	assert payload.contains('"logEvents":[')
	assert payload.contains('"timestamp":1710000000000')
}

fn test_format_f64_integer() {
	assert format_f64(42.0) == '42'
	assert format_f64(0.0) == '0'
	assert format_f64(-1.0) == '-1'
}

fn test_format_f64_decimal() {
	assert format_f64(3.14) == '3.14'
	assert format_f64(0.5) == '0.5'
}

fn test_cloudwatch_metrics_set_value() {
	setup_cwm_test_env()
	defer { cleanup_cwm_test_env() }

	mut s := new_cloudwatch_metrics({
		'namespace':        'TestNS'
		'batch.max_events': '1000'
	})!

	m := event.Metric{
		name: 'unique.users'
		kind: .absolute
		value: event.MetricValue(event.SetValue{
			values: ['alice', 'bob', 'charlie']
		})
		timestamp: time.now()
	}
	s.send(event.Event(m)) or {}
	assert s.buffer.len == 1
	emf := s.buffer[0].emf_json
	assert emf.contains('"unique.users":3')
}

fn test_cloudwatch_metrics_explicit_credentials() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent', true)
	defer { os.unsetenv('AWS_SHARED_CREDENTIALS_FILE') }

	s := new_cloudwatch_metrics({
		'region':                 'ap-northeast-1'
		'auth.access_key_id':     'AKIACWM'
		'auth.secret_access_key': 'cwmsecret'
	})!
	assert s.creds.access_key_id == 'AKIACWM'
	assert s.creds.secret_access_key == 'cwmsecret'
	assert s.region == 'ap-northeast-1'
}
