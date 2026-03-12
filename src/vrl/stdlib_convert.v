module vrl

// to_syslog_level(value)
fn fn_to_syslog_level(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('to_syslog_level requires 1 argument')
	}
	a := args[0]
	severity := match a {
		int { a }
		else { return error('to_syslog_level requires an integer') }
	}
	level := match severity {
		0 { 'emerg' }
		1 { 'alert' }
		2 { 'crit' }
		3 { 'err' }
		4 { 'warning' }
		5 { 'notice' }
		6 { 'info' }
		7 { 'debug' }
		else { return error('invalid syslog severity: ${severity}') }
	}
	return VrlValue(level)
}

// to_syslog_severity(value)
fn fn_to_syslog_severity(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('to_syslog_severity requires 1 argument')
	}
	a := args[0]
	level := match a {
		string { a }
		else { return error('to_syslog_severity requires a string') }
	}
	severity := match level.to_lower() {
		'emerg', 'emergency' { 0 }
		'alert' { 1 }
		'crit', 'critical' { 2 }
		'err', 'error' { 3 }
		'warning', 'warn' { 4 }
		'notice' { 5 }
		'info', 'informational' { 6 }
		'debug' { 7 }
		else { return error('invalid syslog level: ${level}') }
	}
	return VrlValue(severity)
}

// to_syslog_facility(value)
fn fn_to_syslog_facility(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('to_syslog_facility requires 1 argument')
	}
	a := args[0]
	code := match a {
		int { a }
		else { return error('to_syslog_facility requires an integer') }
	}
	facility := match code {
		0 { 'kern' }
		1 { 'user' }
		2 { 'mail' }
		3 { 'daemon' }
		4 { 'auth' }
		5 { 'syslog' }
		6 { 'lpr' }
		7 { 'news' }
		8 { 'uucp' }
		9 { 'cron' }
		10 { 'authpriv' }
		11 { 'ftp' }
		12 { 'ntp' }
		13 { 'security' }
		14 { 'console' }
		15 { 'solaris-cron' }
		16 { 'local0' }
		17 { 'local1' }
		18 { 'local2' }
		19 { 'local3' }
		20 { 'local4' }
		21 { 'local5' }
		22 { 'local6' }
		23 { 'local7' }
		else { return error('invalid syslog facility code: ${code}') }
	}
	return VrlValue(facility)
}

// to_syslog_facility_code(value)
fn fn_to_syslog_facility_code(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('to_syslog_facility_code requires 1 argument')
	}
	a := args[0]
	facility := match a {
		string { a }
		else { return error('to_syslog_facility_code requires a string') }
	}
	code := match facility.to_lower() {
		'kern' { 0 }
		'user' { 1 }
		'mail' { 2 }
		'daemon' { 3 }
		'auth' { 4 }
		'syslog' { 5 }
		'lpr' { 6 }
		'news' { 7 }
		'uucp' { 8 }
		'cron' { 9 }
		'authpriv' { 10 }
		'ftp' { 11 }
		'ntp' { 12 }
		'security' { 13 }
		'console' { 14 }
		'solaris-cron' { 15 }
		'local0' { 16 }
		'local1' { 17 }
		'local2' { 18 }
		'local3' { 19 }
		'local4' { 20 }
		'local5' { 21 }
		'local6' { 22 }
		'local7' { 23 }
		else { return error('invalid syslog facility: ${facility}') }
	}
	return VrlValue(code)
}
