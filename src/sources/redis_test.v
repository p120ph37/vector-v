module sources

fn test_parse_redis_url_default() {
	addr := parse_redis_url('redis://myhost:6380')
	assert addr.host == 'myhost'
	assert addr.port == 6380
	assert addr.auth == ''
}

fn test_parse_redis_url_with_auth() {
	addr := parse_redis_url('redis://user:secret@myhost:6380')
	assert addr.host == 'myhost'
	assert addr.port == 6380
	assert addr.auth == 'user:secret'
}

fn test_parse_redis_url_password_only() {
	addr := parse_redis_url('redis://:mypass@myhost:6380')
	assert addr.host == 'myhost'
	assert addr.port == 6380
	assert addr.auth == 'mypass'
}

fn test_parse_redis_url_no_port() {
	addr := parse_redis_url('redis://somehost')
	assert addr.host == 'somehost'
	assert addr.port == 6379
	assert addr.auth == ''
}

fn test_parse_redis_url_with_db_path() {
	addr := parse_redis_url('redis://myhost:6380/0')
	assert addr.host == 'myhost'
	assert addr.port == 6380
}

fn test_parse_redis_url_rediss_scheme() {
	addr := parse_redis_url('rediss://secure:7000')
	assert addr.host == 'secure'
	assert addr.port == 7000
}

fn test_parse_redis_url_empty_host() {
	addr := parse_redis_url('redis://:6379')
	// Empty host before the colon defaults to 127.0.0.1
	assert addr.host == '127.0.0.1'
	assert addr.port == 6379
}

fn test_new_redis_source_defaults() {
	s := new_redis_source({
		'key': 'my-channel'
	}) or { panic(err.str()) }
	assert s.url == 'redis://127.0.0.1:6379'
	assert s.key == 'my-channel'
	assert s.mode == .subscribe
	assert s.list_option == 'lpop'
	assert s.poll_interval_ms == 1000
	assert s.host == '127.0.0.1'
	assert s.port == 6379
	assert s.auth == ''
}

fn test_new_redis_source_missing_key() {
	new_redis_source(map[string]string{}) or {
		assert err.msg().contains('key is required')
		return
	}
	assert false, 'expected error for missing key'
}

fn test_new_redis_source_custom() {
	s := new_redis_source({
		'key':  'events'
		'url':  'redis://myredis:7000'
		'mode': 'subscribe'
	}) or { panic(err.str()) }
	assert s.url == 'redis://myredis:7000'
	assert s.key == 'events'
	assert s.mode == .subscribe
	assert s.host == 'myredis'
	assert s.port == 7000
}

fn test_new_redis_source_list_mode() {
	s := new_redis_source({
		'key':               'work-queue'
		'mode':              'list'
		'list_option':       'rpop'
		'poll_interval_ms':  '500'
	}) or { panic(err.str()) }
	assert s.mode == .list
	assert s.list_option == 'rpop'
	assert s.poll_interval_ms == 500
	assert s.key == 'work-queue'
}

fn test_new_redis_source_list_mode_defaults() {
	s := new_redis_source({
		'key':  'queue'
		'mode': 'list'
	}) or { panic(err.str()) }
	assert s.mode == .list
	assert s.list_option == 'lpop'
	assert s.poll_interval_ms == 1000
}

fn test_new_redis_source_invalid_poll_interval() {
	s := new_redis_source({
		'key':              'queue'
		'mode':             'list'
		'poll_interval_ms': '-10'
	}) or { panic(err.str()) }
	assert s.poll_interval_ms == 1000
}

fn test_new_redis_source_with_auth_url() {
	s := new_redis_source({
		'key': 'chan'
		'url': 'redis://user:pass@redis.local:6380'
	}) or { panic(err.str()) }
	assert s.host == 'redis.local'
	assert s.port == 6380
	assert s.auth == 'user:pass'
}

fn test_redis_source_registry() {
	s := build_source('redis', {
		'key': 'test-channel'
	}) or { panic(err.str()) }
	assert s is RedisSource
}

fn test_redis_source_registry_missing_key() {
	build_source('redis', map[string]string{}) or {
		assert err.msg().contains('key is required')
		return
	}
	assert false, 'expected error for missing key'
}
