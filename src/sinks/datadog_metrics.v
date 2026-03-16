module sinks

import event
import json
import time

// DatadogMetricsSink sends metric events to the Datadog Metrics API.
// Mirrors Vector's datadog_metrics sink (src/sinks/datadog/).
//
// Metrics are buffered as Datadog metric JSON objects and flushed as a JSON
// payload to {endpoint}/api/v2/series with the DD-API-KEY header.
//
// Config options:
//   api_key:             Datadog API key (required)
//   site:                Datadog site (default: "datadoghq.com")
//   endpoint:            Override endpoint URL (optional)
//   default_namespace:   Namespace prefix for metric names (default: "")
//   batch.max_events:    Max events per batch (default: 100)
//   batch.timeout_secs:  Batch timeout in seconds (default: 5)
pub struct DatadogMetricsSink {
	api_key           string
	endpoint          string
	default_namespace string
	batch_max         int = 100
	batch_timeout     time.Duration = 5 * time.second
mut:
	buffer     []string
	last_flush time.Time
}

// new_datadog_metrics creates a new DatadogMetricsSink from config options.
pub fn new_datadog_metrics(opts map[string]string) !DatadogMetricsSink {
	api_key := opts['api_key'] or {
		opts['default_api_key'] or {
			return error('datadog_metrics: api_key is required')
		}
	}

	site := opts['site'] or { 'datadoghq.com' }
	endpoint := opts['endpoint'] or { 'https://api.${site}' }

	default_namespace := opts['default_namespace'] or { '' }

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

	return DatadogMetricsSink{
		api_key: api_key
		endpoint: endpoint.trim_right('/')
		default_namespace: default_namespace
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers a metric event and flushes when batch is full or timeout expires.
// Non-metric events are silently dropped.
pub fn (mut s DatadogMetricsSink) send(e event.Event) ! {
	match e {
		event.Metric {
			encoded := s.encode_metric(e)
			if encoded.len > 0 {
				s.buffer << encoded
			}
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

// flush sends all buffered metrics to the Datadog Metrics API.
pub fn (mut s DatadogMetricsSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	payload := '{"series":[${s.buffer.join(",")}]}'
	url := '${s.endpoint}/api/v2/series'

	mut http_batch := new_http_batch({
		'endpoint': url
	})

	mut extra_headers := map[string]string{}
	extra_headers['DD-API-KEY'] = s.api_key
	extra_headers['Content-Type'] = 'application/json'

	http_batch.send_payload(payload, extra_headers) or {
		eprintln('datadog_metrics: failed to send batch: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of metrics currently buffered.
pub fn (s &DatadogMetricsSink) total_buffered() int {
	return s.buffer.len
}

// encode_metric encodes a single metric as a Datadog series JSON object.
fn (s &DatadogMetricsSink) encode_metric(m event.Metric) string {
	mut name := m.name
	if s.default_namespace.len > 0 {
		if m.namespace.len > 0 {
			name = '${m.namespace}.${name}'
		} else {
			name = '${s.default_namespace}.${name}'
		}
	} else if m.namespace.len > 0 {
		name = '${m.namespace}.${name}'
	}

	ts := m.timestamp.unix()
	metric_type := dd_metric_type(m.value)
	value := dd_metric_value(m.value)

	mut parts := []string{}
	parts << '"metric":${json.encode(name)}'
	parts << '"type":"${metric_type}"'
	parts << '"points":[{"timestamp":${ts},"value":${value}}]'

	// Add tags
	if m.tags.len > 0 {
		mut tag_list := []string{}
		for k, v in m.tags {
			tag_list << json.encode('${k}:${v}')
		}
		parts << '"tags":[${tag_list.join(",")}]'
	}

	return '{${parts.join(",")}}'
}

// dd_metric_type returns the Datadog metric type string.
fn dd_metric_type(v event.MetricValue) string {
	match v {
		event.CounterValue { return 'count' }
		event.GaugeValue { return 'gauge' }
		event.DistributionValue { return 'distribution' }
		event.HistogramValue { return 'gauge' }
		event.SummaryValue { return 'gauge' }
		event.SetValue { return 'gauge' }
	}
}

// dd_metric_value extracts the primary numeric value from a MetricValue.
fn dd_metric_value(v event.MetricValue) f64 {
	match v {
		event.CounterValue { return v.value }
		event.GaugeValue { return v.value }
		event.DistributionValue {
			mut total := f64(0)
			for sample in v.samples {
				total += sample.value * f64(sample.rate)
			}
			return total
		}
		event.HistogramValue { return v.sum }
		event.SummaryValue { return v.sum }
		event.SetValue { return f64(v.values.len) }
	}
}
