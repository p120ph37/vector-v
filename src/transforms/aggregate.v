module transforms

import event
import time

// AggregateTransform aggregates metric events over a configurable time interval.
// Mirrors Vector's aggregate transform (src/transforms/aggregate/).
//
// Incoming metrics are accumulated per unique (name, namespace, tags, kind) tuple.
// Counters are summed, gauges keep the latest value, sets are unioned.
// When the interval elapses, accumulated metrics are flushed.
//
// Non-metric events pass through unchanged.
//
// Config options:
//   interval_ms:   Aggregation window in milliseconds (default: 10000)
//   mode:          "auto" or "manual" (default: auto; manual requires explicit flush_if_expired)
pub struct AggregateTransform {
	interval time.Duration
mut:
	buckets    map[string]AggBucket
	last_flush time.Time
}

struct AggBucket {
mut:
	name      string
	namespace string
	tags      map[string]string
	kind      event.MetricKind
	counter   f64
	gauge     f64
	set       map[string]bool
	histogram AggHistogram
	summary   AggSummary
	typ       AggMetricType
	timestamp time.Time
}

struct AggHistogram {
mut:
	buckets map[string]u64 // upper_limit_str -> count
	count   u64
	sum     f64
}

struct AggSummary {
mut:
	count u64
	sum   f64
}

enum AggMetricType {
	counter
	gauge
	set
	histogram
	summary
	distribution
}

// new_aggregate creates a new AggregateTransform from config options.
pub fn new_aggregate(opts map[string]string) !AggregateTransform {
	mut interval_ms := 10000
	if ims := opts['interval_ms'] {
		interval_ms = ims.int()
		if interval_ms <= 0 {
			interval_ms = 10000
		}
	}

	return AggregateTransform{
		interval: time.Duration(i64(interval_ms) * 1_000_000)
		last_flush: time.now()
	}
}

// transform accumulates a metric or passes through non-metric events.
pub fn (mut t AggregateTransform) transform(e event.Event) ![]event.Event {
	mut result := []event.Event{}

	// Check if flush is needed
	t.flush_if_expired(mut result)

	match e {
		event.Metric {
			key := t.metric_key(e)
			if key in t.buckets {
				mut bucket := t.buckets[key]
				t.merge_metric(mut bucket, e)
				t.buckets[key] = bucket
			} else {
				t.buckets[key] = t.init_bucket(e)
			}
			return result
		}
		else {
			result << e
			return result
		}
	}
}

// flush_all flushes all accumulated metrics (call on shutdown).
pub fn (mut t AggregateTransform) flush_all() []event.Event {
	mut result := []event.Event{}
	for _, bucket in t.buckets {
		result << event.Event(t.bucket_to_metric(bucket))
	}
	t.buckets.clear()
	t.last_flush = time.now()
	return result
}

// flush_if_expired flushes if the interval has elapsed.
pub fn (mut t AggregateTransform) flush_if_expired(mut result []event.Event) {
	if time.since(t.last_flush) >= t.interval {
		for _, bucket in t.buckets {
			result << event.Event(t.bucket_to_metric(bucket))
		}
		t.buckets.clear()
		t.last_flush = time.now()
	}
}

fn (t &AggregateTransform) metric_key(m event.Metric) string {
	mut parts := []string{}
	parts << m.name
	parts << m.namespace
	kind_str := match m.kind {
		.incremental { 'inc' }
		.absolute { 'abs' }
	}
	parts << kind_str
	// Sort tags for consistent key
	mut tag_keys := m.tags.keys()
	tag_keys.sort()
	for k in tag_keys {
		parts << '${k}=${m.tags[k]}'
	}
	return parts.join('|')
}

fn (t &AggregateTransform) init_bucket(m event.Metric) AggBucket {
	mut b := AggBucket{
		name: m.name
		namespace: m.namespace
		tags: m.tags.clone()
		kind: m.kind
		timestamp: m.timestamp
	}

	match m.value {
		event.CounterValue {
			b.typ = .counter
			b.counter = m.value.value
		}
		event.GaugeValue {
			b.typ = .gauge
			b.gauge = m.value.value
		}
		event.SetValue {
			b.typ = .set
			for v in m.value.values {
				b.set[v] = true
			}
		}
		event.HistogramValue {
			b.typ = .histogram
			for bucket in m.value.buckets {
				key := '${bucket.upper_limit}'
				b.histogram.buckets[key] = bucket.count
			}
			b.histogram.count = m.value.count
			b.histogram.sum = m.value.sum
		}
		event.SummaryValue {
			b.typ = .summary
			b.summary.count = m.value.count
			b.summary.sum = m.value.sum
		}
		event.DistributionValue {
			b.typ = .distribution
			// Sum sample values as counter-like
			for s in m.value.samples {
				b.counter += s.value * f64(s.rate)
			}
		}
	}

	return b
}

fn (t &AggregateTransform) merge_metric(mut b AggBucket, m event.Metric) {
	b.timestamp = m.timestamp

	match m.value {
		event.CounterValue {
			if m.kind == .incremental {
				b.counter += m.value.value
			} else {
				b.counter = m.value.value
			}
		}
		event.GaugeValue {
			// Gauges always take the latest value
			b.gauge = m.value.value
		}
		event.SetValue {
			for v in m.value.values {
				b.set[v] = true
			}
		}
		event.HistogramValue {
			for bucket in m.value.buckets {
				key := '${bucket.upper_limit}'
				b.histogram.buckets[key] = (b.histogram.buckets[key] or { u64(0) }) + bucket.count
			}
			b.histogram.count += m.value.count
			b.histogram.sum += m.value.sum
		}
		event.SummaryValue {
			b.summary.count += m.value.count
			b.summary.sum += m.value.sum
		}
		event.DistributionValue {
			for s in m.value.samples {
				b.counter += s.value * f64(s.rate)
			}
		}
	}
}

fn (t &AggregateTransform) bucket_to_metric(b AggBucket) event.Metric {
	mut m := event.Metric{
		name: b.name
		namespace: b.namespace
		tags: b.tags.clone()
		kind: b.kind
		timestamp: b.timestamp
	}

	match b.typ {
		.counter, .distribution {
			m.value = event.MetricValue(event.CounterValue{value: b.counter})
		}
		.gauge {
			m.value = event.MetricValue(event.GaugeValue{value: b.gauge})
		}
		.set {
			mut vals := []string{cap: b.set.len}
			for v, _ in b.set {
				vals << v
			}
			m.value = event.MetricValue(event.SetValue{values: vals})
		}
		.histogram {
			mut buckets := []event.Bucket{}
			for key, count in b.histogram.buckets {
				buckets << event.Bucket{
					upper_limit: key.f64()
					count: count
				}
			}
			m.value = event.MetricValue(event.HistogramValue{
				buckets: buckets
				count: b.histogram.count
				sum: b.histogram.sum
			})
		}
		.summary {
			m.value = event.MetricValue(event.SummaryValue{
				count: b.summary.count
				sum: b.summary.sum
			})
		}
	}

	return m
}
