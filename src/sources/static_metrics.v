module sources

import event
import time

// StaticMetricsSource emits fixed metric values at configurable intervals.
// Useful for synthetic monitoring and testing metric pipelines.
//
// Config options:
//   interval_secs:              Emission interval in seconds (default: 10)
//   metrics.<name>.type:        Metric type: counter, gauge (required per metric)
//   metrics.<name>.value:       Metric value (required per metric)
//   metrics.<name>.tags.<key>:  Tag key=value on the metric
//   namespace:                  Optional metric namespace prefix
pub struct StaticMetricsSource {
	interval  time.Duration = 10 * time.second
	metrics   []StaticMetricDef
	namespace string
}

// StaticMetricDef holds the definition of a single static metric.
struct StaticMetricDef {
	name   string
	typ    StaticMetricType
	value  f64
	tags   map[string]string
}

enum StaticMetricType {
	counter
	gauge
}

// new_static_metrics creates a new StaticMetricsSource from config options.
pub fn new_static_metrics(opts map[string]string) StaticMetricsSource {
	mut interval_secs := 10.0
	if s := opts['interval_secs'] {
		interval_secs = s.f64()
		if interval_secs <= 0 {
			interval_secs = 10.0
		}
	}

	namespace := opts['namespace'] or { '' }

	// Discover metric names from keys matching "metrics.<name>.type"
	mut metric_names := map[string]bool{}
	for key, _ in opts {
		if key.starts_with('metrics.') {
			parts := key.split('.')
			if parts.len >= 3 {
				metric_names[parts[1]] = true
			}
		}
	}

	mut metrics := []StaticMetricDef{}
	for name, _ in metric_names {
		type_key := 'metrics.${name}.type'
		value_key := 'metrics.${name}.value'

		typ_str := opts[type_key] or { continue }
		val_str := opts[value_key] or { '0' }

		typ := match typ_str {
			'counter' { StaticMetricType.counter }
			'gauge' { StaticMetricType.gauge }
			else { continue }
		}

		val := val_str.f64()

		// Collect tags
		mut tags := map[string]string{}
		tag_prefix := 'metrics.${name}.tags.'
		for k, v in opts {
			if k.starts_with(tag_prefix) {
				tag_name := k[tag_prefix.len..]
				if tag_name.len > 0 {
					tags[tag_name] = v
				}
			}
		}

		metrics << StaticMetricDef{
			name: name
			typ: typ
			value: val
			tags: tags
		}
	}

	return StaticMetricsSource{
		interval: time.Duration(i64(interval_secs * 1_000_000_000))
		metrics: metrics
		namespace: namespace
	}
}

// run emits configured metrics at the configured interval.
pub fn (s &StaticMetricsSource) run(output chan event.Event) {
	for {
		for m in s.metrics {
			mut metric := event.Metric{
				name: m.name
				namespace: s.namespace
				tags: m.tags.clone()
				timestamp: time.now()
				meta: event.EventMetadata{
					source_type: 'static_metrics'
				}
			}

			match m.typ {
				.counter {
					metric.kind = .incremental
					metric.value = event.CounterValue{
						value: m.value
					}
				}
				.gauge {
					metric.kind = .absolute
					metric.value = event.GaugeValue{
						value: m.value
					}
				}
			}

			output <- event.Event(metric)
		}
		time.sleep(s.interval)
	}
}
