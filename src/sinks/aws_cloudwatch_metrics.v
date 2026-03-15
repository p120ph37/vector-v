module sinks

import aws
import event
import json
import time

// CloudWatchMetricsSink sends metrics to AWS CloudWatch using the Embedded Metric
// Format (EMF). EMF metrics are sent as structured JSON log events to CloudWatch
// Logs, which automatically extracts metric data.
//
// This approach mirrors how many production systems publish CloudWatch metrics:
// by writing EMF-formatted log events to a CloudWatch Logs stream. CloudWatch
// automatically parses the _aws metadata and creates metric data points.
//
// Config options:
//   region:                    AWS region (e.g., us-east-1)
//   namespace:                 CloudWatch metric namespace (default: "Vector")
//   group_name:                Log group for EMF logs (default: /metrics/vector)
//   stream_name:               Log stream for EMF logs (default: vector-metrics)
//   create_missing_group:      Auto-create log group (default: true)
//   create_missing_stream:     Auto-create log stream (default: true)
//   batch.max_events:          Max events per PutLogEvents call (default: 100)
//   batch.timeout_secs:        Max seconds before flushing (default: 1)
//   endpoint:                  Custom endpoint URL (for testing/localstack)
//   auth.access_key_id:        Explicit AWS access key
//   auth.secret_access_key:    Explicit AWS secret key
//   auth.session_token:        Explicit session token
//   auth.profile:              AWS profile name
pub struct CloudWatchMetricsSink {
	namespace    string
	group_name   string
	stream_name  string
	region       string
	endpoint     string
	creds        aws.AwsCredentials
	create_missing_group  bool = true
	create_missing_stream bool = true
	batch_max    int = 100
	batch_timeout time.Duration = 1 * time.second
mut:
	buffer       []EmfEntry
	last_flush   time.Time
	initialized  bool
}

struct EmfEntry {
	timestamp_ms i64
	emf_json     string
}

// new_cloudwatch_metrics creates a new CloudWatchMetricsSink from config options.
pub fn new_cloudwatch_metrics(opts map[string]string) !CloudWatchMetricsSink {
	resolved := aws.resolve_credentials(opts)!
	if resolved.creds.access_key_id.len == 0 && resolved.source != .none {
		return error('aws_cloudwatch_metrics: no AWS credentials found')
	}

	region := if resolved.creds.region.len > 0 {
		resolved.creds.region
	} else {
		opts['region'] or { 'us-east-1' }
	}

	namespace := opts['namespace'] or { 'Vector' }
	group_name := opts['group_name'] or { '/metrics/vector' }
	stream_name := opts['stream_name'] or { 'vector-metrics' }
	endpoint := opts['endpoint'] or { 'https://logs.${region}.amazonaws.com' }

	cmg_val := opts['create_missing_group'] or { 'true' }
	cms_val := opts['create_missing_stream'] or { 'true' }

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
		if batch_max > 10000 {
			batch_max = 10000
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return CloudWatchMetricsSink{
		namespace: namespace
		group_name: group_name
		stream_name: stream_name
		region: region
		endpoint: endpoint
		creds: aws.AwsCredentials{
			access_key_id: resolved.creds.access_key_id
			secret_access_key: resolved.creds.secret_access_key
			session_token: resolved.creds.session_token
			region: region
		}
		create_missing_group: cmg_val == 'true'
		create_missing_stream: cms_val == 'true'
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send converts a metric event to EMF format and buffers it.
pub fn (mut s CloudWatchMetricsSink) send(e event.Event) ! {
	match e {
		event.Metric {
			emf := s.metric_to_emf(e)
			s.buffer << emf

			if s.buffer.len >= s.batch_max {
				s.flush()!
			}
		}
		else {}
	}

	if time.since(s.last_flush) > s.batch_timeout && s.buffer.len > 0 {
		s.flush()!
	}
}

fn (mut s CloudWatchMetricsSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	if !s.initialized {
		if s.create_missing_group {
			s.ensure_log_group() or {
				eprintln('cloudwatch_metrics: failed to create log group: ${err}')
			}
		}
		if s.create_missing_stream {
			s.ensure_log_stream() or {
				eprintln('cloudwatch_metrics: failed to create log stream: ${err}')
			}
		}
		s.initialized = true
	}

	s.put_log_events() or {
		eprintln('cloudwatch_metrics: PutLogEvents failed: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

fn (s &CloudWatchMetricsSink) metric_to_emf(m event.Metric) EmfEntry {
	ts_ms := m.timestamp.unix_milli()

	// Determine metric type and value
	mut metric_value := 0.0
	mut unit := 'None'
	metric_type := match m.value {
		event.CounterValue {
			metric_value = m.value.value
			'Count'
		}
		event.GaugeValue {
			metric_value = m.value.value
			'None'
		}
		event.DistributionValue {
			if m.value.samples.len > 0 {
				metric_value = m.value.samples[0].value
			}
			'None'
		}
		event.HistogramValue {
			metric_value = m.value.sum
			unit = 'Count'
			'None'
		}
		event.SummaryValue {
			metric_value = m.value.sum
			'None'
		}
		event.SetValue {
			metric_value = f64(m.value.values.len)
			unit = 'Count'
			'Count'
		}
	}

	metric_name := if m.namespace.len > 0 {
		'${m.namespace}.${m.name}'
	} else {
		m.name
	}

	// Build EMF JSON
	emf := build_emf_json(s.namespace, metric_name, metric_value, unit, metric_type,
		m.tags, ts_ms)

	return EmfEntry{
		timestamp_ms: ts_ms
		emf_json: emf
	}
}

// build_emf_json constructs an EMF-formatted JSON string.
// Exported for testing.
pub fn build_emf_json(namespace string, metric_name string, value f64, unit string, metric_type string, dimensions map[string]string, timestamp_ms i64) string {
	// Build dimension keys list
	mut dim_keys := []string{}
	for k, _ in dimensions {
		dim_keys << json.encode(k)
	}

	dim_keys_json := '[${dim_keys.join(",")}]'

	// EMF structure:
	// {
	//   "_aws": {
	//     "Timestamp": <ms>,
	//     "CloudWatchMetrics": [{
	//       "Namespace": "...",
	//       "Dimensions": [["dim1","dim2"]],
	//       "Metrics": [{"Name":"...", "Unit":"...", "StorageResolution": 60}]
	//     }]
	//   },
	//   "dim1": "val1",
	//   "metric_name": value
	// }

	mut parts := []string{}
	parts << '"_aws":{"Timestamp":${timestamp_ms},"CloudWatchMetrics":[{"Namespace":${json.encode(namespace)},"Dimensions":[${dim_keys_json}],"Metrics":[{"Name":${json.encode(metric_name)},"Unit":${json.encode(unit)}}]}]}'

	// Add dimension values as top-level keys
	for k, v in dimensions {
		parts << '${json.encode(k)}:${json.encode(v)}'
	}

	// Add metric value as top-level key
	// Format float without trailing zeros for clean JSON
	value_str := format_f64(value)
	parts << '${json.encode(metric_name)}:${value_str}'

	return '{${parts.join(",")}}'
}

fn format_f64(v f64) string {
	if v == f64(i64(v)) {
		return '${i64(v)}'
	}
	return '${v}'
}

fn (s &CloudWatchMetricsSink) put_log_events() ! {
	mut log_events := []string{}
	for entry in s.buffer {
		escaped := json.encode(entry.emf_json)
		log_events << '{"timestamp":${entry.timestamp_ms},"message":${escaped}}'
	}

	payload := '{"logGroupName":${json.encode(s.group_name)},"logStreamName":${json.encode(s.stream_name)},"logEvents":[${log_events.join(",")}]}'

	s.call_api('Logs_20140328.PutLogEvents', payload)!
}

fn (s &CloudWatchMetricsSink) ensure_log_group() ! {
	payload := '{"logGroupName":${json.encode(s.group_name)}}'
	s.call_api('Logs_20140328.CreateLogGroup', payload) or {
		if err.msg().contains('ResourceAlreadyExistsException') || err.msg().contains('already exists') {
			return
		}
		return err
	}
}

fn (s &CloudWatchMetricsSink) ensure_log_stream() ! {
	payload := '{"logGroupName":${json.encode(s.group_name)},"logStreamName":${json.encode(s.stream_name)}}'
	s.call_api('Logs_20140328.CreateLogStream', payload) or {
		if err.msg().contains('ResourceAlreadyExistsException') || err.msg().contains('already exists') {
			return
		}
		return err
	}
}

fn (s &CloudWatchMetricsSink) call_api(target string, payload string) ! {
	aws_send_payload(s.endpoint, s.creds, s.region, 'logs', target, payload)!
}

// total_buffered returns the number of EMF entries currently buffered.
pub fn (s &CloudWatchMetricsSink) total_buffered() int {
	return s.buffer.len
}

// build_put_log_events_payload builds the PutLogEvents JSON payload.
// Exported for testing.
pub fn (s &CloudWatchMetricsSink) build_put_log_events_payload() string {
	mut log_events := []string{}
	for entry in s.buffer {
		escaped := json.encode(entry.emf_json)
		log_events << '{"timestamp":${entry.timestamp_ms},"message":${escaped}}'
	}
	return '{"logGroupName":${json.encode(s.group_name)},"logStreamName":${json.encode(s.stream_name)},"logEvents":[${log_events.join(",")}]}'
}
