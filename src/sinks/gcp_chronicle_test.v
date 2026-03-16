module sinks

import event
import mockserver

// ---------------------------------------------------------------------------
// GcpChronicleSink tests
// ---------------------------------------------------------------------------

fn test_new_gcp_chronicle_defaults() {
	s := new_gcp_chronicle({
		'customer_id': 'cust-123'
		'log_type':    'WINEVTLOG'
	})!
	assert s.customer_id == 'cust-123'
	assert s.log_type == 'WINEVTLOG'
	assert s.region == 'us'
	assert s.namespace == ''
	assert s.api_key == ''
	assert s.encoding_codec == 'json'
	assert s.batch_max_events == 100
	assert s.batch_timeout_ms == 1000
	assert s.buffer.len == 0
}

fn test_new_gcp_chronicle_missing_customer_id() {
	new_gcp_chronicle({
		'log_type': 'WINEVTLOG'
	}) or {
		assert err.msg().contains('customer_id is required')
		return
	}
	assert false, 'expected error for missing customer_id'
}

fn test_new_gcp_chronicle_empty_customer_id() {
	new_gcp_chronicle({
		'customer_id': ''
		'log_type':    'WINEVTLOG'
	}) or {
		assert err.msg().contains('customer_id is required')
		return
	}
	assert false, 'expected error for empty customer_id'
}

fn test_new_gcp_chronicle_missing_log_type() {
	new_gcp_chronicle({
		'customer_id': 'cust-123'
	}) or {
		assert err.msg().contains('log_type is required')
		return
	}
	assert false, 'expected error for missing log_type'
}

fn test_new_gcp_chronicle_empty_log_type() {
	new_gcp_chronicle({
		'customer_id': 'cust-123'
		'log_type':    ''
	}) or {
		assert err.msg().contains('log_type is required')
		return
	}
	assert false, 'expected error for empty log_type'
}

fn test_new_gcp_chronicle_custom_config() {
	s := new_gcp_chronicle({
		'customer_id':           'cust-xyz'
		'log_type':              'SYSLOG'
		'region':                'europe'
		'namespace':             'prod-env'
		'auth.api_key':          'my-key'
		'auth.credentials_file': '/path/to/sa.json'
		'encoding.codec':        'text'
		'batch.max_events':      '500'
		'batch.timeout_ms':      '2000'
	})!
	assert s.customer_id == 'cust-xyz'
	assert s.log_type == 'SYSLOG'
	assert s.region == 'europe'
	assert s.namespace == 'prod-env'
	assert s.api_key == 'my-key'
	assert s.credentials_file == '/path/to/sa.json'
	assert s.encoding_codec == 'text'
	assert s.batch_max_events == 500
	assert s.batch_timeout_ms == 2000
}

fn test_gcp_chronicle_negative_batch_max() {
	s := new_gcp_chronicle({
		'customer_id':      'cust-123'
		'log_type':         'WINEVTLOG'
		'batch.max_events': '-1'
	})!
	assert s.batch_max_events == 100
}

fn test_gcp_chronicle_negative_batch_timeout() {
	s := new_gcp_chronicle({
		'customer_id':      'cust-123'
		'log_type':         'WINEVTLOG'
		'batch.timeout_ms': '0'
	})!
	assert s.batch_timeout_ms == 1000
}

fn test_build_chronicle_url() {
	url := build_chronicle_url('us')
	assert url == 'https://us-malachiteingestion-pa.googleapis.com/v2/unstructuredlogentries:batchCreate'
}

fn test_build_chronicle_url_europe() {
	url := build_chronicle_url('europe')
	assert url == 'https://europe-malachiteingestion-pa.googleapis.com/v2/unstructuredlogentries:batchCreate'
}

fn test_build_chronicle_url_asia() {
	url := build_chronicle_url('asia-southeast1')
	assert url == 'https://asia-southeast1-malachiteingestion-pa.googleapis.com/v2/unstructuredlogentries:batchCreate'
}

fn test_build_chronicle_url_with_endpoint() {
	url := build_chronicle_url_with_endpoint('http://localhost:8080')
	assert url == 'http://localhost:8080/v2/unstructuredlogentries:batchCreate'
}

fn test_gcp_chronicle_send_buffers() {
	mut s := new_gcp_chronicle({
		'customer_id':      'cust-123'
		'log_type':         'WINEVTLOG'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('hello chronicle'))
	s.send(ev) or {}
	assert s.total_buffered() == 1

	ev2 := event.Event(event.new_log('second message'))
	s.send(ev2) or {}
	assert s.total_buffered() == 2
}

fn test_gcp_chronicle_total_buffered() {
	mut s := new_gcp_chronicle({
		'customer_id':      'cust-123'
		'log_type':         'WINEVTLOG'
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

fn test_gcp_chronicle_flush_empty() {
	mut s := new_gcp_chronicle({
		'customer_id': 'cust-123'
		'log_type':    'WINEVTLOG'
	})!

	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_gcp_chronicle_drops_non_log() {
	mut s := new_gcp_chronicle({
		'customer_id':      'cust-123'
		'log_type':         'WINEVTLOG'
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

fn test_gcp_chronicle_build_entries_payload() {
	mut s := new_gcp_chronicle({
		'customer_id':      'cust-123'
		'log_type':         'WINEVTLOG'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('test message'))
	s.send(ev) or {}

	payload := s.build_entries_payload()
	assert payload.contains('"customer_id":"cust-123"')
	assert payload.contains('"log_type":"WINEVTLOG"')
	assert payload.contains('"entries":[')
	assert payload.contains('"log_text"')
	assert payload.contains('"ts_rfc3339"')
	// No namespace by default
	assert !payload.contains('"namespace"')
}

fn test_gcp_chronicle_build_entries_with_namespace() {
	mut s := new_gcp_chronicle({
		'customer_id':      'cust-123'
		'log_type':         'SYSLOG'
		'namespace':        'prod'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('namespaced'))
	s.send(ev) or {}

	payload := s.build_entries_payload()
	assert payload.contains('"namespace":"prod"')
}

fn test_gcp_chronicle_build_entries_text_codec() {
	mut s := new_gcp_chronicle({
		'customer_id':      'cust-123'
		'log_type':         'WINEVTLOG'
		'encoding.codec':   'text'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('plain text'))
	s.send(ev) or {}

	payload := s.build_entries_payload()
	assert payload.contains('"log_text":"plain text"')
}

fn test_gcp_chronicle_build_entries_multiple() {
	mut s := new_gcp_chronicle({
		'customer_id':      'cust-123'
		'log_type':         'WINEVTLOG'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('entry ${i}'))
		s.send(ev) or {}
	}

	payload := s.build_entries_payload()
	assert payload.contains('entry 0')
	assert payload.contains('entry 1')
	assert payload.contains('entry 2')
}
