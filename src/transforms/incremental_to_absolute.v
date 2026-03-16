module transforms

import event

// IncrementalToAbsoluteTransform converts incremental metrics to absolute
// metrics by maintaining running state for each metric name.
//
// For counters, the incremental value is added to a running total.
// For gauges, the latest value is kept (gauges are already absolute semantically).
// For sets, the values are unioned across incremental updates.
//
// Non-metric events pass through unchanged. Metrics that are already
// absolute pass through unchanged.
//
// Config options:
//   (none required)
pub struct IncrementalToAbsoluteTransform {
mut:
	counters map[string]f64
	gauges   map[string]f64
	sets     map[string]map[string]bool
}

// new_incremental_to_absolute creates a new IncrementalToAbsoluteTransform.
pub fn new_incremental_to_absolute(opts map[string]string) !IncrementalToAbsoluteTransform {
	return IncrementalToAbsoluteTransform{}
}

// transform converts an incremental metric to absolute by accumulating state.
pub fn (mut t IncrementalToAbsoluteTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.Metric {
			// Already absolute — pass through
			if e.kind == .absolute {
				return [event.Event(e)]
			}

			// Build a state key from name + tags for unique tracking
			key := build_metric_key(e)

			match e.value {
				event.CounterValue {
					if key in t.counters {
						t.counters[key] = t.counters[key] + e.value.value
					} else {
						t.counters[key] = e.value.value
					}
					mut m := event.Metric{
						name: e.name
						namespace: e.namespace
						tags: e.tags.clone()
						kind: .absolute
						value: event.MetricValue(event.CounterValue{
							value: t.counters[key]
						})
						timestamp: e.timestamp
						meta: e.meta
					}
					return [event.Event(m)]
				}
				event.GaugeValue {
					t.gauges[key] = e.value.value
					mut m := event.Metric{
						name: e.name
						namespace: e.namespace
						tags: e.tags.clone()
						kind: .absolute
						value: event.MetricValue(event.GaugeValue{
							value: t.gauges[key]
						})
						timestamp: e.timestamp
						meta: e.meta
					}
					return [event.Event(m)]
				}
				event.SetValue {
					if key !in t.sets {
						t.sets[key] = map[string]bool{}
					}
					for v in e.value.values {
						t.sets[key][v] = true
					}
					mut values := t.sets[key].keys()
					values.sort()
					mut m := event.Metric{
						name: e.name
						namespace: e.namespace
						tags: e.tags.clone()
						kind: .absolute
						value: event.MetricValue(event.SetValue{
							values: values
						})
						timestamp: e.timestamp
						meta: e.meta
					}
					return [event.Event(m)]
				}
				else {
					// Unsupported metric type for incremental — pass through as-is
					return [event.Event(e)]
				}
			}
		}
		else {
			// Non-metric events pass through unchanged
			return [e]
		}
	}
}

// state_counter returns the current accumulated counter value for a metric name.
// Exported for testing.
pub fn (t &IncrementalToAbsoluteTransform) state_counter(name string) f64 {
	return t.counters[name] or { 0.0 }
}

// state_gauge returns the current gauge value for a metric name.
// Exported for testing.
pub fn (t &IncrementalToAbsoluteTransform) state_gauge(name string) f64 {
	return t.gauges[name] or { 0.0 }
}

// state_set_values returns the current accumulated set values for a metric name.
// Exported for testing.
pub fn (t &IncrementalToAbsoluteTransform) state_set_values(name string) []string {
	if name in t.sets {
		mut values := t.sets[name].keys()
		values.sort()
		return values
	}
	return []string{}
}

fn build_metric_key(m event.Metric) string {
	mut key := m.name
	if m.namespace.len > 0 {
		key = '${m.namespace}.${m.name}'
	}
	if m.tags.len > 0 {
		mut tag_keys := m.tags.keys()
		tag_keys.sort()
		for tk in tag_keys {
			key += ';${tk}=${m.tags[tk]}'
		}
	}
	return key
}
