module sinks

import event
import net.http
import time

// PrometheusSink pushes metrics to a Prometheus Pushgateway-compatible endpoint
// using Prometheus exposition text format. Mirrors Vector's prometheus_exporter
// sink pattern adapted for push-based delivery.
//
// Config options:
//   endpoint:            Pushgateway URL (required)
//   job:                 Job label for grouping (default: "vector")
//   batch.max_events:    Max events per push (default: 100)
//   batch.timeout_secs:  Batch timeout in seconds (default: 5)
//   auth.user/password:  Basic auth
//   auth.token:          Bearer token
//   default_namespace:   Namespace prefix for metric names (default: "")
pub struct PrometheusSink {
	endpoint          string
	job               string = 'vector'
	default_namespace string
	batch_max         int = 100
	batch_timeout     time.Duration = 5 * time.second
	auth_header       string
mut:
	buffer     []event.Metric
	last_flush time.Time
}

// new_prometheus_sink creates a new PrometheusSink from config options.
pub fn new_prometheus_sink(opts map[string]string) !PrometheusSink {
	endpoint := opts['endpoint'] or {
		return error('prometheus sink: endpoint is required')
	}

	job := opts['job'] or { 'vector' }

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
	}

	mut batch_timeout_secs := 5.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 5.0
		}
	}

	mut auth_header := ''
	if user := opts['auth.user'] {
		password := opts['auth.password'] or { '' }
		auth_header = 'Basic ' + base64_encode('${user}:${password}')
	}
	if token := opts['auth.token'] {
		auth_header = 'Bearer ${token}'
	}

	default_namespace := opts['default_namespace'] or { '' }

	return PrometheusSink{
		endpoint: endpoint
		job: job
		default_namespace: default_namespace
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		auth_header: auth_header
		last_flush: time.now()
	}
}

// send buffers a metric event and flushes when batch is full or timeout expires.
// Non-metric events are silently dropped.
pub fn (mut s PrometheusSink) send(e event.Event) ! {
	match e {
		event.Metric {
			s.buffer << e
		}
		else {
			// Silently drop non-metric events
			return
		}
	}

	if s.buffer.len >= s.batch_max {
		s.flush()!
	}

	if time.since(s.last_flush) > s.batch_timeout && s.buffer.len > 0 {
		s.flush()!
	}
}

// flush sends all buffered metrics to the Pushgateway endpoint.
pub fn (mut s PrometheusSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	mut lines := []string{}
	for m in s.buffer {
		formatted := s.format_metric(m)
		if formatted.len > 0 {
			lines << formatted
		}
	}

	payload := lines.join('\n')
	if payload.len > 0 {
		s.push(payload)!
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of metrics currently buffered.
pub fn (s &PrometheusSink) total_buffered() int {
	return s.buffer.len
}

fn (s &PrometheusSink) push(payload string) ! {
	url := '${s.endpoint}/metrics/job/${s.job}'

	mut header := http.new_custom_header_from_map({
		'Content-Type': 'text/plain; version=0.0.4; charset=utf-8'
	})!

	if s.auth_header.len > 0 {
		header.add_custom('Authorization', s.auth_header)!
	}

	resp := http.fetch(http.FetchConfig{
		url: url
		method: .post
		data: payload
		header: header
		verbose: false
	}) or {
		return error('prometheus: push failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('prometheus: HTTP ${resp.status_code}: ${resp.body}')
	}
}

fn (s &PrometheusSink) format_metric(m event.Metric) string {
	mut name := m.name
	// Apply namespace prefix
	if s.default_namespace.len > 0 {
		if m.namespace.len > 0 {
			name = '${m.namespace}_${name}'
		} else {
			name = '${s.default_namespace}_${name}'
		}
	} else if m.namespace.len > 0 {
		name = '${m.namespace}_${name}'
	}

	// Sanitize metric name: replace non-alphanumeric/underscore with underscore
	name = sanitize_metric_name(name)

	ts_ms := m.timestamp.unix() * 1000

	match m.value {
		event.CounterValue {
			full_name := if name.ends_with('_total') { name } else { '${name}_total' }
			tags_str := prom_format_tags(m.tags)
			return '${full_name}${tags_str} ${m.value.value} ${ts_ms}'
		}
		event.GaugeValue {
			tags_str := prom_format_tags(m.tags)
			return '${name}${tags_str} ${m.value.value} ${ts_ms}'
		}
		event.HistogramValue {
			return format_histogram(name, m.tags, m.value, ts_ms)
		}
		event.SummaryValue {
			return format_summary(name, m.tags, m.value, ts_ms)
		}
		event.SetValue {
			// Emit set as gauge with count of unique values
			tags_str := prom_format_tags(m.tags)
			return '${name}${tags_str} ${m.value.values.len} ${ts_ms}'
		}
		event.DistributionValue {
			// Emit distribution as histogram with synthetic buckets
			return format_distribution_as_histogram(name, m.tags, m.value, ts_ms)
		}
	}
}

// format_prometheus formats a single metric in Prometheus exposition text format.
fn format_prometheus(m event.Metric) string {
	name := sanitize_metric_name(m.name)
	ts_ms := m.timestamp.unix() * 1000

	match m.value {
		event.CounterValue {
			full_name := if name.ends_with('_total') { name } else { '${name}_total' }
			tags_str := prom_format_tags(m.tags)
			return '${full_name}${tags_str} ${m.value.value} ${ts_ms}'
		}
		event.GaugeValue {
			tags_str := prom_format_tags(m.tags)
			return '${name}${tags_str} ${m.value.value} ${ts_ms}'
		}
		event.HistogramValue {
			return format_histogram(name, m.tags, m.value, ts_ms)
		}
		event.SummaryValue {
			return format_summary(name, m.tags, m.value, ts_ms)
		}
		event.SetValue {
			tags_str := prom_format_tags(m.tags)
			return '${name}${tags_str} ${m.value.values.len} ${ts_ms}'
		}
		event.DistributionValue {
			return format_distribution_as_histogram(name, m.tags, m.value, ts_ms)
		}
	}
}

// prom_format_tags formats metric tags as Prometheus label string: {key="val",...}
fn prom_format_tags(tags map[string]string) string {
	if tags.len == 0 {
		return ''
	}
	mut parts := []string{}
	for k, v in tags {
		// Escape label values
		escaped := v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
		parts << '${k}="${escaped}"'
	}
	return '{${parts.join(",")}}'
}

// format_histogram formats a histogram metric as multiple exposition lines.
fn format_histogram(name string, tags map[string]string, h event.HistogramValue, ts_ms i64) string {
	mut lines := []string{}

	for bucket in h.buckets {
		mut bucket_tags := tags.clone()
		bucket_tags['le'] = format_float(bucket.upper_limit)
		tags_str := prom_format_tags(bucket_tags)
		lines << '${name}_bucket${tags_str} ${bucket.count} ${ts_ms}'
	}

	// Add +Inf bucket
	mut inf_tags := tags.clone()
	inf_tags['le'] = '+Inf'
	inf_tags_str := prom_format_tags(inf_tags)
	lines << '${name}_bucket${inf_tags_str} ${h.count} ${ts_ms}'

	base_tags := prom_format_tags(tags)
	lines << '${name}_sum${base_tags} ${h.sum} ${ts_ms}'
	lines << '${name}_count${base_tags} ${h.count} ${ts_ms}'

	return lines.join('\n')
}

// format_summary formats a summary metric as multiple exposition lines.
fn format_summary(name string, tags map[string]string, s event.SummaryValue, ts_ms i64) string {
	mut lines := []string{}

	for q in s.quantiles {
		mut q_tags := tags.clone()
		q_tags['quantile'] = format_float(q.quantile)
		tags_str := prom_format_tags(q_tags)
		lines << '${name}${tags_str} ${q.value} ${ts_ms}'
	}

	base_tags := prom_format_tags(tags)
	lines << '${name}_sum${base_tags} ${s.sum} ${ts_ms}'
	lines << '${name}_count${base_tags} ${s.count} ${ts_ms}'

	return lines.join('\n')
}

// format_distribution_as_histogram emits a distribution as a histogram with
// synthetic buckets derived from the sample values.
fn format_distribution_as_histogram(name string, tags map[string]string, d event.DistributionValue, ts_ms i64) string {
	// Compute count and sum from samples
	mut total_count := u64(0)
	mut total_sum := f64(0)
	for sample in d.samples {
		total_count += u64(sample.rate)
		total_sum += sample.value * f64(sample.rate)
	}

	// Use standard histogram buckets
	buckets := [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
	mut lines := []string{}

	for bound in buckets {
		mut count := u64(0)
		for sample in d.samples {
			if sample.value <= bound {
				count += u64(sample.rate)
			}
		}
		mut bucket_tags := tags.clone()
		bucket_tags['le'] = format_float(bound)
		tags_str := prom_format_tags(bucket_tags)
		lines << '${name}_bucket${tags_str} ${count} ${ts_ms}'
	}

	mut inf_tags := tags.clone()
	inf_tags['le'] = '+Inf'
	inf_tags_str := prom_format_tags(inf_tags)
	lines << '${name}_bucket${inf_tags_str} ${total_count} ${ts_ms}'

	base_tags := prom_format_tags(tags)
	lines << '${name}_sum${base_tags} ${total_sum} ${ts_ms}'
	lines << '${name}_count${base_tags} ${total_count} ${ts_ms}'

	return lines.join('\n')
}

// sanitize_metric_name replaces invalid characters in metric names with underscores.
fn sanitize_metric_name(name string) string {
	mut result := []u8{cap: name.len}
	for i, c in name {
		if (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || c == `_` || c == `:` {
			result << c
		} else if c >= `0` && c <= `9` {
			if i == 0 {
				result << `_`
			}
			result << c
		} else {
			result << `_`
		}
	}
	return result.bytestr()
}

// format_float formats a float without unnecessary trailing zeros.
fn format_float(v f64) string {
	s := '${v}'
	return s
}
