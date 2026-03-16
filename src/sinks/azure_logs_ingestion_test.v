module sinks

import event
import mockserver

// ---------------------------------------------------------------------------
// AzureLogsIngestionSink tests
// ---------------------------------------------------------------------------

fn test_new_azure_logs_ingestion_defaults() {
	s := new_azure_logs_ingestion({
		'endpoint':         'https://my-dce.eastus.ingest.monitor.azure.com'
		'dcr_immutable_id': 'dcr-abc123'
		'stream_name':      'Custom-MyTable_CL'
	})!
	assert s.endpoint == 'https://my-dce.eastus.ingest.monitor.azure.com'
	assert s.dcr_immutable_id == 'dcr-abc123'
	assert s.stream_name == 'Custom-MyTable_CL'
	assert s.bearer_token == ''
	assert s.encoding_codec == 'json'
	assert s.batch_max_events == 100
	assert s.batch_timeout_ms == 1000
	assert s.buffer.len == 0
}

fn test_new_azure_logs_ingestion_missing_endpoint() {
	new_azure_logs_ingestion({
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
	}) or {
		assert err.msg().contains('endpoint is required')
		return
	}
	assert false, 'expected error for missing endpoint'
}

fn test_new_azure_logs_ingestion_empty_endpoint() {
	new_azure_logs_ingestion({
		'endpoint':         ''
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
	}) or {
		assert err.msg().contains('endpoint is required')
		return
	}
	assert false, 'expected error for empty endpoint'
}

fn test_new_azure_logs_ingestion_missing_dcr() {
	new_azure_logs_ingestion({
		'endpoint':    'https://example.com'
		'stream_name': 'Custom-T'
	}) or {
		assert err.msg().contains('dcr_immutable_id is required')
		return
	}
	assert false, 'expected error for missing dcr_immutable_id'
}

fn test_new_azure_logs_ingestion_empty_dcr() {
	new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': ''
		'stream_name':      'Custom-T'
	}) or {
		assert err.msg().contains('dcr_immutable_id is required')
		return
	}
	assert false, 'expected error for empty dcr_immutable_id'
}

fn test_new_azure_logs_ingestion_missing_stream_name() {
	new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': 'dcr-abc'
	}) or {
		assert err.msg().contains('stream_name is required')
		return
	}
	assert false, 'expected error for missing stream_name'
}

fn test_new_azure_logs_ingestion_empty_stream_name() {
	new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      ''
	}) or {
		assert err.msg().contains('stream_name is required')
		return
	}
	assert false, 'expected error for empty stream_name'
}

fn test_new_azure_logs_ingestion_custom_config() {
	s := new_azure_logs_ingestion({
		'endpoint':          'https://custom-dce.ingest.monitor.azure.com'
		'dcr_immutable_id':  'dcr-xyz'
		'stream_name':       'Custom-Logs_CL'
		'auth.bearer_token': 'my-token-123'
		'batch.max_events':  '500'
		'batch.timeout_ms':  '2000'
	})!
	assert s.endpoint == 'https://custom-dce.ingest.monitor.azure.com'
	assert s.dcr_immutable_id == 'dcr-xyz'
	assert s.stream_name == 'Custom-Logs_CL'
	assert s.bearer_token == 'my-token-123'
	assert s.batch_max_events == 500
	assert s.batch_timeout_ms == 2000
}

fn test_azure_logs_ingestion_negative_batch_max() {
	s := new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
		'batch.max_events': '-1'
	})!
	assert s.batch_max_events == 100
}

fn test_azure_logs_ingestion_negative_batch_timeout() {
	s := new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
		'batch.timeout_ms': '0'
	})!
	assert s.batch_timeout_ms == 1000
}

fn test_build_ingestion_url() {
	url := build_ingestion_url(
		'https://my-dce.eastus.ingest.monitor.azure.com',
		'dcr-abc123',
		'Custom-MyTable_CL'
	)
	assert url == 'https://my-dce.eastus.ingest.monitor.azure.com/dataCollectionRules/dcr-abc123/streams/Custom-MyTable_CL?api-version=2023-01-01'
}

fn test_build_ingestion_url_custom_endpoint() {
	url := build_ingestion_url(
		'http://localhost:8080',
		'dcr-test',
		'Custom-Test_CL'
	)
	assert url == 'http://localhost:8080/dataCollectionRules/dcr-test/streams/Custom-Test_CL?api-version=2023-01-01'
}

fn test_azure_logs_ingestion_send_buffers() {
	mut s := new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('hello azure'))
	s.send(ev) or {}
	assert s.total_buffered() == 1

	ev2 := event.Event(event.new_log('second message'))
	s.send(ev2) or {}
	assert s.total_buffered() == 2
}

fn test_azure_logs_ingestion_total_buffered() {
	mut s := new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	assert s.total_buffered() == 0
	for i in 0 .. 5 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_azure_logs_ingestion_flush_empty() {
	mut s := new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
	})!

	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_azure_logs_ingestion_drops_non_log() {
	mut s := new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	metric := event.Event(event.Metric{
		name: 'test.gauge'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 42.0})
	})
	s.send(metric) or {}
	assert s.total_buffered() == 0
}

fn test_azure_logs_ingestion_build_payload() {
	mut s := new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('test message'))
	s.send(ev) or {}

	payload := s.build_payload()
	assert payload.starts_with('[')
	assert payload.ends_with(']')
	assert payload.contains('test message')
}

fn test_azure_logs_ingestion_build_payload_multiple() {
	mut s := new_azure_logs_ingestion({
		'endpoint':         'https://example.com'
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or {}
	}

	payload := s.build_payload()
	assert payload.starts_with('[')
	assert payload.ends_with(']')
	assert payload.contains('msg 0')
	assert payload.contains('msg 1')
	assert payload.contains('msg 2')
}

// ---------------------------------------------------------------------------
// Mock server integration tests
// ---------------------------------------------------------------------------

fn test_azure_logs_ingestion_flush_to_mock() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/dataCollectionRules/dcr-abc/streams/Custom-T', mockserver.respond(204, ''))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_azure_logs_ingestion({
		'endpoint':          mock.url()
		'dcr_immutable_id':  'dcr-abc'
		'stream_name':       'Custom-T'
		'auth.bearer_token': 'test-token'
		'batch.max_events':  '1000'
		'batch.timeout_ms':  '3600000'
	})!

	ev1 := event.Event(event.new_log('ingestion-1'))
	ev2 := event.Event(event.new_log('ingestion-2'))
	s.send(ev1) or {}
	s.send(ev2) or {}
	assert s.total_buffered() == 2

	s.flush() or { panic(err.str()) }
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].body.starts_with('[')
	assert reqs[0].headers['authorization'] == 'Bearer test-token'
}

fn test_azure_logs_ingestion_flush_error() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/dataCollectionRules/dcr-abc/streams/Custom-T', mockserver.respond(403, '{"error":"forbidden"}'))
	) or { panic(err.str()) }
	defer { mock.stop() }

	mut s := new_azure_logs_ingestion({
		'endpoint':         mock.url()
		'dcr_immutable_id': 'dcr-abc'
		'stream_name':      'Custom-T'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('will-fail'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('403')
		return
	}
}
