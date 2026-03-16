module sources

fn test_new_amqp_source_defaults() {
	s := new_amqp_source(map[string]string{})
	assert s.connection_string == 'amqp://guest:guest@127.0.0.1:5672/%2f'
	assert s.exchange == ''
	assert s.exchange_type == 'fanout'
	assert s.queue == ''
	assert s.routing_key == '#'
	assert s.consumer_tag == 'vector'
	assert s.prefetch_count == 10
	assert s.exchange_key == 'amqp_exchange'
	assert s.routing_key_field == 'amqp_routing_key'
	assert s.decoding_codec == 'bytes'
	assert s.tls_enabled == false
}

fn test_new_amqp_source_custom() {
	s := new_amqp_source({
		'connection':      'amqp://user:pass@rabbit.local:5673/myvhost'
		'exchange':        'logs'
		'exchange_type':   'topic'
		'queue':           'vector-queue'
		'routing_key':     'app.*.info'
		'consumer_tag':    'my-consumer'
		'prefetch_count':  '50'
		'exchange_key':    'custom_exchange'
		'routing_key_field': 'custom_rk'
		'decoding.codec':  'json'
		'tls.enabled':     'true'
	})
	assert s.connection_string == 'amqp://user:pass@rabbit.local:5673/myvhost'
	assert s.exchange == 'logs'
	assert s.exchange_type == 'topic'
	assert s.queue == 'vector-queue'
	assert s.routing_key == 'app.*.info'
	assert s.consumer_tag == 'my-consumer'
	assert s.prefetch_count == 50
	assert s.exchange_key == 'custom_exchange'
	assert s.routing_key_field == 'custom_rk'
	assert s.decoding_codec == 'json'
	assert s.tls_enabled == true
}

fn test_parse_amqp_url() {
	// Standard URL
	host, port, vhost, user, password := parse_amqp_url('amqp://guest:guest@127.0.0.1:5672/%2f')!
	assert host == '127.0.0.1'
	assert port == 5672
	assert vhost == '/'
	assert user == 'guest'
	assert password == 'guest'

	// With named vhost
	h2, p2, v2, u2, pw2 := parse_amqp_url('amqp://admin:secret@rabbit.local:5673/production')!
	assert h2 == 'rabbit.local'
	assert p2 == 5673
	assert v2 == 'production'
	assert u2 == 'admin'
	assert pw2 == 'secret'

	// With credentials, default port
	h3, p3, _, u3, pw3 := parse_amqp_url('amqp://myuser:mypass@localhost')!
	assert h3 == 'localhost'
	assert p3 == 5672
	assert u3 == 'myuser'
	assert pw3 == 'mypass'

	// Default port (no port specified)
	h4, p4, _, _, _ := parse_amqp_url('amqp://guest:guest@broker.example.com')!
	assert h4 == 'broker.example.com'
	assert p4 == 5672
}

fn test_parse_amqp_url_invalid() {
	// Missing scheme
	parse_amqp_url('http://localhost:5672') or {
		assert err.msg().contains('invalid AMQP URL')
		return
	}
	assert false, 'expected error for invalid URL'
}

fn test_validate_amqp_exchange_type() {
	// Valid types
	assert validate_amqp_exchange_type('fanout') == true
	assert validate_amqp_exchange_type('direct') == true
	assert validate_amqp_exchange_type('topic') == true
	assert validate_amqp_exchange_type('headers') == true

	// Invalid types
	assert validate_amqp_exchange_type('') == false
	assert validate_amqp_exchange_type('invalid') == false
	assert validate_amqp_exchange_type('FANOUT') == false
	assert validate_amqp_exchange_type('queue') == false
}

fn test_build_amqp_metadata() {
	meta := build_amqp_metadata('my-exchange', 'my.routing.key', 42)
	assert meta['exchange'] == 'my-exchange'
	assert meta['routing_key'] == 'my.routing.key'
	assert meta['delivery_tag'] == '42'
}

fn test_amqp_source_prefetch_config() {
	// Custom prefetch
	s1 := new_amqp_source({
		'prefetch_count': '100'
	})
	assert s1.prefetch_count == 100

	// Invalid prefetch falls back to default
	s2 := new_amqp_source({
		'prefetch_count': '-5'
	})
	assert s2.prefetch_count == 10

	// Zero prefetch falls back to default
	s3 := new_amqp_source({
		'prefetch_count': '0'
	})
	assert s3.prefetch_count == 10
}

fn test_amqp_source_consumer_tag() {
	// Default consumer tag
	s1 := new_amqp_source(map[string]string{})
	assert s1.consumer_tag == 'vector'

	// Custom consumer tag
	s2 := new_amqp_source({
		'consumer_tag': 'my-app-consumer'
	})
	assert s2.consumer_tag == 'my-app-consumer'
}

fn test_amqp_source_tls_config() {
	// TLS disabled by default
	s1 := new_amqp_source(map[string]string{})
	assert s1.tls_enabled == false

	// TLS enabled
	s2 := new_amqp_source({
		'tls.enabled': 'true'
	})
	assert s2.tls_enabled == true

	// TLS explicitly disabled
	s3 := new_amqp_source({
		'tls.enabled': 'false'
	})
	assert s3.tls_enabled == false
}

fn test_parse_amqp_url_amqps_scheme() {
	host, port, vhost, user, password := parse_amqp_url('amqps://admin:secret@secure.rabbit.io:5671/production')!
	assert host == 'secure.rabbit.io'
	assert port == 5671
	assert vhost == 'production'
	assert user == 'admin'
	assert password == 'secret'
}

fn test_parse_amqp_url_user_without_password() {
	// user@ with no colon separator means password is empty
	host, port, _, user, password := parse_amqp_url('amqp://justuser@myhost:5672/')!
	assert host == 'myhost'
	assert port == 5672
	assert user == 'justuser'
	assert password == ''
}

fn test_parse_amqp_url_uppercase_percent_2f() {
	// %2F (uppercase) should also decode to /
	_, _, vhost, _, _ := parse_amqp_url('amqp://guest:guest@localhost:5672/%2F')!
	assert vhost == '/'
}

fn test_parse_amqp_url_empty_vhost() {
	// Trailing slash with nothing after it should default to /
	_, _, vhost, _, _ := parse_amqp_url('amqp://guest:guest@localhost:5672/')!
	assert vhost == '/'
}

fn test_parse_amqp_url_no_credentials_no_vhost() {
	// No @ sign, no vhost
	host, port, vhost, user, password := parse_amqp_url('amqp://myhost:5672')!
	assert host == 'myhost'
	assert port == 5672
	assert vhost == '/'
	assert user == 'guest'
	assert password == 'guest'
}

fn test_parse_amqp_url_invalid_port() {
	// Invalid port string falls back to default
	host, port, _, _, _ := parse_amqp_url('amqp://guest:guest@myhost:abc')!
	assert host == 'myhost'
	assert port == 5672
}

fn test_parse_amqp_url_empty_host_after_at() {
	// Empty host after credentials => defaults to 127.0.0.1
	host, port, _, user, _ := parse_amqp_url('amqp://user:pass@:5672/')!
	assert host == '127.0.0.1'
	assert port == 5672
	assert user == 'user'
}

fn test_new_amqp_source_offset_key() {
	s := new_amqp_source({
		'offset_key': 'custom_offset'
	})
	assert s.offset_key == 'custom_offset'

	// Default offset_key
	s2 := new_amqp_source(map[string]string{})
	assert s2.offset_key == 'amqp_offset'
}

fn test_amqp_source_exchange_types() {
	// Each valid exchange type can be configured
	for et in ['fanout', 'direct', 'topic', 'headers'] {
		s := new_amqp_source({
			'exchange_type': et
		})
		assert s.exchange_type == et
		assert validate_amqp_exchange_type(s.exchange_type) == true
	}
}
