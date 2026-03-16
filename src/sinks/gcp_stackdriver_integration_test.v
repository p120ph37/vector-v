module sinks

import event
import mockserver

fn test_gcp_stackdriver_flush_to_server() {
	mut mock := mockserver.start(
		mockserver.post('/v2/entries:write', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_stackdriver({
		'project_id':       'test-project'
		'log_id':           'test-logs'
		'endpoint':         mock.url()
		'auth.api_key':     'test-key'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('hello stackdriver'))
	s.send(ev) or {}
	assert s.total_buffered() == 1

	s.flush()!
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].path == '/v2/entries:write'
	assert reqs[0].body.contains('"entries"')
	assert reqs[0].body.contains('hello stackdriver')
}

fn test_gcp_stackdriver_auto_flush() {
	mut mock := mockserver.start(
		mockserver.post('/v2/entries:write', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'endpoint':         mock.url()
		'batch.max_events': '2'
		'batch.timeout_ms': '3600000'
	})!

	ev1 := event.Event(event.new_log('msg1'))
	ev2 := event.Event(event.new_log('msg2'))
	s.send(ev1) or {}
	s.send(ev2) or {}

	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
}

fn test_gcp_stackdriver_server_error() {
	mut mock := mockserver.start(
		mockserver.post('/v2/entries:write', mockserver.respond(500, '{"error":"internal"}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'endpoint':         mock.url()
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('will fail'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('500')
		return
	}
	assert false, 'expected error on 500'
}

fn test_gcp_stackdriver_api_key_header() {
	mut mock := mockserver.start(
		mockserver.post('/v2/entries:write', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'endpoint':         mock.url()
		'auth.api_key':     'secret-key'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('key test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	api_key := reqs[0].headers['x-goog-api-key'] or { '' }
	assert api_key == 'secret-key'
}

fn test_gcp_stackdriver_log_name_in_payload() {
	mut mock := mockserver.start(
		mockserver.post('/v2/entries:write', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_stackdriver({
		'project_id':       'my-project'
		'log_id':           'app-logs'
		'endpoint':         mock.url()
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('log name test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body.contains('projects/my-project/logs/app-logs')
}

fn test_gcp_stackdriver_resource_in_payload() {
	mut mock := mockserver.start(
		mockserver.post('/v2/entries:write', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_stackdriver({
		'project_id':               'proj'
		'log_id':                   'logs'
		'endpoint':                 mock.url()
		'resource.type':            'gce_instance'
		'resource.labels.zone':     'us-east1-b'
		'resource.labels.instance': 'vm-1'
		'batch.max_events':         '1000'
		'batch.timeout_ms':         '3600000'
	})!

	ev := event.Event(event.new_log('resource test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body.contains('"type":"gce_instance"')
	assert reqs[0].body.contains('us-east1-b')
}

fn test_gcp_stackdriver_text_payload() {
	mut mock := mockserver.start(
		mockserver.post('/v2/entries:write', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'endpoint':         mock.url()
		'encoding.codec':   'text'
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	ev := event.Event(event.new_log('plain text msg'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body.contains('"textPayload"')
	assert reqs[0].body.contains('plain text msg')
}

fn test_gcp_stackdriver_multiple_entries() {
	mut mock := mockserver.start(
		mockserver.post('/v2/entries:write', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_stackdriver({
		'project_id':       'proj'
		'log_id':           'logs'
		'endpoint':         mock.url()
		'batch.max_events': '1000'
		'batch.timeout_ms': '3600000'
	})!

	for i in 0 .. 3 {
		ev := event.Event(event.new_log('entry ${i}'))
		s.send(ev) or {}
	}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body.contains('entry 0')
	assert reqs[0].body.contains('entry 1')
	assert reqs[0].body.contains('entry 2')
}
