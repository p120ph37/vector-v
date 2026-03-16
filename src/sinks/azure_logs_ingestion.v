module sinks

import event
import net.http
import time

// AzureLogsIngestionSink sends log events to the Azure Logs Ingestion API
// (Data Collection Rules / Data Collection Endpoints).
// Mirrors Vector's azure_logs_ingestion sink.
//
// Events are batched and sent via the Logs Ingestion REST API.
//
// Config options:
//   endpoint:              DCE endpoint URL (required)
//   dcr_immutable_id:      Data Collection Rule immutable ID (required)
//   stream_name:           Stream name (required, e.g. "Custom-MyTable_CL")
//   auth.bearer_token:     Bearer token for authentication
//   encoding.codec:        json (default)
//   batch.max_events:      Max events per API call (default: 100)
//   batch.timeout_ms:      Flush timeout in milliseconds (default: 1000)
pub struct AzureLogsIngestionSink {
pub mut:
	endpoint         string
	dcr_immutable_id string
	stream_name      string
	bearer_token     string
	encoding_codec   string = 'json'
	batch_max_events int    = 100
	batch_timeout_ms int    = 1000
	buffer           []string
	last_flush       time.Time
}

// new_azure_logs_ingestion creates a new AzureLogsIngestionSink from config options.
pub fn new_azure_logs_ingestion(opts map[string]string) !AzureLogsIngestionSink {
	endpoint := opts['endpoint'] or {
		return error('azure_logs_ingestion: endpoint is required')
	}
	if endpoint.len == 0 {
		return error('azure_logs_ingestion: endpoint is required')
	}

	dcr_immutable_id := opts['dcr_immutable_id'] or {
		return error('azure_logs_ingestion: dcr_immutable_id is required')
	}
	if dcr_immutable_id.len == 0 {
		return error('azure_logs_ingestion: dcr_immutable_id is required')
	}

	stream_name := opts['stream_name'] or {
		return error('azure_logs_ingestion: stream_name is required')
	}
	if stream_name.len == 0 {
		return error('azure_logs_ingestion: stream_name is required')
	}

	bearer_token := opts['auth.bearer_token'] or { '' }
	encoding_codec := opts['encoding.codec'] or { 'json' }

	mut batch_max_events := 100
	if v := opts['batch.max_events'] {
		batch_max_events = v.int()
		if batch_max_events <= 0 {
			batch_max_events = 100
		}
	}

	mut batch_timeout_ms := 1000
	if v := opts['batch.timeout_ms'] {
		batch_timeout_ms = v.int()
		if batch_timeout_ms <= 0 {
			batch_timeout_ms = 1000
		}
	}

	return AzureLogsIngestionSink{
		endpoint: endpoint
		dcr_immutable_id: dcr_immutable_id
		stream_name: stream_name
		bearer_token: bearer_token
		encoding_codec: encoding_codec
		batch_max_events: batch_max_events
		batch_timeout_ms: batch_timeout_ms
		last_flush: time.now()
	}
}

// build_ingestion_url constructs the Logs Ingestion API URL.
pub fn build_ingestion_url(endpoint string, dcr_immutable_id string, stream_name string) string {
	return '${endpoint}/dataCollectionRules/${dcr_immutable_id}/streams/${stream_name}?api-version=2023-01-01'
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s AzureLogsIngestionSink) send(e event.Event) ! {
	match e {
		event.LogEvent {
			message := e.to_json()
			s.buffer << message

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

// flush sends buffered entries to the Logs Ingestion API.
pub fn (mut s AzureLogsIngestionSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	url := build_ingestion_url(s.endpoint, s.dcr_immutable_id, s.stream_name)
	payload := s.build_payload()

	mut header := http.Header{}
	header.add_custom('Content-Type', 'application/json') or {}
	if s.bearer_token.len > 0 {
		header.add_custom('Authorization', 'Bearer ${s.bearer_token}') or {}
	}

	resp := http.fetch(http.FetchConfig{
		url: url
		method: .post
		data: payload
		header: header
		verbose: false
	}) or {
		return error('azure_logs_ingestion: request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('azure_logs_ingestion: HTTP ${resp.status_code}: ${resp.body}')
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of log entries currently buffered.
pub fn (s &AzureLogsIngestionSink) total_buffered() int {
	return s.buffer.len
}

// build_payload constructs the JSON array payload for the Logs Ingestion API.
pub fn (s &AzureLogsIngestionSink) build_payload() string {
	return '[${s.buffer.join(",")}]'
}
