module sinks

import event
import time

// InfluxDbSink sends metric events to InfluxDB via the v2 write API.
// Mirrors Vector's influxdb_logs and influxdb_metrics sinks.
//
// Metrics are formatted as InfluxDB line protocol and batched before sending
// to {endpoint}/api/v2/write?org={org}&bucket={bucket}&precision=ns.
// Log events are sent as measurement "logs" with the message as a field.
//
// Config options:
//   endpoint:            InfluxDB URL (required, e.g., "http://localhost:8086")
//   org:                 Organization name (required for v2)
//   bucket:              Bucket name (required)
//   token:               API token for authentication (required)
//   measurement:         Default measurement name for logs (default: "logs")
//   encoding.codec:      json or text (default: json) — for log events only
//   batch.max_events:    Max events per batch (default: 100)
//   batch.timeout_secs:  Batch timeout in seconds (default: 1)
//   tags_key:            Log event field containing extra tags (default: "")
pub struct InfluxDbSink {
	endpoint      string
	org           string
	bucket        string
	token         string
	measurement   string = 'logs'
	batch_max     int    = 100
	batch_timeout time.Duration = 1 * time.second
mut:
	buffer     []string
	last_flush time.Time
}

// new_influxdb creates a new InfluxDbSink from config options.
pub fn new_influxdb(opts map[string]string) !InfluxDbSink {
	endpoint := opts['endpoint'] or {
		return error('influxdb: endpoint is required')
	}
	org := opts['org'] or {
		return error('influxdb: org is required')
	}
	bucket := opts['bucket'] or {
		return error('influxdb: bucket is required')
	}
	token := opts['token'] or {
		return error('influxdb: token is required')
	}

	measurement := opts['measurement'] or { 'logs' }

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return InfluxDbSink{
		endpoint: endpoint.trim_right('/')
		org: org
		bucket: bucket
		token: token
		measurement: measurement
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s InfluxDbSink) send(e event.Event) ! {
	line := s.encode_line_protocol(e)
	if line.len > 0 {
		s.buffer << line
	}

	if s.buffer.len >= s.batch_max {
		s.flush()!
	}

	if time.since(s.last_flush) > s.batch_timeout && s.buffer.len > 0 {
		s.flush()!
	}
}

// flush sends all buffered line protocol data to InfluxDB.
pub fn (mut s InfluxDbSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	payload := s.buffer.join('\n')
	url := '${s.endpoint}/api/v2/write?org=${s.org}&bucket=${s.bucket}&precision=ns'

	mut http_batch := new_http_batch({
		'endpoint': url
	})
	http_batch.auth_header = 'Token ${s.token}'

	mut extra_headers := map[string]string{}
	extra_headers['Content-Type'] = 'text/plain; charset=utf-8'

	http_batch.send_payload(payload, extra_headers) or {
		eprintln('influxdb: failed to send batch: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &InfluxDbSink) total_buffered() int {
	return s.buffer.len
}

// encode_line_protocol encodes an event as an InfluxDB line protocol string.
// Format: measurement,tag1=val1,tag2=val2 field1=value1,field2=value2 timestamp_ns
pub fn (s &InfluxDbSink) encode_line_protocol(e event.Event) string {
	match e {
		event.Metric {
			return s.encode_metric(e)
		}
		event.LogEvent {
			return s.encode_log(e)
		}
		event.TraceEvent {
			return s.encode_trace(e)
		}
	}
}

// encode_metric encodes a metric event as line protocol.
fn (s &InfluxDbSink) encode_metric(m event.Metric) string {
	measurement := if m.namespace.len > 0 {
		'${m.namespace}.${m.name}'
	} else {
		m.name
	}

	// Build tag set from metric tags
	mut tag_parts := []string{}
	for k, v in m.tags {
		tag_parts << '${escape_lp_key(k)}=${escape_lp_tag_value(v)}'
	}

	tag_str := if tag_parts.len > 0 { ',${tag_parts.join(",")}' } else { '' }

	// Build field set from metric value
	fields := encode_metric_fields(m.value)
	ts := m.timestamp.unix() * 1_000_000_000

	return '${escape_lp_measurement(measurement)}${tag_str} ${fields} ${ts}'
}

// encode_log encodes a log event as line protocol.
fn (s &InfluxDbSink) encode_log(e event.LogEvent) string {
	msg := e.message()
	escaped_msg := escape_lp_field_value(msg)
	ts := time.now().unix() * 1_000_000_000
	return '${escape_lp_measurement(s.measurement)} message="${escaped_msg}" ${ts}'
}

// encode_trace encodes a trace event as line protocol.
fn (s &InfluxDbSink) encode_trace(e event.TraceEvent) string {
	ts := time.now().unix() * 1_000_000_000
	return '${escape_lp_measurement(s.measurement)} trace=true ${ts}'
}

// encode_metric_fields encodes metric value fields for line protocol.
fn encode_metric_fields(v event.MetricValue) string {
	match v {
		event.CounterValue {
			return 'value=${v.value}'
		}
		event.GaugeValue {
			return 'value=${v.value}'
		}
		event.SetValue {
			return 'count=${v.values.len}i'
		}
		event.DistributionValue {
			mut total := f64(0)
			mut count := u64(0)
			for sample in v.samples {
				total += sample.value * f64(sample.rate)
				count += u64(sample.rate)
			}
			return 'sum=${total},count=${count}i'
		}
		event.HistogramValue {
			return 'sum=${v.sum},count=${v.count}i'
		}
		event.SummaryValue {
			return 'sum=${v.sum},count=${v.count}i'
		}
	}
}

// escape_lp_measurement escapes measurement name for line protocol.
// Commas and spaces must be escaped.
fn escape_lp_measurement(s string) string {
	return s.replace(',', '\\,').replace(' ', '\\ ')
}

// escape_lp_key escapes a tag key or field key for line protocol.
fn escape_lp_key(s string) string {
	return s.replace(',', '\\,').replace('=', '\\=').replace(' ', '\\ ')
}

// escape_lp_tag_value escapes a tag value for line protocol.
fn escape_lp_tag_value(s string) string {
	return s.replace(',', '\\,').replace('=', '\\=').replace(' ', '\\ ')
}

// escape_lp_field_value escapes a string field value for line protocol.
fn escape_lp_field_value(s string) string {
	return s.replace('\\', '\\\\').replace('"', '\\"')
}
