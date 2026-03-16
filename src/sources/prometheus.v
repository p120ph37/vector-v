module sources

import event
import net.http
import time

// PrometheusSource polls Prometheus exposition format endpoints at configurable
// intervals and emits metric events. Mirrors Vector's prometheus_scrape source.
//
// Config options:
//   endpoints:             Comma-separated list of URLs to scrape (required)
//   scrape_interval_secs:  Polling interval in seconds (default: 15)
//   scrape_timeout_secs:   Timeout for each scrape request in seconds (default: 5)
//   auth.user/password:    Basic auth
//   auth.token:            Bearer token
//   tls.enabled:           Enable TLS (default: false)
//   honor_labels:          If true, keep existing labels; if false, rename to exported_ (default: false)
//   instance_tag:          Tag name for host:port of scraped instance (default: "instance", set "" to disable)
//   endpoint_tag:          Tag name for scraped endpoint URL (default: "endpoint", set "" to disable)
//   query.*:               Custom query parameters appended to endpoint URLs
pub struct PrometheusSource {
	endpoints        []string
	scrape_interval  time.Duration = 15 * time.second
	scrape_timeout   time.Duration = 5 * time.second
	auth_header      string
	honor_labels     bool
	instance_tag     string = 'instance'
	endpoint_tag     string = 'endpoint'
	query            map[string]string
	tls_enabled      bool
}

// new_prometheus creates a new PrometheusSource from config options.
pub fn new_prometheus(opts map[string]string) !PrometheusSource {
	endpoints_str := opts['endpoints'] or {
		return error('prometheus source: endpoints is required')
	}
	mut endpoints := []string{}
	for ep in endpoints_str.split(',') {
		trimmed := ep.trim_space()
		if trimmed.len > 0 {
			endpoints << trimmed
		}
	}
	if endpoints.len == 0 {
		return error('prometheus source: at least one endpoint is required')
	}

	mut scrape_secs := 15.0
	if s := opts['scrape_interval_secs'] {
		scrape_secs = s.f64()
		if scrape_secs <= 0 {
			scrape_secs = 15.0
		}
	}

	mut timeout_secs := 5.0
	if s := opts['scrape_timeout_secs'] {
		timeout_secs = s.f64()
		if timeout_secs <= 0 {
			timeout_secs = 5.0
		}
	}

	auth_header := parse_auth_header(opts)

	honor_str := opts['honor_labels'] or { 'false' }
	honor_labels := honor_str == 'true'

	instance_tag := opts['instance_tag'] or { 'instance' }
	endpoint_tag := opts['endpoint_tag'] or { 'endpoint' }

	mut query := map[string]string{}
	for k, v in opts {
		if k.starts_with('query.') {
			query[k[6..]] = v
		}
	}

	tls_enabled := if tls_opt := opts['tls.enabled'] {
		tls_opt == 'true'
	} else {
		false
	}

	// Upgrade http:// to https:// when TLS is enabled
	mut final_endpoints := endpoints.clone()
	if tls_enabled {
		for i, ep in final_endpoints {
			if ep.starts_with('http://') {
				final_endpoints[i] = 'https://' + ep[7..]
			}
		}
	}

	return PrometheusSource{
		endpoints: final_endpoints
		scrape_interval: time.Duration(i64(scrape_secs * 1_000_000_000))
		scrape_timeout: time.Duration(i64(timeout_secs * 1_000_000_000))
		auth_header: auth_header
		honor_labels: honor_labels
		instance_tag: instance_tag
		endpoint_tag: endpoint_tag
		query: query
		tls_enabled: tls_enabled
	}
}

// run polls each endpoint at the configured interval and emits metric events.
pub fn (s &PrometheusSource) run(output chan event.Event) {
	for {
		for ep in s.endpoints {
			s.scrape(ep, output)
		}
		time.sleep(s.scrape_interval)
	}
}

fn (s &PrometheusSource) scrape(endpoint string, output chan event.Event) {
	// Build URL with query parameters
	url := build_scrape_url(endpoint, s.query)

	mut header := http.Header{}
	if s.auth_header.len > 0 {
		header.add_custom('Authorization', s.auth_header) or {}
	}
	header.add_custom('Accept', 'text/plain') or {}

	resp := http.fetch(http.FetchConfig{
		url: url
		method: .get
		header: header
		verbose: false
	}) or {
		eprintln('prometheus: scrape failed for ${endpoint}: ${err}')
		return
	}

	if resp.status_code >= 400 {
		if resp.status_code == 404 && !endpoint.contains('/metrics') {
			eprintln("prometheus: HTTP 404 from ${endpoint} — did you mean to use /metrics?")
		} else {
			eprintln('prometheus: HTTP ${resp.status_code} from ${endpoint}')
		}
		return
	}

	// Derive instance (host:port) and endpoint URL for tagging
	instance_val := extract_host_port(endpoint)

	metrics := parse_prometheus_text(resp.body)
	for m in metrics {
		mut metric := m
		// Apply instance_tag
		if s.instance_tag.len > 0 {
			apply_tag(mut metric, s.instance_tag, instance_val, s.honor_labels)
		}
		// Apply endpoint_tag
		if s.endpoint_tag.len > 0 {
			apply_tag(mut metric, s.endpoint_tag, url, s.honor_labels)
		}
		metric.meta.source_type = 'prometheus'
		output <- event.Event(metric)
	}
}

// apply_tag sets a tag on a metric, handling honor_labels logic.
// If honor_labels is true and the tag already exists, the existing value is kept.
// If honor_labels is false and the tag already exists, the existing value is
// moved to exported_{tag} and the new value is set.
fn apply_tag(mut metric event.Metric, tag string, value string, honor_labels bool) {
	existing := metric.tags[tag] or { '' }
	if existing.len > 0 {
		if honor_labels {
			// Keep existing value
			return
		}
		// Rename existing to exported_{tag}
		metric.tags['exported_${tag}'] = existing
	}
	metric.tags[tag] = value
}

// extract_host_port extracts host:port from a URL string.
// Falls back to the raw endpoint if parsing fails.
fn extract_host_port(endpoint string) string {
	// Strip scheme
	mut rest := endpoint
	if rest.starts_with('https://') {
		rest = rest[8..]
	} else if rest.starts_with('http://') {
		rest = rest[7..]
	}
	// Strip path
	slash_idx := rest.index('/') or { -1 }
	if slash_idx >= 0 {
		rest = rest[..slash_idx]
	}
	// If no port, add default based on scheme
	if !rest.contains(':') {
		if endpoint.starts_with('https://') {
			return '${rest}:443'
		}
		return '${rest}:80'
	}
	return rest
}

// build_scrape_url appends query parameters to an endpoint URL.
fn build_scrape_url(endpoint string, query map[string]string) string {
	if query.len == 0 {
		return endpoint
	}
	mut parts := []string{}
	for k, v in query {
		parts << '${k}=${v}'
	}
	separator := if endpoint.contains('?') { '&' } else { '?' }
	return '${endpoint}${separator}${parts.join("&")}'
}

// parse_auth_header extracts an Authorization header value from config options.
// Supports auth.user/auth.password (Basic) and auth.token (Bearer).
// Bearer takes precedence if both are specified.
fn parse_auth_header(opts map[string]string) string {
	mut auth_header := ''
	if user := opts['auth.user'] {
		password := opts['auth.password'] or { '' }
		auth_header = 'Basic ' + sources_base64('${user}:${password}')
	}
	if token := opts['auth.token'] {
		auth_header = 'Bearer ${token}'
	}
	return auth_header
}

// sources_base64 is a minimal base64 encoder for auth headers.
// Shared across all sources that need Basic auth encoding.
fn sources_base64(s string) string {
	alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	mut result := []u8{}
	bytes := s.bytes()
	mut i := 0
	for i < bytes.len {
		b0 := bytes[i]
		b1 := if i + 1 < bytes.len { bytes[i + 1] } else { u8(0) }
		b2 := if i + 2 < bytes.len { bytes[i + 2] } else { u8(0) }
		result << alphabet[b0 >> 2]
		result << alphabet[((b0 & 0x03) << 4) | (b1 >> 4)]
		if i + 1 < bytes.len {
			result << alphabet[((b1 & 0x0f) << 2) | (b2 >> 6)]
		} else {
			result << `=`
		}
		if i + 2 < bytes.len {
			result << alphabet[b2 & 0x3f]
		} else {
			result << `=`
		}
		i += 3
	}
	return result.bytestr()
}

// parse_prometheus_text parses Prometheus exposition format text into metrics.
fn parse_prometheus_text(text string) []event.Metric {
	mut metrics := []event.Metric{}
	mut metric_types := map[string]string{}

	lines := text.split('\n')
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}

		// Parse TYPE comments
		if trimmed.starts_with('# TYPE ') {
			parts := trimmed[7..].split(' ')
			if parts.len >= 2 {
				metric_types[parts[0]] = parts[1]
			}
			continue
		}

		// Skip HELP and other comments
		if trimmed.starts_with('#') {
			continue
		}

		if m := parse_prometheus_line(trimmed, metric_types) {
			metrics << m
		}
	}

	// Post-process: merge histogram and summary families
	return merge_metric_families(metrics, metric_types)
}

// parse_prometheus_line parses a single Prometheus exposition line into a metric.
fn parse_prometheus_line(line string, metric_types map[string]string) !event.Metric {
	// Format: metric_name{label1="val1",label2="val2"} value [timestamp]
	mut name := ''
	mut tags := map[string]string{}
	mut rest := ''

	// Find labels section
	brace_start := line.index('{') or { -1 }
	if brace_start >= 0 {
		name = line[..brace_start]
		brace_end := line[brace_start..].index('}') or {
			return error('invalid line: unmatched brace')
		}
		abs_brace_end := brace_start + brace_end
		labels_str := line[brace_start + 1..abs_brace_end]
		tags = parse_labels(labels_str)
		rest = line[abs_brace_end + 1..].trim_space()
	} else {
		// No labels
		space_idx := line.index(' ') or {
			return error('invalid line: no value')
		}
		name = line[..space_idx]
		rest = line[space_idx + 1..].trim_space()
	}

	if name.len == 0 {
		return error('invalid line: empty metric name')
	}

	// Parse value and optional timestamp
	value_parts := rest.split(' ')
	if value_parts.len == 0 || value_parts[0].len == 0 {
		return error('invalid line: no value')
	}

	value_str := value_parts[0]
	value := value_str.f64()

	mut ts := time.now()
	if value_parts.len > 1 && value_parts[1].len > 0 {
		// Timestamp is in milliseconds since epoch
		ts_ms := value_parts[1].i64()
		ts = time.unix_microsecond(ts_ms * 1000, 0)
	}

	// Determine the base metric name for type lookup
	base_name := get_base_metric_name(name)
	metric_type := metric_types[base_name] or { 'untyped' }

	// Create metric based on type
	mut metric := event.Metric{
		name: name
		tags: tags
		kind: .absolute
		timestamp: ts
	}

	match metric_type {
		'counter' {
			metric.value = event.CounterValue{
				value: value
			}
		}
		'gauge' {
			metric.value = event.GaugeValue{
				value: value
			}
		}
		else {
			// For histogram, summary, and untyped: store as gauge initially.
			// Histogram/summary families are merged in post-processing.
			metric.value = event.GaugeValue{
				value: value
			}
		}
	}

	return metric
}

// parse_labels parses a Prometheus label string like `label1="val1",label2="val2"`.
fn parse_labels(s string) map[string]string {
	mut labels := map[string]string{}
	if s.len == 0 {
		return labels
	}

	mut i := 0
	for i < s.len {
		// Find key
		eq := s[i..].index('=') or { break }
		abs_eq := i + eq
		key := s[i..abs_eq].trim_space()

		// Find value (quoted)
		quote_start := s[abs_eq..].index('"') or { break }
		abs_quote_start := abs_eq + quote_start
		mut quote_end := abs_quote_start + 1
		for quote_end < s.len {
			if s[quote_end] == `\\` && quote_end + 1 < s.len {
				quote_end += 2
				continue
			}
			if s[quote_end] == `"` {
				break
			}
			quote_end++
		}

		if quote_end <= s.len {
			val := s[abs_quote_start + 1..quote_end]
			// Unescape basic sequences
			unescaped := val.replace('\\\\', '\\').replace('\\"', '"').replace('\\n', '\n')
			labels[key] = unescaped
		}

		// Move past the closing quote and any comma
		i = quote_end + 1
		if i < s.len && s[i] == `,` {
			i++
		}
	}

	return labels
}

// get_base_metric_name strips histogram/summary suffixes to find the base name.
fn get_base_metric_name(name string) string {
	for suffix in ['_bucket', '_count', '_sum', '_total', '_created', '_info'] {
		if name.ends_with(suffix) {
			return name[..name.len - suffix.len]
		}
	}
	return name
}

// merge_metric_families merges histogram and summary component metrics into
// composite HistogramValue and SummaryValue metrics.
fn merge_metric_families(metrics []event.Metric, metric_types map[string]string) []event.Metric {
	mut result := []event.Metric{}
	mut histogram_families := map[string]HistogramFamily{}
	mut summary_families := map[string]SummaryFamily{}

	for m in metrics {
		base := get_base_metric_name(m.name)
		mtype := metric_types[base] or { 'untyped' }

		match mtype {
			'histogram' {
				// Build composite label key (tags without "le")
				label_key := make_family_key(base, m.tags, 'le')
				mut family := histogram_families[label_key] or {
					HistogramFamily{
						base_name: base
						tags: filter_tag(m.tags, 'le')
						timestamp: m.timestamp
					}
				}
				val := (m.value as event.GaugeValue).value
				if m.name.ends_with('_bucket') {
					le := m.tags['le'] or { '' }
					family.buckets << event.Bucket{
						upper_limit: le.f64()
						count: u64(val)
					}
				} else if m.name.ends_with('_count') {
					family.count = u64(val)
				} else if m.name.ends_with('_sum') {
					family.sum = val
				}
				histogram_families[label_key] = family
			}
			'summary' {
				label_key := make_family_key(base, m.tags, 'quantile')
				mut family := summary_families[label_key] or {
					SummaryFamily{
						base_name: base
						tags: filter_tag(m.tags, 'quantile')
						timestamp: m.timestamp
					}
				}
				val := (m.value as event.GaugeValue).value
				if m.name.ends_with('_count') {
					family.count = u64(val)
				} else if m.name.ends_with('_sum') {
					family.sum = val
				} else {
					q := m.tags['quantile'] or { '0' }
					family.quantiles << event.Quantile{
						quantile: q.f64()
						value: val
					}
				}
				summary_families[label_key] = family
			}
			else {
				result << m
			}
		}
	}

	// Emit merged histogram metrics
	for _, family in histogram_families {
		result << event.Metric{
			name: family.base_name
			tags: family.tags
			kind: .absolute
			timestamp: family.timestamp
			value: event.HistogramValue{
				buckets: family.buckets
				count: family.count
				sum: family.sum
			}
		}
	}

	// Emit merged summary metrics
	for _, family in summary_families {
		result << event.Metric{
			name: family.base_name
			tags: family.tags
			kind: .absolute
			timestamp: family.timestamp
			value: event.SummaryValue{
				quantiles: family.quantiles
				count: family.count
				sum: family.sum
			}
		}
	}

	return result
}

struct HistogramFamily {
	base_name string
	tags      map[string]string
	timestamp time.Time
mut:
	buckets []event.Bucket
	count   u64
	sum     f64
}

struct SummaryFamily {
	base_name string
	tags      map[string]string
	timestamp time.Time
mut:
	quantiles []event.Quantile
	count     u64
	sum       f64
}

// make_family_key creates a unique key for a metric family by base name and
// tags, excluding the specified label (e.g., "le" for histograms).
fn make_family_key(base string, tags map[string]string, exclude string) string {
	mut parts := [base]
	for k, v in tags {
		if k != exclude {
			parts << '${k}=${v}'
		}
	}
	parts.sort()
	return parts.join(',')
}

// filter_tag returns a copy of tags with the specified key removed.
fn filter_tag(tags map[string]string, exclude string) map[string]string {
	mut result := map[string]string{}
	for k, v in tags {
		if k != exclude {
			result[k] = v
		}
	}
	return result
}
