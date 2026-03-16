module transforms

import event
import time

// LogToMetricTransform converts log events into metric events.
// Mirrors Vector's log_to_metric transform (src/transforms/log_to_metric/).
//
// Extracts numeric values from log fields and creates counter, gauge, set,
// histogram, or summary metrics. Non-log events pass through unchanged.
//
// Config options:
//   metrics.0.type:         counter, gauge, set, histogram, summary
//   metrics.0.field:        Log field to extract value from
//   metrics.0.name:         Metric name (default: field name)
//   metrics.0.namespace:    Metric namespace (optional)
//   metrics.0.tags.*:       Static or dynamic tags ({{ field }})
//   metrics.0.kind:         incremental or absolute (default: incremental)
//   all_metrics:            If true, do not drop the original log (default: false)
pub struct LogToMetricTransform {
	metrics    []MetricConfig
	all_metrics bool
}

struct MetricConfig {
	typ       MetricType
	field     string
	name      string
	namespace string
	tags      map[string]string // key -> literal or "{{ field }}"
	kind      event.MetricKind
}

enum MetricType {
	counter
	gauge
	set
	histogram
	summary
}

// new_log_to_metric creates a new LogToMetricTransform from config options.
pub fn new_log_to_metric(opts map[string]string) !LogToMetricTransform {
	mut metrics := []MetricConfig{}

	// Parse metrics.N.type, metrics.N.field, etc.
	for i in 0 .. 32 {
		prefix := 'metrics.${i}.'
		typ_str := opts['${prefix}type'] or { break }

		field := opts['${prefix}field'] or {
			return error('log_to_metric: metrics.${i}.field is required')
		}

		typ := match typ_str {
			'counter' { MetricType.counter }
			'gauge' { MetricType.gauge }
			'set' { MetricType.set }
			'histogram' { MetricType.histogram }
			'summary' { MetricType.summary }
			else { return error('log_to_metric: unknown metric type "${typ_str}"') }
		}

		name := opts['${prefix}name'] or { field }
		namespace := opts['${prefix}namespace'] or { '' }

		kind := match opts['${prefix}kind'] or { 'incremental' } {
			'absolute' { event.MetricKind.absolute }
			else { event.MetricKind.incremental }
		}

		mut tags := map[string]string{}
		for k, v in opts {
			tag_prefix := '${prefix}tags.'
			if k.starts_with(tag_prefix) {
				tag_name := k[tag_prefix.len..]
				tags[tag_name] = v
			}
		}

		metrics << MetricConfig{
			typ: typ
			field: field
			name: name
			namespace: namespace
			tags: tags
			kind: kind
		}
	}

	if metrics.len == 0 {
		return error('log_to_metric: at least one metric definition required')
	}

	am_str := opts['all_metrics'] or { 'false' }
	all_metrics := am_str == 'true'

	return LogToMetricTransform{
		metrics: metrics
		all_metrics: all_metrics
	}
}

// transform converts a log event to one or more metric events.
pub fn (t &LogToMetricTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			mut result := []event.Event{}

			for mc in t.metrics {
				val := e.get(mc.field) or { continue }

				// Resolve tags
				mut resolved_tags := map[string]string{}
				for tag_key, tag_val in mc.tags {
					resolved_tags[tag_key] = resolve_template(tag_val, e)
				}

				metric := build_metric_from_config(mc, val, resolved_tags)
				result << event.Event(metric)
			}

			if result.len == 0 {
				// No metrics produced — pass through original if all_metrics
				if t.all_metrics {
					return [e]
				}
				return []
			}

			return result
		}
		else {
			return [e]
		}
	}
}

fn build_metric_from_config(mc MetricConfig, val event.Value, tags map[string]string) event.Metric {
	mut m := event.Metric{
		name: mc.name
		namespace: mc.namespace
		kind: mc.kind
		tags: tags
		timestamp: time.now()
	}

	match mc.typ {
		.counter {
			m.value = event.MetricValue(event.CounterValue{
				value: val_to_f64(val)
			})
		}
		.gauge {
			m.value = event.MetricValue(event.GaugeValue{
				value: val_to_f64(val)
			})
		}
		.set {
			m.value = event.MetricValue(event.SetValue{
				values: [event.value_to_string(val)]
			})
		}
		.histogram {
			m.value = event.MetricValue(event.DistributionValue{
				samples: [event.Sample{value: val_to_f64(val), rate: 1}]
				statistic: .histogram
			})
		}
		.summary {
			m.value = event.MetricValue(event.DistributionValue{
				samples: [event.Sample{value: val_to_f64(val), rate: 1}]
				statistic: .summary
			})
		}
	}

	return m
}

fn resolve_template(tmpl string, e event.LogEvent) string {
	// Handle {{ field }} template syntax
	if tmpl.starts_with('{{') && tmpl.ends_with('}}') {
		field := tmpl[2..tmpl.len - 2].trim_space()
		if val := e.get(field) {
			return event.value_to_string(val)
		}
		return ''
	}
	return tmpl
}

fn val_to_f64(v event.Value) f64 {
	match v {
		int { return f64(v) }
		event.Float { return f64(v) }
		string { return v.f64() }
		bool { return if v { 1.0 } else { 0.0 } }
		else { return 0.0 }
	}
}
