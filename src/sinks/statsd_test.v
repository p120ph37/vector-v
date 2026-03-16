module sinks

import event
import time

fn test_format_statsd_counter() {
	m := event.Metric{
		name: 'requests'
		kind: .incremental
		value: event.CounterValue{value: 5.0}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 1
	assert lines[0] == 'requests:5.0|c'
}

fn test_format_statsd_gauge() {
	m := event.Metric{
		name: 'temperature'
		kind: .absolute
		value: event.GaugeValue{value: 42.5}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 1
	assert lines[0] == 'temperature:42.5|g'
}

fn test_format_statsd_set() {
	m := event.Metric{
		name: 'users'
		kind: .incremental
		value: event.SetValue{values: ['alice', 'bob']}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 2
	assert lines[0] == 'users:alice|s'
	assert lines[1] == 'users:bob|s'
}

fn test_format_statsd_distribution() {
	m := event.Metric{
		name: 'latency'
		kind: .incremental
		value: event.DistributionValue{
			samples: [
				event.Sample{value: 100.0, rate: 1},
				event.Sample{value: 200.0, rate: 1},
			]
			statistic: .histogram
		}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 2
	assert lines[0] == 'latency:100.0|h'
	assert lines[1] == 'latency:200.0|h'
}

fn test_format_statsd_with_tags() {
	m := event.Metric{
		name: 'requests'
		kind: .incremental
		value: event.CounterValue{value: 1.0}
		tags: {
			'env': 'prod'
		}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 1
	assert lines[0].contains('|#env:prod')
	assert lines[0].starts_with('requests:1.0|c')
}

fn test_format_statsd_with_namespace() {
	m := event.Metric{
		name: 'requests'
		kind: .incremental
		value: event.CounterValue{value: 1.0}
		timestamp: time.now()
	}
	lines := format_statsd(m, 'myapp')
	assert lines.len == 1
	assert lines[0] == 'myapp.requests:1.0|c'
}

fn test_format_statsd_with_metric_namespace() {
	m := event.Metric{
		name: 'requests'
		namespace: 'service'
		kind: .incremental
		value: event.CounterValue{value: 1.0}
		timestamp: time.now()
	}
	// Metric's own namespace takes priority over default_namespace
	lines := format_statsd(m, 'default_ns')
	assert lines.len == 1
	assert lines[0] == 'service.requests:1.0|c'
}

fn test_format_statsd_histogram_value() {
	m := event.Metric{
		name: 'duration'
		kind: .incremental
		value: event.HistogramValue{
			buckets: [event.Bucket{upper_limit: 100.0, count: 5}]
			count: 5
			sum: 250.0
		}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 1
	assert lines[0] == 'duration:250.0|h'
}

fn test_format_statsd_summary_value() {
	m := event.Metric{
		name: 'latency'
		kind: .incremental
		value: event.SummaryValue{
			quantiles: [event.Quantile{quantile: 0.99, value: 500.0}]
			count: 100
			sum: 30000.0
		}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 1
	assert lines[0] == 'latency:30000.0|h'
}

fn test_format_statsd_empty_set() {
	m := event.Metric{
		name: 'users'
		kind: .incremental
		value: event.SetValue{values: []}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 0
}

fn test_format_statsd_tag_without_value() {
	m := event.Metric{
		name: 'requests'
		kind: .incremental
		value: event.CounterValue{value: 1.0}
		tags: {
			'bare': ''
		}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 1
	assert lines[0].contains('|#bare')
	// bare tag without value should NOT have a colon
	assert !lines[0].contains('bare:')
}

fn test_format_statsd_multiple_tags() {
	m := event.Metric{
		name: 'req'
		kind: .incremental
		value: event.CounterValue{value: 1.0}
		tags: {
			'env':  'prod'
			'host': 'web1'
		}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 1
	// Tags should be comma-separated after |#
	assert lines[0].contains('|#')
	assert lines[0].contains('env:prod')
	assert lines[0].contains('host:web1')
}

fn test_new_statsd_sink_defaults() {
	s := new_statsd_sink({}) or { panic(err.str()) }
	assert s.mode == .udp
	assert s.address == '127.0.0.1:8125'
	assert s.default_namespace == ''
	assert s.batch_max == 100
}

fn test_new_statsd_sink_custom() {
	s := new_statsd_sink({
		'mode':               'tcp'
		'address':            '10.0.0.1:9125'
		'default_namespace':  'myapp'
		'batch.max_events':   '50'
		'batch.timeout_secs': '5'
	}) or { panic(err.str()) }
	assert s.mode == .tcp
	assert s.address == '10.0.0.1:9125'
	assert s.default_namespace == 'myapp'
	assert s.batch_max == 50
}

fn test_new_statsd_sink_invalid_batch_max() {
	s := new_statsd_sink({
		'batch.max_events': '-1'
	}) or { panic(err.str()) }
	assert s.batch_max == 100
}

fn test_new_statsd_sink_invalid_batch_timeout() {
	s := new_statsd_sink({
		'batch.timeout_secs': '-1'
	}) or { panic(err.str()) }
	// Negative timeout resets to 1.0s = 1_000_000_000 ns
	assert s.batch_timeout == 1 * time.second
}

fn test_new_statsd_sink_unknown_mode_defaults_udp() {
	s := new_statsd_sink({
		'mode': 'invalid'
	}) or { panic(err.str()) }
	assert s.mode == .udp
}

fn test_statsd_sink_send_non_metric() {
	mut s := new_statsd_sink({}) or { panic(err.str()) }
	log_ev := event.new_log('hello world')
	// LogEvent should be silently dropped, no error
	s.send(event.Event(log_ev)) or { panic(err.str()) }
	assert s.total_buffered() == 0
}

fn test_statsd_sink_buffering() {
	mut s := new_statsd_sink({
		'batch.max_events': '1000'
	}) or { panic(err.str()) }

	m := event.Metric{
		name: 'test'
		kind: .incremental
		value: event.CounterValue{value: 1.0}
		timestamp: time.now()
	}
	// Send without actually flushing (batch won't be full)
	s.send(event.Event(m)) or {
		// flush may fail because no server is running, but buffering should work
	}
	assert s.total_buffered() >= 1
}

fn test_statsd_sink_close() {
	mut s := new_statsd_sink({}) or { panic(err.str()) }
	// Close should be safe even when not connected
	s.close()
	assert s.connected == false
	assert s.tcp_fd == -1
}

fn test_statsd_sink_flush_empty() {
	mut s := new_statsd_sink({}) or { panic(err.str()) }
	// Flushing with empty buffer should be a no-op
	s.flush() or { panic(err.str()) }
	assert s.total_buffered() == 0
}

fn test_statsd_sink_registry() {
	sink := build_sink('statsd', {
		'address': '127.0.0.1:9999'
	}) or { panic(err.str()) }
	match sink {
		StatsdSink {
			assert sink.address == '127.0.0.1:9999'
		}
		else {
			assert false, 'expected StatsdSink'
		}
	}
}

fn test_format_statsd_no_tags() {
	// Verify no tag suffix when tags map is empty
	m := event.Metric{
		name: 'simple'
		kind: .absolute
		value: event.GaugeValue{value: 10.0}
		timestamp: time.now()
	}
	lines := format_statsd(m, '')
	assert lines.len == 1
	assert lines[0] == 'simple:10.0|g'
	assert !lines[0].contains('#')
}
