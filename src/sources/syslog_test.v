module sources

import event

fn test_new_syslog_defaults() {
	s := new_syslog({})
	assert s.mode == .tcp
	assert s.address == '0.0.0.0:514'
}

fn test_new_syslog_udp_mode() {
	s := new_syslog({
		'mode': 'udp'
	})
	assert s.mode == .udp
}

fn test_new_syslog_tcp_mode() {
	s := new_syslog({
		'mode': 'tcp'
	})
	assert s.mode == .tcp
}

fn test_new_syslog_invalid_mode_defaults_tcp() {
	s := new_syslog({
		'mode': 'invalid'
	})
	assert s.mode == .tcp
}

fn test_new_syslog_custom_address() {
	s := new_syslog({
		'address': '127.0.0.1:1514'
	})
	assert s.address == '127.0.0.1:1514'
}

fn test_new_syslog_all_options() {
	s := new_syslog({
		'mode':    'udp'
		'address': '0.0.0.0:5140'
	})
	assert s.mode == .udp
	assert s.address == '0.0.0.0:5140'
}

fn test_parse_syslog_rfc3164_basic() {
	ev := parse_syslog_message('<34>Jan  5 12:00:00 myhost su: pam_unix(su-l):session opened')
	assert ev.meta.source_type == 'syslog'
	msg := ev.get('message') or { event.Value('') }
	assert msg == event.Value('pam_unix(su-l):session opened')
	hostname := ev.get('hostname') or { event.Value('') }
	assert hostname == event.Value('myhost')
	appname := ev.get('appname') or { event.Value('') }
	assert appname == event.Value('su')
	severity := ev.get('severity') or { event.Value('') }
	// pri=34 -> facility=4(auth), severity=2(crit)
	assert severity == event.Value('crit')
	facility := ev.get('facility') or { event.Value('') }
	assert facility == event.Value('auth')
}

fn test_parse_syslog_rfc5424_basic() {
	ev := parse_syslog_message('<165>1 2023-08-11T12:00:00Z router1 myapp 1234 ID47 - Hello world')
	assert ev.meta.source_type == 'syslog'
	msg := ev.get('message') or { event.Value('') }
	assert msg == event.Value('Hello world')
	hostname := ev.get('hostname') or { event.Value('') }
	assert hostname == event.Value('router1')
	appname := ev.get('appname') or { event.Value('') }
	assert appname == event.Value('myapp')
	version := ev.get('version') or { event.Value(0) }
	assert version == event.Value(1)
}

fn test_parse_syslog_rfc5424_with_structured_data() {
	ev := parse_syslog_message('<165>1 2023-08-11T12:00:00Z host app 1234 ID47 [exampleSDID@32473 iut="3"] msg after sd')
	msg := ev.get('message') or { event.Value('') }
	assert msg == event.Value('msg after sd')
}

fn test_parse_syslog_rfc5424_nil_values() {
	ev := parse_syslog_message('<13>1 2023-08-11T12:00:00Z - - - - - The message')
	msg := ev.get('message') or { event.Value('') }
	assert msg == event.Value('The message')
	// hostname should not be set when it's '-'
	hostname := ev.get('hostname') or { event.Value('not_set') }
	assert hostname == event.Value('not_set')
}

fn test_parse_syslog_severity_emergency() {
	ev := parse_syslog_message('<0>Jan  1 00:00:00 host app: emergency')
	severity := ev.get('severity') or { event.Value('') }
	assert severity == event.Value('emerg')
}

fn test_parse_syslog_severity_debug() {
	ev := parse_syslog_message('<15>Jan  1 00:00:00 host app: debug message')
	severity := ev.get('severity') or { event.Value('') }
	assert severity == event.Value('debug')
}

fn test_parse_syslog_facility_kern() {
	// pri=0: facility=0(kern), severity=0(emerg)
	ev := parse_syslog_message('<0>Jan  1 00:00:00 host app: kernel')
	facility := ev.get('facility') or { event.Value('') }
	assert facility == event.Value('kern')
}

fn test_parse_syslog_facility_local0() {
	// local0=16, severity info=6 -> pri = 16*8+6 = 134
	ev := parse_syslog_message('<134>Jan  1 00:00:00 host app: local0')
	facility := ev.get('facility') or { event.Value('') }
	assert facility == event.Value('local0')
}

fn test_parse_syslog_no_priority() {
	ev := parse_syslog_message('no priority here')
	msg := ev.get('message') or { event.Value('') }
	assert msg == event.Value('no priority here')
}

fn test_parse_syslog_empty_string() {
	ev := parse_syslog_message('')
	msg := ev.get('message') or { event.Value('') }
	assert msg == event.Value('')
}

fn test_parse_syslog_rfc3164_with_pid() {
	ev := parse_syslog_message('<86>Jan 10 09:30:15 webserver nginx[12345]: GET /index.html 200')
	appname := ev.get('appname') or { event.Value('') }
	assert appname == event.Value('nginx')
	msg := ev.get('message') or { event.Value('') }
	assert msg == event.Value('GET /index.html 200')
}

fn test_parse_syslog_rfc5424_timestamp_field() {
	ev := parse_syslog_message('<165>1 2023-08-11T12:00:00.123456Z host app - - - test')
	ts := ev.get('timestamp') or { event.Value('') }
	assert ts == event.Value('2023-08-11T12:00:00.123456Z')
}

fn test_parse_rfc5424_missing_fields() {
	// Not enough fields for RFC 5424, but starts with digit
	result := parse_rfc5424('1 ts')
	assert result.valid == false
}

fn test_parse_rfc3164_short_message() {
	result := parse_rfc3164('short')
	assert result.message == 'short'
}

fn test_parse_rfc3164_no_month() {
	result := parse_rfc3164('Xyz  1 12:00:00 host msg')
	assert result.message == 'Xyz  1 12:00:00 host msg'
}
