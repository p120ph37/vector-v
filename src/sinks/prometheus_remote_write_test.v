module sinks

import event
import time

fn test_new_prometheus_remote_write_defaults() {
	s := new_prometheus_remote_write({
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }
	assert s.endpoint == 'http://prometheus:9090/api/v1/write'
	assert s.tenant_id == ''
	assert s.default_namespace == ''
	assert s.batch_max == 100
	assert s.auth_header == ''
}

fn test_new_prometheus_remote_write_missing_endpoint() {
	new_prometheus_remote_write(map[string]string{}) or {
		assert err.msg().contains('endpoint is required')
		return
	}
	assert false, 'expected error for missing endpoint'
}

fn test_new_prometheus_remote_write_custom() {
	s := new_prometheus_remote_write({
		'endpoint':           'http://mimir:9009/api/v1/push'
		'tenant_id':          'team-a'
		'default_namespace':  'myapp'
		'batch.max_events':   '50'
		'batch.timeout_secs': '10'
	}) or { panic(err.str()) }
	assert s.endpoint == 'http://mimir:9009/api/v1/push'
	assert s.tenant_id == 'team-a'
	assert s.default_namespace == 'myapp'
	assert s.batch_max == 50
}

fn test_new_prometheus_remote_write_auth_bearer() {
	s := new_prometheus_remote_write({
		'endpoint':   'http://prometheus:9090/api/v1/write'
		'auth.token': 'secret123'
	}) or { panic(err.str()) }
	assert s.auth_header == 'Bearer secret123'
}

fn test_new_prometheus_remote_write_auth_basic() {
	s := new_prometheus_remote_write({
		'endpoint':      'http://prometheus:9090/api/v1/write'
		'auth.user':     'user'
		'auth.password': 'pass'
	}) or { panic(err.str()) }
	assert s.auth_header.starts_with('Basic ')
}

fn test_new_prometheus_remote_write_batch_invalid() {
	s := new_prometheus_remote_write({
		'endpoint':           'http://prometheus:9090/api/v1/write'
		'batch.max_events':   '-1'
		'batch.timeout_secs': '-5'
	}) or { panic(err.str()) }
	assert s.batch_max == 100
	assert s.batch_timeout == 5_000_000_000
}

fn test_prometheus_remote_write_send_non_metric() {
	mut s := new_prometheus_remote_write({
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 0
}

fn test_prometheus_remote_write_buffering() {
	mut s := new_prometheus_remote_write({
		'endpoint':         'http://prometheus:9090/api/v1/write'
		'batch.max_events': '1000'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'test_metric'
		kind: .absolute
		value: event.GaugeValue{value: 42.0}
		timestamp: time.now()
	}
	s.send(event.Event(m)) or { panic(err.str()) }
	assert s.total_buffered() == 1

	m2 := event.Metric{
		name: 'test_metric2'
		kind: .absolute
		value: event.CounterValue{value: 10.0}
		timestamp: time.now()
	}
	s.send(event.Event(m2)) or { panic(err.str()) }
	assert s.total_buffered() == 2
}

fn test_prometheus_remote_write_flush_empty() {
	mut s := new_prometheus_remote_write({
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }
	s.flush() or { panic(err.str()) }
	assert s.total_buffered() == 0
}

fn test_prometheus_remote_write_format_counter() {
	s := new_prometheus_remote_write({
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'http_requests'
		kind: .incremental
		value: event.CounterValue{value: 100.0}
		tags: {'method': 'GET'}
		timestamp: time.unix(1000)
	}
	result := s.format_metric(m)
	assert result.contains('http_requests_total')
	assert result.contains('method="GET"')
	assert result.contains('100')
}

fn test_prometheus_remote_write_format_gauge() {
	s := new_prometheus_remote_write({
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'temperature'
		kind: .absolute
		value: event.GaugeValue{value: 22.5}
		tags: {'location': 'office'}
		timestamp: time.unix(2000)
	}
	result := s.format_metric(m)
	assert result.contains('temperature{')
	assert result.contains('location="office"')
	assert result.contains('22.5')
}

fn test_prometheus_remote_write_format_histogram() {
	s := new_prometheus_remote_write({
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'request_duration'
		kind: .absolute
		value: event.HistogramValue{
			buckets: [
				event.Bucket{upper_limit: 0.5, count: 10},
				event.Bucket{upper_limit: 1.0, count: 20},
			]
			count: 25
			sum: 15.5
		}
		tags: {'handler': 'api'}
		timestamp: time.unix(3000)
	}
	result := s.format_metric(m)
	assert result.contains('request_duration_bucket{')
	assert result.contains('le="+Inf"')
	assert result.contains('request_duration_sum{')
	assert result.contains('request_duration_count{')
}

fn test_prometheus_remote_write_format_summary() {
	s := new_prometheus_remote_write({
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'latency'
		kind: .absolute
		value: event.SummaryValue{
			quantiles: [
				event.Quantile{quantile: 0.5, value: 0.05},
				event.Quantile{quantile: 0.99, value: 0.1},
			]
			count: 100
			sum: 5.0
		}
		tags: {'service': 'web'}
		timestamp: time.unix(4000)
	}
	result := s.format_metric(m)
	assert result.contains('latency{')
	assert result.contains('quantile="0.5"')
	assert result.contains('latency_sum{')
	assert result.contains('latency_count{')
}

fn test_prometheus_remote_write_format_set() {
	s := new_prometheus_remote_write({
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'unique_users'
		kind: .absolute
		value: event.SetValue{values: ['a', 'b', 'c']}
		tags: {'region': 'us'}
		timestamp: time.unix(5000)
	}
	result := s.format_metric(m)
	assert result.contains('unique_users{')
	assert result.contains('3')
}

fn test_prometheus_remote_write_format_distribution() {
	s := new_prometheus_remote_write({
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'request_size'
		kind: .absolute
		value: event.DistributionValue{
			samples: [
				event.Sample{value: 0.003, rate: 2},
				event.Sample{value: 7.0, rate: 1},
			]
			statistic: .histogram
		}
		timestamp: time.unix(6000)
	}
	result := s.format_metric(m)
	assert result.contains('request_size_bucket{')
	assert result.contains('le="+Inf"')
	assert result.contains('request_size_sum')
	assert result.contains('request_size_count')
}

fn test_prometheus_remote_write_with_namespace() {
	s := new_prometheus_remote_write({
		'endpoint':          'http://prometheus:9090/api/v1/write'
		'default_namespace': 'myapp'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'requests'
		kind: .absolute
		value: event.GaugeValue{value: 42.0}
		timestamp: time.unix(100)
	}
	result := s.format_metric(m)
	assert result.contains('myapp_requests')
}

fn test_prometheus_remote_write_metric_namespace_precedence() {
	s := new_prometheus_remote_write({
		'endpoint':          'http://prometheus:9090/api/v1/write'
		'default_namespace': 'myapp'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'requests'
		namespace: 'override'
		kind: .absolute
		value: event.GaugeValue{value: 1.0}
		timestamp: time.unix(100)
	}
	result := s.format_metric(m)
	assert result.contains('override_requests')
}

fn test_prometheus_remote_write_registry() {
	s := build_sink('prometheus_remote_write', {
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }
	assert s is PrometheusRemoteWriteSink
}

fn test_prometheus_remote_write_encode_all() {
	mut s := new_prometheus_remote_write({
		'endpoint':         'http://prometheus:9090/api/v1/write'
		'batch.max_events': '1000'
	}) or { panic(err.str()) }

	// Buffer multiple metrics
	for i in 0 .. 5 {
		m := event.Metric{
			name: 'metric_${i}'
			kind: .absolute
			value: event.GaugeValue{value: f64(i)}
			timestamp: time.unix(i64(1000 + i))
		}
		s.send(event.Event(m)) or { panic(err.str()) }
	}
	assert s.total_buffered() == 5

	// Verify encode
	payload := s.encode_remote_write()
	for i in 0 .. 5 {
		assert payload.contains('metric_${i}')
	}
}

fn test_prometheus_remote_write_gauge_no_tags() {
	s := new_prometheus_remote_write({
		'endpoint': 'http://prometheus:9090/api/v1/write'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'up'
		kind: .absolute
		value: event.GaugeValue{value: 1.0}
		timestamp: time.unix(100)
	}
	result := s.format_metric(m)
	assert result.contains('up ')
	assert !result.contains('{')
}
