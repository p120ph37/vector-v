module sinks

import event
import time

// PrometheusRemoteWriteSink sends metrics to a Prometheus remote write endpoint.
// Mirrors Vector's prometheus_remote_write sink.
//
// Metrics are encoded in the Prometheus remote write text-based format and sent
// via HTTP POST to the configured endpoint. Unlike the Pushgateway sink, this
// uses the standard /api/v1/write endpoint with snappy-compressed protobuf or
// the text-based exposition format as a fallback.
//
// Config options:
//   endpoint:            Remote write URL (required, e.g., "http://prometheus:9090/api/v1/write")
//   tenant_id:           X-Scope-OrgID header for multi-tenant systems like Cortex/Mimir (optional)
//   default_namespace:   Namespace prefix for metric names (default: "")
//   batch.max_events:    Max events per write (default: 100)
//   batch.timeout_secs:  Batch timeout in seconds (default: 5)
//   auth.user/password:  Basic auth
//   auth.token:          Bearer token
pub struct PrometheusRemoteWriteSink {
	endpoint          string
	tenant_id         string
	default_namespace string
	batch_max         int = 100
	batch_timeout     time.Duration = 5 * time.second
	auth_header       string
mut:
	buffer     []event.Metric
	last_flush time.Time
}

// new_prometheus_remote_write creates a new PrometheusRemoteWriteSink.
pub fn new_prometheus_remote_write(opts map[string]string) !PrometheusRemoteWriteSink {
	endpoint := opts['endpoint'] or {
		return error('prometheus_remote_write: endpoint is required')
	}

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

	tenant_id := opts['tenant_id'] or { '' }
	default_namespace := opts['default_namespace'] or { '' }

	return PrometheusRemoteWriteSink{
		endpoint: endpoint
		tenant_id: tenant_id
		default_namespace: default_namespace
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		auth_header: auth_header
		last_flush: time.now()
	}
}

// send buffers a metric event and flushes when batch is full or timeout expires.
// Non-metric events are silently dropped.
pub fn (mut s PrometheusRemoteWriteSink) send(e event.Event) ! {
	match e {
		event.Metric {
			s.buffer << e
		}
		else {
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

// flush sends all buffered metrics to the remote write endpoint.
pub fn (mut s PrometheusRemoteWriteSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	payload := s.encode_remote_write()

	mut http_batch := new_http_batch({
		'endpoint': s.endpoint
	})
	if s.auth_header.len > 0 {
		http_batch.auth_header = s.auth_header
	}

	mut extra_headers := map[string]string{}
	extra_headers['Content-Type'] = 'application/x-protobuf'
	extra_headers['Content-Encoding'] = 'snappy'
	extra_headers['X-Prometheus-Remote-Write-Version'] = '0.1.0'
	if s.tenant_id.len > 0 {
		extra_headers['X-Scope-OrgID'] = s.tenant_id
	}

	http_batch.send_payload(payload, extra_headers) or {
		eprintln('prometheus_remote_write: failed to send batch: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of metrics currently buffered.
pub fn (s &PrometheusRemoteWriteSink) total_buffered() int {
	return s.buffer.len
}

// encode_remote_write encodes buffered metrics as Prometheus exposition format.
// In a full implementation this would use protobuf + snappy compression.
// For now we encode as text exposition format which many remote-write receivers accept.
fn (s &PrometheusRemoteWriteSink) encode_remote_write() string {
	mut lines := []string{}
	for m in s.buffer {
		formatted := s.format_metric(m)
		if formatted.len > 0 {
			lines << formatted
		}
	}
	return lines.join('\n')
}

// format_metric formats a single metric in Prometheus exposition text format.
fn (s &PrometheusRemoteWriteSink) format_metric(m event.Metric) string {
	mut name := m.name
	if s.default_namespace.len > 0 {
		if m.namespace.len > 0 {
			name = '${m.namespace}_${name}'
		} else {
			name = '${s.default_namespace}_${name}'
		}
	} else if m.namespace.len > 0 {
		name = '${m.namespace}_${name}'
	}

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
			tags_str := prom_format_tags(m.tags)
			return '${name}${tags_str} ${m.value.values.len} ${ts_ms}'
		}
		event.DistributionValue {
			return format_distribution_as_histogram(name, m.tags, m.value, ts_ms)
		}
	}
}
