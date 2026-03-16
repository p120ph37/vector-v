module sinks

import event
import time

fn test_format_prometheus_counter() {
	m := event.Metric{
		name: 'http_requests'
		kind: .incremental
		value: event.CounterValue{value: 100.0}
		tags: {
			'method': 'GET'
		}
		timestamp: time.unix(1000)
	}
	result := format_prometheus(m)
	assert result.contains('http_requests_total')
	assert result.contains('method="GET"')
	assert result.contains('100')
	assert result.contains('1000000') // 1000 * 1000 ms
}

fn test_format_prometheus_counter_already_total() {
	m := event.Metric{
		name: 'http_requests_total'
		value: event.CounterValue{value: 50.0}
		tags: {
			'code': '200'
		}
		timestamp: time.unix(500)
	}
	result := format_prometheus(m)
	// Should not double-suffix _total
	assert result.contains('http_requests_total{')
	assert !result.contains('http_requests_total_total')
	assert result.contains('50')
}

fn test_format_prometheus_gauge() {
	m := event.Metric{
		name: 'temperature'
		kind: .absolute
		value: event.GaugeValue{value: 22.5}
		tags: {
			'location': 'office'
		}
		timestamp: time.unix(2000)
	}
	result := format_prometheus(m)
	assert result.contains('temperature{')
	assert result.contains('location="office"')
	assert result.contains('22.5')
	assert !result.contains('_total')
}

fn test_format_prometheus_histogram() {
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
		tags: {
			'handler': 'api'
		}
		timestamp: time.unix(3000)
	}
	result := format_prometheus(m)
	assert result.contains('request_duration_bucket{')
	assert result.contains('le="0.5"')
	assert result.contains('le="1.0"')
	assert result.contains('le="+Inf"')
	assert result.contains('request_duration_sum{')
	assert result.contains('request_duration_count{')
	assert result.contains('15.5')
	assert result.contains('25')
}

fn test_format_prometheus_summary() {
	m := event.Metric{
		name: 'rpc_latency'
		kind: .absolute
		value: event.SummaryValue{
			quantiles: [
				event.Quantile{quantile: 0.5, value: 0.05},
				event.Quantile{quantile: 0.99, value: 0.1},
			]
			count: 100
			sum: 5.0
		}
		tags: {
			'service': 'web'
		}
		timestamp: time.unix(4000)
	}
	result := format_prometheus(m)
	assert result.contains('rpc_latency{')
	assert result.contains('quantile="0.5"')
	assert result.contains('quantile="0.99"')
	assert result.contains('rpc_latency_sum{')
	assert result.contains('rpc_latency_count{')
	assert result.contains('100')
	assert result.contains('5')
}

fn test_format_prometheus_set() {
	m := event.Metric{
		name: 'unique_users'
		kind: .absolute
		value: event.SetValue{
			values: ['alice', 'bob', 'charlie']
		}
		tags: {
			'region': 'us'
		}
		timestamp: time.unix(5000)
	}
	result := format_prometheus(m)
	assert result.contains('unique_users{')
	assert result.contains('region="us"')
	assert result.contains('3') // 3 unique values
}

fn test_format_prometheus_distribution() {
	m := event.Metric{
		name: 'request_size'
		kind: .absolute
		value: event.DistributionValue{
			samples: [
				event.Sample{value: 0.003, rate: 2},
				event.Sample{value: 0.5, rate: 3},
				event.Sample{value: 7.0, rate: 1},
			]
			statistic: .histogram
		}
		timestamp: time.unix(6000)
	}
	result := format_prometheus(m)
	assert result.contains('request_size_bucket{')
	assert result.contains('le="+Inf"')
	assert result.contains('request_size_sum')
	assert result.contains('request_size_count')
	// Total count should be 2+3+1=6
	assert result.contains('6')
}

fn test_prom_format_tags_basic() {
	tags := {
		'method': 'GET'
		'code':   '200'
	}
	result := prom_format_tags(tags)
	assert result.starts_with('{')
	assert result.ends_with('}')
	assert result.contains('method="GET"')
	assert result.contains('code="200"')
}

fn test_prom_format_tags_empty() {
	tags := map[string]string{}
	result := prom_format_tags(tags)
	assert result == ''
}

fn test_prom_format_tags_escaped() {
	tags := {
		'msg': 'hello"world'
		'path': 'a\\b'
		'note': 'line\none'
	}
	result := prom_format_tags(tags)
	assert result.contains('msg="hello\\"world"')
	assert result.contains('path="a\\\\b"')
	assert result.contains('note="line\\none"')
}

fn test_sanitize_metric_name_valid() {
	assert sanitize_metric_name('http_requests_total') == 'http_requests_total'
	assert sanitize_metric_name('MyMetric') == 'MyMetric'
	assert sanitize_metric_name('a_b_c') == 'a_b_c'
}

fn test_sanitize_metric_name_invalid_chars() {
	assert sanitize_metric_name('my-metric') == 'my_metric'
	assert sanitize_metric_name('my.metric') == 'my_metric'
	assert sanitize_metric_name('metric@name') == 'metric_name'
}

fn test_sanitize_metric_name_leading_digit() {
	result := sanitize_metric_name('1metric')
	assert result.starts_with('_')
	assert result.contains('1')
	assert result.contains('metric')
}

fn test_sanitize_metric_name_colon() {
	assert sanitize_metric_name('namespace:metric') == 'namespace:metric'
}

fn test_sanitize_metric_name_digits() {
	assert sanitize_metric_name('metric123') == 'metric123'
}

fn test_new_prometheus_sink() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	opts['job'] = 'my_job'
	s := new_prometheus_sink(opts) or { panic(err.str()) }
	assert s.endpoint == 'http://localhost:9091'
	assert s.job == 'my_job'
}

fn test_new_prometheus_sink_defaults() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	s := new_prometheus_sink(opts) or { panic(err.str()) }
	assert s.job == 'vector'
	assert s.batch_max == 100
	assert s.default_namespace == ''
}

fn test_new_prometheus_sink_missing_endpoint() {
	opts := map[string]string{}
	if _ := new_prometheus_sink(opts) {
		assert false, 'expected error for missing endpoint'
	}
}

fn test_new_prometheus_sink_auth_bearer() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	opts['auth.token'] = 'secret123'
	s := new_prometheus_sink(opts) or { panic(err.str()) }
	assert s.auth_header == 'Bearer secret123'
}

fn test_new_prometheus_sink_auth_basic() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	opts['auth.user'] = 'user'
	opts['auth.password'] = 'pass'
	s := new_prometheus_sink(opts) or { panic(err.str()) }
	assert s.auth_header.starts_with('Basic ')
}

fn test_new_prometheus_sink_batch_config() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	opts['batch.max_events'] = '50'
	opts['batch.timeout_secs'] = '10'
	s := new_prometheus_sink(opts) or { panic(err.str()) }
	assert s.batch_max == 50
	assert s.batch_timeout == 10_000_000_000 // 10 seconds
}

fn test_new_prometheus_sink_batch_invalid() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	opts['batch.max_events'] = '-1'
	opts['batch.timeout_secs'] = '-5'
	s := new_prometheus_sink(opts) or { panic(err.str()) }
	assert s.batch_max == 100
	assert s.batch_timeout == 5_000_000_000 // default 5 seconds
}

fn test_new_prometheus_sink_namespace() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	opts['default_namespace'] = 'myapp'
	s := new_prometheus_sink(opts) or { panic(err.str()) }
	assert s.default_namespace == 'myapp'
}

fn test_prometheus_sink_send_non_metric() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	mut s := new_prometheus_sink(opts) or { panic(err.str()) }
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or { panic(err.str()) }
	// Non-metric events should be silently dropped
	assert s.total_buffered() == 0
}

fn test_prometheus_sink_buffering() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	opts['batch.max_events'] = '1000' // high limit to avoid flush
	mut s := new_prometheus_sink(opts) or { panic(err.str()) }

	m := event.Metric{
		name: 'test_metric'
		kind: .absolute
		value: event.GaugeValue{value: 42.0}
		timestamp: time.now()
	}
	ev := event.Event(m)
	s.send(ev) or { panic(err.str()) }
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

fn test_prometheus_sink_registry() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	s := build_sink('prometheus', opts) or { panic(err.str()) }
	assert s is PrometheusSink
}

fn test_prometheus_remote_write_sink_registry() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	s := build_sink('prometheus_remote_write', opts) or { panic(err.str()) }
	assert s is PrometheusSink
}

fn test_format_prometheus_gauge_no_tags() {
	m := event.Metric{
		name: 'up'
		kind: .absolute
		value: event.GaugeValue{value: 1.0}
		timestamp: time.unix(100)
	}
	result := format_prometheus(m)
	assert result.contains('up ')
	assert result.contains('1')
	// No braces when no tags
	assert !result.contains('{')
}

fn test_format_histogram_function() {
	h := event.HistogramValue{
		buckets: [
			event.Bucket{upper_limit: 0.1, count: 5},
			event.Bucket{upper_limit: 0.5, count: 10},
		]
		count: 12
		sum: 3.5
	}
	tags := {
		'host': 'web1'
	}
	result := format_histogram('req', tags, h, 1000000)
	assert result.contains('req_bucket{')
	assert result.contains('le="0.1"')
	assert result.contains('le="0.5"')
	assert result.contains('le="+Inf"')
	assert result.contains('req_sum{')
	assert result.contains('req_count{')
	assert result.contains('host="web1"')
}

fn test_format_summary_function() {
	s := event.SummaryValue{
		quantiles: [
			event.Quantile{quantile: 0.5, value: 100.0},
			event.Quantile{quantile: 0.9, value: 200.0},
		]
		count: 50
		sum: 7500.0
	}
	tags := {
		'env': 'prod'
	}
	result := format_summary('latency', tags, s, 2000000)
	assert result.contains('latency{')
	assert result.contains('quantile="0.5"')
	assert result.contains('quantile="0.9"')
	assert result.contains('latency_sum{')
	assert result.contains('latency_count{')
	assert result.contains('env="prod"')
}

fn test_format_distribution_as_histogram_function() {
	d := event.DistributionValue{
		samples: [
			event.Sample{value: 0.001, rate: 5},
			event.Sample{value: 2.0, rate: 3},
		]
		statistic: .histogram
	}
	tags := map[string]string{}
	result := format_distribution_as_histogram('dist', tags, d, 3000000)
	assert result.contains('dist_bucket{')
	assert result.contains('le="+Inf"')
	assert result.contains('dist_sum')
	assert result.contains('dist_count')
	// Total count = 5+3=8
	assert result.contains('8')
}

fn test_format_float_integer() {
	result := format_float(1.0)
	assert result.contains('1')
}

fn test_format_float_decimal() {
	result := format_float(0.5)
	assert result.contains('0.5')
}

fn test_format_metric_with_namespace() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	opts['default_namespace'] = 'myapp'
	s := new_prometheus_sink(opts) or { panic(err.str()) }

	m := event.Metric{
		name: 'requests'
		kind: .absolute
		value: event.GaugeValue{value: 42.0}
		timestamp: time.unix(100)
	}
	result := s.format_metric(m)
	assert result.contains('myapp_requests')
}

fn test_format_metric_with_metric_namespace() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	s := new_prometheus_sink(opts) or { panic(err.str()) }

	m := event.Metric{
		name: 'requests'
		namespace: 'custom'
		kind: .absolute
		value: event.GaugeValue{value: 42.0}
		timestamp: time.unix(100)
	}
	result := s.format_metric(m)
	assert result.contains('custom_requests')
}

fn test_format_metric_namespace_precedence() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	opts['default_namespace'] = 'myapp'
	s := new_prometheus_sink(opts) or { panic(err.str()) }

	m := event.Metric{
		name: 'requests'
		namespace: 'override'
		kind: .absolute
		value: event.GaugeValue{value: 1.0}
		timestamp: time.unix(100)
	}
	result := s.format_metric(m)
	// Metric namespace should be used when present
	assert result.contains('override_requests')
}

fn test_prometheus_sink_flush_empty() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://localhost:9091'
	mut s := new_prometheus_sink(opts) or { panic(err.str()) }
	// Flush with empty buffer should not error
	s.flush() or { panic(err.str()) }
	assert s.total_buffered() == 0
}

fn test_format_prometheus_set_empty() {
	m := event.Metric{
		name: 'empty_set'
		kind: .absolute
		value: event.SetValue{
			values: []
		}
		timestamp: time.unix(100)
	}
	result := format_prometheus(m)
	assert result.contains('empty_set')
	assert result.contains('0')
}

fn test_format_histogram_empty_buckets() {
	h := event.HistogramValue{
		buckets: []
		count: 0
		sum: 0
	}
	tags := map[string]string{}
	result := format_histogram('empty_hist', tags, h, 1000)
	assert result.contains('empty_hist_bucket{')
	assert result.contains('le="+Inf"')
	assert result.contains('empty_hist_sum')
	assert result.contains('empty_hist_count')
}
