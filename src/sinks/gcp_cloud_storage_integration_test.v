module sinks

import event
import mockserver

fn test_gcp_cloud_storage_flush_to_server() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/upload/storage/v1/b/', mockserver.respond(200, '{"name":"test.log"}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_cloud_storage({
		'bucket':          'test-bucket'
		'endpoint':        mock.url()
		'auth.api_key':    'test-key'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('hello gcs'))
	s.send(ev) or {}
	assert s.total_buffered() == 1

	s.flush()!
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'POST'
	assert reqs[0].path.contains('test-bucket')
	assert reqs[0].body.contains('hello gcs')
}

fn test_gcp_cloud_storage_auto_flush() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/upload/storage/v1/b/', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'endpoint':        mock.url()
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

fn test_gcp_cloud_storage_server_error() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/upload/storage/v1/b/', mockserver.respond(500, '{"error":"fail"}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'endpoint':        mock.url()
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

fn test_gcp_cloud_storage_api_key_header() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/upload/storage/v1/b/', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_cloud_storage({
		'bucket':       'b1'
		'endpoint':     mock.url()
		'auth.api_key': 'my-secret-key'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('api key test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	api_key := reqs[0].headers['x-goog-api-key'] or { '' }
	assert api_key == 'my-secret-key'
}

fn test_gcp_cloud_storage_content_type() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/upload/storage/v1/b/', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'endpoint':        mock.url()
		'encoding.codec':  'json'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('json test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	ct := reqs[0].headers['content-type'] or { '' }
	assert ct == 'application/json'
}

fn test_gcp_cloud_storage_text_codec_to_server() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/upload/storage/v1/b/', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'endpoint':        mock.url()
		'encoding.codec':  'text'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('plain text'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body == 'plain text'
}

fn test_gcp_cloud_storage_acl_header() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/upload/storage/v1/b/', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'endpoint':        mock.url()
		'acl':             'private'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('acl test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	acl := reqs[0].headers['x-goog-acl'] or { '' }
	assert acl == 'private'
}

fn test_gcp_cloud_storage_storage_class_header() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/upload/storage/v1/b/', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'endpoint':        mock.url()
		'storage_class':   'COLDLINE'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('class test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	sc := reqs[0].headers['x-goog-storage-class'] or { '' }
	assert sc == 'COLDLINE'
}

fn test_gcp_cloud_storage_metadata_headers() {
	mut mock := mockserver.start(
		mockserver.post_prefix('/upload/storage/v1/b/', mockserver.respond(200, '{}'))
	)!
	defer { mock.stop() }

	mut s := new_gcp_cloud_storage({
		'bucket':          'b1'
		'endpoint':        mock.url()
		'metadata.env':    'prod'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('meta test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	meta := reqs[0].headers['x-goog-meta-env'] or { '' }
	assert meta == 'prod'
}
