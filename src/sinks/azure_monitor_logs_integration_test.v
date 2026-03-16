module sinks

import event
import mockserver

fn test_azure_monitor_flush_to_server() {
	mut mock := mockserver.start(
		mockserver.post('/api/logs?api-version=2016-04-01', mockserver.respond(200, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_monitor_logs({
		'customer_id':    'ws-123'
		'log_type':       'TestLog'
		'auth.shared_key': 'dGVzdGtleQ=='
		'endpoint':       mock.url()
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('hello azure monitor'))
	s.send(ev) or {}
	assert s.total_buffered() == 1

	s.flush()!
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].path.contains('/api/logs')
	assert reqs[0].body.contains('hello azure monitor')
}

fn test_azure_monitor_auto_flush() {
	mut mock := mockserver.start(
		mockserver.post('/api/logs?api-version=2016-04-01', mockserver.respond(200, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_monitor_logs({
		'customer_id':      'ws-123'
		'log_type':         'TestLog'
		'endpoint':         mock.url()
		'batch.max_events': '2'
	})!

	ev1 := event.Event(event.new_log('msg1'))
	ev2 := event.Event(event.new_log('msg2'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
}

fn test_azure_monitor_server_error() {
	mut mock := mockserver.start(
		mockserver.post('/api/logs?api-version=2016-04-01', mockserver.respond(500, '{"error":"fail"}'))
	)!
	defer { mock.stop() }

	mut s := new_azure_monitor_logs({
		'customer_id':      'ws-123'
		'log_type':         'TestLog'
		'endpoint':         mock.url()
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('will fail'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('500')
		return
	}
	assert false, 'expected error on 500'
}

fn test_azure_monitor_shared_key_auth() {
	mut mock := mockserver.start(
		mockserver.post('/api/logs?api-version=2016-04-01', mockserver.respond(200, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_monitor_logs({
		'customer_id':    'ws-123'
		'log_type':       'TestLog'
		'auth.shared_key': 'dGVzdGtleQ=='
		'endpoint':       mock.url()
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('auth test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	auth := reqs[0].headers['authorization'] or { '' }
	assert auth.starts_with('SharedKey ')
}

fn test_azure_monitor_log_type_header() {
	mut mock := mockserver.start(
		mockserver.post('/api/logs?api-version=2016-04-01', mockserver.respond(200, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_monitor_logs({
		'customer_id':      'ws-123'
		'log_type':         'MyCustomLog'
		'endpoint':         mock.url()
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('header test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	log_type := reqs[0].headers['log-type'] or { '' }
	assert log_type == 'MyCustomLog'
}

fn test_azure_monitor_resource_id_header() {
	mut mock := mockserver.start(
		mockserver.post('/api/logs?api-version=2016-04-01', mockserver.respond(200, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_monitor_logs({
		'customer_id':       'ws-123'
		'log_type':          'TestLog'
		'azure_resource_id': '/subscriptions/sub-1/resourceGroups/rg-1'
		'endpoint':          mock.url()
		'batch.max_events':  '1000'
	})!

	ev := event.Event(event.new_log('resource test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	resource_id := reqs[0].headers['x-ms-azureresourceid'] or { '' }
	assert resource_id.contains('/subscriptions/')
}

fn test_azure_monitor_time_generated_header() {
	mut mock := mockserver.start(
		mockserver.post('/api/logs?api-version=2016-04-01', mockserver.respond(200, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_monitor_logs({
		'customer_id':        'ws-123'
		'log_type':           'TestLog'
		'time_generated_key': 'event_time'
		'endpoint':           mock.url()
		'batch.max_events':   '1000'
	})!

	ev := event.Event(event.new_log('time test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	tg := reqs[0].headers['time-generated-field'] or { '' }
	assert tg == 'event_time'
}

fn test_azure_monitor_payload_is_json_array() {
	mut mock := mockserver.start(
		mockserver.post('/api/logs?api-version=2016-04-01', mockserver.respond(200, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_monitor_logs({
		'customer_id':      'ws-123'
		'log_type':         'TestLog'
		'endpoint':         mock.url()
		'batch.max_events': '1000'
	})!

	ev1 := event.Event(event.new_log('msg1'))
	ev2 := event.Event(event.new_log('msg2'))
	s.send(ev1) or {}
	s.send(ev2) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body.starts_with('[')
	assert reqs[0].body.ends_with(']')
	assert reqs[0].body.contains('msg1')
	assert reqs[0].body.contains('msg2')
}
