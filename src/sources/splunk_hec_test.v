module sources

fn test_parse_hec_events_basic() {
	body := '{"event":"hello world","host":"myhost","source":"mysource","sourcetype":"mytype"}'
	events := parse_hec_events(body)
	assert events.len == 1
	assert events[0].event_text == 'hello world'
	assert events[0].host == 'myhost'
	assert events[0].source == 'mysource'
	assert events[0].sourcetype == 'mytype'
}

fn test_parse_hec_events_multiple() {
	body := '{"event":"first"}\n{"event":"second"}\n{"event":"third"}'
	events := parse_hec_events(body)
	assert events.len == 3
	assert events[0].event_text == 'first'
	assert events[1].event_text == 'second'
	assert events[2].event_text == 'third'
}

fn test_parse_hec_events_with_fields() {
	body := '{"event":"test","host":"web01","source":"/var/log/app.log","sourcetype":"json_no_timestamp","index":"main"}'
	events := parse_hec_events(body)
	assert events.len == 1
	assert events[0].event_text == 'test'
	assert events[0].host == 'web01'
	assert events[0].source == '/var/log/app.log'
	assert events[0].sourcetype == 'json_no_timestamp'
	assert events[0].index == 'main'
}

fn test_parse_hec_events_empty() {
	events1 := parse_hec_events('')
	assert events1.len == 0

	events2 := parse_hec_events('   \n  \n  ')
	assert events2.len == 0
}

fn test_parse_hec_events_with_timestamp() {
	body := '{"event":"timed","time":1672531200}'
	events := parse_hec_events(body)
	assert events.len == 1
	assert events[0].event_text == 'timed'
	assert events[0].timestamp == 1672531200
}

fn test_parse_hec_events_invalid_json() {
	events := parse_hec_events('not json at all')
	assert events.len == 0
}

fn test_new_splunk_hec_source_defaults() {
	s := new_splunk_hec_source(map[string]string{})
	assert s.address == '0.0.0.0:8088'
	assert s.token == ''
	assert s.store_hec_token == false
}

fn test_new_splunk_hec_source_custom() {
	s := new_splunk_hec_source({
		'address':         '127.0.0.1:9090'
		'token':           'my-secret-token'
		'store_hec_token': 'true'
	})
	assert s.address == '127.0.0.1:9090'
	assert s.token == 'my-secret-token'
	assert s.store_hec_token == true
}

fn test_splunk_hec_source_registry() {
	s := build_source('splunk_hec', map[string]string{}) or { panic(err.str()) }
	assert s is SplunkHecSource
}
