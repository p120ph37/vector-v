module sources

import event

fn test_parse_prometheus_counter() {
	text := '# TYPE http_requests counter\nhttp_requests_total{method="GET"} 1234\n'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'http_requests_total'
	val := m.value
	match val {
		event.CounterValue {
			assert val.value == 1234.0
		}
		else {
			assert false, 'expected CounterValue'
		}
	}
	assert m.tags['method'] == 'GET'
	assert m.kind == .absolute
}

fn test_parse_prometheus_gauge() {
	text := '# TYPE temperature gauge\ntemperature{location="office"} 22.5\n'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'temperature'
	val := m.value
	match val {
		event.GaugeValue {
			assert val.value == 22.5
		}
		else {
			assert false, 'expected GaugeValue'
		}
	}
	assert m.tags['location'] == 'office'
}

fn test_parse_prometheus_untyped() {
	text := 'some_metric 42\n'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'some_metric'
	val := m.value
	match val {
		event.GaugeValue {
			assert val.value == 42.0
		}
		else {
			assert false, 'expected GaugeValue for untyped metric'
		}
	}
}

fn test_parse_prometheus_histogram() {
	text := '# TYPE request_duration histogram
request_duration_bucket{le="0.5"} 10
request_duration_bucket{le="1.0"} 20
request_duration_bucket{le="+Inf"} 25
request_duration_count 25
request_duration_sum 15.5
'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'request_duration'
	val := m.value
	match val {
		event.HistogramValue {
			assert val.count == 25
			assert val.sum == 15.5
			assert val.buckets.len >= 2
		}
		else {
			assert false, 'expected HistogramValue'
		}
	}
}

fn test_parse_prometheus_summary() {
	text := '# TYPE rpc_duration summary
rpc_duration{quantile="0.5"} 0.05
rpc_duration{quantile="0.9"} 0.08
rpc_duration{quantile="0.99"} 0.1
rpc_duration_count 100
rpc_duration_sum 5.5
'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'rpc_duration'
	val := m.value
	match val {
		event.SummaryValue {
			assert val.count == 100
			assert val.sum == 5.5
			assert val.quantiles.len == 3
		}
		else {
			assert false, 'expected SummaryValue'
		}
	}
}

fn test_parse_prometheus_labels() {
	text := 'my_metric{key1="val1",key2="val2"} 10\n'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.tags['key1'] == 'val1'
	assert m.tags['key2'] == 'val2'
	assert m.tags.len == 2
}

fn test_parse_prometheus_no_labels() {
	text := 'metric_name 42\n'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'metric_name'
	assert m.tags.len == 0
	val := m.value
	match val {
		event.GaugeValue {
			assert val.value == 42.0
		}
		else {
			assert false, 'expected GaugeValue'
		}
	}
}

fn test_parse_prometheus_escaped_labels() {
	text := 'my_metric{msg="hello\\"world",path="a\\\\b",note="line\\none"} 1\n'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.tags['msg'] == 'hello"world'
	assert m.tags['path'] == 'a\\b'
	assert m.tags['note'] == 'line\none'
}

fn test_parse_prometheus_comments() {
	text := '# HELP http_requests Total HTTP requests
# TYPE http_requests counter
http_requests_total 99
'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'http_requests_total'
	val := m.value
	match val {
		event.CounterValue {
			assert val.value == 99.0
		}
		else {
			assert false, 'expected CounterValue'
		}
	}
}

fn test_parse_prometheus_empty_lines() {
	text := '\n\n# TYPE x gauge\n\nx 5\n\n'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'x'
	val := m.value
	match val {
		event.GaugeValue {
			assert val.value == 5.0
		}
		else {
			assert false, 'expected GaugeValue'
		}
	}
}

fn test_parse_prometheus_timestamp() {
	text := '# TYPE my_metric gauge\nmy_metric 42 1234567890000\n'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'my_metric'
	// Timestamp should be 1234567890 seconds (1234567890000 ms)
	// time.unix() returns microseconds in V
	assert m.timestamp.unix() / 1_000_000 == 1234567890
}

fn test_new_prometheus_source() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost:9090/metrics'
	src := new_prometheus(opts) or { panic(err.str()) }
	assert src.endpoints.len == 1
	assert src.endpoints[0] == 'http://localhost:9090/metrics'
	assert src.honor_labels == true
}

fn test_new_prometheus_source_missing_endpoint() {
	opts := map[string]string{}
	if _ := new_prometheus(opts) {
		assert false, 'expected error for missing endpoints'
	}
}

fn test_new_prometheus_source_auth_bearer() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost:9090/metrics'
	opts['auth.token'] = 'my-secret-token'
	src := new_prometheus(opts) or { panic(err.str()) }
	assert src.auth_header == 'Bearer my-secret-token'
}

fn test_new_prometheus_source_auth_basic() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost:9090/metrics'
	opts['auth.user'] = 'admin'
	opts['auth.password'] = 'pass'
	src := new_prometheus(opts) or { panic(err.str()) }
	assert src.auth_header.starts_with('Basic ')
}

fn test_new_prometheus_source_multiple_endpoints() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://host1:9090/metrics, http://host2:9090/metrics'
	src := new_prometheus(opts) or { panic(err.str()) }
	assert src.endpoints.len == 2
	assert src.endpoints[0] == 'http://host1:9090/metrics'
	assert src.endpoints[1] == 'http://host2:9090/metrics'
}

fn test_new_prometheus_source_empty_endpoints() {
	mut opts := map[string]string{}
	opts['endpoints'] = '  ,  ,  '
	if _ := new_prometheus(opts) {
		assert false, 'expected error for empty endpoints'
	}
}

fn test_new_prometheus_source_scrape_interval() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost:9090/metrics'
	opts['scrape_interval_secs'] = '30'
	src := new_prometheus(opts) or { panic(err.str()) }
	assert src.scrape_interval == 30_000_000_000 // 30 seconds in nanoseconds
}

fn test_new_prometheus_source_honor_labels_false() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost:9090/metrics'
	opts['honor_labels'] = 'false'
	src := new_prometheus(opts) or { panic(err.str()) }
	assert src.honor_labels == false
}

fn test_new_prometheus_source_instance() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost:9090/metrics'
	opts['instance'] = 'myhost:9090'
	src := new_prometheus(opts) or { panic(err.str()) }
	assert src.instance == 'myhost:9090'
}

fn test_new_prometheus_source_negative_scrape_interval() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost:9090/metrics'
	opts['scrape_interval_secs'] = '-5'
	src := new_prometheus(opts) or { panic(err.str()) }
	// Negative should default to 15 seconds
	assert src.scrape_interval == 15_000_000_000
}

fn test_prometheus_source_registry() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost:9090/metrics'
	s := build_source('prometheus', opts) or { panic(err.str()) }
	assert s is PrometheusSource
}

fn test_prometheus_scrape_source_registry() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost:9090/metrics'
	s := build_source('prometheus_scrape', opts) or { panic(err.str()) }
	assert s is PrometheusSource
}

fn test_parse_labels_empty() {
	labels := parse_labels('')
	assert labels.len == 0
}

fn test_parse_labels_single() {
	labels := parse_labels('key="value"')
	assert labels.len == 1
	assert labels['key'] == 'value'
}

fn test_parse_labels_multiple() {
	labels := parse_labels('a="1",b="2",c="3"')
	assert labels.len == 3
	assert labels['a'] == '1'
	assert labels['b'] == '2'
	assert labels['c'] == '3'
}

fn test_get_base_metric_name_bucket() {
	assert get_base_metric_name('request_duration_bucket') == 'request_duration'
}

fn test_get_base_metric_name_count() {
	assert get_base_metric_name('request_duration_count') == 'request_duration'
}

fn test_get_base_metric_name_sum() {
	assert get_base_metric_name('request_duration_sum') == 'request_duration'
}

fn test_get_base_metric_name_total() {
	assert get_base_metric_name('http_requests_total') == 'http_requests'
}

fn test_get_base_metric_name_created() {
	assert get_base_metric_name('my_metric_created') == 'my_metric'
}

fn test_get_base_metric_name_info() {
	assert get_base_metric_name('build_info') == 'build'
}

fn test_get_base_metric_name_no_suffix() {
	assert get_base_metric_name('simple_metric') == 'simple_metric'
}

fn test_filter_tag() {
	tags := {
		'a': '1'
		'b': '2'
		'c': '3'
	}
	result := filter_tag(tags, 'b')
	assert result.len == 2
	assert result['a'] == '1'
	assert result['c'] == '3'
	assert 'b' !in result
}

fn test_filter_tag_nonexistent() {
	tags := {
		'a': '1'
	}
	result := filter_tag(tags, 'z')
	assert result.len == 1
	assert result['a'] == '1'
}

fn test_make_family_key() {
	tags := {
		'method': 'GET'
		'le':     '0.5'
	}
	key := make_family_key('request_duration', tags, 'le')
	assert key.contains('request_duration')
	assert key.contains('method=GET')
	assert !key.contains('le=')
}

fn test_prom_base64() {
	assert prom_base64('') == ''
	assert prom_base64('f') == 'Zg=='
	assert prom_base64('fo') == 'Zm8='
	assert prom_base64('foo') == 'Zm9v'
	assert prom_base64('foobar') == 'Zm9vYmFy'
}

fn test_parse_prometheus_text_empty() {
	metrics := parse_prometheus_text('')
	assert metrics.len == 0
}

fn test_parse_prometheus_text_only_comments() {
	text := '# HELP some help text
# TYPE some_metric gauge
# another comment
'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 0
}

fn test_parse_prometheus_multiple_metrics() {
	text := '# TYPE a gauge
# TYPE b counter
a 10
b_total 20
'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 2
}

fn test_parse_prometheus_histogram_with_labels() {
	text := '# TYPE req histogram
req_bucket{host="a",le="0.1"} 5
req_bucket{host="a",le="1.0"} 15
req_bucket{host="a",le="+Inf"} 20
req_count{host="a"} 20
req_sum{host="a"} 8.5
'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'req'
	assert m.tags['host'] == 'a'
	// le should be filtered out
	assert 'le' !in m.tags
}

fn test_parse_prometheus_summary_with_labels() {
	text := '# TYPE latency summary
latency{host="b",quantile="0.5"} 0.02
latency{host="b",quantile="0.99"} 0.1
latency_count{host="b"} 50
latency_sum{host="b"} 3.0
'
	metrics := parse_prometheus_text(text)
	assert metrics.len == 1
	m := metrics[0]
	assert m.name == 'latency'
	assert m.tags['host'] == 'b'
	assert 'quantile' !in m.tags
	val := m.value
	match val {
		event.SummaryValue {
			assert val.quantiles.len == 2
			assert val.count == 50
			assert val.sum == 3.0
		}
		else {
			assert false, 'expected SummaryValue'
		}
	}
}

fn test_parse_prometheus_line_invalid_no_value() {
	types := map[string]string{}
	if _ := parse_prometheus_line('metric_no_value', types) {
		assert false, 'expected error'
	}
}

fn test_parse_prometheus_line_unmatched_brace() {
	types := map[string]string{}
	if _ := parse_prometheus_line('metric{label="val" 123', types) {
		assert false, 'expected error for unmatched brace'
	}
}

fn test_parse_prometheus_line_counter() {
	types := {
		'http_requests': 'counter'
	}
	m := parse_prometheus_line('http_requests_total{method="POST"} 55', types) or {
		panic(err.str())
	}
	assert m.name == 'http_requests_total'
	val := m.value
	match val {
		event.CounterValue {
			assert val.value == 55.0
		}
		else {
			assert false, 'expected CounterValue'
		}
	}
}

fn test_parse_prometheus_line_gauge_no_labels() {
	types := {
		'cpu_temp': 'gauge'
	}
	m := parse_prometheus_line('cpu_temp 72.5', types) or { panic(err.str()) }
	assert m.name == 'cpu_temp'
	assert m.tags.len == 0
	val := m.value
	match val {
		event.GaugeValue {
			assert val.value == 72.5
		}
		else {
			assert false, 'expected GaugeValue'
		}
	}
}

fn test_parse_prometheus_line_with_timestamp() {
	types := map[string]string{}
	m := parse_prometheus_line('my_metric 99 1609459200000', types) or { panic(err.str()) }
	assert m.name == 'my_metric'
	assert m.timestamp.unix() / 1_000_000 == 1609459200
}

fn test_merge_metric_families_no_histogram_summary() {
	metrics := [
		event.Metric{
			name: 'simple'
			value: event.GaugeValue{value: 1.0}
		},
	]
	types := map[string]string{}
	result := merge_metric_families(metrics, types)
	assert result.len == 1
	assert result[0].name == 'simple'
}
