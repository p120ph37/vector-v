module vrl

fn test_parse_grok_simple_word() {
	result := fn_parse_grok([VrlValue('hello'), VrlValue('%{WORD:w}')]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('w') or { panic('no w') }) == VrlValue('hello')
}

fn test_parse_grok_int() {
	result := fn_parse_grok([VrlValue('42'), VrlValue('%{INT:num}')]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('num') or { panic('no num') }) == VrlValue('42')
}

fn test_parse_grok_ip_and_word() {
	input := '192.168.1.1 GET'
	pattern := '%{IPV4:ip} %{WORD:method}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('ip') or { panic('no ip') }) == VrlValue('192.168.1.1')
	assert (obj.get('method') or { panic('no method') }) == VrlValue('GET')
}

fn test_parse_grok_greedydata() {
	input := 'prefix: everything else here'
	pattern := '%{WORD:key}: %{GREEDYDATA:value}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('key') or { panic('no key') }) == VrlValue('prefix')
	assert (obj.get('value') or { panic('no value') }) == VrlValue('everything else here')
}

fn test_parse_grok_number() {
	input := 'value is 3.14'
	pattern := 'value is %{NUMBER:num}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('num') or { panic('no num') }) == VrlValue('3.14')
}

fn test_parse_grok_notspace() {
	input := 'foo bar baz'
	pattern := '%{NOTSPACE:a} %{NOTSPACE:b} %{NOTSPACE:c}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('a') or { panic('no a') }) == VrlValue('foo')
	assert (obj.get('b') or { panic('no b') }) == VrlValue('bar')
	assert (obj.get('c') or { panic('no c') }) == VrlValue('baz')
}

fn test_parse_grok_loglevel() {
	input := 'info Hello world'
	pattern := '%{LOGLEVEL:level} %{GREEDYDATA:message}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('level') or { panic('no level') }) == VrlValue('info')
	assert (obj.get('message') or { panic('no message') }) == VrlValue('Hello world')
}

fn test_parse_grok_uuid() {
	input := '550e8400-e29b-41d4-a716-446655440000'
	pattern := '%{UUID:id}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('id') or { panic('no id') }) == VrlValue('550e8400-e29b-41d4-a716-446655440000')
}

fn test_parse_grok_email() {
	input := 'user@example.com sent mail'
	pattern := '%{EMAILADDRESS:email} %{GREEDYDATA:action}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('email') or { panic('no email') }) == VrlValue('user@example.com')
}

fn test_parse_grok_hostname() {
	input := 'myhost.example.com'
	pattern := '%{HOSTNAME:host}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('host') or { panic('no host') }) == VrlValue('myhost.example.com')
}

fn test_parse_grok_no_match() {
	_ := fn_parse_grok([VrlValue('abc'), VrlValue('%{INT:num}')]) or {
		assert err.msg().contains('unable to parse')
		return
	}
	panic('expected error for non-matching input')
}

fn test_parse_grok_unknown_pattern() {
	_ := fn_parse_grok([VrlValue('test'), VrlValue('%{NONEXISTENT:val}')]) or {
		assert err.msg().contains('unknown grok pattern')
		return
	}
	panic('expected error for unknown pattern')
}

fn test_parse_grok_multiple_numbers() {
	input := '42 items in 3.14 seconds'
	pattern := '%{INT:count} items in %{NUMBER:duration} seconds'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('count') or { panic('no count') }) == VrlValue('42')
	assert (obj.get('duration') or { panic('no duration') }) == VrlValue('3.14')
}

fn test_parse_grok_iso_timestamp() {
	input := '2020-10-02T23:22:12Z info Hello'
	pattern := '%{TIMESTAMP_ISO8601:ts} %{LOGLEVEL:level} %{GREEDYDATA:msg}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('level') or { panic('no level') }) == VrlValue('info')
}

fn test_parse_grok_syslog_timestamp() {
	input := 'Jan 23 14:30:01'
	pattern := '%{SYSLOGTIMESTAMP:ts}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('ts') or { panic('no ts') }) == VrlValue('Jan 23 14:30:01')
}

fn test_parse_grok_mac_address() {
	input := '00:1A:2B:3C:4D:5E'
	pattern := '%{COMMONMAC:mac}'
	result := fn_parse_grok([VrlValue(input), VrlValue(pattern)]) or { panic(err.msg()) }
	obj := result as ObjectMap
	assert (obj.get('mac') or { panic('no mac') }) == VrlValue('00:1A:2B:3C:4D:5E')
}
