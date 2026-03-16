module sources

import event

fn test_parse_statsd_counter() {
	m := parse_statsd('foo:1|c') or { panic(err.str()) }
	assert m.name == 'foo'
	assert m.kind == .incremental
	val := m.value
	match val {
		event.CounterValue {
			assert val.value == 1.0
		}
		else {
			assert false, 'expected CounterValue'
		}
	}
	assert m.meta.source_type == 'statsd'
}

fn test_parse_statsd_gauge() {
	m := parse_statsd('bar:42.5|g') or { panic(err.str()) }
	assert m.name == 'bar'
	assert m.kind == .absolute
	val := m.value
	match val {
		event.GaugeValue {
			assert val.value == 42.5
		}
		else {
			assert false, 'expected GaugeValue'
		}
	}
}

fn test_parse_statsd_set() {
	m := parse_statsd('unique:user123|s') or { panic(err.str()) }
	assert m.name == 'unique'
	assert m.kind == .incremental
	val := m.value
	match val {
		event.SetValue {
			assert val.values.len == 1
			assert val.values[0] == 'user123'
		}
		else {
			assert false, 'expected SetValue'
		}
	}
}

fn test_parse_statsd_timer() {
	m := parse_statsd('latency:320|ms') or { panic(err.str()) }
	assert m.name == 'latency'
	assert m.kind == .incremental
	val := m.value
	match val {
		event.DistributionValue {
			assert val.statistic == .histogram
			assert val.samples.len == 1
			assert val.samples[0].value == 320.0
			assert val.samples[0].rate == 1
		}
		else {
			assert false, 'expected DistributionValue'
		}
	}
}

fn test_parse_statsd_histogram() {
	m := parse_statsd('request_time:150|h') or { panic(err.str()) }
	assert m.name == 'request_time'
	assert m.kind == .incremental
	val := m.value
	match val {
		event.DistributionValue {
			assert val.statistic == .histogram
			assert val.samples.len == 1
			assert val.samples[0].value == 150.0
			assert val.samples[0].rate == 1
		}
		else {
			assert false, 'expected DistributionValue'
		}
	}
}

fn test_parse_statsd_with_tags() {
	m := parse_statsd('metric:1|c|#env:prod,host:web1') or { panic(err.str()) }
	assert m.name == 'metric'
	assert m.tags.len == 2
	assert m.tags['env'] == 'prod'
	assert m.tags['host'] == 'web1'
}

fn test_parse_statsd_with_sample_rate() {
	m := parse_statsd('metric:1|c|@0.5') or { panic(err.str()) }
	assert m.name == 'metric'
	val := m.value
	match val {
		event.CounterValue {
			assert val.value == 1.0
		}
		else {
			assert false, 'expected CounterValue'
		}
	}
}

fn test_parse_statsd_with_tags_and_rate() {
	m := parse_statsd('metric:1|c|@0.5|#tag:val') or { panic(err.str()) }
	assert m.name == 'metric'
	assert m.tags.len == 1
	assert m.tags['tag'] == 'val'
	val := m.value
	match val {
		event.CounterValue {
			assert val.value == 1.0
		}
		else {
			assert false, 'expected CounterValue'
		}
	}
}

fn test_parse_statsd_with_sample_rate_distribution() {
	// With sample_rate=0.5, rate should be u32(1.0/0.5) = 2
	m := parse_statsd('latency:100|ms|@0.5') or { panic(err.str()) }
	val := m.value
	match val {
		event.DistributionValue {
			assert val.samples[0].rate == 2
		}
		else {
			assert false, 'expected DistributionValue'
		}
	}
}

fn test_parse_statsd_invalid_no_colon() {
	if _ := parse_statsd('nocolon') {
		assert false, 'expected error for missing colon'
	}
}

fn test_parse_statsd_invalid_no_type() {
	if _ := parse_statsd('name:1') {
		assert false, 'expected error for missing type'
	}
}

fn test_parse_statsd_invalid_type() {
	if _ := parse_statsd('name:1|x') {
		assert false, 'expected error for unknown type'
	}
}

fn test_parse_statsd_empty_name() {
	if _ := parse_statsd(':1|c') {
		assert false, 'expected error for empty name'
	}
}

fn test_parse_statsd_tag_without_value() {
	m := parse_statsd('metric:1|c|#bare_tag') or { panic(err.str()) }
	assert m.tags.len == 1
	assert m.tags['bare_tag'] == ''
}

fn test_parse_statsd_invalid_sample_rate_zero() {
	// sample_rate <= 0 is treated as 1.0
	m := parse_statsd('latency:100|ms|@0') or { panic(err.str()) }
	val := m.value
	match val {
		event.DistributionValue {
			assert val.samples[0].rate == 1
		}
		else {
			assert false, 'expected DistributionValue'
		}
	}
}

fn test_parse_statsd_invalid_sample_rate_above_one() {
	// sample_rate > 1.0 is treated as 1.0
	m := parse_statsd('latency:100|ms|@2.0') or { panic(err.str()) }
	val := m.value
	match val {
		event.DistributionValue {
			assert val.samples[0].rate == 1
		}
		else {
			assert false, 'expected DistributionValue'
		}
	}
}

fn test_parse_statsd_gauge_float() {
	m := parse_statsd('temperature:98.6|g') or { panic(err.str()) }
	val := m.value
	match val {
		event.GaugeValue {
			assert val.value == 98.6
		}
		else {
			assert false, 'expected GaugeValue'
		}
	}
}

fn test_parse_statsd_counter_large_value() {
	m := parse_statsd('big:999999|c') or { panic(err.str()) }
	val := m.value
	match val {
		event.CounterValue {
			assert val.value == 999999.0
		}
		else {
			assert false, 'expected CounterValue'
		}
	}
}

fn test_new_statsd_defaults() {
	s := new_statsd({})
	assert s.mode == .udp
	assert s.address == '0.0.0.0:8125'
}

fn test_new_statsd_custom() {
	s := new_statsd({
		'mode':    'tcp'
		'address': '127.0.0.1:9000'
	})
	assert s.mode == .tcp
	assert s.address == '127.0.0.1:9000'
}

fn test_new_statsd_unknown_mode_defaults_udp() {
	s := new_statsd({
		'mode': 'invalid'
	})
	assert s.mode == .udp
}

fn test_statsd_source_registry() {
	src := build_source('statsd', {
		'address': '0.0.0.0:9999'
	}) or { panic(err.str()) }
	match src {
		StatsdSource {
			assert src.address == '0.0.0.0:9999'
		}
		else {
			assert false, 'expected StatsdSource'
		}
	}
}
