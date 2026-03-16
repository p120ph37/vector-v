module sources

import event

fn test_new_mqtt_source_defaults() {
	s := new_mqtt_source({
		'topic': 'test/events'
	}) or { panic(err.str()) }
	assert s.host == '127.0.0.1'
	assert s.port == 1883
	assert s.topic == 'test/events'
	assert s.qos == 1
	assert s.client_id == 'vector'
	assert s.username == ''
	assert s.password == ''
	assert s.clean_session == true
	assert s.keep_alive_secs == 60
	assert s.max_packet_size == 268435456
	assert s.tls_enabled == false
	assert s.decoding_codec == 'bytes'
	assert s.topic_key == 'mqtt_topic'
}

fn test_new_mqtt_source_missing_topic() {
	new_mqtt_source(map[string]string{}) or {
		assert err.msg().contains('topic is required')
		return
	}
	assert false, 'expected error for missing topic'
}

fn test_new_mqtt_source_custom() {
	s := new_mqtt_source({
		'topic':           'sensors/+/temperature'
		'host':            'broker.example.com'
		'port':            '1884'
		'qos':             '2'
		'client_id':       'my-vector'
		'username':        'user1'
		'password':        'pass1'
		'clean_session':   'false'
		'keep_alive_secs': '30'
		'decoding.codec':  'json'
		'topic_key':       'source_topic'
	}) or { panic(err.str()) }
	assert s.host == 'broker.example.com'
	assert s.port == 1884
	assert s.topic == 'sensors/+/temperature'
	assert s.qos == 2
	assert s.client_id == 'my-vector'
	assert s.username == 'user1'
	assert s.password == 'pass1'
	assert s.clean_session == false
	assert s.keep_alive_secs == 30
	assert s.decoding_codec == 'json'
	assert s.topic_key == 'source_topic'
}

fn test_validate_mqtt_topic() {
	// Valid topics
	assert validate_mqtt_topic('test/events') == true
	assert validate_mqtt_topic('sensor/temperature') == true
	assert validate_mqtt_topic('#') == true
	assert validate_mqtt_topic('test/#') == true
	assert validate_mqtt_topic('+/temperature') == true
	assert validate_mqtt_topic('sensors/+/data') == true
	assert validate_mqtt_topic('+/+/+') == true
	assert validate_mqtt_topic('a/b/c/d') == true
	assert validate_mqtt_topic('test') == true

	// Invalid topics
	assert validate_mqtt_topic('') == false
	assert validate_mqtt_topic('test/#/more') == false // # not at end
	assert validate_mqtt_topic('test/ab#') == false // # not entire level
	assert validate_mqtt_topic('test/ab+') == false // + not entire level
	assert validate_mqtt_topic('test/+cd') == false // + not entire level
}

fn test_validate_mqtt_qos() {
	assert validate_mqtt_qos(0) == true
	assert validate_mqtt_qos(1) == true
	assert validate_mqtt_qos(2) == true
	assert validate_mqtt_qos(3) == false
	assert validate_mqtt_qos(-1) == false
	assert validate_mqtt_qos(99) == false
}

fn test_build_mqtt_connect_flags() {
	// Clean session only
	flags1 := build_mqtt_connect_flags(true, false, false, false, 0, false)
	assert flags1 == 0x02

	// No flags at all
	flags2 := build_mqtt_connect_flags(false, false, false, false, 0, false)
	assert flags2 == 0x00

	// Clean session + username + password
	flags3 := build_mqtt_connect_flags(true, true, true, false, 0, false)
	assert flags3 == 0x02 | 0x80 | 0x40 // = 0xC2

	// Clean session + will (QoS 1)
	flags4 := build_mqtt_connect_flags(true, false, false, true, 1, false)
	assert flags4 == 0x02 | 0x04 | (1 << 3) // = 0x0E

	// Clean session + will (QoS 2, retain)
	flags5 := build_mqtt_connect_flags(true, false, false, true, 2, true)
	assert flags5 == 0x02 | 0x04 | (2 << 3) | 0x20 // = 0x36

	// All flags: clean session, username, password, will QoS 1 retain
	flags6 := build_mqtt_connect_flags(true, true, true, true, 1, true)
	assert flags6 == 0x02 | 0x80 | 0x40 | 0x04 | (1 << 3) | 0x20 // = 0xEE
}

fn test_parse_mqtt_url() {
	// Basic mqtt:// URL
	host1, port1, tls1 := parse_mqtt_url('mqtt://broker.local') or { panic(err.str()) }
	assert host1 == 'broker.local'
	assert port1 == 1883
	assert tls1 == false

	// mqtt:// with port
	host2, port2, tls2 := parse_mqtt_url('mqtt://broker.local:1884') or { panic(err.str()) }
	assert host2 == 'broker.local'
	assert port2 == 1884
	assert tls2 == false

	// mqtts:// URL (TLS)
	host3, port3, tls3 := parse_mqtt_url('mqtts://secure.broker.io') or { panic(err.str()) }
	assert host3 == 'secure.broker.io'
	assert port3 == 8883
	assert tls3 == true

	// mqtts:// with explicit port
	host4, port4, tls4 := parse_mqtt_url('mqtts://secure.broker.io:9883') or {
		panic(err.str())
	}
	assert host4 == 'secure.broker.io'
	assert port4 == 9883
	assert tls4 == true
}

fn test_parse_mqtt_url_invalid() {
	// Invalid scheme
	parse_mqtt_url('http://broker.local') or {
		assert err.msg().contains('unsupported URL scheme')
		return
	}
	assert false, 'expected error for invalid scheme'
}

fn test_mqtt_source_tls_default_port() {
	// When TLS is enabled and no explicit port, should default to 8883
	s := new_mqtt_source({
		'topic':       'test/events'
		'tls.enabled': 'true'
	}) or { panic(err.str()) }
	assert s.tls_enabled == true
	assert s.port == 8883

	// When TLS is enabled but port is explicitly set, use explicit port
	s2 := new_mqtt_source({
		'topic':       'test/events'
		'tls.enabled': 'true'
		'port':        '9999'
	}) or { panic(err.str()) }
	assert s2.tls_enabled == true
	assert s2.port == 9999
}

fn test_mqtt_source_auth_config() {
	s := new_mqtt_source({
		'topic':    'secure/topic'
		'username': 'myuser'
		'password': 'mypass'
	}) or { panic(err.str()) }
	assert s.username == 'myuser'
	assert s.password == 'mypass'
	assert s.topic == 'secure/topic'
}

fn test_new_mqtt_source_empty_topic() {
	// Topic key present but empty string should error
	new_mqtt_source({
		'topic': ''
	}) or {
		assert err.msg().contains('topic is required')
		return
	}
	assert false, 'expected error for empty topic'
}

fn test_new_mqtt_source_empty_host_fallback() {
	// Host present but empty should fallback to default
	s := new_mqtt_source({
		'topic': 'test/events'
		'host':  ''
	}) or { panic(err.str()) }
	assert s.host == '127.0.0.1'
}

fn test_new_mqtt_source_invalid_qos_fallback() {
	// QoS out of range (too high) should fallback to 1
	s := new_mqtt_source({
		'topic': 'test/events'
		'qos':   '5'
	}) or { panic(err.str()) }
	assert s.qos == 1

	// QoS negative should fallback to 1
	s2 := new_mqtt_source({
		'topic': 'test/events'
		'qos':   '-1'
	}) or { panic(err.str()) }
	assert s2.qos == 1
}

fn test_new_mqtt_source_invalid_port_fallback() {
	// Port = 0 should keep default
	s := new_mqtt_source({
		'topic': 'test/events'
		'port':  '0'
	}) or { panic(err.str()) }
	assert s.port == 1883

	// Non-numeric port should keep default
	s2 := new_mqtt_source({
		'topic': 'test/events'
		'port':  'abc'
	}) or { panic(err.str()) }
	assert s2.port == 1883
}

fn test_new_mqtt_source_empty_client_id_fallback() {
	// Empty client_id should fallback to 'vector'
	s := new_mqtt_source({
		'topic':     'test/events'
		'client_id': ''
	}) or { panic(err.str()) }
	assert s.client_id == 'vector'
}

fn test_new_mqtt_source_keep_alive_invalid_fallback() {
	// keep_alive_secs = 0 should fallback to 60
	s := new_mqtt_source({
		'topic':           'test/events'
		'keep_alive_secs': '0'
	}) or { panic(err.str()) }
	assert s.keep_alive_secs == 60

	// Negative keep_alive_secs should fallback to 60
	s2 := new_mqtt_source({
		'topic':           'test/events'
		'keep_alive_secs': '-10'
	}) or { panic(err.str()) }
	assert s2.keep_alive_secs == 60
}

fn test_new_mqtt_source_max_packet_size_invalid_fallback() {
	// max_packet_size = 0 should fallback to default
	s := new_mqtt_source({
		'topic':           'test/events'
		'max_packet_size': '0'
	}) or { panic(err.str()) }
	assert s.max_packet_size == 268435456

	// Negative max_packet_size should fallback to default
	s2 := new_mqtt_source({
		'topic':           'test/events'
		'max_packet_size': '-100'
	}) or { panic(err.str()) }
	assert s2.max_packet_size == 268435456
}

fn test_new_mqtt_source_tls_enabled_false() {
	// tls.enabled present but set to 'false'
	s := new_mqtt_source({
		'topic':       'test/events'
		'tls.enabled': 'false'
	}) or { panic(err.str()) }
	assert s.tls_enabled == false
	assert s.port == 1883
}

fn test_new_mqtt_source_clean_session_true_explicit() {
	// clean_session explicitly set to 'true'
	s := new_mqtt_source({
		'topic':         'test/events'
		'clean_session': 'true'
	}) or { panic(err.str()) }
	assert s.clean_session == true

	// clean_session set to any non-'false' value stays true
	s2 := new_mqtt_source({
		'topic':         'test/events'
		'clean_session': 'yes'
	}) or { panic(err.str()) }
	assert s2.clean_session == true
}

fn test_new_mqtt_source_valid_max_packet_size() {
	s := new_mqtt_source({
		'topic':           'test/events'
		'max_packet_size': '1024'
	}) or { panic(err.str()) }
	assert s.max_packet_size == 1024
}

fn test_new_mqtt_source_qos_zero() {
	// QoS 0 is valid
	s := new_mqtt_source({
		'topic': 'test/events'
		'qos':   '0'
	}) or { panic(err.str()) }
	assert s.qos == 0
}

fn test_validate_mqtt_topic_double_slash() {
	// Empty level between slashes is invalid
	assert validate_mqtt_topic('a//b') == false
	assert validate_mqtt_topic('a///b') == false
}

fn test_validate_mqtt_topic_trailing_slash() {
	// Trailing slash (empty last level) is allowed by the validator
	// because the check excludes first and last levels
	assert validate_mqtt_topic('test/') == true
	assert validate_mqtt_topic('/test') == true
}

fn test_parse_mqtt_url_with_path() {
	// URL with trailing path should strip the path
	host, port, tls := parse_mqtt_url('mqtt://broker.local/some/path') or { panic(err.str()) }
	assert host == 'broker.local'
	assert port == 1883
	assert tls == false
}

fn test_parse_mqtt_url_empty_host() {
	// mqtt:// with nothing after scheme => default host/port
	host, port, tls := parse_mqtt_url('mqtt://') or { panic(err.str()) }
	assert host == '127.0.0.1'
	assert port == 1883
	assert tls == false
}

fn test_parse_mqtt_url_empty_host_with_colon() {
	// mqtt://:1884 => empty host before colon, should fallback to 127.0.0.1
	host, port, tls := parse_mqtt_url('mqtt://:1884') or { panic(err.str()) }
	assert host == '127.0.0.1'
	assert port == 1884
	assert tls == false
}

fn test_parse_mqtt_url_invalid_port() {
	// mqtt://host:abc => port parses to 0, keeps default
	host, port, tls := parse_mqtt_url('mqtt://broker.local:abc') or { panic(err.str()) }
	assert host == 'broker.local'
	assert port == 1883
	assert tls == false
}

fn test_parse_mqtt_url_mqtts_with_path() {
	// mqtts URL with path
	host, port, tls := parse_mqtt_url('mqtts://secure.broker.io:9883/path') or {
		panic(err.str())
	}
	assert host == 'secure.broker.io'
	assert port == 9883
	assert tls == true
}

fn test_parse_mqtt_url_mqtts_empty() {
	// mqtts:// with nothing after scheme
	host, port, tls := parse_mqtt_url('mqtts://') or { panic(err.str()) }
	assert host == '127.0.0.1'
	assert port == 8883
	assert tls == true
}

fn test_build_mqtt_connect_flags_will_qos0() {
	// Will flag with QoS 0, no retain
	flags := build_mqtt_connect_flags(false, false, false, true, 0, false)
	assert flags == 0x04
}

fn test_build_mqtt_connect_flags_will_no_retain() {
	// Will flag with QoS 2, no retain (tests will without retain)
	flags := build_mqtt_connect_flags(false, false, false, true, 2, false)
	assert flags == 0x04 | (2 << 3) // = 0x14
}

fn test_build_mqtt_connect_flags_password_only() {
	// Password without username
	flags := build_mqtt_connect_flags(false, false, true, false, 0, false)
	assert flags == 0x40
}

fn test_build_mqtt_connect_flags_username_only() {
	// Username without password
	flags := build_mqtt_connect_flags(false, true, false, false, 0, false)
	assert flags == 0x80
}

fn test_mqtt_source_run_stub() {
	// Exercise the run() stub to cover it
	s := new_mqtt_source({
		'topic': 'test/events'
	}) or { panic(err.str()) }
	ch := chan event.Event{cap: 1}
	s.run(ch)
	ch.close()
}

fn test_parse_mqtt_url_port_with_path() {
	// mqtt://host:1884/path - port + path stripping
	host, port, tls := parse_mqtt_url('mqtt://broker.local:1884/path') or { panic(err.str()) }
	assert host == 'broker.local'
	assert port == 1884
	assert tls == false
}

fn test_parse_mqtt_url_mqtts_no_port() {
	// mqtts://host with no port uses 8883
	host, port, tls := parse_mqtt_url('mqtts://myhost') or { panic(err.str()) }
	assert host == 'myhost'
	assert port == 8883
	assert tls == true
}

fn test_parse_mqtt_url_various_invalid_schemes() {
	// Various invalid schemes
	parse_mqtt_url('tcp://broker.local') or {
		assert err.msg().contains('unsupported URL scheme')
		return
	}
	assert false, 'expected error for tcp scheme'
}

fn test_new_mqtt_source_qos_3_invalid() {
	// QoS 3 is invalid, should fallback to 1
	s := new_mqtt_source({
		'topic': 'test/events'
		'qos':   '3'
	}) or { panic(err.str()) }
	assert s.qos == 1
}
