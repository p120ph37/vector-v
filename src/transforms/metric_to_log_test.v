module transforms

import event

fn test_metric_to_log_counter() {
	t := new_metric_to_log({})!

	m := event.Event(event.Metric{
		name: 'requests_total'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 42.0})
	})
	result := t.transform(m)!
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			assert first.message() == 'requests_total'
			name_val := first.get('name') or { event.Value('') }
			assert name_val == event.Value('requests_total')
			kind_val := first.get('kind') or { event.Value('') }
			assert kind_val == event.Value('incremental')
			json_str := first.to_json()
			assert json_str.contains('"counter"')
			assert json_str.contains('42')
		}
		else { assert false, 'expected LogEvent' }
	}
}

fn test_metric_to_log_gauge() {
	t := new_metric_to_log({})!

	m := event.Event(event.Metric{
		name: 'cpu_usage'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.75})
	})
	result := t.transform(m)!
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			assert first.message() == 'cpu_usage'
			kind_val := first.get('kind') or { event.Value('') }
			assert kind_val == event.Value('absolute')
			json_str := first.to_json()
			assert json_str.contains('"gauge"')
			assert json_str.contains('0.75')
		}
		else { assert false, 'expected LogEvent' }
	}
}

fn test_metric_to_log_set() {
	t := new_metric_to_log({})!

	m := event.Event(event.Metric{
		name: 'unique_users'
		kind: .incremental
		value: event.MetricValue(event.SetValue{
			values: ['user-1', 'user-2', 'user-3']
		})
	})
	result := t.transform(m)!
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert json_str.contains('"set"')
	assert json_str.contains('user-1')
	assert json_str.contains('user-2')
}

fn test_metric_to_log_with_tags() {
	t := new_metric_to_log({})!

	m := event.Event(event.Metric{
		name: 'requests'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
		tags: {
			'host':   'server01'
			'region': 'us-east-1'
		}
	})
	result := t.transform(m)!
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			json_str := first.to_json()
			assert json_str.contains('"tags"')
			assert json_str.contains('server01')
			assert json_str.contains('us-east-1')
			// Host tag should be promoted to top level
			host_val := first.get('host') or { event.Value('') }
			assert host_val == event.Value('server01')
		}
		else { assert false }
	}
}

fn test_metric_to_log_custom_host_tag() {
	t := new_metric_to_log({'host_tag': 'hostname'})!

	m := event.Event(event.Metric{
		name: 'requests'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
		tags: {'hostname': 'myhost'}
	})
	result := t.transform(m)!
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			host_val := first.get('host') or { event.Value('') }
			assert host_val == event.Value('myhost')
		}
		else { assert false }
	}
}

fn test_metric_to_log_with_namespace() {
	t := new_metric_to_log({})!

	m := event.Event(event.Metric{
		name: 'requests'
		namespace: 'app'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	result := t.transform(m)!
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent {
			ns_val := first.get('namespace') or { event.Value('') }
			assert ns_val == event.Value('app')
		}
		else { assert false }
	}
}

fn test_metric_to_log_non_metric_passthrough() {
	t := new_metric_to_log({})!

	log := event.Event(event.new_log('hello'))
	result := t.transform(log)!
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent { assert first.message() == 'hello' }
		else { assert false }
	}
}

fn test_metric_to_log_trace_passthrough() {
	t := new_metric_to_log({})!

	mut tr := event.new_trace()
	tr.set('span', event.Value('abc'))
	result := t.transform(event.Event(tr))!
	assert result.len == 1
}

fn test_metric_to_log_histogram() {
	t := new_metric_to_log({})!

	m := event.Event(event.Metric{
		name: 'request_duration'
		kind: .absolute
		value: event.MetricValue(event.HistogramValue{
			buckets: [
				event.Bucket{upper_limit: 0.1, count: 10},
				event.Bucket{upper_limit: 0.5, count: 25},
				event.Bucket{upper_limit: 1.0, count: 30},
			]
			count: 30
			sum: 12.5
		})
	})
	result := t.transform(m)!
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert json_str.contains('"histogram"')
	assert json_str.contains('buckets')
	assert json_str.contains('12.5')
}

fn test_metric_to_log_summary() {
	t := new_metric_to_log({})!

	m := event.Event(event.Metric{
		name: 'latency'
		kind: .absolute
		value: event.MetricValue(event.SummaryValue{
			quantiles: [
				event.Quantile{quantile: 0.5, value: 0.1},
				event.Quantile{quantile: 0.99, value: 0.5},
			]
			count: 100
			sum: 25.0
		})
	})
	result := t.transform(m)!
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert json_str.contains('"summary"')
	assert json_str.contains('quantiles')
}

fn test_metric_to_log_source_type() {
	t := new_metric_to_log({})!

	m := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	result := t.transform(m)!
	assert result.len == 1

	first := result[0]
	match first {
		event.LogEvent { assert first.meta.source_type == 'metric_to_log' }
		else { assert false }
	}
}

fn test_metric_to_log_distribution() {
	t := new_metric_to_log({})!

	m := event.Event(event.Metric{
		name: 'request_time'
		kind: .incremental
		value: event.MetricValue(event.DistributionValue{
			samples: [
				event.Sample{value: 0.1, rate: 5},
				event.Sample{value: 0.5, rate: 10},
			]
			statistic: .histogram
		})
	})
	result := t.transform(m)!
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert json_str.contains('"distribution"')
	assert json_str.contains('samples')
	assert json_str.contains('histogram')
}

fn test_metric_to_log_via_registry() {
	mut t := build_transform('metric_to_log', {})!

	m := event.Event(event.Metric{
		name: 'test'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	result := apply_transform(mut t, m)!
	assert result.len == 1
}

fn test_metric_to_log_no_tags() {
	t := new_metric_to_log({})!

	m := event.Event(event.Metric{
		name: 'simple_metric'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 99.0})
	})
	result := t.transform(m)!
	assert result.len == 1

	json_str := result[0].to_json_string()
	assert !json_str.contains('"tags"')
}
