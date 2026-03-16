module sinks

import event
import mockserver
import os

fn test_azure_blob_flush_to_server() {
	os.setenv('AZURE_STORAGE_ACCOUNT', 'teststorage', true)
	os.setenv('AZURE_STORAGE_KEY', 'dGVzdGtleQ==', true)
	defer {
		os.unsetenv('AZURE_STORAGE_ACCOUNT')
		os.unsetenv('AZURE_STORAGE_KEY')
	}

	mut mock := mockserver.start(
		mockserver.put_prefix('/', mockserver.respond(201, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_blob({
		'container_name':          'test-container'
		'endpoint':                mock.url()
		'auth.storage_access_key': 'dGVzdGtleQ=='
		'batch.max_events':        '1000'
	})!

	ev := event.Event(event.new_log('hello azure blob'))
	s.send(ev) or {}
	assert s.total_buffered() == 1

	s.flush()!
	assert s.total_buffered() == 0

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].method == 'PUT'
	assert reqs[0].path.contains('test-container')
	assert reqs[0].body.contains('hello azure blob')
}

fn test_azure_blob_auto_flush_on_batch_full() {
	os.setenv('AZURE_STORAGE_ACCOUNT', 'teststorage', true)
	os.setenv('AZURE_STORAGE_KEY', 'dGVzdGtleQ==', true)
	defer {
		os.unsetenv('AZURE_STORAGE_ACCOUNT')
		os.unsetenv('AZURE_STORAGE_KEY')
	}

	mut mock := mockserver.start(
		mockserver.put_prefix('/', mockserver.respond(201, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_blob({
		'container_name':   'c1'
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

fn test_azure_blob_server_error() {
	os.setenv('AZURE_STORAGE_ACCOUNT', 'teststorage', true)
	os.setenv('AZURE_STORAGE_KEY', 'dGVzdGtleQ==', true)
	defer {
		os.unsetenv('AZURE_STORAGE_ACCOUNT')
		os.unsetenv('AZURE_STORAGE_KEY')
	}

	mut mock := mockserver.start(
		mockserver.put_prefix('/', mockserver.respond(500, '{"error":"internal"}'))
	)!
	defer { mock.stop() }

	mut s := new_azure_blob({
		'container_name':   'c1'
		'endpoint':         mock.url()
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('will fail'))
	s.send(ev) or {}

	s.flush() or {
		assert err.msg().contains('500')
		return
	}
	assert false, 'expected error on 500 response'
}

fn test_azure_blob_shared_key_auth_header() {
	os.setenv('AZURE_STORAGE_ACCOUNT', 'teststorage', true)
	os.setenv('AZURE_STORAGE_KEY', 'dGVzdGtleQ==', true)
	defer {
		os.unsetenv('AZURE_STORAGE_ACCOUNT')
		os.unsetenv('AZURE_STORAGE_KEY')
	}

	mut mock := mockserver.start(
		mockserver.put_prefix('/', mockserver.respond(201, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_blob({
		'container_name':          'c1'
		'endpoint':                mock.url()
		'auth.storage_access_key': 'dGVzdGtleQ=='
		'batch.max_events':        '1000'
	})!

	ev := event.Event(event.new_log('auth test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	auth := reqs[0].headers['authorization'] or { '' }
	assert auth.starts_with('SharedKey ')
}

fn test_azure_blob_content_type_header() {
	os.setenv('AZURE_STORAGE_ACCOUNT', 'teststorage', true)
	os.setenv('AZURE_STORAGE_KEY', 'dGVzdGtleQ==', true)
	defer {
		os.unsetenv('AZURE_STORAGE_ACCOUNT')
		os.unsetenv('AZURE_STORAGE_KEY')
	}

	mut mock := mockserver.start(
		mockserver.put_prefix('/', mockserver.respond(201, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_blob({
		'container_name':   'c1'
		'endpoint':         mock.url()
		'encoding.codec':   'json'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('json blob'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	ct := reqs[0].headers['content-type'] or { '' }
	assert ct == 'application/json'
}

fn test_azure_blob_text_codec_to_server() {
	os.setenv('AZURE_STORAGE_ACCOUNT', 'teststorage', true)
	os.setenv('AZURE_STORAGE_KEY', 'dGVzdGtleQ==', true)
	defer {
		os.unsetenv('AZURE_STORAGE_ACCOUNT')
		os.unsetenv('AZURE_STORAGE_KEY')
	}

	mut mock := mockserver.start(
		mockserver.put_prefix('/', mockserver.respond(201, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_blob({
		'container_name':   'c1'
		'endpoint':         mock.url()
		'encoding.codec':   'text'
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('plain text'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	assert reqs[0].body == 'plain text'
}

fn test_azure_blob_ms_headers() {
	os.setenv('AZURE_STORAGE_ACCOUNT', 'teststorage', true)
	os.setenv('AZURE_STORAGE_KEY', 'dGVzdGtleQ==', true)
	defer {
		os.unsetenv('AZURE_STORAGE_ACCOUNT')
		os.unsetenv('AZURE_STORAGE_KEY')
	}

	mut mock := mockserver.start(
		mockserver.put_prefix('/', mockserver.respond(201, ''))
	)!
	defer { mock.stop() }

	mut s := new_azure_blob({
		'container_name':   'c1'
		'endpoint':         mock.url()
		'batch.max_events': '1000'
	})!

	ev := event.Event(event.new_log('header test'))
	s.send(ev) or {}
	s.flush()!

	reqs := mock.wait_for_requests(1, 5000)
	assert reqs.len >= 1
	// Verify Azure-specific headers
	blob_type := reqs[0].headers['x-ms-blob-type'] or { '' }
	assert blob_type == 'BlockBlob'
	version := reqs[0].headers['x-ms-version'] or { '' }
	assert version == '2021-12-02'
	date := reqs[0].headers['x-ms-date'] or { '' }
	assert date.len > 0
}
