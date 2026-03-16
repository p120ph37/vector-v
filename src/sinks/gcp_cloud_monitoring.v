module sinks

import event
import json
import net.http
import os
import time

// GcpCloudMonitoringSink sends metric events to Google Cloud Monitoring
// (formerly Stackdriver Metrics) via the timeSeries.create REST API.
// Mirrors Vector's gcp_stackdriver_metrics sink.
//
// Metric events are converted to GCP TimeSeries format and sent in batches.
//
// Config options:
//   project_id:            GCP project ID (required)
//   default_namespace:     Default metric namespace prefix (optional)
//   endpoint:              Cloud Monitoring API endpoint
//                          (default: https://monitoring.googleapis.com)
//   auth.api_key:          API key authentication
//   auth.credentials_file: Service account JSON file path
//   resource.type:         Monitored resource type (default: "global")
//   resource.labels.*:     Monitored resource labels (optional)
//   batch.max_events:      Max metrics per API call (default: 200)
//   batch.timeout_ms:      Flush timeout in milliseconds (default: 1000)
pub struct GcpCloudMonitoringSink {
pub mut:
	project_id        string
	default_namespace string
	endpoint          string = 'https://monitoring.googleapis.com'
	api_key           string
	credentials_file  string
	resource_type     string = 'global'
	resource_labels   map[string]string
	batch_max_events  int = 200
	batch_timeout_ms  int = 1000
	buffer            []event.Metric
	last_flush        time.Time
}

// new_gcp_cloud_monitoring creates a new GcpCloudMonitoringSink from config options.
pub fn new_gcp_cloud_monitoring(opts map[string]string) !GcpCloudMonitoringSink {
	project_id := opts['project_id'] or {
		return error('gcp_cloud_monitoring: project_id is required')
	}
	if project_id.len == 0 {
		return error('gcp_cloud_monitoring: project_id is required')
	}

	default_namespace := opts['default_namespace'] or { '' }
	endpoint := opts['endpoint'] or { 'https://monitoring.googleapis.com' }
	api_key := opts['auth.api_key'] or { '' }

	credentials_file := opts['auth.credentials_file'] or {
		os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
	}

	resource_type := opts['resource.type'] or { 'global' }

	// Collect resource.labels.* options
	mut resource_labels := map[string]string{}
	for k, v in opts {
		if k.starts_with('resource.labels.') {
			label_key := k[16..] // strip "resource.labels." prefix
			resource_labels[label_key] = v
		}
	}

	mut batch_max_events := 200
	if v := opts['batch.max_events'] {
		batch_max_events = v.int()
		if batch_max_events <= 0 {
			batch_max_events = 200
		}
	}

	mut batch_timeout_ms := 1000
	if v := opts['batch.timeout_ms'] {
		batch_timeout_ms = v.int()
		if batch_timeout_ms <= 0 {
			batch_timeout_ms = 1000
		}
	}

	return GcpCloudMonitoringSink{
		project_id: project_id
		default_namespace: default_namespace
		endpoint: endpoint
		api_key: api_key
		credentials_file: credentials_file
		resource_type: resource_type
		resource_labels: resource_labels
		batch_max_events: batch_max_events
		batch_timeout_ms: batch_timeout_ms
		last_flush: time.now()
	}
}

// build_monitoring_url constructs the Cloud Monitoring timeSeries.create URL.
pub fn build_monitoring_url(endpoint string, project_id string) string {
	return '${endpoint}/v3/projects/${project_id}/timeSeries'
}

// send buffers a metric event and flushes when batch is full or timeout expires.
pub fn (mut s GcpCloudMonitoringSink) send(e event.Event) ! {
	match e {
		event.Metric {
			s.buffer << e

			if s.buffer.len >= s.batch_max_events {
				s.flush()!
			}
		}
		else {}
	}

	if time.since(s.last_flush) > time.Duration(i64(s.batch_timeout_ms) * 1_000_000) && s.buffer.len > 0 {
		s.flush()!
	}
}

// flush sends buffered metrics to the Cloud Monitoring API.
pub fn (mut s GcpCloudMonitoringSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	url := build_monitoring_url(s.endpoint, s.project_id)
	payload := s.build_time_series_payload()

	mut header := http.Header{}
	header.add_custom('Content-Type', 'application/json') or {}
	if s.api_key.len > 0 {
		header.add_custom('X-Goog-Api-Key', s.api_key) or {}
	}

	resp := http.fetch(http.FetchConfig{
		url: url
		method: .post
		data: payload
		header: header
		verbose: false
	}) or {
		return error('gcp_cloud_monitoring: request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('gcp_cloud_monitoring: HTTP ${resp.status_code}: ${resp.body}')
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of metrics currently buffered.
pub fn (s &GcpCloudMonitoringSink) total_buffered() int {
	return s.buffer.len
}

// build_time_series_payload constructs the timeSeries.create JSON payload.
pub fn (s &GcpCloudMonitoringSink) build_time_series_payload() string {
	// Build resource JSON
	mut resource_labels_parts := []string{}
	for k, v in s.resource_labels {
		resource_labels_parts << '${json.encode(k)}:${json.encode(v)}'
	}
	mut resource_json := '{"type":${json.encode(s.resource_type)}'
	if resource_labels_parts.len > 0 {
		resource_json += ',"labels":{${resource_labels_parts.join(",")}}'
	}
	resource_json += '}'

	mut time_series := []string{}
	for m in s.buffer {
		ts := s.metric_to_time_series(m, resource_json)
		if ts.len > 0 {
			time_series << ts
		}
	}

	return '{"timeSeries":[${time_series.join(",")}]}'
}

fn (s &GcpCloudMonitoringSink) metric_to_time_series(m event.Metric, resource_json string) string {
	// Build metric type
	mut metric_type := ''
	if s.default_namespace.len > 0 {
		metric_type = 'custom.googleapis.com/${s.default_namespace}/${m.name}'
	} else if m.namespace.len > 0 {
		metric_type = 'custom.googleapis.com/${m.namespace}/${m.name}'
	} else {
		metric_type = 'custom.googleapis.com/${m.name}'
	}

	// Build metric labels from tags
	mut label_parts := []string{}
	for k, v in m.tags {
		label_parts << '${json.encode(k)}:${json.encode(v)}'
	}
	mut labels_json := ''
	if label_parts.len > 0 {
		labels_json = ',"labels":{${label_parts.join(",")}}'
	}

	// Timestamp
	now := time.utc()
	ts := if m.timestamp.unix() > 0 {
		'${m.timestamp.year:04d}-${m.timestamp.month:02d}-${m.timestamp.day:02d}T${m.timestamp.hour:02d}:${m.timestamp.minute:02d}:${m.timestamp.second:02d}Z'
	} else {
		'${now.year:04d}-${now.month:02d}-${now.day:02d}T${now.hour:02d}:${now.minute:02d}:${now.second:02d}Z'
	}

	// Build value based on metric type
	mut value_json := ''
	mut metric_kind := ''

	match m.value {
		event.CounterValue {
			metric_kind = 'CUMULATIVE'
			value_json = '"doubleValue":${m.value.value}'
		}
		event.GaugeValue {
			metric_kind = 'GAUGE'
			value_json = '"doubleValue":${m.value.value}'
		}
		event.DistributionValue {
			metric_kind = 'GAUGE'
			if m.value.samples.len > 0 {
				value_json = '"doubleValue":${m.value.samples[0].value}'
			} else {
				value_json = '"doubleValue":0'
			}
		}
		else {
			return ''
		}
	}

	mut ts_json := '{"metric":{"type":${json.encode(metric_type)}${labels_json}}'
	ts_json += ',"resource":${resource_json}'
	ts_json += ',"metricKind":"${metric_kind}"'
	ts_json += ',"valueType":"DOUBLE"'
	ts_json += ',"points":[{"interval":{"endTime":"${ts}"},"value":{${value_json}}}]'
	ts_json += '}'

	return ts_json
}
