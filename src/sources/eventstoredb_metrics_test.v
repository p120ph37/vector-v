module sources

// --- Constructor tests ---

fn test_new_eventstoredb_metrics_defaults() {
	s := new_eventstoredb_metrics(map[string]string{})
	assert s.endpoint == 'http://localhost:2113'
	assert s.scrape_interval == 15_000_000_000 // 15 seconds in nanoseconds
	assert s.namespace == 'eventstoredb'
}

fn test_new_eventstoredb_metrics_custom_endpoint() {
	s := new_eventstoredb_metrics({
		'endpoint': 'http://esdb.local:2113'
	})
	assert s.endpoint == 'http://esdb.local:2113'
}

fn test_new_eventstoredb_metrics_custom_interval() {
	s := new_eventstoredb_metrics({
		'scrape_interval_secs': '30'
	})
	assert s.scrape_interval == 30_000_000_000
}

fn test_new_eventstoredb_metrics_negative_interval_clamps() {
	s := new_eventstoredb_metrics({
		'scrape_interval_secs': '-5'
	})
	// Negative should default to 15 seconds
	assert s.scrape_interval == 15_000_000_000
}

fn test_new_eventstoredb_metrics_zero_interval_clamps() {
	s := new_eventstoredb_metrics({
		'scrape_interval_secs': '0'
	})
	// Zero should default to 15 seconds
	assert s.scrape_interval == 15_000_000_000
}

fn test_new_eventstoredb_metrics_custom_namespace() {
	s := new_eventstoredb_metrics({
		'namespace': 'mydb'
	})
	assert s.namespace == 'mydb'
}

fn test_new_eventstoredb_metrics_all_options() {
	s := new_eventstoredb_metrics({
		'endpoint':              'http://esdb.prod:2113'
		'scrape_interval_secs':  '60'
		'namespace':             'prod_esdb'
	})
	assert s.endpoint == 'http://esdb.prod:2113'
	assert s.scrape_interval == 60_000_000_000
	assert s.namespace == 'prod_esdb'
}

// --- Parse tests ---

fn test_parse_eventstoredb_stats_basic() {
	content := '{
		"proc-cpu": 12.5,
		"proc-mem": 1073741824,
		"proc-threadsCount": 8,
		"sys-cpu": 45.2,
		"sys-freeMem": 4294967296,
		"es-queue-MainQueue-length": 100,
		"es-readOps": 500,
		"es-writeOps": 250
	}'
	stats := parse_eventstoredb_stats(content)
	assert stats.proc_cpu == 12.5
	assert stats.proc_mem == 1073741824.0
	assert stats.proc_threads_count == 8.0
	assert stats.sys_cpu == 45.2
	assert stats.sys_free_mem == 4294967296.0
	assert stats.queue_length_main == 100.0
	assert stats.es_read_ops == 500.0
	assert stats.es_write_ops == 250.0
}

fn test_parse_eventstoredb_stats_empty() {
	stats := parse_eventstoredb_stats('{}')
	assert stats.proc_cpu == 0.0
	assert stats.proc_mem == 0.0
	assert stats.proc_threads_count == 0.0
	assert stats.sys_cpu == 0.0
	assert stats.sys_free_mem == 0.0
	assert stats.queue_length_main == 0.0
	assert stats.es_read_ops == 0.0
	assert stats.es_write_ops == 0.0
}

fn test_parse_eventstoredb_stats_partial() {
	content := '{
		"proc-cpu": 5.0,
		"es-writeOps": 42
	}'
	stats := parse_eventstoredb_stats(content)
	assert stats.proc_cpu == 5.0
	assert stats.proc_mem == 0.0
	assert stats.proc_threads_count == 0.0
	assert stats.sys_cpu == 0.0
	assert stats.sys_free_mem == 0.0
	assert stats.queue_length_main == 0.0
	assert stats.es_read_ops == 0.0
	assert stats.es_write_ops == 42.0
}

// --- extract_esdb_f64 tests ---

fn test_extract_esdb_f64_basic() {
	content := '{"proc-cpu": 75.3, "proc-mem": 1024}'
	assert extract_esdb_f64(content, 'proc-cpu') == 75.3
	assert extract_esdb_f64(content, 'proc-mem') == 1024.0
}

fn test_extract_esdb_f64_missing() {
	content := '{"proc-cpu": 10.0}'
	assert extract_esdb_f64(content, 'nonexistent') == 0.0
}

fn test_extract_esdb_f64_negative() {
	content := '{"proc-cpu": -3.14}'
	assert extract_esdb_f64(content, 'proc-cpu') == -3.14
}
