module transforms

import event
import json
import time

// MetricToLogTransform converts metric events into log events.
// Mirrors Vector's metric_to_log transform (src/transforms/metric_to_log/).
//
// Each metric is serialized to a log event with structured fields:
//   name, namespace, kind, timestamp, tags.*, counter/gauge/set/distribution/histogram/summary
//
// Config options:
//   host_tag:              Tag key to promote to top-level "host" field (default: "host")
//   timezone:              Timezone for timestamp formatting (default: local)
//   metric_tag_values:     "single" or "full" — how to represent tag values (default: single)
pub struct MetricToLogTransform {
	host_tag          string
	metric_tag_values string
}

// new_metric_to_log creates a new MetricToLogTransform from config options.
pub fn new_metric_to_log(opts map[string]string) !MetricToLogTransform {
	return MetricToLogTransform{
		host_tag: opts['host_tag'] or { 'host' }
		metric_tag_values: opts['metric_tag_values'] or { 'single' }
	}
}

// transform converts a metric event to a log event.
pub fn (t &MetricToLogTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.Metric {
			mut log := event.new_log('')

			// Core metric fields
			log.set('name', event.Value(e.name))
			if e.namespace.len > 0 {
				log.set('namespace', event.Value(e.namespace))
			}

			kind_str := match e.kind {
				.incremental { 'incremental' }
				.absolute { 'absolute' }
			}
			log.set('kind', event.Value(kind_str))

			// Timestamp
			if e.timestamp.unix() > 0 {
				log.set('timestamp', event.Value(e.timestamp))
			} else {
				log.set('timestamp', event.Value(time.now()))
			}

			// Tags
			if e.tags.len > 0 {
				mut tag_map := map[string]event.Value{}
				for k, v in e.tags {
					tag_map[k] = event.Value(v)
				}
				log.set('tags', event.Value(tag_map))

				// Promote host_tag to top-level
				if t.host_tag.len > 0 {
					if host_val := e.tags[t.host_tag] {
						log.set('host', event.Value(host_val))
					}
				}
			}

			// Metric value
			match e.value {
				event.CounterValue {
					mut counter_map := map[string]event.Value{}
					counter_map['value'] = event.Value(event.Float(e.value.value))
					log.set('counter', event.Value(counter_map))
				}
				event.GaugeValue {
					mut gauge_map := map[string]event.Value{}
					gauge_map['value'] = event.Value(event.Float(e.value.value))
					log.set('gauge', event.Value(gauge_map))
				}
				event.SetValue {
					mut vals := []event.Value{}
					for sv in e.value.values {
						vals << event.Value(sv)
					}
					mut set_map := map[string]event.Value{}
					set_map['values'] = event.Value(vals)
					log.set('set', event.Value(set_map))
				}
				event.DistributionValue {
					mut dist_map := map[string]event.Value{}
					mut samples := []event.Value{}
					for s in e.value.samples {
						mut sm := map[string]event.Value{}
						sm['value'] = event.Value(event.Float(s.value))
						sm['rate'] = event.Value(int(s.rate))
						samples << event.Value(sm)
					}
					dist_map['samples'] = event.Value(samples)
					stat_str := match e.value.statistic {
						.histogram { 'histogram' }
						.summary { 'summary' }
					}
					dist_map['statistic'] = event.Value(stat_str)
					log.set('distribution', event.Value(dist_map))
				}
				event.HistogramValue {
					mut hist_map := map[string]event.Value{}
					mut buckets := []event.Value{}
					for b in e.value.buckets {
						mut bm := map[string]event.Value{}
						bm['upper_limit'] = event.Value(event.Float(b.upper_limit))
						bm['count'] = event.Value(int(b.count))
						buckets << event.Value(bm)
					}
					hist_map['buckets'] = event.Value(buckets)
					hist_map['count'] = event.Value(int(e.value.count))
					hist_map['sum'] = event.Value(event.Float(e.value.sum))
					log.set('histogram', event.Value(hist_map))
				}
				event.SummaryValue {
					mut summ_map := map[string]event.Value{}
					mut quantiles := []event.Value{}
					for q in e.value.quantiles {
						mut qm := map[string]event.Value{}
						qm['quantile'] = event.Value(event.Float(q.quantile))
						qm['value'] = event.Value(event.Float(q.value))
						quantiles << event.Value(qm)
					}
					summ_map['quantiles'] = event.Value(quantiles)
					summ_map['count'] = event.Value(int(e.value.count))
					summ_map['sum'] = event.Value(event.Float(e.value.sum))
					log.set('summary', event.Value(summ_map))
				}
			}

			// Set message to metric name for readability
			log.set('message', event.Value(e.name))
			log.meta.source_type = 'metric_to_log'

			return [event.Event(log)]
		}
		else {
			return [e]
		}
	}
}
