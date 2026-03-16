module sinks

import event

fn test_new_redis_defaults() {
	s := new_redis({
		'key': 'mylist'
	}) or { panic(err.str()) }
	assert s.key == 'mylist'
	assert s.addr.host == '127.0.0.1'
	assert s.addr.port == 6379
	assert s.addr.password == ''
	assert s.mode == .lpush
	assert s.codec == .json_codec
	assert s.batch_max == 100
}

fn test_new_redis_missing_key() {
	new_redis(map[string]string{}) or {
		assert err.msg().contains('key is required')
		return
	}
	assert false, 'expected error for missing key'
}

fn test_new_redis_custom() {
	s := new_redis({
		'key':              'events'
		'url':              'redis://myhost:6380'
		'mode':             'rpush'
		'encoding.codec':   'text'
		'batch.max_events': '50'
	}) or { panic(err.str()) }
	assert s.key == 'events'
	assert s.addr.host == 'myhost'
	assert s.addr.port == 6380
	assert s.mode == .rpush
	assert s.codec == .text_codec
	assert s.batch_max == 50
}

fn test_encode_redis_command() {
	// Simple command
	result := encode_redis_command(['LPUSH', 'key', 'val'])
	assert result.contains('*3\r\n')
	assert result.contains('\$5\r\nLPUSH\r\n')
	assert result.contains('\$3\r\nkey\r\n')
	assert result.contains('\$3\r\nval\r\n')

	// Single argument
	result2 := encode_redis_command(['PING'])
	assert result2 == '*1\r\n\$4\r\nPING\r\n'
}

fn test_parse_redis_sink_url() {
	// Default URL
	addr1 := parse_redis_sink_url('redis://127.0.0.1:6379')
	assert addr1.host == '127.0.0.1'
	assert addr1.port == 6379
	assert addr1.password == ''

	// Custom host and port
	addr2 := parse_redis_sink_url('redis://myredis:6380')
	assert addr2.host == 'myredis'
	assert addr2.port == 6380

	// With password
	addr3 := parse_redis_sink_url('redis://:secret@localhost:6379')
	assert addr3.host == 'localhost'
	assert addr3.port == 6379
	assert addr3.password == 'secret'

	// With trailing path (database number)
	addr4 := parse_redis_sink_url('redis://host:6379/0')
	assert addr4.host == 'host'
	assert addr4.port == 6379

	// Host only, no port
	addr5 := parse_redis_sink_url('redis://myhost')
	assert addr5.host == 'myhost'
	assert addr5.port == 6379

	// rediss:// scheme
	addr6 := parse_redis_sink_url('rediss://secure:6380')
	assert addr6.host == 'secure'
	assert addr6.port == 6380
}

fn test_redis_send_buffers() {
	mut s := new_redis({
		'key':              'mylist'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('message ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}

fn test_redis_total_buffered() {
	mut s := new_redis({
		'key':              'mylist'
		'batch.max_events': '10000'
	}) or { panic(err.str()) }

	assert s.total_buffered() == 0
	ev := event.Event(event.new_log('hello'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	s.send(ev) or {}
	assert s.total_buffered() == 2
}

fn test_redis_flush_empty() {
	mut s := new_redis({
		'key': 'mylist'
	}) or { panic(err.str()) }
	s.flush() or {
		assert false, 'flush of empty buffer should not error'
	}
	assert s.total_buffered() == 0
}

fn test_redis_publish_mode() {
	s := new_redis({
		'key':  'mychannel'
		'mode': 'publish'
	}) or { panic(err.str()) }
	assert s.mode == .publish
	assert s.key == 'mychannel'
}

fn test_redis_registry() {
	sink := build_sink('redis', {
		'key': 'testlist'
	}) or { panic(err.str()) }
	match sink {
		RedisSink {
			assert sink.key == 'testlist'
			assert sink.mode == .lpush
		}
		else {
			assert false, 'expected RedisSink'
		}
	}
}
