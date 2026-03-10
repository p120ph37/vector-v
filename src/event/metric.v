module event

import time

// MetricKind indicates whether a metric is absolute or incremental.
pub enum MetricKind {
	incremental
	absolute
}

// MetricValue holds the actual value of a metric, mirroring Vector's MetricValue.
pub type MetricValue = CounterValue | GaugeValue | SetValue | DistributionValue | HistogramValue | SummaryValue

pub struct CounterValue {
pub:
	value f64
}

pub struct GaugeValue {
pub:
	value f64
}

pub struct SetValue {
pub:
	values []string
}

pub struct DistributionValue {
pub:
	samples  []Sample
	statistic StatisticKind
}

pub struct Sample {
pub:
	value f64
	rate  u32
}

pub enum StatisticKind {
	histogram
	summary
}

pub struct HistogramValue {
pub:
	buckets []Bucket
	count   u64
	sum     f64
}

pub struct Bucket {
pub:
	upper_limit f64
	count       u64
}

pub struct SummaryValue {
pub:
	quantiles []Quantile
	count     u64
	sum       f64
}

pub struct Quantile {
pub:
	quantile f64
	value    f64
}

// Metric represents a metric event in the pipeline, mirroring Vector's Metric.
pub struct Metric {
pub mut:
	name      string
	namespace string
	tags      map[string]string
	kind      MetricKind
	value     MetricValue
	timestamp time.Time
	meta      EventMetadata
}

// new_counter creates a new counter metric.
pub fn new_counter(name string, value f64, kind MetricKind) Metric {
	return Metric{
		name: name
		kind: kind
		value: CounterValue{
			value: value
		}
		timestamp: time.now()
	}
}

// new_gauge creates a new gauge metric.
pub fn new_gauge(name string, value f64) Metric {
	return Metric{
		name: name
		kind: .absolute
		value: GaugeValue{
			value: value
		}
		timestamp: time.now()
	}
}
