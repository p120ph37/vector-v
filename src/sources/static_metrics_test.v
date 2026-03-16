module sources

import event

fn test_new_static_metrics_defaults() {
	s := new_static_metrics({})
	assert s.metrics.len == 0
	assert s.namespace == ''
}

fn test_new_static_metrics_interval() {
	s := new_static_metrics({
		'interval_secs': '5'
	})
	assert s.interval > 0
}

fn test_new_static_metrics_negative_interval_defaults() {
	s := new_static_metrics({
		'interval_secs': '-1'
	})
	assert s.interval > 0
}

fn test_new_static_metrics_single_gauge() {
	s := new_static_metrics({
		'metrics.cpu_usage.type':  'gauge'
		'metrics.cpu_usage.value': '75.5'
	})
	assert s.metrics.len == 1
	assert s.metrics[0].name == 'cpu_usage'
	assert s.metrics[0].typ == .gauge
	assert s.metrics[0].value == 75.5
}

fn test_new_static_metrics_single_counter() {
	s := new_static_metrics({
		'metrics.requests.type':  'counter'
		'metrics.requests.value': '1.0'
	})
	assert s.metrics.len == 1
	assert s.metrics[0].name == 'requests'
	assert s.metrics[0].typ == .counter
	assert s.metrics[0].value == 1.0
}

fn test_new_static_metrics_with_tags() {
	s := new_static_metrics({
		'metrics.temp.type':     'gauge'
		'metrics.temp.value':    '22.5'
		'metrics.temp.tags.env': 'prod'
		'metrics.temp.tags.dc':  'us-east-1'
	})
	assert s.metrics.len == 1
	assert s.metrics[0].tags.len == 2
	assert s.metrics[0].tags['env'] == 'prod'
	assert s.metrics[0].tags['dc'] == 'us-east-1'
}

fn test_new_static_metrics_multiple_metrics() {
	s := new_static_metrics({
		'metrics.cpu.type':    'gauge'
		'metrics.cpu.value':   '50.0'
		'metrics.reqs.type':   'counter'
		'metrics.reqs.value':  '10.0'
	})
	assert s.metrics.len == 2
	// Find each metric by name (order not guaranteed from map iteration)
	mut found_cpu := false
	mut found_reqs := false
	for m in s.metrics {
		if m.name == 'cpu' {
			assert m.typ == .gauge
			assert m.value == 50.0
			found_cpu = true
		}
		if m.name == 'reqs' {
			assert m.typ == .counter
			assert m.value == 10.0
			found_reqs = true
		}
	}
	assert found_cpu
	assert found_reqs
}

fn test_new_static_metrics_invalid_type_skipped() {
	s := new_static_metrics({
		'metrics.bad.type':  'histogram'
		'metrics.bad.value': '1.0'
	})
	assert s.metrics.len == 0
}

fn test_new_static_metrics_missing_type_skipped() {
	s := new_static_metrics({
		'metrics.no_type.value': '1.0'
	})
	assert s.metrics.len == 0
}

fn test_new_static_metrics_missing_value_defaults_zero() {
	s := new_static_metrics({
		'metrics.m.type': 'gauge'
	})
	assert s.metrics.len == 1
	assert s.metrics[0].value == 0.0
}

fn test_new_static_metrics_namespace() {
	s := new_static_metrics({
		'namespace':           'myapp'
		'metrics.foo.type':    'gauge'
		'metrics.foo.value':   '1.0'
	})
	assert s.namespace == 'myapp'
}

fn test_new_static_metrics_no_tags() {
	s := new_static_metrics({
		'metrics.m.type':  'counter'
		'metrics.m.value': '5.0'
	})
	assert s.metrics.len == 1
	assert s.metrics[0].tags.len == 0
}
