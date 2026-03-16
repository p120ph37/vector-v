module sources

import event

fn test_new_internal_metrics_defaults() {
	s := new_internal_metrics({})
	assert s.scrape_interval == 2_000_000_000 // 2 seconds in nanoseconds
}

fn test_new_internal_metrics_custom_interval() {
	s := new_internal_metrics({
		'scrape_interval_secs': '5'
	})
	assert s.scrape_interval == 5_000_000_000
}

fn test_new_internal_metrics_negative_interval() {
	s := new_internal_metrics({
		'scrape_interval_secs': '-1'
	})
	// Should default to 2 seconds
	assert s.scrape_interval == 2_000_000_000
}

fn test_new_internal_metrics_zero_interval() {
	s := new_internal_metrics({
		'scrape_interval_secs': '0'
	})
	assert s.scrape_interval == 2_000_000_000
}

fn test_register_and_increment_counter() {
	reset_internal_metrics_registry()
	register_internal_counter('events_processed_total', 'src_stdin', 'stdin', 'source')
	increment_internal_counter('events_processed_total', 'src_stdin', 10.0)

	key := 'events_processed_total|src_stdin'
	assert key in internal_metrics_registry.counters
	assert internal_metrics_registry.counters[key].value == 10.0
}

fn test_increment_counter_accumulates() {
	reset_internal_metrics_registry()
	register_internal_counter('bytes_processed_total', 'src_demo', 'demo_logs', 'source')
	increment_internal_counter('bytes_processed_total', 'src_demo', 100.0)
	increment_internal_counter('bytes_processed_total', 'src_demo', 200.0)

	key := 'bytes_processed_total|src_demo'
	assert internal_metrics_registry.counters[key].value == 300.0
}

fn test_register_and_set_gauge() {
	reset_internal_metrics_registry()
	register_internal_gauge('buffer_size', 'sink_http', 'http', 'sink')
	set_internal_gauge('buffer_size', 'sink_http', 42.0)

	key := 'buffer_size|sink_http'
	assert key in internal_metrics_registry.gauges
	assert internal_metrics_registry.gauges[key].value == 42.0
}

fn test_set_gauge_overwrites() {
	reset_internal_metrics_registry()
	register_internal_gauge('queue_depth', 'xf_remap', 'remap', 'transform')
	set_internal_gauge('queue_depth', 'xf_remap', 10.0)
	set_internal_gauge('queue_depth', 'xf_remap', 5.0)

	key := 'queue_depth|xf_remap'
	assert internal_metrics_registry.gauges[key].value == 5.0
}

fn test_counter_tags_match_upstream_format() {
	reset_internal_metrics_registry()
	register_internal_counter('component_received_events_total', 'my_source', 'stdin', 'source')

	key := 'component_received_events_total|my_source'
	tags := internal_metrics_registry.counters[key].tags.clone()
	assert tags['component_id'] == 'my_source'
	assert tags['component_type'] == 'stdin'
	assert tags['component_kind'] == 'source'
}

fn test_gauge_tags_match_upstream_format() {
	reset_internal_metrics_registry()
	register_internal_gauge('uptime_seconds', 'global', 'internal_metrics', 'source')

	key := 'uptime_seconds|global'
	tags := internal_metrics_registry.gauges[key].tags.clone()
	assert tags['component_id'] == 'global'
	assert tags['component_type'] == 'internal_metrics'
	assert tags['component_kind'] == 'source'
}

fn test_collect_snapshot_has_uptime() {
	reset_internal_metrics_registry()
	metrics := collect_internal_metrics_snapshot()
	// Should always have at least uptime_seconds
	assert metrics.len >= 1
	uptime := metrics[0]
	assert uptime.name == 'uptime_seconds'
	assert uptime.namespace == 'vector'
	assert uptime.meta.source_type == 'internal_metrics'
}

fn test_collect_snapshot_uptime_is_gauge() {
	reset_internal_metrics_registry()
	metrics := collect_internal_metrics_snapshot()
	uptime := metrics[0]
	assert uptime.kind == .absolute
	val := uptime.value
	match val {
		event.GaugeValue {
			// uptime should be >= 0
			assert val.value >= 0.0
		}
		else {
			assert false, 'expected GaugeValue for uptime_seconds'
		}
	}
}

fn test_collect_snapshot_includes_counters() {
	reset_internal_metrics_registry()
	register_internal_counter('events_processed_total', 'src1', 'stdin', 'source')
	increment_internal_counter('events_processed_total', 'src1', 50.0)

	metrics := collect_internal_metrics_snapshot()
	// uptime + 1 counter = 2
	assert metrics.len == 2
	counter_metric := metrics[1]
	assert counter_metric.name == 'events_processed_total'
	assert counter_metric.namespace == 'vector'
	assert counter_metric.kind == .incremental
	val := counter_metric.value
	match val {
		event.CounterValue {
			assert val.value == 50.0
		}
		else {
			assert false, 'expected CounterValue'
		}
	}
}

fn test_collect_snapshot_includes_gauges() {
	reset_internal_metrics_registry()
	register_internal_gauge('buffer_bytes', 'sink1', 'http', 'sink')
	set_internal_gauge('buffer_bytes', 'sink1', 1024.0)

	metrics := collect_internal_metrics_snapshot()
	// uptime + 1 gauge = 2
	assert metrics.len == 2
	gauge_metric := metrics[1]
	assert gauge_metric.name == 'buffer_bytes'
	assert gauge_metric.namespace == 'vector'
	assert gauge_metric.kind == .absolute
	val := gauge_metric.value
	match val {
		event.GaugeValue {
			assert val.value == 1024.0
		}
		else {
			assert false, 'expected GaugeValue'
		}
	}
}

fn test_collect_snapshot_counter_has_component_tags() {
	reset_internal_metrics_registry()
	register_internal_counter('component_sent_events_total', 'my_sink', 'console', 'sink')
	increment_internal_counter('component_sent_events_total', 'my_sink', 1.0)

	metrics := collect_internal_metrics_snapshot()
	counter_metric := metrics[1]
	assert counter_metric.tags['component_id'] == 'my_sink'
	assert counter_metric.tags['component_type'] == 'console'
	assert counter_metric.tags['component_kind'] == 'sink'
}

fn test_collect_snapshot_all_standard_metrics() {
	reset_internal_metrics_registry()

	// Register all standard upstream metrics
	register_internal_counter('events_processed_total', 'src', 'stdin', 'source')
	register_internal_counter('bytes_processed_total', 'src', 'stdin', 'source')
	register_internal_counter('component_errors_total', 'src', 'stdin', 'source')
	register_internal_counter('component_received_events_total', 'src', 'stdin', 'source')
	register_internal_counter('component_sent_events_total', 'src', 'stdin', 'source')

	metrics := collect_internal_metrics_snapshot()
	// 1 uptime gauge + 5 counters = 6
	assert metrics.len == 6

	mut names := []string{}
	for m in metrics {
		names << m.name
		// All should have namespace "vector"
		assert m.namespace == 'vector'
		// All should have source_type "internal_metrics"
		assert m.meta.source_type == 'internal_metrics'
	}
	assert 'uptime_seconds' in names
	assert 'events_processed_total' in names
	assert 'bytes_processed_total' in names
	assert 'component_errors_total' in names
	assert 'component_received_events_total' in names
	assert 'component_sent_events_total' in names
}

fn test_increment_unregistered_counter_is_noop() {
	reset_internal_metrics_registry()
	// Should not panic or add anything
	increment_internal_counter('nonexistent', 'id', 1.0)
	assert internal_metrics_registry.counters.len == 0
}

fn test_set_unregistered_gauge_is_noop() {
	reset_internal_metrics_registry()
	set_internal_gauge('nonexistent', 'id', 1.0)
	assert internal_metrics_registry.gauges.len == 0
}

fn test_reset_registry_clears_all() {
	register_internal_counter('test_counter', 'c1', 'demo', 'source')
	register_internal_gauge('test_gauge', 'g1', 'demo', 'source')
	reset_internal_metrics_registry()
	assert internal_metrics_registry.counters.len == 0
	assert internal_metrics_registry.gauges.len == 0
}
