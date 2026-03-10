module event

fn test_metric_counter() {
	m := Metric{
		name: 'requests_total'
		namespace: 'app'
		kind: .incremental
		value: MetricValue(CounterValue{value: 1.0})
	}
	assert m.name == 'requests_total'
	assert m.namespace == 'app'
	assert m.kind == .incremental
}

fn test_metric_gauge() {
	m := Metric{
		name: 'cpu_usage'
		kind: .absolute
		value: MetricValue(GaugeValue{value: 0.75})
	}
	assert m.name == 'cpu_usage'
	assert m.kind == .absolute
}

fn test_metric_set() {
	m := Metric{
		name: 'unique_users'
		kind: .incremental
		value: MetricValue(SetValue{values: ['user1', 'user2', 'user3']})
	}
	assert m.name == 'unique_users'
	v := m.value
	match v {
		SetValue {
			assert v.values.len == 3
		}
		else {
			assert false, 'expected SetValue'
		}
	}
}

fn test_metric_distribution() {
	m := Metric{
		name: 'response_time'
		kind: .incremental
		value: MetricValue(DistributionValue{
			samples: [Sample{value: 0.1, rate: 1}, Sample{value: 0.2, rate: 2}]
			statistic: .summary
		})
	}
	assert m.name == 'response_time'
}

fn test_metric_tags() {
	mut tags := map[string]string{}
	tags['env'] = 'production'
	tags['host'] = 'server01'
	m := Metric{
		name: 'cpu'
		kind: .absolute
		value: MetricValue(GaugeValue{value: 0.5})
		tags: tags
	}
	assert m.tags['env'] == 'production'
	assert m.tags['host'] == 'server01'
}

fn test_new_counter_helper() {
	m := new_counter('requests', 5.0, .incremental)
	assert m.name == 'requests'
	assert m.kind == .incremental
}

fn test_new_gauge_helper() {
	m := new_gauge('temperature', 72.5)
	assert m.name == 'temperature'
	assert m.kind == .absolute
}
