module sinks

import event
import time

fn test_new_influxdb_defaults() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'myorg'
		'bucket':   'mybucket'
		'token':    'my-token'
	}) or { panic(err.str()) }
	assert s.endpoint == 'http://localhost:8086'
	assert s.org == 'myorg'
	assert s.bucket == 'mybucket'
	assert s.token == 'my-token'
	assert s.measurement == 'logs'
	assert s.batch_max == 100
}

fn test_new_influxdb_missing_endpoint() {
	new_influxdb({
		'org':    'myorg'
		'bucket': 'mybucket'
		'token':  'tok'
	}) or {
		assert err.msg().contains('endpoint is required')
		return
	}
	assert false, 'expected error for missing endpoint'
}

fn test_new_influxdb_missing_org() {
	new_influxdb({
		'endpoint': 'http://localhost:8086'
		'bucket':   'mybucket'
		'token':    'tok'
	}) or {
		assert err.msg().contains('org is required')
		return
	}
	assert false, 'expected error for missing org'
}

fn test_new_influxdb_missing_bucket() {
	new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'myorg'
		'token':    'tok'
	}) or {
		assert err.msg().contains('bucket is required')
		return
	}
	assert false, 'expected error for missing bucket'
}

fn test_new_influxdb_missing_token() {
	new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'myorg'
		'bucket':   'mybucket'
	}) or {
		assert err.msg().contains('token is required')
		return
	}
	assert false, 'expected error for missing token'
}

fn test_new_influxdb_custom() {
	s := new_influxdb({
		'endpoint':           'http://influx.example.com:8086/'
		'org':                'custom-org'
		'bucket':             'custom-bucket'
		'token':              'custom-token'
		'measurement':        'app_logs'
		'batch.max_events':   '50'
		'batch.timeout_secs': '10'
	}) or { panic(err.str()) }
	assert s.endpoint == 'http://influx.example.com:8086'
	assert s.org == 'custom-org'
	assert s.bucket == 'custom-bucket'
	assert s.token == 'custom-token'
	assert s.measurement == 'app_logs'
	assert s.batch_max == 50
}

fn test_influxdb_batch_invalid() {
	s := new_influxdb({
		'endpoint':           'http://localhost:8086'
		'org':                'o'
		'bucket':             'b'
		'token':              't'
		'batch.max_events':   '-1'
		'batch.timeout_secs': '-5'
	}) or { panic(err.str()) }
	assert s.batch_max == 100
}

fn test_influxdb_send_buffers() {
	mut s := new_influxdb({
		'endpoint':         'http://localhost:8086'
		'org':              'o'
		'bucket':           'b'
		'token':            't'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 3
}

fn test_influxdb_total_buffered() {
	mut s := new_influxdb({
		'endpoint':         'http://localhost:8086'
		'org':              'o'
		'bucket':           'b'
		'token':            't'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	s.send(ev) or {}
	assert s.total_buffered() == 2
}

fn test_influxdb_flush_empty() {
	mut s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_influxdb_encode_counter_metric() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'http_requests'
		kind: .incremental
		value: event.CounterValue{value: 42.0}
		tags: {
			'method': 'GET'
			'host':   'web1'
		}
		timestamp: time.unix(1000)
	}
	line := s.encode_line_protocol(event.Event(m))
	assert line.contains('http_requests')
	assert line.contains('method=GET')
	assert line.contains('host=web1')
	assert line.contains('value=42')
}

fn test_influxdb_encode_gauge_metric() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'temperature'
		kind: .absolute
		value: event.GaugeValue{value: 22.5}
		timestamp: time.unix(2000)
	}
	line := s.encode_line_protocol(event.Event(m))
	assert line.contains('temperature')
	assert line.contains('value=22.5')
}

fn test_influxdb_encode_metric_with_namespace() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'requests'
		namespace: 'myapp'
		kind: .incremental
		value: event.CounterValue{value: 1.0}
		timestamp: time.unix(1000)
	}
	line := s.encode_line_protocol(event.Event(m))
	assert line.contains('myapp.requests')
}

fn test_influxdb_encode_log() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('hello world'))
	line := s.encode_line_protocol(ev)
	assert line.contains('logs')
	assert line.contains('message="hello world"')
}

fn test_influxdb_encode_log_custom_measurement() {
	s := new_influxdb({
		'endpoint':    'http://localhost:8086'
		'org':         'o'
		'bucket':      'b'
		'token':       't'
		'measurement': 'app_events'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('test'))
	line := s.encode_line_protocol(ev)
	assert line.contains('app_events')
}

fn test_influxdb_encode_set_metric() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'unique_users'
		kind: .absolute
		value: event.SetValue{values: ['alice', 'bob']}
		timestamp: time.unix(1000)
	}
	line := s.encode_line_protocol(event.Event(m))
	assert line.contains('unique_users')
	assert line.contains('count=2i')
}

fn test_influxdb_encode_histogram_metric() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'request_duration'
		kind: .absolute
		value: event.HistogramValue{
			buckets: [event.Bucket{upper_limit: 0.5, count: 10}]
			count: 15
			sum: 7.5
		}
		timestamp: time.unix(1000)
	}
	line := s.encode_line_protocol(event.Event(m))
	assert line.contains('request_duration')
	assert line.contains('sum=7.5')
	assert line.contains('count=15i')
}

fn test_influxdb_encode_summary_metric() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'latency'
		kind: .absolute
		value: event.SummaryValue{
			quantiles: [event.Quantile{quantile: 0.5, value: 0.1}]
			count: 100
			sum: 50.0
		}
		timestamp: time.unix(1000)
	}
	line := s.encode_line_protocol(event.Event(m))
	assert line.contains('latency')
	assert line.contains('sum=50')
	assert line.contains('count=100i')
}

fn test_influxdb_encode_distribution_metric() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
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
	line := s.encode_line_protocol(event.Event(m))
	assert line.contains('dist')
	assert line.contains('sum=5')
	assert line.contains('count=3i')
}

fn test_influxdb_encode_trace() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }

	ev := event.Event(event.TraceEvent{})
	line := s.encode_line_protocol(ev)
	assert line.contains('trace=true')
}

fn test_escape_lp_measurement_basic() {
	assert escape_lp_measurement('cpu') == 'cpu'
	assert escape_lp_measurement('cpu load') == 'cpu\\ load'
	assert escape_lp_measurement('cpu,load') == 'cpu\\,load'
}

fn test_escape_lp_key_basic() {
	assert escape_lp_key('host') == 'host'
	assert escape_lp_key('host name') == 'host\\ name'
	assert escape_lp_key('host,name') == 'host\\,name'
	assert escape_lp_key('host=name') == 'host\\=name'
}

fn test_escape_lp_tag_value_basic() {
	assert escape_lp_tag_value('web1') == 'web1'
	assert escape_lp_tag_value('web 1') == 'web\\ 1'
}

fn test_escape_lp_field_value_basic() {
	assert escape_lp_field_value('hello') == 'hello'
	assert escape_lp_field_value('say "hi"') == 'say \\"hi\\"'
	assert escape_lp_field_value('back\\slash') == 'back\\\\slash'
}

fn test_influxdb_registry() {
	sink := build_sink('influxdb', {
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }
	match sink {
		InfluxDbSink {
			assert sink.endpoint == 'http://localhost:8086'
			assert sink.org == 'o'
		}
		else {
			assert false, 'expected InfluxDbSink'
		}
	}
}

fn test_influxdb_registry_metrics() {
	sink := build_sink('influxdb_metrics', {
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }
	assert sink is InfluxDbSink
}

fn test_influxdb_registry_logs() {
	sink := build_sink('influxdb_logs', {
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }
	assert sink is InfluxDbSink
}

fn test_influxdb_send_metric_buffers() {
	mut s := new_influxdb({
		'endpoint':         'http://localhost:8086'
		'org':              'o'
		'bucket':           'b'
		'token':            't'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.GaugeValue{value: 99.0}
		timestamp: time.now()
	}
	s.send(event.Event(m)) or {}
	assert s.total_buffered() == 1
	s.send(event.Event(m)) or {}
	assert s.total_buffered() == 2
}

fn test_influxdb_encode_metric_special_chars_in_tags() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.GaugeValue{value: 50.0}
		tags: {
			'host name': 'web,1'
		}
		timestamp: time.unix(1000)
	}
	line := s.encode_line_protocol(event.Event(m))
	assert line.contains('host\\ name=web\\,1')
}

fn test_influxdb_encode_log_special_chars() {
	s := new_influxdb({
		'endpoint': 'http://localhost:8086'
		'org':      'o'
		'bucket':   'b'
		'token':    't'
	}) or { panic(err.str()) }

	ev := event.Event(event.new_log('say "hello"'))
	line := s.encode_line_protocol(ev)
	assert line.contains('message="say \\"hello\\""')
}
