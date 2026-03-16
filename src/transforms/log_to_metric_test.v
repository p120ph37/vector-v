module transforms

import event
import json

fn test_log_to_metric_counter() {
	t := new_log_to_metric({
		'metrics.0.type':  'counter'
		'metrics.0.field': 'count'
		'metrics.0.name':  'request_total'
	})!

	mut log := event.new_log('test')
	log.set('count', event.Value(5))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			assert m.name == 'request_total'
			assert m.kind == .incremental
			v := m.value
			match v {
				event.CounterValue { assert v.value == 5.0 }
				else { assert false, 'expected CounterValue' }
			}
		}
		else { assert false, 'expected Metric' }
	}
}

fn test_log_to_metric_gauge() {
	t := new_log_to_metric({
		'metrics.0.type':  'gauge'
		'metrics.0.field': 'temperature'
		'metrics.0.kind':  'absolute'
	})!

	mut log := event.new_log('test')
	log.set('temperature', event.Value(event.Float(72.5)))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			assert m.name == 'temperature'
			assert m.kind == .absolute
			v := m.value
			match v {
				event.GaugeValue { assert v.value == 72.5 }
				else { assert false, 'expected GaugeValue' }
			}
		}
		else { assert false, 'expected Metric' }
	}
}

fn test_log_to_metric_set() {
	t := new_log_to_metric({
		'metrics.0.type':  'set'
		'metrics.0.field': 'user_id'
		'metrics.0.name':  'unique_users'
	})!

	mut log := event.new_log('test')
	log.set('user_id', event.Value('user-42'))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			assert m.name == 'unique_users'
			v := m.value
			match v {
				event.SetValue {
					assert v.values.len == 1
					assert v.values[0] == 'user-42'
				}
				else { assert false, 'expected SetValue' }
			}
		}
		else { assert false, 'expected Metric' }
	}
}

fn test_log_to_metric_histogram() {
	t := new_log_to_metric({
		'metrics.0.type':  'histogram'
		'metrics.0.field': 'latency'
	})!

	mut log := event.new_log('test')
	log.set('latency', event.Value(event.Float(0.25)))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			assert m.name == 'latency'
			v := m.value
			match v {
				event.DistributionValue {
					assert v.samples.len == 1
					assert v.samples[0].value == 0.25
					assert v.statistic == .histogram
				}
				else { assert false, 'expected DistributionValue' }
			}
		}
		else { assert false, 'expected Metric' }
	}
}

fn test_log_to_metric_summary() {
	t := new_log_to_metric({
		'metrics.0.type':  'summary'
		'metrics.0.field': 'duration'
	})!

	mut log := event.new_log('test')
	log.set('duration', event.Value(event.Float(1.5)))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			v := m.value
			match v {
				event.DistributionValue { assert v.statistic == .summary }
				else { assert false, 'expected DistributionValue' }
			}
		}
		else { assert false, 'expected Metric' }
	}
}

fn test_log_to_metric_with_tags() {
	t := new_log_to_metric({
		'metrics.0.type':       'counter'
		'metrics.0.field':      'count'
		'metrics.0.tags.env':   'production'
		'metrics.0.tags.host':  '{{ hostname }}'
	})!

	mut log := event.new_log('test')
	log.set('count', event.Value(1))
	log.set('hostname', event.Value('server01'))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			assert m.tags['env'] == 'production'
			assert m.tags['host'] == 'server01'
		}
		else { assert false, 'expected Metric' }
	}
}

fn test_log_to_metric_with_namespace() {
	t := new_log_to_metric({
		'metrics.0.type':      'counter'
		'metrics.0.field':     'count'
		'metrics.0.name':      'requests'
		'metrics.0.namespace': 'app'
	})!

	mut log := event.new_log('test')
	log.set('count', event.Value(1))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric { assert m.namespace == 'app' }
		else { assert false, 'expected Metric' }
	}
}

fn test_log_to_metric_multiple_metrics() {
	t := new_log_to_metric({
		'metrics.0.type':  'counter'
		'metrics.0.field': 'bytes'
		'metrics.0.name':  'bytes_total'
		'metrics.1.type':  'gauge'
		'metrics.1.field': 'cpu'
		'metrics.1.name':  'cpu_usage'
		'metrics.1.kind':  'absolute'
	})!

	mut log := event.new_log('test')
	log.set('bytes', event.Value(1024))
	log.set('cpu', event.Value(event.Float(0.75)))
	result := t.transform(event.Event(log))!
	assert result.len == 2
}

fn test_log_to_metric_missing_field_skipped() {
	t := new_log_to_metric({
		'metrics.0.type':  'counter'
		'metrics.0.field': 'missing_field'
	})!

	log := event.new_log('test')
	result := t.transform(event.Event(log))!
	assert result.len == 0
}

fn test_log_to_metric_non_log_passthrough() {
	t := new_log_to_metric({
		'metrics.0.type':  'counter'
		'metrics.0.field': 'count'
	})!

	metric := event.Event(event.Metric{
		name: 'existing'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{value: 1.0})
	})
	result := t.transform(metric)!
	assert result.len == 1
}

fn test_log_to_metric_string_value() {
	t := new_log_to_metric({
		'metrics.0.type':  'counter'
		'metrics.0.field': 'count'
	})!

	mut log := event.new_log('test')
	log.set('count', event.Value('42'))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			v := m.value
			match v {
				event.CounterValue { assert v.value == 42.0 }
				else { assert false }
			}
		}
		else { assert false }
	}
}

fn test_log_to_metric_bool_value() {
	t := new_log_to_metric({
		'metrics.0.type':  'counter'
		'metrics.0.field': 'flag'
	})!

	mut log := event.new_log('test')
	log.set('flag', event.Value(true))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric {
			v := m.value
			match v {
				event.CounterValue { assert v.value == 1.0 }
				else { assert false }
			}
		}
		else { assert false }
	}
}

fn test_log_to_metric_missing_config_errors() {
	if _ := new_log_to_metric({}) {
		assert false, 'expected error for no metrics'
	}
}

fn test_log_to_metric_missing_field_config_errors() {
	if _ := new_log_to_metric({'metrics.0.type': 'counter'}) {
		assert false, 'expected error for missing field'
	}
}

fn test_log_to_metric_unknown_type_errors() {
	if _ := new_log_to_metric({'metrics.0.type': 'unknown', 'metrics.0.field': 'x'}) {
		assert false, 'expected error for unknown type'
	}
}

fn test_log_to_metric_dynamic_tag_missing_field() {
	t := new_log_to_metric({
		'metrics.0.type':      'counter'
		'metrics.0.field':     'count'
		'metrics.0.tags.host': '{{ nonexistent }}'
	})!

	mut log := event.new_log('test')
	log.set('count', event.Value(1))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric { assert m.tags['host'] == '' }
		else { assert false }
	}
}

fn test_log_to_metric_default_name_from_field() {
	t := new_log_to_metric({
		'metrics.0.type':  'counter'
		'metrics.0.field': 'request_count'
	})!

	mut log := event.new_log('test')
	log.set('request_count', event.Value(10))
	result := t.transform(event.Event(log))!
	assert result.len == 1

	m := result[0]
	match m {
		event.Metric { assert m.name == 'request_count' }
		else { assert false }
	}
}

fn test_log_to_metric_via_registry() {
	mut t := build_transform('log_to_metric', {
		'metrics.0.type':  'counter'
		'metrics.0.field': 'count'
	})!

	mut log := event.new_log('test')
	log.set('count', event.Value(1))
	result := apply_transform(mut t, event.Event(log))!
	assert result.len == 1
}
