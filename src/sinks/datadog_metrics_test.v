module sinks

import event
import time

fn test_new_datadog_metrics_defaults() {
	s := new_datadog_metrics({
		'api_key': 'my-api-key'
	}) or { panic(err.str()) }
	assert s.api_key == 'my-api-key'
	assert s.endpoint == 'https://api.datadoghq.com'
	assert s.default_namespace == ''
	assert s.batch_max == 100
}

fn test_new_datadog_metrics_missing_api_key() {
	new_datadog_metrics(map[string]string{}) or {
		assert err.msg().contains('api_key is required')
		return
	}
	assert false, 'expected error for missing api_key'
}

fn test_new_datadog_metrics_default_api_key() {
	s := new_datadog_metrics({
		'default_api_key': 'fallback-key'
	}) or { panic(err.str()) }
	assert s.api_key == 'fallback-key'
}

fn test_new_datadog_metrics_custom() {
	s := new_datadog_metrics({
		'api_key':            'custom-key'
		'site':               'datadoghq.eu'
		'endpoint':           'https://custom.api.example.com/'
		'default_namespace':  'myapp'
		'batch.max_events':   '200'
		'batch.timeout_secs': '10'
	}) or { panic(err.str()) }
	assert s.api_key == 'custom-key'
	assert s.endpoint == 'https://custom.api.example.com'
	assert s.default_namespace == 'myapp'
	assert s.batch_max == 200
}

fn test_datadog_metrics_batch_invalid() {
	s := new_datadog_metrics({
		'api_key':            'k'
		'batch.max_events':   '-1'
		'batch.timeout_secs': '-5'
	}) or { panic(err.str()) }
	assert s.batch_max == 100
}

fn test_datadog_metrics_send_drops_non_metric() {
	mut s := new_datadog_metrics({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('hello'))
	s.send(ev) or { panic(err.str()) }
	assert s.total_buffered() == 0
}

fn test_datadog_metrics_send_buffers_metric() {
	mut s := new_datadog_metrics({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.GaugeValue{value: 85.0}
		timestamp: time.now()
	}
	s.send(event.Event(m)) or { panic(err.str()) }
	assert s.total_buffered() == 1
}

fn test_datadog_metrics_total_buffered() {
	mut s := new_datadog_metrics({
		'api_key':          'key'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	m := event.Metric{
		name: 'req'
		kind: .incremental
		value: event.CounterValue{value: 1.0}
		timestamp: time.now()
	}
	s.send(event.Event(m)) or { panic(err.str()) }
	assert s.total_buffered() == 1
	s.send(event.Event(m)) or { panic(err.str()) }
	assert s.total_buffered() == 2
}

fn test_datadog_metrics_flush_empty() {
	mut s := new_datadog_metrics({
		'api_key': 'key'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_datadog_metrics_encode_counter() {
	s := new_datadog_metrics({
		'api_key': 'key'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'http_requests'
		kind: .incremental
		value: event.CounterValue{value: 42.0}
		tags: {'method': 'GET'}
		timestamp: time.unix(1000)
	}
	encoded := s.encode_metric(m)
	assert encoded.contains('"metric":"http_requests"')
	assert encoded.contains('"type":"count"')
	assert encoded.contains('"value":42')
	assert encoded.contains('"method:GET"')
}

fn test_datadog_metrics_encode_gauge() {
	s := new_datadog_metrics({
		'api_key': 'key'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'temperature'
		kind: .absolute
		value: event.GaugeValue{value: 22.5}
		timestamp: time.unix(2000)
	}
	encoded := s.encode_metric(m)
	assert encoded.contains('"metric":"temperature"')
	assert encoded.contains('"type":"gauge"')
	assert encoded.contains('"value":22.5')
}

fn test_datadog_metrics_encode_with_namespace() {
	s := new_datadog_metrics({
		'api_key':           'key'
		'default_namespace': 'myapp'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'requests'
		kind: .absolute
		value: event.GaugeValue{value: 1.0}
		timestamp: time.unix(1000)
	}
	encoded := s.encode_metric(m)
	assert encoded.contains('"metric":"myapp.requests"')
}

fn test_datadog_metrics_encode_metric_namespace_precedence() {
	s := new_datadog_metrics({
		'api_key':           'key'
		'default_namespace': 'myapp'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'requests'
		namespace: 'override'
		kind: .absolute
		value: event.GaugeValue{value: 1.0}
		timestamp: time.unix(1000)
	}
	encoded := s.encode_metric(m)
	assert encoded.contains('"metric":"override.requests"')
}

fn test_datadog_metrics_encode_set() {
	s := new_datadog_metrics({
		'api_key': 'key'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'unique'
		kind: .absolute
		value: event.SetValue{values: ['a', 'b', 'c']}
		timestamp: time.unix(1000)
	}
	encoded := s.encode_metric(m)
	assert encoded.contains('"type":"gauge"')
	assert encoded.contains('"value":3')
}

fn test_datadog_metrics_encode_distribution() {
	s := new_datadog_metrics({
		'api_key': 'key'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'dist'
		kind: .absolute
		value: event.DistributionValue{
			samples: [
				event.Sample{value: 1.0, rate: 2},
				event.Sample{value: 3.0, rate: 1},
			]
			statistic: .histogram
		}
		timestamp: time.unix(1000)
	}
	encoded := s.encode_metric(m)
	assert encoded.contains('"type":"distribution"')
	assert encoded.contains('"value":5')
}

fn test_datadog_metrics_encode_histogram() {
	s := new_datadog_metrics({
		'api_key': 'key'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'hist'
		kind: .absolute
		value: event.HistogramValue{
			buckets: [event.Bucket{upper_limit: 1.0, count: 10}]
			count: 10
			sum: 7.5
		}
		timestamp: time.unix(1000)
	}
	encoded := s.encode_metric(m)
	assert encoded.contains('"type":"gauge"')
	assert encoded.contains('"value":7.5')
}

fn test_datadog_metrics_encode_summary() {
	s := new_datadog_metrics({
		'api_key': 'key'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'summary'
		kind: .absolute
		value: event.SummaryValue{
			quantiles: [event.Quantile{quantile: 0.5, value: 0.1}]
			count: 100
			sum: 50.0
		}
		timestamp: time.unix(1000)
	}
	encoded := s.encode_metric(m)
	assert encoded.contains('"type":"gauge"')
	assert encoded.contains('"value":50')
}

fn test_datadog_metrics_encode_no_tags() {
	s := new_datadog_metrics({
		'api_key': 'key'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'test'
		kind: .absolute
		value: event.GaugeValue{value: 1.0}
		timestamp: time.unix(1000)
	}
	encoded := s.encode_metric(m)
	assert !encoded.contains('"tags"')
}

fn test_datadog_metrics_registry() {
	sink := build_sink('datadog_metrics', {
		'api_key': 'test-key'
	}) or { panic(err.str()) }
	match sink {
		DatadogMetricsSink {
			assert sink.api_key == 'test-key'
			assert sink.endpoint == 'https://api.datadoghq.com'
		}
		else {
			assert false, 'expected DatadogMetricsSink'
		}
	}
}

fn test_dd_metric_type_all() {
	assert dd_metric_type(event.CounterValue{value: 1.0}) == 'count'
	assert dd_metric_type(event.GaugeValue{value: 1.0}) == 'gauge'
	assert dd_metric_type(event.DistributionValue{}) == 'distribution'
	assert dd_metric_type(event.HistogramValue{}) == 'gauge'
	assert dd_metric_type(event.SummaryValue{}) == 'gauge'
	assert dd_metric_type(event.SetValue{}) == 'gauge'
}

fn test_dd_metric_value_all() {
	assert dd_metric_value(event.CounterValue{value: 42.0}) == 42.0
	assert dd_metric_value(event.GaugeValue{value: 3.14}) == 3.14
	assert dd_metric_value(event.SetValue{values: ['a', 'b']}) == 2.0
	assert dd_metric_value(event.HistogramValue{sum: 10.0}) == 10.0
	assert dd_metric_value(event.SummaryValue{sum: 5.0}) == 5.0
}

fn test_dd_metric_value_distribution() {
	v := event.DistributionValue{
		samples: [
			event.Sample{value: 2.0, rate: 3},
			event.Sample{value: 1.0, rate: 2},
		]
	}
	// 2.0*3 + 1.0*2 = 8.0
	assert dd_metric_value(v) == 8.0
}
