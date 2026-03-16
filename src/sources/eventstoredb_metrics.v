module sources

import event
import net.http
import time

// EventStoreDbMetricsSource polls an EventStoreDB /stats endpoint at configurable
// intervals and emits metric events. Mirrors Vector's eventstoredb_metrics source.
//
// Config options:
//   endpoint:              EventStoreDB stats URL (default: http://localhost:2113)
//   scrape_interval_secs:  Polling interval in seconds (default: 15)
//   namespace:             Metric namespace prefix (default: "eventstoredb")
pub struct EventStoreDbMetricsSource {
	endpoint        string        = 'http://localhost:2113'
	scrape_interval time.Duration = 15 * time.second
	namespace       string        = 'eventstoredb'
}

// EventStoreDbStats holds parsed stats from the EventStoreDB /stats JSON response.
pub struct EventStoreDbStats {
pub:
	proc_cpu             f64
	proc_mem             f64
	proc_threads_count   f64
	sys_cpu              f64
	sys_free_mem         f64
	queue_length_main    f64
	es_read_ops          f64
	es_write_ops         f64
}

// new_eventstoredb_metrics creates a new EventStoreDbMetricsSource from config options.
pub fn new_eventstoredb_metrics(opts map[string]string) EventStoreDbMetricsSource {
	endpoint := opts['endpoint'] or { 'http://localhost:2113' }

	mut scrape_secs := 15.0
	if s := opts['scrape_interval_secs'] {
		scrape_secs = s.f64()
		if scrape_secs <= 0 {
			scrape_secs = 15.0
		}
	}

	namespace := opts['namespace'] or { 'eventstoredb' }

	return EventStoreDbMetricsSource{
		endpoint: endpoint
		scrape_interval: time.Duration(i64(scrape_secs * 1_000_000_000))
		namespace: namespace
	}
}

// run polls the EventStoreDB stats endpoint at the configured interval and emits metric events.
pub fn (s &EventStoreDbMetricsSource) run(output chan event.Event) {
	for {
		s.scrape(output)
		time.sleep(s.scrape_interval)
	}
}

// scrape fetches stats from the EventStoreDB endpoint and emits metrics.
fn (s &EventStoreDbMetricsSource) scrape(output chan event.Event) {
	stats_url := s.endpoint.trim_right('/') + '/stats'

	mut header := http.Header{}
	header.add_custom('Accept', 'application/json') or {}

	resp := http.fetch(http.FetchConfig{
		url: stats_url
		method: .get
		header: header
		verbose: false
	}) or {
		eprintln('eventstoredb_metrics: scrape failed for ${stats_url}: ${err}')
		return
	}

	if resp.status_code >= 400 {
		eprintln('eventstoredb_metrics: HTTP ${resp.status_code} from ${stats_url}')
		return
	}

	stats := parse_eventstoredb_stats(resp.body)

	// Gauges
	s.emit_esdb_gauge(output, 'process_cpu', stats.proc_cpu)
	s.emit_esdb_gauge(output, 'process_memory_bytes', stats.proc_mem)
	s.emit_esdb_gauge(output, 'process_threads', stats.proc_threads_count)
	s.emit_esdb_gauge(output, 'system_cpu', stats.sys_cpu)
	s.emit_esdb_gauge(output, 'system_free_memory_bytes', stats.sys_free_mem)
	s.emit_esdb_gauge(output, 'queue_length_main', stats.queue_length_main)

	// Counters
	s.emit_esdb_counter(output, 'read_ops', stats.es_read_ops)
	s.emit_esdb_counter(output, 'write_ops', stats.es_write_ops)
}

// emit_esdb_gauge emits a gauge metric event.
fn (s &EventStoreDbMetricsSource) emit_esdb_gauge(output chan event.Event, name string, value f64) {
	mut m := event.new_gauge(name, value)
	m.namespace = s.namespace
	m.meta.source_type = 'eventstoredb_metrics'
	output <- event.Event(m)
}

// emit_esdb_counter emits a counter metric event.
fn (s &EventStoreDbMetricsSource) emit_esdb_counter(output chan event.Event, name string, value f64) {
	mut m := event.new_counter(name, value, .incremental)
	m.namespace = s.namespace
	m.meta.source_type = 'eventstoredb_metrics'
	output <- event.Event(m)
}

// parse_eventstoredb_stats parses the JSON stats response from EventStoreDB.
pub fn parse_eventstoredb_stats(content string) EventStoreDbStats {
	return EventStoreDbStats{
		proc_cpu: extract_esdb_f64(content, 'proc-cpu')
		proc_mem: extract_esdb_f64(content, 'proc-mem')
		proc_threads_count: extract_esdb_f64(content, 'proc-threadsCount')
		sys_cpu: extract_esdb_f64(content, 'sys-cpu')
		sys_free_mem: extract_esdb_f64(content, 'sys-freeMem')
		queue_length_main: extract_esdb_f64(content, 'es-queue-MainQueue-length')
		es_read_ops: extract_esdb_f64(content, 'es-readOps')
		es_write_ops: extract_esdb_f64(content, 'es-writeOps')
	}
}

// extract_esdb_f64 finds a JSON key in the content and returns its numeric value.
// Returns 0.0 if the key is not found.
fn extract_esdb_f64(content string, key string) f64 {
	search := '"${key}"'
	idx := content.index(search) or { return 0.0 }
	// Find the colon after the key
	rest := content[idx + search.len..]
	colon := rest.index(':') or { return 0.0 }
	after_colon := rest[colon + 1..].trim_left(' \t')
	// Extract the numeric value (up to next comma, brace, or newline)
	mut end := 0
	for end < after_colon.len {
		c := after_colon[end]
		if c == `,` || c == `}` || c == `\n` || c == `\r` {
			break
		}
		end++
	}
	if end == 0 {
		return 0.0
	}
	val_str := after_colon[..end].trim_space()
	return val_str.f64()
}
