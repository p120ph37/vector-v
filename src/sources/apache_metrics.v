module sources

import event
import net.http
import time

// ApacheMetricsSource polls Apache mod_status endpoints at configurable intervals
// and emits metric events. Mirrors Vector's apache_metrics source.
//
// Config options:
//   endpoints:             Comma-separated list of URLs to scrape (required)
//   scrape_interval_secs:  Polling interval in seconds (default: 15)
//   namespace:             Metric namespace prefix (default: 'apache')
//   auth.user/password:    Basic auth
//   auth.token:            Bearer token
pub struct ApacheMetricsSource {
	endpoints       []string
	scrape_interval time.Duration = 15 * time.second
	namespace       string = 'apache'
	auth_header     string
}

// ApacheStatusEntry represents a single key-value pair from mod_status ?auto output.
pub struct ApacheStatusEntry {
pub:
	key       string
	value_str string
	value     f64
}

// new_apache_metrics creates a new ApacheMetricsSource from config options.
pub fn new_apache_metrics(opts map[string]string) !ApacheMetricsSource {
	endpoints_str := opts['endpoints'] or {
		return error('apache_metrics source: endpoints is required')
	}
	mut endpoints := []string{}
	for ep in endpoints_str.split(',') {
		trimmed := ep.trim_space()
		if trimmed.len > 0 {
			endpoints << trimmed
		}
	}
	if endpoints.len == 0 {
		return error('apache_metrics source: at least one endpoint is required')
	}

	mut scrape_secs := 15.0
	if s := opts['scrape_interval_secs'] {
		scrape_secs = s.f64()
		if scrape_secs <= 0 {
			scrape_secs = 15.0
		}
	}

	namespace := opts['namespace'] or { 'apache' }

	auth_header := parse_auth_header(opts)

	return ApacheMetricsSource{
		endpoints: endpoints
		scrape_interval: time.Duration(i64(scrape_secs * 1_000_000_000))
		namespace: namespace
		auth_header: auth_header
	}
}

// run polls each endpoint at the configured interval and emits metric events.
pub fn (s &ApacheMetricsSource) run(output chan event.Event) {
	for {
		for ep in s.endpoints {
			s.scrape(ep, output)
		}
		time.sleep(s.scrape_interval)
	}
}

// scrape fetches mod_status from the given endpoint, parses it, and emits metrics.
fn (s &ApacheMetricsSource) scrape(endpoint string, output chan event.Event) {
	mut header := http.Header{}
	if s.auth_header.len > 0 {
		header.add_custom('Authorization', s.auth_header) or {}
	}

	resp := http.fetch(http.FetchConfig{
		url: endpoint
		method: .get
		header: header
		verbose: false
	}) or {
		eprintln('apache_metrics: scrape failed for ${endpoint}: ${err}')
		return
	}

	if resp.status_code >= 400 {
		eprintln('apache_metrics: HTTP ${resp.status_code} from ${endpoint}')
		return
	}

	entries := parse_apache_status(resp.body)
	mut tags := map[string]string{}
	tags['endpoint'] = endpoint

	mut scoreboard := ''

	for entry in entries {
		match entry.key {
			'Total Accesses' {
				s.emit_apache_counter(output, 'total_accesses', entry.value, tags)
			}
			'Total kBytes' {
				s.emit_apache_counter(output, 'total_kbytes', entry.value, tags)
			}
			'CPULoad' {
				s.emit_apache_gauge(output, 'cpu_load', entry.value, tags)
			}
			'Uptime' {
				s.emit_apache_gauge(output, 'uptime', entry.value, tags)
			}
			'ReqPerSec' {
				s.emit_apache_gauge(output, 'req_per_sec', entry.value, tags)
			}
			'BytesPerSec' {
				s.emit_apache_gauge(output, 'bytes_per_sec', entry.value, tags)
			}
			'BytesPerReq' {
				s.emit_apache_gauge(output, 'bytes_per_req', entry.value, tags)
			}
			'BusyWorkers' {
				s.emit_apache_gauge(output, 'busy_workers', entry.value, tags)
			}
			'IdleWorkers' {
				s.emit_apache_gauge(output, 'idle_workers', entry.value, tags)
			}
			'Scoreboard' {
				scoreboard = entry.value_str
			}
			else {}
		}
	}

	if scoreboard.len > 0 {
		counts := apache_scoreboard_counts(scoreboard)
		for state, count in counts {
			mut sb_tags := map[string]string{}
			sb_tags['endpoint'] = endpoint
			sb_tags['state'] = state
			s.emit_apache_gauge(output, 'scoreboard', f64(count), sb_tags)
		}
	}
}

// emit_apache_gauge emits a gauge metric with namespace and source_type.
fn (s &ApacheMetricsSource) emit_apache_gauge(output chan event.Event, name string, value f64, tags map[string]string) {
	mut metric := event.Metric{
		name: name
		namespace: s.namespace
		tags: tags.clone()
		kind: .absolute
		value: event.GaugeValue{
			value: value
		}
		timestamp: time.now()
	}
	metric.meta.source_type = 'apache_metrics'
	output <- event.Event(metric)
}

// emit_apache_counter emits a counter metric with namespace and source_type.
fn (s &ApacheMetricsSource) emit_apache_counter(output chan event.Event, name string, value f64, tags map[string]string) {
	mut metric := event.Metric{
		name: name
		namespace: s.namespace
		tags: tags.clone()
		kind: .absolute
		value: event.CounterValue{
			value: value
		}
		timestamp: time.now()
	}
	metric.meta.source_type = 'apache_metrics'
	output <- event.Event(metric)
}

// parse_apache_status parses Apache mod_status ?auto format into key-value entries.
// The format is line-based: "Key: Value"
pub fn parse_apache_status(content string) []ApacheStatusEntry {
	mut entries := []ApacheStatusEntry{}
	lines := content.split('\n')
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		colon := trimmed.index(': ') or { continue }
		key := trimmed[..colon]
		value_str := trimmed[colon + 2..]
		entries << ApacheStatusEntry{
			key: key
			value_str: value_str
			value: value_str.f64()
		}
	}
	return entries
}

// apache_scoreboard_counts counts the occurrences of each character type in an
// Apache mod_status scoreboard string.
pub fn apache_scoreboard_counts(scoreboard string) map[string]int {
	mut counts := map[string]int{}
	for ch in scoreboard {
		state := match ch {
			`_` { 'waiting' }
			`S` { 'starting' }
			`R` { 'reading' }
			`W` { 'writing' }
			`K` { 'keepalive' }
			`D` { 'dns' }
			`C` { 'closing' }
			`L` { 'logging' }
			`G` { 'graceful' }
			`I` { 'idle' }
			`.` { 'open' }
			else { '' }
		}
		if state.len > 0 {
			counts[state] = counts[state] + 1
		}
	}
	return counts
}

