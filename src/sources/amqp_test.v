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
