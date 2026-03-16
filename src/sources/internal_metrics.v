module sources

import event
import time

// InternalMetricsRegistry stores counters and gauges that components increment.
// Other parts of Vector-V register and update metrics here.
pub struct InternalMetricsRegistry {
mut:
	counters map[string]InternalCounter
	gauges   map[string]InternalGauge
	start_time time.Time = time.now()
}

struct InternalCounter {
	tags map[string]string
mut:
	value f64
}

struct InternalGauge {
	tags map[string]string
mut:
	value f64
}

// Global registry for internal metrics.
__global internal_metrics_registry = InternalMetricsRegistry{}

// register_internal_counter registers a counter metric with component tags.
pub fn register_internal_counter(name string, component_id string, component_type string, component_kind string) {
	key := '${name}|${component_id}'
	if key !in internal_metrics_registry.counters {
		internal_metrics_registry.counters[key] = InternalCounter{
			tags: {
				'component_id':   component_id
				'component_type': component_type
				'component_kind': component_kind
			}
		}
	}
}

// increment_internal_counter increments a counter by the given value.
pub fn increment_internal_counter(name string, component_id string, value f64) {
	key := '${name}|${component_id}'
	if key in internal_metrics_registry.counters {
		internal_metrics_registry.counters[key].value += value
	}
}

// register_internal_gauge registers a gauge metric with component tags.
pub fn register_internal_gauge(name string, component_id string, component_type string, component_kind string) {
	key := '${name}|${component_id}'
	if key !in internal_metrics_registry.gauges {
		internal_metrics_registry.gauges[key] = InternalGauge{
			tags: {
				'component_id':   component_id
				'component_type': component_type
				'component_kind': component_kind
			}
		}
	}
}

// set_internal_gauge sets a gauge to the given value.
pub fn set_internal_gauge(name string, component_id string, value f64) {
	key := '${name}|${component_id}'
	if key in internal_metrics_registry.gauges {
		internal_metrics_registry.gauges[key].value = value
	}
}

// InternalMetricsSource emits Vector-V's own internal metrics (component
// throughput, errors, uptime, etc). Mirrors Vector's internal_metrics source.
//
// Periodically scrapes the global InternalMetricsRegistry and emits metric
// events with namespace "vector" and tags: component_id, component_type,
// component_kind.
//
// Standard metrics emitted:
//   events_processed_total (counter) — per component
//   bytes_processed_total (counter) — per component
//   component_errors_total (counter)
//   uptime_seconds (gauge)
//   component_received_events_total (counter)
//   component_sent_events_total (counter)
//
// Config options:
//   scrape_interval_secs:  Scrape interval in seconds (default: 2)
pub struct InternalMetricsSource {
	scrape_interval time.Duration = 2 * time.second
}

// new_internal_metrics creates a new InternalMetricsSource from config options.
pub fn new_internal_metrics(opts map[string]string) InternalMetricsSource {
	mut scrape_secs := 2.0
	if s := opts['scrape_interval_secs'] {
		scrape_secs = s.f64()
		if scrape_secs <= 0 {
			scrape_secs = 2.0
		}
	}

	return InternalMetricsSource{
		scrape_interval: time.Duration(i64(scrape_secs * 1_000_000_000))
	}
}

// run periodically scrapes the internal metrics registry and emits events.
pub fn (s &InternalMetricsSource) run(output chan event.Event) {
	for {
		s.emit_metrics(output)
		time.sleep(s.scrape_interval)
	}
}

// emit_metrics scrapes all registered counters and gauges and emits them.
fn (s &InternalMetricsSource) emit_metrics(output chan event.Event) {
	now := time.now()

	// Emit uptime gauge (always present)
	uptime_secs := f64(now.unix() - internal_metrics_registry.start_time.unix())
	mut uptime_metric := event.Metric{
		name: 'uptime_seconds'
		namespace: 'vector'
		kind: .absolute
		value: event.GaugeValue{
			value: uptime_secs
		}
		timestamp: now
		meta: event.EventMetadata{
			source_type: 'internal_metrics'
		}
	}
	output <- event.Event(uptime_metric)

	// Emit all registered counters
	for key, counter in internal_metrics_registry.counters {
		name := key.split('|')[0] or { key }
		mut m := event.Metric{
			name: name
			namespace: 'vector'
			tags: counter.tags.clone()
			kind: .incremental
			value: event.CounterValue{
				value: counter.value
			}
			timestamp: now
			meta: event.EventMetadata{
				source_type: 'internal_metrics'
			}
		}
		output <- event.Event(m)
	}

	// Emit all registered gauges
	for key, gauge in internal_metrics_registry.gauges {
		name := key.split('|')[0] or { key }
		mut m := event.Metric{
			name: name
			namespace: 'vector'
			tags: gauge.tags.clone()
			kind: .absolute
			value: event.GaugeValue{
				value: gauge.value
			}
			timestamp: now
			meta: event.EventMetadata{
				source_type: 'internal_metrics'
			}
		}
		output <- event.Event(m)
	}
}

// collect_snapshot returns all current metrics without emitting to a channel.
// Useful for testing and introspection.
fn collect_internal_metrics_snapshot() []event.Metric {
	mut result := []event.Metric{}
	now := time.now()

	// Uptime
	uptime_secs := f64(now.unix() - internal_metrics_registry.start_time.unix())
	result << event.Metric{
		name: 'uptime_seconds'
		namespace: 'vector'
		kind: .absolute
		value: event.GaugeValue{
			value: uptime_secs
		}
		timestamp: now
		meta: event.EventMetadata{
			source_type: 'internal_metrics'
		}
	}

	for key, counter in internal_metrics_registry.counters {
		name := key.split('|')[0] or { key }
		result << event.Metric{
			name: name
			namespace: 'vector'
			tags: counter.tags.clone()
			kind: .incremental
			value: event.CounterValue{
				value: counter.value
			}
			timestamp: now
			meta: event.EventMetadata{
				source_type: 'internal_metrics'
			}
		}
	}

	for key, gauge in internal_metrics_registry.gauges {
		name := key.split('|')[0] or { key }
		result << event.Metric{
			name: name
			namespace: 'vector'
			tags: gauge.tags.clone()
			kind: .absolute
			value: event.GaugeValue{
				value: gauge.value
			}
			timestamp: now
			meta: event.EventMetadata{
				source_type: 'internal_metrics'
			}
		}
	}

	return result
}

// reset_internal_metrics_registry clears all counters and gauges.
// Used for testing.
fn reset_internal_metrics_registry() {
	internal_metrics_registry.counters = map[string]InternalCounter{}
	internal_metrics_registry.gauges = map[string]InternalGauge{}
	internal_metrics_registry.start_time = time.now()
}
