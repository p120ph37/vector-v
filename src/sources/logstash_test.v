module sources

import event

fn test_parse_logstash_line_basic() {
	ev := parse_logstash_line('{"message":"hello world"}') or { panic(err.str()) }
	assert ev.message() == 'hello world'
	assert ev.meta.source_type == 'logstash'
}

fn test_parse_logstash_line_with_fields() {
	ev := parse_logstash_line('{"message":"test event","host":"web01","level":"info","port":"8080"}') or {
		panic(err.str())
	}
	assert ev.message() == 'test event'
	host := ev.get('host') or { panic('missing host') }
	assert host == event.Value('web01')
	level := ev.get('level') or { panic('missing level') }
	assert level == event.Value('info')
	port := ev.get('port') or { panic('missing port') }
	assert port == event.Value('8080')
}

fn test_parse_logstash_line_no_message() {
	ev := parse_logstash_line('{"host":"server1","level":"error"}') or { panic(err.str()) }
	assert ev.message() == ''
	host := ev.get('host') or { panic('missing host') }
	assert host == event.Value('server1')
}

fn test_parse_logstash_line_empty_object() {
	ev := parse_logstash_line('{}') or { panic(err.str()) }
	assert ev.message() == ''
	assert ev.meta.source_type == 'logstash'
}

fn test_parse_logstash_line_invalid_json() {
	if _ := parse_logstash_line('not json at all') {
		assert false, 'expected error for invalid JSON'
	}
}

fn test_parse_logstash_line_empty() {
	if _ := parse_logstash_line('') {
		assert false, 'expected error for empty line'
	}
}

fn test_parse_logstash_line_whitespace_only() {
	if _ := parse_logstash_line('   ') {
		assert false, 'expected error for whitespace-only line'
	}
}

fn test_parse_logstash_line_beats_format() {
	// Typical Beats/Logstash output format
	ev := parse_logstash_line('{"message":"Application started","@timestamp":"2023-01-01T00:00:00.000Z","host":"web01","type":"app_log","tags":"production"}') or {
		panic(err.str())
	}
	assert ev.message() == 'Application started'
	ts := ev.get('@timestamp') or { panic('missing @timestamp') }
	assert ts == event.Value('2023-01-01T00:00:00.000Z')
	typ := ev.get('type') or { panic('missing type') }
	assert typ == event.Value('app_log')
}

fn test_parse_logstash_line_numeric_values() {
	ev := parse_logstash_line('{"message":"metric","count":"42","latency":"1.5"}') or {
		panic(err.str())
	}
	assert ev.message() == 'metric'
	count := ev.get('count') or { panic('missing count') }
	assert count == event.Value('42')
}

fn test_parse_logstash_line_boolean_values() {
	ev := parse_logstash_line('{"message":"test","active":"true","debug":"false"}') or {
		panic(err.str())
	}
	active := ev.get('active') or { panic('missing active') }
	assert active == event.Value('true')
}

fn test_parse_logstash_line_special_characters() {
	ev := parse_logstash_line('{"message":"line with \\"quotes\\" and \\\\backslashes"}') or {
		panic(err.str())
	}
	msg := ev.message()
	assert msg.contains('quotes')
}

fn test_parse_logstash_line_with_trimming() {
	ev := parse_logstash_line('  {"message":"padded"}  ') or { panic(err.str()) }
	assert ev.message() == 'padded'
}

fn test_parse_logstash_line_many_fields() {
	ev := parse_logstash_line('{"message":"multi","a":"1","b":"2","c":"3","d":"4"}') or {
		panic(err.str())
	}
	assert ev.message() == 'multi'
	a := ev.get('a') or { panic('missing a') }
	assert a == event.Value('1')
	d := ev.get('d') or { panic('missing d') }
	assert d == event.Value('4')
}

fn test_new_logstash_defaults() {
	s := new_logstash(map[string]string{})
	assert s.address == '0.0.0.0:5044'
}

fn test_new_logstash_custom() {
	s := new_logstash({
		'address': '127.0.0.1:9999'
	})
	assert s.address == '127.0.0.1:9999'
}

fn test_logstash_source_registry() {
	s := build_source('logstash', map[string]string{}) or { panic(err.str()) }
	assert s is LogstashSource
}
