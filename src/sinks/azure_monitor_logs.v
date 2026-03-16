module sinks

import event
import json
import net.http
import os
import time

// AzureMonitorLogsSink sends log events to Azure Monitor Logs (Log Analytics)
// via the Data Collector API (also known as the HTTP Data Collector API).
// Mirrors Vector's azure_monitor_logs sink.
//
// Config options:
//   customer_id:           Log Analytics workspace ID (required)
//   shared_key:            Primary or secondary key (required, or set via env)
//   log_type:              Custom log type name (required, becomes <LogType>_CL table)
//   endpoint:              Custom endpoint (default: https://<customer_id>.ods.opinsights.azure.com)
//   azure_resource_id:     Optional Azure resource ID for resource-context logging
//   time_generated_key:    Field name to use as TimeGenerated (optional)
//   encoding.codec:        json or text (default: json)
//   batch.max_events:      Max events per API call (default: 100)
//   batch.timeout_secs:    Max seconds before flushing (default: 1)
pub struct AzureMonitorLogsSink {
	customer_id        string
	shared_key         string
	log_type           string
	endpoint           string
	azure_resource_id  string
	time_generated_key string
	codec              AzureMonitorCodec
	batch_max          int = 100
	batch_timeout      time.Duration = 1 * time.second
mut:
	buffer     []string
	last_flush time.Time
}

enum AzureMonitorCodec {
	json_codec
	text_codec
}

// new_azure_monitor_logs creates a new AzureMonitorLogsSink from config options.
pub fn new_azure_monitor_logs(opts map[string]string) !AzureMonitorLogsSink {
	customer_id := opts['customer_id'] or {
		return error('azure_monitor_logs: customer_id is required')
	}
	if customer_id.len == 0 {
		return error('azure_monitor_logs: customer_id is required')
	}

	mut shared_key := opts['auth.shared_key'] or { '' }
	if shared_key.len == 0 {
		shared_key = os.getenv('AZURE_MONITOR_SHARED_KEY')
	}

	log_type := opts['log_type'] or {
		return error('azure_monitor_logs: log_type is required')
	}
	if log_type.len == 0 {
		return error('azure_monitor_logs: log_type is required')
	}

	endpoint := opts['endpoint'] or { 'https://${customer_id}.ods.opinsights.azure.com' }
	azure_resource_id := opts['azure_resource_id'] or { '' }
	time_generated_key := opts['time_generated_key'] or { '' }

	codec := match opts['encoding.codec'] or { 'json' } {
		'text' { AzureMonitorCodec.text_codec }
		else { AzureMonitorCodec.json_codec }
	}

	mut batch_max := 100
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 100
		}
	}

	mut batch_timeout_secs := 1.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 1.0
		}
	}

	return AzureMonitorLogsSink{
		customer_id: customer_id
		shared_key: shared_key
		log_type: log_type
		endpoint: endpoint
		azure_resource_id: azure_resource_id
		time_generated_key: time_generated_key
		codec: codec
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s AzureMonitorLogsSink) send(e event.Event) ! {
	match e {
		event.LogEvent {
			message := match s.codec {
				.text_codec {
					encoded_msg := json.encode(e.message())
					'{"message":${encoded_msg}}'
				}
				.json_codec { e.to_json() }
			}

			s.buffer << message

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

// flush sends buffered events to the Azure Monitor Data Collector API.
pub fn (mut s AzureMonitorLogsSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	payload := s.build_payload()

	s.post_data(payload) or {
		eprintln('azure_monitor_logs: post failed: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &AzureMonitorLogsSink) total_buffered() int {
	return s.buffer.len
}

// build_payload constructs the JSON array payload from buffered events.
pub fn (s &AzureMonitorLogsSink) build_payload() string {
	return '[${s.buffer.join(",")}]'
}

// build_monitor_url constructs the Data Collector API URL.
pub fn build_monitor_url(endpoint string) string {
	return '${endpoint}/api/logs?api-version=2016-04-01'
}

fn (s &AzureMonitorLogsSink) post_data(payload string) ! {
	url := build_monitor_url(s.endpoint)
	now := time.utc()
	date_str := azure_rfc1123_date(now)
	content_length := payload.len.str()

	mut header := http.Header{}
	header.add_custom('Content-Type', 'application/json') or {}
	header.add_custom('Log-Type', s.log_type) or {}
	header.add_custom('x-ms-date', date_str) or {}

	if s.azure_resource_id.len > 0 {
		header.add_custom('x-ms-AzureResourceId', s.azure_resource_id) or {}
	}
	if s.time_generated_key.len > 0 {
		header.add_custom('time-generated-field', s.time_generated_key) or {}
	}

	if s.shared_key.len > 0 {
		string_to_sign := 'POST\n${content_length}\napplication/json\nx-ms-date:${date_str}\n/api/logs'
		signature := azure_sign(s.shared_key, string_to_sign)
		header.add_custom('Authorization', 'SharedKey ${s.customer_id}:${signature}') or {}
	}

	resp := http.fetch(http.FetchConfig{
		url: url
		method: .post
		data: payload
		header: header
		verbose: false
	}) or {
		return error('Azure Monitor HTTP request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('Azure Monitor HTTP ${resp.status_code}: ${resp.body}')
	}
}
