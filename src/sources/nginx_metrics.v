module sources

import event
import net.http
import time

// NginxMetricsSource scrapes Nginx stub_status endpoints at configurable
// intervals and emits metric events. Mirrors Vector's nginx_metrics source.
//
// Config options:
//   endpoints:             Comma-separated list of URLs to scrape (required)
//   scrape_interval_secs:  Polling interval in seconds (default: 15)
//   namespace:             Metric namespace prefix (default: "nginx")
//   auth.user/password:    Basic auth
//   auth.token:            Bearer token
pub struct NginxMetricsSource {
	endpoints       []string
	scrape_interval time.Duration = 15 * time.second
	namespace       string        = 'nginx'
	auth_header     string
}

// NginxStubStatus holds parsed values from the Nginx stub_status response.
pub struct NginxStubStatus {
pub:
	active   u64
	accepts  u64
	handled  u64
	requests u64
	reading  u64
	writing  u64
	waiting  u64
}

// new_nginx_metrics creates a new NginxMetricsSource from config options.
pub fn new_nginx_metrics(opts map[string]string) !NginxMetricsSource {
	endpoints_str := opts['endpoints'] or {
		return error('nginx_metrics source: endpoints is required')
	}
	mut endpoints := []string{}
	for ep in endpoints_str.split(',') {
		trimmed := ep.trim_space()
		if trimmed.len > 0 {
			endpoints << trimmed
		}
	}
	if endpoints.len == 0 {
		return error('nginx_metrics source: at least one endpoint is required')
	}

	mut scrape_secs := 15.0
	if s := opts['scrape_interval_secs'] {
		scrape_secs = s.f64()
		if scrape_secs <= 0 {
			scrape_secs = 15.0
		}
	}

	auth_header := parse_auth_header(opts)

	namespace := opts['namespace'] or { 'nginx' }

	return NginxMetricsSource{
		endpoints: endpoints
		scrape_interval: time.Duration(i64(scrape_secs * 1_000_000_000))
		auth_header: auth_header
		namespace: namespace
	}
}

// run polls each endpoint at the configured interval and emits metric events.
pub fn (s &NginxMetricsSource) run(output chan event.Event) {
	for {
		for ep in s.endpoints {
			s.scrape(ep, output)
		}
		time.sleep(s.scrape_interval)
	}
}

// scrape fetches a single endpoint, parses the stub_status response, and emits metrics.
fn (s &NginxMetricsSource) scrape(endpoint string, output chan event.Event) {
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
		eprintln('nginx_metrics: scrape failed for ${endpoint}: ${err}')
		return
	}

	if resp.status_code >= 400 {
		eprintln('nginx_metrics: HTTP ${resp.status_code} from ${endpoint}')
		return
	}

	status := parse_nginx_stub_status(resp.body)
	tags := map[string]string{}

	s.emit_nginx_gauge(output, 'connections_active', f64(status.active), tags)
	s.emit_nginx_counter(output, 'connections_accepted', f64(status.accepts), tags)
	s.emit_nginx_counter(output, 'connections_handled', f64(status.handled), tags)
	s.emit_nginx_counter(output, 'requests', f64(status.requests), tags)
	s.emit_nginx_gauge(output, 'connections_reading', f64(status.reading), tags)
	s.emit_nginx_gauge(output, 'connections_writing', f64(status.writing), tags)
	s.emit_nginx_gauge(output, 'connections_waiting', f64(status.waiting), tags)
}

// emit_nginx_gauge emits a gauge metric with the configured namespace.
fn (s &NginxMetricsSource) emit_nginx_gauge(output chan event.Event, name string, value f64, tags map[string]string) {
	mut m := event.new_gauge(name, value)
	m.namespace = s.namespace
	m.tags = tags.clone()
	m.meta.source_type = 'nginx_metrics'
	output <- event.Event(m)
}

// emit_nginx_counter emits a counter metric with the configured namespace.
fn (s &NginxMetricsSource) emit_nginx_counter(output chan event.Event, name string, value f64, tags map[string]string) {
	mut m := event.new_counter(name, value, .incremental)
	m.namespace = s.namespace
	m.tags = tags.clone()
	m.meta.source_type = 'nginx_metrics'
	output <- event.Event(m)
}

// parse_nginx_stub_status parses the Nginx stub_status response format:
//
//   Active connections: 291
//   server accepts handled requests
//    16630948 16630948 31070465
//   Reading: 6 Writing: 179 Waiting: 106
pub fn parse_nginx_stub_status(content string) NginxStubStatus {
	mut active := u64(0)
	mut accepts := u64(0)
	mut handled := u64(0)
	mut requests := u64(0)
	mut reading := u64(0)
	mut writing := u64(0)
	mut waiting := u64(0)

	lines := content.split('\n')
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}

		// Line: "Active connections: 291"
		if trimmed.starts_with('Active connections:') {
			val := trimmed.all_after(':').trim_space()
			active = val.u64()
			continue
		}

		// Line: "Reading: 6 Writing: 179 Waiting: 106"
		if trimmed.starts_with('Reading:') {
			parts := trimmed.split_any(' \t').filter(it.len > 0)
			// Expected: ["Reading:", "6", "Writing:", "179", "Waiting:", "106"]
			if parts.len >= 6 {
				reading = parts[1].u64()
				writing = parts[3].u64()
				waiting = parts[5].u64()
			}
			continue
		}

		// Skip the header line "server accepts handled requests"
		if trimmed.starts_with('server') {
			continue
		}

		// Line: " 16630948 16630948 31070465" (accepts handled requests)
		parts := trimmed.split_any(' \t').filter(it.len > 0)
		if parts.len >= 3 {
			// Check if all three parts are numeric
			first_char := parts[0][0]
			if first_char >= `0` && first_char <= `9` {
				accepts = parts[0].u64()
				handled = parts[1].u64()
				requests = parts[2].u64()
			}
		}
	}

	return NginxStubStatus{
		active: active
		accepts: accepts
		handled: handled
		requests: requests
		reading: reading
		writing: writing
		waiting: waiting
	}
}

