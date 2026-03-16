module sinks

import event
import mockserver

// ---------------------------------------------------------------------------
// GcpCloudMonitoringSink tests
// ---------------------------------------------------------------------------

fn test_new_gcp_cloud_monitoring_defaults() {
	s := new_gcp_cloud_monitoring({
		'project_id': 'my-project'
	})!
	assert s.project_id == 'my-project'
	assert s.default_namespace == ''
	assert s.endpoint == 'https://monitoring.googleapis.com'
	assert s.api_key == ''
	assert s.resource_type == 'global'
	assert s.resource_labels.len == 0
	assert s.batch_max_events == 200
	assert s.batch_timeout_ms == 1000
	assert s.buffer.len == 0
}

fn test_new_gcp_cloud_monitoring_missing_project_id() {
	new_gcp_cloud_monitoring(map[string]string{}) or {
		assert err.msg().contains('project_id is required')
		return
	}
	assert false, 'expected error for missing project_id'
}

fn test_new_gcp_cloud_monitoring_empty_project_id() {
	new_gcp_cloud_monitoring({
		'project_id': ''
	}) or {
		assert err.msg().contains('project_id is required')
		return
	}
	assert false, 'expected error for empty project_id'
}

fn test_new_gcp_cloud_monitoring_custom_config() {
	s := new_gcp_cloud_monitoring({
		'project_id':            'custom-proj'
		'default_namespace':     'myapp'
		'endpoint':              'http://localhost:9090'
		'auth.api_key':          'test-key'
		'auth.credentials_file': '/path/to/sa.json'
		'resource.type':         'gce_instance'
		'resource.labels.zone':  'us-central1-a'
		'batch.max_events':      '50'
		'batch.timeout_ms':      '5000'
	})!
	assert s.project_id == 'custom-proj'
	assert s.default_namespace == 'myapp'
	assert s.endpoint == 'http://localhost:9090'
	assert s.api_key == 'test-key'
	assert s.credentials_file == '/path/to/sa.json'
	assert s.resource_type == 'gce_instance'
	assert s.resource_labels['zone'] == 'us-central1-a'
	assert s.batch_max_events == 50
	assert s.batch_timeout_ms == 5000
}

fn test_gcp_cloud_monitoring_negative_batch_max() {
	s := new_gcp_cloud_monitoring({
		'project_id':       'proj'
		'batch.max_events': '-1'
	})!
	assert s.batch_max_events == 200
}

fn test_gcp_cloud_monitoring_negative_batch_timeout() {
	s := new_gcp_cloud_monitoring({
		'project_id':       'proj'
		'batch.timeout_ms': '0'
	})!
	assert s.batch_timeout_ms == 1000
}

fn test_build_monitoring_url() {
	url := build_monitoring_url('https://monitoring.googleapis.com', 'my-project')
	assert url == 'https://monitoring.googleapis.com/v3/projects/my-project/timeSeries'
}

fn test_build_monitoring_url_custom_endpoint() {
	url := build_monitoring_url('http://localhost:8080', 'test-proj')
	assert url == 'http://localhost:8080/v3/projects/test-proj/timeSeries'
}

fn test_gcp_cloud_monitoring_send_buffers() {
	mut s := new_gcp_cloud_monitoring({
		'project_id':       'proj'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	m := event.Event(event.Metric{
		name: 'cpu_usage'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 75.5})
	})
	s.send(m) or {}
	assert s.total_buffered() == 1

	m2 := event.Event(event.Metric{
		name: 'mem_usage'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 60.0})
	})
	s.send(m2) or {}
	assert s.total_buffered() == 2
}

fn test_gcp_cloud_monitoring_total_buffered() {
	mut s := new_gcp_cloud_monitoring({
		'project_id':       'proj'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	assert s.total_buffered() == 0
	for i in 0 .. 5 {
		m := event.Event(event.Metric{
			name: 'metric_${i}'
			kind: .absolute
			value: event.MetricValue(event.GaugeValue{value: f64(i)})
		})
		s.send(m) or {}
	}
	assert s.total_buffered() == 5
}

fn test_gcp_cloud_monitoring_flush_empty() {
	mut s := new_gcp_cloud_monitoring({
		'project_id': 'proj'
	})!

	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_gcp_cloud_monitoring_drops_non_metric() {
	mut s := new_gcp_cloud_monitoring({
		'project_id':       'proj'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('this is a log'))
	s.send(ev) or {}
	assert s.total_buffered() == 0
}

fn test_gcp_cloud_monitoring_build_payload_gauge() {
	mut s := new_gcp_cloud_monitoring({
		'project_id':       'my-project'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	m := event.Event(event.Metric{
		name: 'cpu_usage'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 75.5})
		tags: {
			'host': 'web-01'
		}
	})
	s.send(m) or {}

	payload := s.build_time_series_payload()
	assert payload.contains('"timeSeries":[')
	assert payload.contains('custom.googleapis.com')
	assert payload.contains('cpu_usage')
	assert payload.contains('"metricKind":"GAUGE"')
	assert payload.contains('"doubleValue":75.5')
	assert payload.contains('"host"')
	assert payload.contains('"web-01"')
}

fn test_gcp_cloud_monitoring_build_payload_counter() {
	mut s := new_gcp_cloud_monitoring({
		'project_id':       'my-project'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	m := event.Event(event.Metric{
		name: 'requests_total'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 42.0})
	})
	s.send(m) or {}

	payload := s.build_time_series_payload()
	assert payload.contains('"timeSeries":[')
	assert payload.contains('requests_total')
	assert payload.contains('"metricKind":"CUMULATIVE"')
	assert payload.contains('"doubleValue":42')
}

fn test_gcp_cloud_monitoring_build_payload_with_namespace() {
	mut s := new_gcp_cloud_monitoring({
		'project_id':        'my-project'
		'default_namespace': 'myapp'
		'batch.max_events':  '1000'
		'batch.timeout_ms':  '3600000'
	})!

	m := event.Event(event.Metric{
		name: 'latency'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 100.0})
	})
	s.send(m) or {}

	payload := s.build_time_series_payload()
	assert payload.contains('custom.googleapis.com/myapp/latency')
}

fn test_gcp_cloud_monitoring_build_payload_resource_labels() {
	mut s := new_gcp_cloud_monitoring({
		'project_id':              'my-project'
		'resource.type':           'gce_instance'
		'resource.labels.zone':    'us-central1-a'
		'batch.max_events':        '1000'
		'batch.timeout_ms':        '3600000'
	})!

	m := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 50.0})
	})
	s.send(m) or {}

	payload := s.build_time_series_payload()
	assert payload.contains('"type":"gce_instance"')
	assert payload.contains('"labels":{')
}

fn test_gcp_cloud_monitoring_build_payload_multiple() {
	mut s := new_gcp_cloud_monitoring({
		'project_id':       'proj'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	for i in 0 .. 3 {
		m := event.Event(event.Metric{
			name: 'metric_${i}'
			kind: .absolute
			value: event.MetricValue(event.GaugeValue{value: f64(i) * 10.0})
		})
		s.send(m) or {}
	}

	payload := s.build_time_series_payload()
	assert payload.contains('metric_0')
	assert payload.contains('metric_1')
	assert payload.contains('metric_2')
}

// ---------------------------------------------------------------------------
// Mock server integration tests
// ---------------------------------------------------------------------------

fn test_gcp_cloud_monitoring_flush_to_mock() {
	mut mock := mockserver.start(
		mockserver.post('/v3/projects/test-proj/timeSeries', mockserver.respond(200, '{}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_gcp_cloud_monitoring({
		'project_id':       'test-proj'
		'endpoint':         mock.url()
		'auth.api_key':     'test-api-key'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	m1 := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 80.0})
	})
	m2 := event.Event(event.Metric{
		name: 'mem'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 60.0})
	})
	s.send(m1) or {}
	s.send(m2) or {}
	assert s.total_buffered() == 2

	s.flush() or { panic(err.str()) }
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].body.contains('"timeSeries"')
	assert reqs[0].headers['x-goog-api-key'] == 'test-api-key'
}

fn test_gcp_cloud_monitoring_flush_error() {
	mut mock := mockserver.start(
		mockserver.post('/v3/projects/err-proj/timeSeries', mockserver.respond(403, '{"error":"forbidden"}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_gcp_cloud_monitoring({
		'project_id':       'err-proj'
		'endpoint':         mock.url()
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	m := event.Event(event.Metric{
		name: 'fail_metric'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 1.0})
	})
	s.send(m) or {}

	s.flush() or {
		assert err.msg().contains('403')
		return
	}
}
