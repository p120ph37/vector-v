module sources

import event

fn test_parse_journald_line_basic() {
	line := '{"MESSAGE":"Started nginx.service","_HOSTNAME":"web01","PRIORITY":"6","_SYSTEMD_UNIT":"nginx.service","_PID":"1234"}'
	ev := parse_journald_line(line) or { panic(err.str()) }
	assert ev.message() == 'Started nginx.service'
	host := ev.get('host') or { panic('missing host') }
	assert host == event.Value('web01')
	severity := ev.get('severity') or { panic('missing severity') }
	assert severity == event.Value('informational')
	unit := ev.get('unit') or { panic('missing unit') }
	assert unit == event.Value('nginx.service')
	pid := ev.get('pid') or { panic('missing pid') }
	assert pid == event.Value('1234')
}

fn test_parse_journald_line_all_fields() {
	line := '{"MESSAGE":"test msg","_HOSTNAME":"server1","PRIORITY":"3","_SYSTEMD_UNIT":"sshd.service","_PID":"5678","SYSLOG_IDENTIFIER":"sshd","_TRANSPORT":"syslog","_UID":"0","_GID":"0","_COMM":"sshd","_EXE":"/usr/sbin/sshd","_BOOT_ID":"abc123","_MACHINE_ID":"def456","__REALTIME_TIMESTAMP":"1672531200000000"}'
	ev := parse_journald_line(line) or { panic(err.str()) }
	assert ev.message() == 'test msg'
	syslog_id := ev.get('syslog_identifier') or { panic('missing syslog_identifier') }
	assert syslog_id == event.Value('sshd')
	transport := ev.get('transport') or { panic('missing transport') }
	assert transport == event.Value('syslog')
	uid := ev.get('uid') or { panic('missing uid') }
	assert uid == event.Value('0')
	gid := ev.get('gid') or { panic('missing gid') }
	assert gid == event.Value('0')
	comm := ev.get('comm') or { panic('missing comm') }
	assert comm == event.Value('sshd')
	exe := ev.get('exe') or { panic('missing exe') }
	assert exe == event.Value('/usr/sbin/sshd')
	boot_id := ev.get('boot_id') or { panic('missing boot_id') }
	assert boot_id == event.Value('abc123')
	machine_id := ev.get('machine_id') or { panic('missing machine_id') }
	assert machine_id == event.Value('def456')
	ts := ev.get('timestamp_us') or { panic('missing timestamp_us') }
	assert ts == event.Value('1672531200000000')
}

fn test_parse_journald_line_source_type() {
	line := '{"MESSAGE":"hello"}'
	ev := parse_journald_line(line) or { panic(err.str()) }
	assert ev.meta.source_type == 'journald'
}

fn test_parse_journald_line_empty_message() {
	line := '{"MESSAGE":"","_HOSTNAME":"host1"}'
	ev := parse_journald_line(line) or { panic(err.str()) }
	assert ev.message() == ''
	host := ev.get('host') or { panic('missing host') }
	assert host == event.Value('host1')
}

fn test_parse_journald_line_missing_optional_fields() {
	line := '{"MESSAGE":"just a message"}'
	ev := parse_journald_line(line) or { panic(err.str()) }
	assert ev.message() == 'just a message'
	// Optional fields should not be present
	if _ := ev.get('host') {
		assert false, 'host should not be present'
	}
	if _ := ev.get('unit') {
		assert false, 'unit should not be present'
	}
	if _ := ev.get('pid') {
		assert false, 'pid should not be present'
	}
}

fn test_parse_journald_line_invalid_json() {
	if _ := parse_journald_line('not valid json') {
		assert false, 'expected error for invalid JSON'
	}
}

fn test_parse_journald_line_empty_json() {
	if _ := parse_journald_line('') {
		assert false, 'expected error for empty string'
	}
}

fn test_map_journald_priority_all_levels() {
	assert map_journald_priority('0') == 'emergency'
	assert map_journald_priority('1') == 'alert'
	assert map_journald_priority('2') == 'critical'
	assert map_journald_priority('3') == 'error'
	assert map_journald_priority('4') == 'warning'
	assert map_journald_priority('5') == 'notice'
	assert map_journald_priority('6') == 'informational'
	assert map_journald_priority('7') == 'debug'
}

fn test_map_journald_priority_unknown() {
	assert map_journald_priority('8') == '8'
	assert map_journald_priority('99') == '99'
	assert map_journald_priority('') == ''
}

fn test_new_journald_defaults() {
	s := new_journald(map[string]string{})
	assert s.current_boot_only == true
	assert s.units.len == 0
	assert s.include_matches.len == 0
}

fn test_new_journald_custom() {
	s := new_journald({
		'current_boot_only': 'false'
		'units':             'nginx.service,sshd.service'
		'include_matches':   'PRIORITY=3,_TRANSPORT=syslog'
	})
	assert s.current_boot_only == false
	assert s.units.len == 2
	assert s.units[0] == 'nginx.service'
	assert s.units[1] == 'sshd.service'
	assert s.include_matches.len == 2
	assert s.include_matches[0] == 'PRIORITY=3'
	assert s.include_matches[1] == '_TRANSPORT=syslog'
}

fn test_new_journald_single_unit() {
	s := new_journald({
		'units': 'docker.service'
	})
	assert s.units.len == 1
	assert s.units[0] == 'docker.service'
}

fn test_new_journald_empty_units() {
	s := new_journald({
		'units': ''
	})
	assert s.units.len == 0
}

fn test_new_journald_units_with_spaces() {
	s := new_journald({
		'units': ' nginx.service , sshd.service , docker.service '
	})
	assert s.units.len == 3
	assert s.units[0] == 'nginx.service'
	assert s.units[1] == 'sshd.service'
	assert s.units[2] == 'docker.service'
}

fn test_parse_journald_line_kernel_message() {
	line := '{"MESSAGE":"EXT4-fs (sda1): mounted filesystem with ordered data mode","_HOSTNAME":"server","PRIORITY":"5","_TRANSPORT":"kernel","_BOOT_ID":"boot-abc"}'
	ev := parse_journald_line(line) or { panic(err.str()) }
	assert ev.message().contains('EXT4-fs')
	severity := ev.get('severity') or { panic('missing severity') }
	assert severity == event.Value('notice')
	transport := ev.get('transport') or { panic('missing transport') }
	assert transport == event.Value('kernel')
}

fn test_journald_source_registry() {
	s := build_source('journald', map[string]string{}) or { panic(err.str()) }
	assert s is JournaldSource
}
