module sources

import event
import net.http
import time

// MongodbMetricsSource polls MongoDB serverStatus endpoints via HTTP and emits
// metric events. Mirrors Vector's mongodb_metrics source using an HTTP endpoint
// approach similar to other metrics sources in this codebase.
//
// Config options:
//   endpoints:             Comma-separated list of MongoDB HTTP endpoints (required)
//   scrape_interval_secs:  Polling interval in seconds (default: 15)
//   namespace:             Metric namespace prefix (default: "mongodb")
pub struct MongodbMetricsSource {
	endpoints       []string
	scrape_interval time.Duration = 15 * time.second
	namespace       string        = 'mongodb'
}

// MongodbServerStatus holds parsed fields from a MongoDB serverStatus response.
pub struct MongodbServerStatus {
pub:
	host                      string
	uptime                    f64
	connections_current       f64
	connections_available     f64
	connections_total_created f64
	mem_resident              f64
	mem_virtual               f64
	ops_insert                f64
	ops_query                 f64
	ops_update                f64
	ops_delete                f64
	ops_getmore               f64
	ops_command               f64
}

// new_mongodb_metrics creates a new MongodbMetricsSource from config options.
pub fn new_mongodb_metrics(opts map[string]string) !MongodbMetricsSource {
	endpoints_str := opts['endpoints'] or {
		return error('mongodb_metrics source: endpoints is required')
	}
	mut endpoints := []string{}
	for ep in endpoints_str.split(',') {
		trimmed := ep.trim_space()
		if trimmed.len > 0 {
			endpoints << trimmed
		}
	}
	if endpoints.len == 0 {
		return error('mongodb_metrics source: at least one endpoint is required')
	}

	mut scrape_secs := 15.0
	if s := opts['scrape_interval_secs'] {
		scrape_secs = s.f64()
		if scrape_secs <= 0 {
			scrape_secs = 15.0
		}
	}

	namespace := opts['namespace'] or { 'mongodb' }

	return MongodbMetricsSource{
		endpoints: endpoints
		scrape_interval: time.Duration(i64(scrape_secs * 1_000_000_000))
		namespace: namespace
	}
}

// run polls each endpoint at the configured interval and emits metric events.
pub fn (s &MongodbMetricsSource) run(output chan event.Event) {
	for {
		for ep in s.endpoints {
			s.scrape(ep, output)
		}
		time.sleep(s.scrape_interval)
	}
}

// scrape fetches serverStatus from a single endpoint and emits metrics.
fn (s &MongodbMetricsSource) scrape(endpoint string, output chan event.Event) {
	resp := http.fetch(http.FetchConfig{
		url: endpoint
		method: .get
		verbose: false
	}) or {
		eprintln('mongodb_metrics: scrape failed for ${endpoint}: ${err}')
		return
	}

	if resp.status_code >= 400 {
		eprintln('mongodb_metrics: HTTP ${resp.status_code} from ${endpoint}')
		return
	}

	status := parse_mongodb_status(resp.body)
	tags := {
		'endpoint': endpoint
	}

	// Gauges
	s.emit_mongo_gauge(output, 'uptime_seconds', status.uptime, tags)
	s.emit_mongo_gauge(output, 'connections_current', status.connections_current, tags)
	s.emit_mongo_gauge(output, 'connections_available', status.connections_available, tags)
	s.emit_mongo_gauge(output, 'memory_resident_megabytes', status.mem_resident, tags)
	s.emit_mongo_gauge(output, 'memory_virtual_megabytes', status.mem_virtual, tags)

	// Counters
	s.emit_mongo_counter(output, 'connections_total_created', status.connections_total_created, tags)
	s.emit_mongo_counter(output, 'opcounters_insert', status.ops_insert, tags)
	s.emit_mongo_counter(output, 'opcounters_query', status.ops_query, tags)
	s.emit_mongo_counter(output, 'opcounters_update', status.ops_update, tags)
	s.emit_mongo_counter(output, 'opcounters_delete', status.ops_delete, tags)
	s.emit_mongo_counter(output, 'opcounters_getmore', status.ops_getmore, tags)
	s.emit_mongo_counter(output, 'opcounters_command', status.ops_command, tags)
}

fn (s &MongodbMetricsSource) emit_mongo_gauge(output chan event.Event, name string, value f64, tags map[string]string) {
	mut m := event.new_gauge(name, value)
	m.namespace = s.namespace
	m.tags = tags.clone()
	m.meta.source_type = 'mongodb_metrics'
	output <- event.Event(m)
}

fn (s &MongodbMetricsSource) emit_mongo_counter(output chan event.Event, name string, value f64, tags map[string]string) {
	mut m := event.new_counter(name, value, .incremental)
	m.namespace = s.namespace
	m.tags = tags.clone()
	m.meta.source_type = 'mongodb_metrics'
	output <- event.Event(m)
}

// parse_mongodb_status parses a MongoDB serverStatus JSON response into a
// MongodbServerStatus struct using simple string matching to extract values
// from the complex nested JSON document.
pub fn parse_mongodb_status(content string) MongodbServerStatus {
	return MongodbServerStatus{
		host: extract_json_string(content, 'host')
		uptime: extract_json_f64(content, 'uptimeMillis') / 1000.0
		connections_current: extract_json_f64(content, 'current')
		connections_available: extract_json_f64(content, 'available')
		connections_total_created: extract_json_f64(content, 'totalCreated')
		mem_resident: extract_json_f64(content, 'resident')
		mem_virtual: extract_json_f64(content, 'virtual')
		ops_insert: extract_json_f64(content, 'insert')
		ops_query: extract_json_f64(content, 'query')
		ops_update: extract_json_f64(content, 'update')
		ops_delete: extract_json_f64(content, 'delete')
		ops_getmore: extract_json_f64(content, 'getmore')
		ops_command: extract_json_f64(content, 'command')
	}
}

// extract_json_f64 finds a JSON key like `"key":` in the content and parses
// the numeric value that follows it. Returns 0 if the key is not found.
fn extract_json_f64(content string, key string) f64 {
	needle := '"${key}"'
	idx := content.index(needle) or { return 0 }
	after := content[idx + needle.len..].trim_left(' \t')
	if after.len == 0 || after[0] != `:` {
		return 0
	}
	val_str := after[1..].trim_left(' \t')
	mut end := 0
	for end < val_str.len {
		c := val_str[end]
		if (c >= `0` && c <= `9`) || c == `.` || c == `-` || c == `e` || c == `E` || c == `+` {
			end++
		} else {
			break
		}
	}
	if end == 0 {
		return 0
	}
	return val_str[..end].f64()
}

// extract_json_string finds a JSON key like `"key":` in the content and
// parses the quoted string value that follows it. Returns '' if not found.
fn extract_json_string(content string, key string) string {
	needle := '"${key}"'
	idx := content.index(needle) or { return '' }
	after := content[idx + needle.len..].trim_left(' \t')
	if after.len == 0 || after[0] != `:` {
		return ''
	}
	val_str := after[1..].trim_left(' \t')
	if val_str.len == 0 || val_str[0] != `"` {
		return ''
	}
	end_quote := val_str[1..].index('"') or { return '' }
	return val_str[1..1 + end_quote]
}
