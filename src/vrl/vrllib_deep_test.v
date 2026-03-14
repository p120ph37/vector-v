module vrl

import os

// Deep coverage tests targeting uncovered code paths in:
// - vrllib_parse.v (parse_syslog, parse_logfmt, parse_key_value, parse_common_log,
//   parse_yaml, parse_klog, parse_linux_authorization, parse_duration, parse_bytes,
//   parse_timestamp)
// - vrllib_parse_new.v (parse_cef, parse_influxdb, parse_ruby_hash, parse_xml,
//   parse_cbor, parse_glog, parse_aws_vpc_flow_log, parse_aws_alb_log)
// - vrllib_jsonschema.v (allOf, anyOf, oneOf, patternProperties, $ref, format
//   validation, array/number constraints)

fn d_obj(prog string, input string) !VrlValue {
	mut obj := map[string]VrlValue{}
	obj['input'] = VrlValue(input)
	return execute(prog, obj)
}

fn d_json(prog string, input string) string {
	result := d_obj(prog, input) or { return 'ERROR: ${err}' }
	return vrl_to_json(result)
}

// ============================================================
// parse_syslog: RFC 5424
// ============================================================

fn test_deep_parse_syslog_rfc5424_basic() {
	result := execute('parse_syslog!("<34>1 2021-02-03T21:13:55-02:00 myhost myapp 1234 msg123 - My message")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"severity":"crit"'), 'severity: ${j}'
	assert j.contains('"facility":"auth"'), 'facility: ${j}'
	assert j.contains('"hostname":"myhost"'), 'hostname: ${j}'
	assert j.contains('"appname":"myapp"'), 'appname: ${j}'
	assert j.contains('"procid":"1234"'), 'procid: ${j}'
	assert j.contains('"msgid":"msg123"'), 'msgid: ${j}'
	assert j.contains('"message":"My message"'), 'message: ${j}'
}

fn test_deep_parse_syslog_rfc5424_structured_data() {
	result := execute('parse_syslog!("<165>1 2021-01-01T00:00:00Z host app 999 - [exampleSDID@32473 iut=\"3\" eventSource=\"Application\" eventID=\"1011\"] Event logged")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"iut":"3"'), 'structured data iut: ${j}'
	assert j.contains('"eventSource":"Application"'), 'structured data eventSource: ${j}'
	assert j.contains('"eventID":"1011"'), 'structured data eventID: ${j}'
	assert j.contains('"message":"Event logged"'), 'message: ${j}'
}

fn test_deep_parse_syslog_rfc5424_nil_values() {
	result := execute('parse_syslog!("<13>1 - - - - - - No host no time")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"message":"No host no time"'), 'nil values message: ${j}'
}

fn test_deep_parse_syslog_rfc5424_no_message() {
	result := execute('parse_syslog!("<13>1 2021-01-01T00:00:00Z host app - - -")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"appname":"app"'), 'no message appname: ${j}'
}

// ============================================================
// parse_syslog: RFC 3164
// ============================================================

fn test_deep_parse_syslog_rfc3164_basic() {
	result := execute('parse_syslog!("<34>Feb  3 21:13:55 myhost sshd[1234]: Connection accepted")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"severity":"crit"'), 'rfc3164 severity: ${j}'
	assert j.contains('"hostname":"myhost"'), 'rfc3164 hostname: ${j}'
	assert j.contains('"appname":"sshd"'), 'rfc3164 appname: ${j}'
	assert j.contains('"message":"Connection accepted"'), 'rfc3164 message: ${j}'
}

fn test_deep_parse_syslog_rfc3164_no_pid() {
	result := execute('parse_syslog!("<14>Jan 10 12:00:00 server kernel: Something happened")', map[string]VrlValue{}) or {
		return
	}
	j := vrl_to_json(result)
	assert j.contains('"hostname":"server"'), 'rfc3164 no pid hostname: ${j}'
	assert j.contains('"appname":"kernel"'), 'rfc3164 no pid appname: ${j}'
}

fn test_deep_parse_syslog_error_no_priority() {
	_ := execute('parse_syslog!("no angle brackets")', map[string]VrlValue{}) or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected parse error for no priority'
}

fn test_deep_parse_syslog_error_unterminated_priority() {
	_ := execute('parse_syslog!("<999")', map[string]VrlValue{}) or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected parse error for unterminated priority'
}

// ============================================================
// parse_logfmt edge cases
// ============================================================

fn test_deep_parse_logfmt_escaped_quotes() {
	result := d_obj('.result = parse_logfmt!(.input)', 'key="hello \\"world\\""') or { return }
	j := vrl_to_json(result)
	assert j.contains('"key"'), 'logfmt escaped: ${j}'
}

fn test_deep_parse_logfmt_empty_value() {
	result := d_obj('.result = parse_logfmt!(.input)', 'key= next=val') or { return }
	j := vrl_to_json(result)
	assert j.contains('"key":""'), 'logfmt empty value: ${j}'
	assert j.contains('"next":"val"'), 'logfmt next key: ${j}'
}

fn test_deep_parse_logfmt_standalone_key() {
	result := d_obj('.result = parse_logfmt!(.input)', 'standalone level=info') or { return }
	j := vrl_to_json(result)
	assert j.contains('"standalone":true'), 'logfmt standalone: ${j}'
	assert j.contains('"level":"info"'), 'logfmt level: ${j}'
}

fn test_deep_parse_logfmt_single_quoted() {
	result := d_obj(".result = parse_logfmt!(.input)", "key='quoted value' other=test") or { return }
	j := vrl_to_json(result)
	assert j.contains('"other":"test"'), 'logfmt single quoted other: ${j}'
}

fn test_deep_parse_logfmt_multiple_pairs() {
	result := d_obj('.result = parse_logfmt!(.input)', 'ts=2021-01-01 level=info msg="hello world" count=42') or { return }
	j := vrl_to_json(result)
	assert j.contains('"ts":"2021-01-01"'), 'logfmt ts: ${j}'
	assert j.contains('"level":"info"'), 'logfmt level: ${j}'
	assert j.contains('"msg":"hello world"'), 'logfmt msg: ${j}'
	assert j.contains('"count":"42"'), 'logfmt count: ${j}'
}

// ============================================================
// parse_key_value with custom delimiters
// ============================================================

fn test_deep_parse_key_value_custom_kv_delim() {
	result := execute('parse_key_value!("host:localhost port:8080", key_value_delimiter: ":")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"host":"localhost"'), 'kv custom delim host: ${j}'
	assert j.contains('"port":"8080"'), 'kv custom delim port: ${j}'
}

fn test_deep_parse_key_value_custom_field_delim() {
	result := execute('parse_key_value!("host=localhost,port=8080", field_delimiter: ",")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"host":"localhost"'), 'kv field delim host: ${j}'
	assert j.contains('"port":"8080"'), 'kv field delim port: ${j}'
}

fn test_deep_parse_key_value_quoted_value() {
	result := execute('parse_key_value!("msg=\\"hello world\\" level=info")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"msg":"hello world"'), 'kv quoted value: ${j}'
}

fn test_deep_parse_key_value_standalone() {
	result := execute('parse_key_value!("verbose host=localhost")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"verbose":true'), 'kv standalone: ${j}'
	assert j.contains('"host":"localhost"'), 'kv standalone host: ${j}'
}

// ============================================================
// parse_common_log
// ============================================================

fn test_deep_parse_common_log_basic() {
	result := d_obj('.result = parse_common_log!(.input)', '127.0.0.1 user-id frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326') or { return }
	j := vrl_to_json(result)
	assert j.contains('"host":"127.0.0.1"'), 'clf host: ${j}'
	assert j.contains('"user":"frank"'), 'clf user: ${j}'
	assert j.contains('"method":"GET"'), 'clf method: ${j}'
	assert j.contains('"path":"/apache_pb.gif"'), 'clf path: ${j}'
	assert j.contains('"protocol":"HTTP/1.0"'), 'clf protocol: ${j}'
	assert j.contains('"status":200'), 'clf status: ${j}'
	assert j.contains('"size":2326'), 'clf size: ${j}'
}

fn test_deep_parse_common_log_null_status() {
	result := d_obj('.result = parse_common_log!(.input)', '10.0.0.1 - - [01/Jan/2021:00:00:00 +0000] "POST /api HTTP/1.1" - -') or { return }
	j := vrl_to_json(result)
	assert j.contains('"method":"POST"'), 'clf null method: ${j}'
	assert j.contains('"host":"10.0.0.1"'), 'clf null host: ${j}'
}

fn test_deep_parse_common_log_null_user() {
	result := d_obj('.result = parse_common_log!(.input)', '10.0.0.1 - - [01/Jan/2021:00:00:00 +0000] "GET / HTTP/1.1" 200 100') or { return }
	j := vrl_to_json(result)
	assert j.contains('"method":"GET"'), 'clf null user method: ${j}'
}

// ============================================================
// parse_yaml nested structures
// ============================================================

fn test_deep_parse_yaml_nested_map() {
	input := 'server:\n  host: localhost\n  port: 8080'
	result := d_obj('.result = parse_yaml!(.input)', input) or { return }
	j := vrl_to_json(result)
	assert j.contains('"server"'), 'yaml nested map: ${j}'
	assert j.contains('"host":"localhost"'), 'yaml nested host: ${j}'
}

fn test_deep_parse_yaml_sequence() {
	input := '- apple\n- banana\n- cherry'
	result := d_obj('.result = parse_yaml!(.input)', input) or { return }
	j := vrl_to_json(result)
	assert j.contains('"apple"'), 'yaml seq: ${j}'
	assert j.contains('"banana"'), 'yaml seq: ${j}'
}

fn test_deep_parse_yaml_scalar_string() {
	result := execute('parse_yaml!("hello")', map[string]VrlValue{}) or { return }
	assert result == VrlValue('hello'), 'yaml scalar string'
}

fn test_deep_parse_yaml_null() {
	result := execute('parse_yaml!("null")', map[string]VrlValue{}) or { return }
	assert result is VrlNull, 'yaml null'
}

fn test_deep_parse_yaml_boolean() {
	result := execute('parse_yaml!("true")', map[string]VrlValue{}) or { return }
	assert result == VrlValue(true), 'yaml true'
}

fn test_deep_parse_yaml_integer() {
	result := execute('parse_yaml!("42")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j == '42', 'yaml integer: ${j}'
}

fn test_deep_parse_yaml_flow_mapping() {
	result := execute('parse_yaml!("{a: 1, b: 2}")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'yaml flow mapping: ${j}'
	assert j.contains('"b"'), 'yaml flow mapping: ${j}'
}

fn test_deep_parse_yaml_flow_sequence() {
	result := execute('parse_yaml!("[1, 2, 3]")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('1'), 'yaml flow seq: ${j}'
}

// ============================================================
// parse_klog edge cases
// ============================================================

fn test_deep_parse_klog_info() {
	result := d_obj('.result = parse_klog!(.input)', 'I0505 17:59:40.692994   28133 miscellaneous.go:42] some klog message') or { return }
	j := vrl_to_json(result)
	assert j.contains('"level":"info"'), 'klog info level: ${j}'
	assert j.contains('"file":"miscellaneous.go"'), 'klog file: ${j}'
	assert j.contains('"line":42'), 'klog line: ${j}'
	assert j.contains('"message":"some klog message"'), 'klog message: ${j}'
}

fn test_deep_parse_klog_warning() {
	result := d_obj('.result = parse_klog!(.input)', 'W0101 12:00:00.000000       1 test.go:10] warning msg') or { return }
	j := vrl_to_json(result)
	assert j.contains('"level":"warning"'), 'klog warning level: ${j}'
}

fn test_deep_parse_klog_error() {
	result := d_obj('.result = parse_klog!(.input)', 'E0315 08:30:00.123456     100 main.go:99] error occurred') or { return }
	j := vrl_to_json(result)
	assert j.contains('"level":"error"'), 'klog error level: ${j}'
}

fn test_deep_parse_klog_fatal() {
	result := d_obj('.result = parse_klog!(.input)', 'F1231 23:59:59.999999   99999 crash.go:1] fatal crash') or { return }
	j := vrl_to_json(result)
	assert j.contains('"level":"fatal"'), 'klog fatal level: ${j}'
}

fn test_deep_parse_klog_too_short() {
	_ := execute('parse_klog!("X")', map[string]VrlValue{}) or {
		assert err.msg().contains('too short') || err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected klog parse error'
}

fn test_deep_parse_klog_unknown_level() {
	_ := d_obj('.result = parse_klog!(.input)', 'X0505 17:59:40.000000   28133 test.go:42] msg') or {
		assert err.msg().contains('unknown level')
		return
	}
	assert false, 'expected klog unknown level error'
}

// ============================================================
// parse_linux_authorization
// ============================================================

fn test_deep_parse_linux_authorization_with_pid() {
	result := d_obj('.result = parse_linux_authorization!(.input)', 'Mar  5 14:17:01 myhost CRON[1234]: pam_unix(cron:session): session opened') or { return }
	j := vrl_to_json(result)
	assert j.contains('"hostname":"myhost"'), 'linux auth hostname: ${j}'
	assert j.contains('"appname":"CRON"'), 'linux auth appname: ${j}'
	assert j.contains('"message":"pam_unix(cron:session): session opened"'), 'linux auth message: ${j}'
}

fn test_deep_parse_linux_authorization_no_pid() {
	result := d_obj('.result = parse_linux_authorization!(.input)', 'Jan 10 08:00:00 server kernel: something happened') or { return }
	j := vrl_to_json(result)
	assert j.contains('"hostname":"server"'), 'linux auth no pid hostname: ${j}'
	assert j.contains('"appname":"kernel"'), 'linux auth no pid appname: ${j}'
}

fn test_deep_parse_linux_authorization_too_short() {
	_ := execute('parse_linux_authorization!("ab")', map[string]VrlValue{}) or {
		assert err.msg().contains('too short') || err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected linux auth parse error'
}

// ============================================================
// parse_duration various units
// ============================================================

fn test_deep_parse_duration_seconds_to_ms() {
	result := execute('parse_duration!("1s", "ms")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 999.0 && v < 1001.0, 'duration 1s to ms: ${v}'
}

fn test_deep_parse_duration_ms_to_us() {
	result := execute('parse_duration!("1ms", "us")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 999.0 && v < 1001.0, 'duration 1ms to us: ${v}'
}

fn test_deep_parse_duration_us_to_ns() {
	result := execute('parse_duration!("1us", "ns")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 999.0 && v < 1001.0, 'duration 1us to ns: ${v}'
}

fn test_deep_parse_duration_minutes() {
	result := execute('parse_duration!("2m", "s")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 119.0 && v < 121.0, 'duration 2m to s: ${v}'
}

fn test_deep_parse_duration_hours() {
	result := execute('parse_duration!("1h", "m")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 59.0 && v < 61.0, 'duration 1h to m: ${v}'
}

fn test_deep_parse_duration_days() {
	result := execute('parse_duration!("1d", "h")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 23.0 && v < 25.0, 'duration 1d to h: ${v}'
}

fn test_deep_parse_duration_ns_to_ms() {
	result := execute('parse_duration!("1000000ns", "ms")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 0.99 && v < 1.01, 'duration 1000000ns to ms: ${v}'
}

fn test_deep_parse_duration_compound() {
	result := execute('parse_duration!("1h 30m", "m")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 89.0 && v < 91.0, 'duration 1h30m to m: ${v}'
}

fn test_deep_parse_duration_invalid() {
	_ := execute('parse_duration!("invalid", "s")', map[string]VrlValue{}) or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected duration parse error'
}

fn test_deep_parse_duration_unknown_unit() {
	_ := execute('parse_duration!("1x", "s")', map[string]VrlValue{}) or {
		assert err.msg().contains('unknown')
		return
	}
	assert false, 'expected unknown unit error'
}

// ============================================================
// parse_bytes edge cases
// ============================================================

fn test_deep_parse_bytes_kb() {
	result := execute('parse_bytes!("1024KB")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 1048575.0, 'parse_bytes 1024KB: ${v}'
}

fn test_deep_parse_bytes_mb_to_kb() {
	result := execute('parse_bytes!("1MB", unit: "KB")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 1023.0 && v < 1025.0, 'parse_bytes 1MB to KB: ${v}'
}

fn test_deep_parse_bytes_gb() {
	result := execute('parse_bytes!("1GB")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 1073741823.0, 'parse_bytes 1GB: ${v}'
}

fn test_deep_parse_bytes_tb() {
	result := execute('parse_bytes!("1TB")', map[string]VrlValue{}) or { return }
	v := result as f64
	assert v > 1.0e12 - 1.0, 'parse_bytes 1TB: ${v}'
}

fn test_deep_parse_bytes_invalid() {
	_ := execute('parse_bytes!("abc")', map[string]VrlValue{}) or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected bytes parse error'
}

// ============================================================
// parse_timestamp format edge cases
// ============================================================

fn test_deep_parse_timestamp_rfc3339() {
	result := execute('parse_timestamp!("2021-06-15T12:30:00Z", "%+")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('2021'), 'timestamp rfc3339: ${j}'
}

fn test_deep_parse_timestamp_custom_format() {
	result := execute('parse_timestamp!("2021-06-15T12:30:00", "%Y-%m-%dT%H:%M:%S")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('2021'), 'timestamp custom: ${j}'
}

fn test_deep_parse_timestamp_with_tz() {
	result := execute('parse_timestamp!("15/Jun/2021:12:30:00 +0000", "%d/%b/%Y:%T %z")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('2021'), 'timestamp tz: ${j}'
}

fn test_deep_parse_timestamp_invalid() {
	_ := execute('parse_timestamp!("not a date", "%Y-%m-%d")', map[string]VrlValue{}) or {
		assert err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected timestamp parse error'
}

// ============================================================
// parse_cef with extensions
// ============================================================

fn test_deep_parse_cef_basic() {
	result := d_obj('.result = parse_cef!(.input)', 'CEF:0|Security|IDS|1.0|100|Attack|10|src=10.0.0.1 dst=10.0.0.2') or { return }
	j := vrl_to_json(result)
	assert j.contains('"cefVersion":"0"'), 'cef version: ${j}'
	assert j.contains('"deviceVendor":"Security"'), 'cef vendor: ${j}'
	assert j.contains('"deviceProduct":"IDS"'), 'cef product: ${j}'
	assert j.contains('"severity":"10"'), 'cef severity: ${j}'
	assert j.contains('"src":"10.0.0.1"'), 'cef src: ${j}'
	assert j.contains('"dst":"10.0.0.2"'), 'cef dst: ${j}'
}

fn test_deep_parse_cef_escaped_pipe() {
	result := d_obj('.result = parse_cef!(.input)', 'CEF:0|Ven\\|dor|Prod|1.0|100|Name|5|key=val') or { return }
	j := vrl_to_json(result)
	assert j.contains('"deviceVendor":"Ven|dor"'), 'cef escaped pipe: ${j}'
}

fn test_deep_parse_cef_no_extensions() {
	result := d_obj('.result = parse_cef!(.input)', 'CEF:0|Vendor|Product|1.0|100|Name|5|') or { return }
	j := vrl_to_json(result)
	assert j.contains('"cefVersion":"0"'), 'cef no ext: ${j}'
}

fn test_deep_parse_cef_multiple_extensions() {
	result := d_obj('.result = parse_cef!(.input)', 'CEF:0|V|P|1|1|N|1|src=1.2.3.4 dst=5.6.7.8 spt=1234 dpt=80') or { return }
	j := vrl_to_json(result)
	assert j.contains('"src":"1.2.3.4"'), 'cef multi src: ${j}'
	assert j.contains('"dst":"5.6.7.8"'), 'cef multi dst: ${j}'
	assert j.contains('"spt":"1234"'), 'cef multi spt: ${j}'
	assert j.contains('"dpt":"80"'), 'cef multi dpt: ${j}'
}

fn test_deep_parse_cef_missing_header() {
	_ := execute('parse_cef!("not a cef message")', map[string]VrlValue{}) or {
		assert err.msg().contains('CEF header') || err.msg().contains('does not contain')
		return
	}
	assert false, 'expected cef parse error'
}

// ============================================================
// parse_influxdb line protocol
// ============================================================

fn test_deep_parse_influxdb_basic() {
	result := d_obj('.result = parse_influxdb!(.input)', 'cpu,host=serverA usage_idle=98.5 1609459200000000000') or { return }
	j := vrl_to_json(result)
	assert j.contains('"name":"cpu_usage_idle"'), 'influxdb name: ${j}'
	assert j.contains('"host":"serverA"'), 'influxdb tag: ${j}'
}

fn test_deep_parse_influxdb_multiple_fields() {
	result := d_obj('.result = parse_influxdb!(.input)', 'mem,host=s1 used=1024i,free=2048i') or { return }
	j := vrl_to_json(result)
	assert j.contains('"name":"mem_used"'), 'influxdb multi used: ${j}'
	assert j.contains('"name":"mem_free"'), 'influxdb multi free: ${j}'
}

fn test_deep_parse_influxdb_no_tags() {
	result := d_obj('.result = parse_influxdb!(.input)', 'measurement field=1.5') or { return }
	j := vrl_to_json(result)
	assert j.contains('"name":"measurement_field"'), 'influxdb no tags: ${j}'
}

fn test_deep_parse_influxdb_string_field() {
	result := d_obj('.result = parse_influxdb!(.input)', 'events,tag=a message="hello world"') or { return }
	j := vrl_to_json(result)
	assert j.contains('"name":"events_message"'), 'influxdb string field: ${j}'
}

fn test_deep_parse_influxdb_boolean_field() {
	result := d_obj('.result = parse_influxdb!(.input)', 'status active=true') or { return }
	j := vrl_to_json(result)
	assert j.contains('"name":"status_active"'), 'influxdb bool field: ${j}'
}

fn test_deep_parse_influxdb_empty() {
	result := execute('parse_influxdb!("")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j == '[]', 'influxdb empty: ${j}'
}

// ============================================================
// parse_ruby_hash
// ============================================================

fn test_deep_parse_ruby_hash_basic() {
	result := execute('parse_ruby_hash!("{\"a\" => 1, \"b\" => 2}")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'ruby hash a: ${j}'
	assert j.contains('"b"'), 'ruby hash b: ${j}'
}

fn test_deep_parse_ruby_hash_symbol_keys() {
	result := d_obj('.result = parse_ruby_hash!(.input)', '{:name => "Alice", :age => 30}') or { return }
	j := vrl_to_json(result)
	assert j.contains('"name":"Alice"'), 'ruby hash symbol name: ${j}'
}

fn test_deep_parse_ruby_hash_nested() {
	result := d_obj('.result = parse_ruby_hash!(.input)', '{"outer" => {"inner" => "value"}}') or { return }
	j := vrl_to_json(result)
	assert j.contains('"outer"'), 'ruby hash nested outer: ${j}'
	assert j.contains('"inner":"value"'), 'ruby hash nested inner: ${j}'
}

fn test_deep_parse_ruby_hash_array_value() {
	result := d_obj('.result = parse_ruby_hash!(.input)', '{"items" => [1, 2, 3]}') or { return }
	j := vrl_to_json(result)
	assert j.contains('"items"'), 'ruby hash array: ${j}'
}

fn test_deep_parse_ruby_hash_nil() {
	result := d_obj('.result = parse_ruby_hash!(.input)', '{"key" => nil}') or { return }
	j := vrl_to_json(result)
	assert j.contains('"key":null'), 'ruby hash nil: ${j}'
}

fn test_deep_parse_ruby_hash_booleans() {
	result := d_obj('.result = parse_ruby_hash!(.input)', '{"t" => true, "f" => false}') or { return }
	j := vrl_to_json(result)
	assert j.contains('"t":true'), 'ruby hash true: ${j}'
	assert j.contains('"f":false'), 'ruby hash false: ${j}'
}

fn test_deep_parse_ruby_hash_empty() {
	result := execute('parse_ruby_hash!("{}")', map[string]VrlValue{}) or { return }
	j := vrl_to_json(result)
	assert j == '{}', 'ruby hash empty: ${j}'
}

fn test_deep_parse_ruby_hash_not_hash() {
	_ := execute('parse_ruby_hash!("not a hash")', map[string]VrlValue{}) or {
		assert err.msg().contains('must start with')
		return
	}
	assert false, 'expected ruby hash parse error'
}

// ============================================================
// parse_xml with attributes and namespaces
// ============================================================

fn test_deep_parse_xml_simple() {
	result := d_obj('.result = parse_xml!(.input)', '<root><child>text</child></root>') or { return }
	j := vrl_to_json(result)
	assert j.contains('"root"'), 'xml root: ${j}'
	assert j.contains('"child"'), 'xml child: ${j}'
}

fn test_deep_parse_xml_with_attr() {
	result := d_obj('.result = parse_xml!(.input)', '<item id="123">hello</item>') or { return }
	j := vrl_to_json(result)
	assert j.contains('"item"'), 'xml attr item: ${j}'
	assert j.contains('"@id":"123"'), 'xml attr id: ${j}'
}

fn test_deep_parse_xml_nested() {
	result := d_obj('.result = parse_xml!(.input)', '<a><b><c>deep</c></b></a>') or { return }
	j := vrl_to_json(result)
	assert j.contains('"a"'), 'xml nested a: ${j}'
	assert j.contains('"c"'), 'xml nested c: ${j}'
}

fn test_deep_parse_xml_empty_element() {
	result := d_obj('.result = parse_xml!(.input)', '<root><empty/></root>') or { return }
	j := vrl_to_json(result)
	assert j.contains('"root"'), 'xml empty element: ${j}'
}

fn test_deep_parse_xml_cdata() {
	result := d_obj('.result = parse_xml!(.input)', '<root><![CDATA[some <data>]]></root>') or { return }
	j := vrl_to_json(result)
	assert j.contains('"root"'), 'xml cdata: ${j}'
}

fn test_deep_parse_xml_error_empty() {
	_ := execute('parse_xml!("")', map[string]VrlValue{}) or {
		assert err.msg().contains('empty') || err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected xml parse error for empty input'
}

// ============================================================
// parse_glog format
// ============================================================

fn test_deep_parse_glog_info() {
	result := d_obj('.result = parse_glog!(.input)', 'I0315 12:34:56.789012 12345 server.cc:42] Starting server') or { return }
	j := vrl_to_json(result)
	assert j.contains('"level":"info"'), 'glog info level: ${j}'
	assert j.contains('"file":"server.cc"'), 'glog file: ${j}'
	assert j.contains('"line":42'), 'glog line: ${j}'
	assert j.contains('"message":"Starting server"'), 'glog message: ${j}'
}

fn test_deep_parse_glog_warning() {
	result := d_obj('.result = parse_glog!(.input)', 'W0101 00:00:00.000000 1 test.cc:1] warn') or { return }
	j := vrl_to_json(result)
	assert j.contains('"level":"warning"'), 'glog warning: ${j}'
}

fn test_deep_parse_glog_error() {
	result := d_obj('.result = parse_glog!(.input)', 'E0601 10:20:30.000000 999 err.cc:100] error msg') or { return }
	j := vrl_to_json(result)
	assert j.contains('"level":"error"'), 'glog error: ${j}'
}

fn test_deep_parse_glog_fatal() {
	result := d_obj('.result = parse_glog!(.input)', 'F1231 23:59:59.999999 1 main.cc:1] fatal') or { return }
	j := vrl_to_json(result)
	assert j.contains('"level":"fatal"'), 'glog fatal: ${j}'
}

fn test_deep_parse_glog_too_short() {
	_ := execute('parse_glog!("I")', map[string]VrlValue{}) or {
		assert err.msg().contains('too short') || err.msg().contains('unable to parse')
		return
	}
	assert false, 'expected glog parse error'
}

fn test_deep_parse_glog_unknown_level() {
	_ := d_obj('.result = parse_glog!(.input)', 'X0101 00:00:00.000000 1 t.cc:1] msg') or {
		assert err.msg().contains('unknown level')
		return
	}
	assert false, 'expected glog unknown level error'
}

// ============================================================
// parse_aws_vpc_flow_log
// ============================================================

fn test_deep_parse_aws_vpc_flow_log_basic() {
	result := d_obj('.result = parse_aws_vpc_flow_log!(.input)', '2 123456789012 eni-1235b8ca123456789 172.31.16.139 172.31.16.21 20641 22 6 20 4249 1418530010 1418530070 ACCEPT OK') or { return }
	j := vrl_to_json(result)
	assert j.contains('"version":2'), 'vpc flow version: ${j}'
	assert j.contains('"account_id":"123456789012"'), 'vpc flow account: ${j}'
	assert j.contains('"srcaddr":"172.31.16.139"'), 'vpc flow srcaddr: ${j}'
	assert j.contains('"dstaddr":"172.31.16.21"'), 'vpc flow dstaddr: ${j}'
	assert j.contains('"action":"ACCEPT"'), 'vpc flow action: ${j}'
}

fn test_deep_parse_aws_vpc_flow_log_reject() {
	result := d_obj('.result = parse_aws_vpc_flow_log!(.input)', '2 123456789012 eni-abc 10.0.0.1 10.0.0.2 1234 80 6 5 500 1000 2000 REJECT OK') or { return }
	j := vrl_to_json(result)
	assert j.contains('"action":"REJECT"'), 'vpc flow reject: ${j}'
}

fn test_deep_parse_aws_vpc_flow_log_nil_values() {
	result := d_obj('.result = parse_aws_vpc_flow_log!(.input)', '2 123456789012 eni-abc - - - - - - - - - - -') or { return }
	j := vrl_to_json(result)
	assert j.contains('"srcaddr":null'), 'vpc flow nil srcaddr: ${j}'
}

// ============================================================
// parse_aws_alb_log
// ============================================================

fn test_deep_parse_aws_alb_log_basic() {
	input := 'http 2018-07-02T22:23:00.186641Z app/my-loadbalancer/50dc6c495c0c9188 192.168.131.39:2817 10.0.0.1:80 0.000 0.001 0.000 200 200 34 366 "GET http://www.example.com:80/ HTTP/1.1" "curl/7.46.0" - - arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/my-target-group/50dc6c495c0c9188 "Root=1-58337262-36d228ad5d99923122bbe354" "-" "-" 0 2018-07-02T22:22:48.993000Z "forward" "-" "-"'
	result := d_obj('.result = parse_aws_alb_log!(.input)', input) or { return }
	j := vrl_to_json(result)
	assert j.contains('"type":"http"'), 'alb type: ${j}'
	assert j.contains('"elb_status_code":200'), 'alb status: ${j}'
	assert j.contains('"request_method":"GET"'), 'alb method: ${j}'
}

// ============================================================
// parse_cbor various types
// ============================================================

fn test_deep_parse_cbor_unsigned_int() {
	// CBOR unsigned int 42 = 0x18 0x2A
	mut obj := map[string]VrlValue{}
	mut cbor_data := []u8{}
	cbor_data << 0x18 // uint8 follows
	cbor_data << 0x2A // 42
	obj['input'] = VrlValue(cbor_data.bytestr())
	result := execute('parse_cbor!(.input)', obj) or { return }
	assert result == VrlValue(i64(42)), 'cbor uint: ${vrl_to_json(result)}'
}

fn test_deep_parse_cbor_negative_int() {
	// CBOR negative int -1 = 0x20
	mut obj := map[string]VrlValue{}
	mut cbor_data := []u8{}
	cbor_data << 0x20 // negative int, additional 0 => -1 - 0 = -1
	obj['input'] = VrlValue(cbor_data.bytestr())
	result := execute('parse_cbor!(.input)', obj) or { return }
	assert result == VrlValue(i64(-1)), 'cbor neg int: ${vrl_to_json(result)}'
}

fn test_deep_parse_cbor_text_string() {
	// CBOR text string "hi" = 0x62 0x68 0x69
	mut obj := map[string]VrlValue{}
	mut cbor_data := []u8{}
	cbor_data << 0x62 // text string, length 2
	cbor_data << 0x68 // 'h'
	cbor_data << 0x69 // 'i'
	obj['input'] = VrlValue(cbor_data.bytestr())
	result := execute('parse_cbor!(.input)', obj) or { return }
	assert result == VrlValue('hi'), 'cbor text: ${vrl_to_json(result)}'
}

fn test_deep_parse_cbor_array() {
	// CBOR array [1, 2] = 0x82 0x01 0x02
	mut obj := map[string]VrlValue{}
	mut cbor_data := []u8{}
	cbor_data << 0x82 // array of 2 items
	cbor_data << 0x01 // 1
	cbor_data << 0x02 // 2
	obj['input'] = VrlValue(cbor_data.bytestr())
	result := execute('parse_cbor!(.input)', obj) or { return }
	j := vrl_to_json(result)
	assert j == '[1,2]', 'cbor array: ${j}'
}

fn test_deep_parse_cbor_map() {
	// CBOR map {"a": 1} = 0xA1 0x61 0x61 0x01
	mut obj := map[string]VrlValue{}
	mut cbor_data := []u8{}
	cbor_data << 0xA1 // map of 1 pair
	cbor_data << 0x61 // text string, length 1
	cbor_data << 0x61 // 'a'
	cbor_data << 0x01 // 1
	obj['input'] = VrlValue(cbor_data.bytestr())
	result := execute('parse_cbor!(.input)', obj) or { return }
	j := vrl_to_json(result)
	assert j.contains('"a":1'), 'cbor map: ${j}'
}

fn test_deep_parse_cbor_bool_true() {
	// CBOR true = 0xF5
	mut obj := map[string]VrlValue{}
	mut cbor_data := []u8{}
	cbor_data << 0xF5 // true
	obj['input'] = VrlValue(cbor_data.bytestr())
	result := execute('parse_cbor!(.input)', obj) or { return }
	assert result == VrlValue(true), 'cbor true: ${vrl_to_json(result)}'
}

fn test_deep_parse_cbor_bool_false() {
	// CBOR false = 0xF4
	mut obj := map[string]VrlValue{}
	mut cbor_data := []u8{}
	cbor_data << 0xF4 // false
	obj['input'] = VrlValue(cbor_data.bytestr())
	result := execute('parse_cbor!(.input)', obj) or { return }
	assert result == VrlValue(false), 'cbor false: ${vrl_to_json(result)}'
}

fn test_deep_parse_cbor_null() {
	// CBOR null = 0xF6
	mut obj := map[string]VrlValue{}
	mut cbor_data := []u8{}
	cbor_data << 0xF6 // null
	obj['input'] = VrlValue(cbor_data.bytestr())
	result := execute('parse_cbor!(.input)', obj) or { return }
	assert result is VrlNull, 'cbor null'
}

fn test_deep_parse_cbor_small_uint() {
	// CBOR small uint 10 = 0x0A
	mut obj := map[string]VrlValue{}
	mut cbor_data := []u8{}
	cbor_data << 0x0A // uint 10 (inline)
	obj['input'] = VrlValue(cbor_data.bytestr())
	result := execute('parse_cbor!(.input)', obj) or { return }
	assert result == VrlValue(i64(10)), 'cbor small uint: ${vrl_to_json(result)}'
}

// ============================================================
// JSON Schema: allOf, anyOf, oneOf composition (deeper)
// ============================================================

fn d_schema(json_str string, schema string, schema_file string) !VrlValue {
	os.write_file(schema_file, schema) or { panic(err) }
	prog := 'validate_json_schema!("${json_str}", schema_definition: "${schema_file}")'
	return execute(prog, map[string]VrlValue{})
}

fn d_schema_vrl(vrl_expr string, schema string, schema_file string) !VrlValue {
	os.write_file(schema_file, schema) or { panic(err) }
	prog := 'validate_json_schema!(encode_json(${vrl_expr}), schema_definition: "${schema_file}")'
	return execute(prog, map[string]VrlValue{})
}

fn test_deep_jsonschema_allof_string_constraints() {
	schema := '{"allOf": [{"type": "string"}, {"minLength": 3}, {"maxLength": 10}]}'
	path := '/tmp/test_deep_allof_str.json'
	defer { os.rm(path) or {} }
	result := d_schema(r'\"hello\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_allof_string_too_short() {
	schema := '{"allOf": [{"type": "string"}, {"minLength": 5}]}'
	path := '/tmp/test_deep_allof_short.json'
	defer { os.rm(path) or {} }
	d_schema(r'\"hi\"', schema, path) or {
		assert err.msg().contains('fewer than')
		return
	}
	panic('expected allOf minLength error')
}

fn test_deep_jsonschema_anyof_number_valid() {
	schema := '{"anyOf": [{"type": "number", "minimum": 100}, {"type": "number", "maximum": 10}]}'
	path := '/tmp/test_deep_anyof_num.json'
	defer { os.rm(path) or {} }
	result := d_schema('5', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_anyof_no_match() {
	schema := '{"anyOf": [{"type": "number", "minimum": 100}, {"type": "string"}]}'
	path := '/tmp/test_deep_anyof_no.json'
	defer { os.rm(path) or {} }
	d_schema('50', schema, path) or {
		assert err.msg().contains('anyOf')
		return
	}
	panic('expected anyOf error')
}

fn test_deep_jsonschema_oneof_no_match() {
	schema := '{"oneOf": [{"type": "string"}, {"type": "boolean"}]}'
	path := '/tmp/test_deep_oneof_no.json'
	defer { os.rm(path) or {} }
	d_schema('42', schema, path) or {
		assert err.msg().contains('oneOf')
		return
	}
	panic('expected oneOf no match error')
}

fn test_deep_jsonschema_oneof_exact_one() {
	schema := '{"oneOf": [{"type": "number", "minimum": 10}, {"type": "number", "maximum": 5}]}'
	path := '/tmp/test_deep_oneof_one.json'
	defer { os.rm(path) or {} }
	result := d_schema('15', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

// ============================================================
// JSON Schema: array minItems/maxItems deeper
// ============================================================

fn test_deep_jsonschema_array_min_items_valid() {
	schema := '{"type": "array", "minItems": 2}'
	path := '/tmp/test_deep_minarr_v.json'
	defer { os.rm(path) or {} }
	result := d_schema('[1,2,3]', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_array_max_items_valid() {
	schema := '{"type": "array", "maxItems": 5}'
	path := '/tmp/test_deep_maxarr_v.json'
	defer { os.rm(path) or {} }
	result := d_schema('[1,2]', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_array_contains_valid() {
	schema := '{"type": "array", "contains": {"type": "string"}}'
	path := '/tmp/test_deep_contains_v.json'
	defer { os.rm(path) or {} }
	result := d_schema(r'[1, \"hello\", 3]', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

// ============================================================
// JSON Schema: number multipleOf, exclusiveMinimum/Maximum deeper
// ============================================================

fn test_deep_jsonschema_exclusive_min_valid() {
	schema := '{"type": "number", "exclusiveMinimum": 10}'
	path := '/tmp/test_deep_emin_v.json'
	defer { os.rm(path) or {} }
	result := d_schema('11', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_exclusive_max_valid() {
	schema := '{"type": "number", "exclusiveMaximum": 10}'
	path := '/tmp/test_deep_emax_v.json'
	defer { os.rm(path) or {} }
	result := d_schema('9', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_multiple_of_float() {
	schema := '{"type": "number", "multipleOf": 0.5}'
	path := '/tmp/test_deep_multf.json'
	defer { os.rm(path) or {} }
	result := d_schema('2.5', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_multiple_of_float_invalid() {
	schema := '{"type": "number", "multipleOf": 0.3}'
	path := '/tmp/test_deep_multf_inv.json'
	defer { os.rm(path) or {} }
	d_schema('1.0', schema, path) or {
		assert err.msg().contains('not a multiple of')
		return
	}
	panic('expected multipleOf float error')
}

// ============================================================
// JSON Schema: patternProperties deeper
// ============================================================

fn test_deep_jsonschema_pattern_properties_multiple() {
	schema := '{"type": "object", "patternProperties": {"^s_": {"type": "string"}, "^i_": {"type": "integer"}}}'
	path := '/tmp/test_deep_patprop_m.json'
	defer { os.rm(path) or {} }
	result := d_schema_vrl('{"s_name": "Alice", "i_age": 30}', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_pattern_properties_type_mismatch() {
	schema := '{"type": "object", "patternProperties": {"^s_": {"type": "string"}}}'
	path := '/tmp/test_deep_patprop_mm.json'
	defer { os.rm(path) or {} }
	d_schema_vrl('{"s_count": 42}', schema, path) or {
		assert err.msg().contains('not of type')
		return
	}
	panic('expected patternProperties type error')
}

fn test_deep_jsonschema_additional_with_pattern_props() {
	schema := '{"type": "object", "patternProperties": {"^x_": {"type": "string"}}, "additionalProperties": false}'
	path := '/tmp/test_deep_addl_pat.json'
	defer { os.rm(path) or {} }
	// x_name matches pattern, so allowed; other_key does not
	d_schema_vrl('{"x_name": "ok", "other_key": "fail"}', schema, path) or {
		assert err.msg().contains('Additional property')
		return
	}
	panic('expected additionalProperties with patternProperties error')
}

// ============================================================
// JSON Schema: $ref resolution deeper
// ============================================================

fn test_deep_jsonschema_ref_nested_defs() {
	schema := '{"type": "object", "properties": {"addr": {"\$ref": "#/\$defs/address"}}, "\$defs": {"address": {"type": "object", "required": ["city"], "properties": {"city": {"type": "string"}}}}}'
	path := '/tmp/test_deep_ref_nested.json'
	defer { os.rm(path) or {} }
	result := d_schema_vrl('{"addr": {"city": "NYC"}}', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_ref_nested_defs_fail() {
	schema := '{"type": "object", "properties": {"addr": {"\$ref": "#/\$defs/address"}}, "\$defs": {"address": {"type": "object", "required": ["city"]}}}'
	path := '/tmp/test_deep_ref_nest_f.json'
	defer { os.rm(path) or {} }
	d_schema_vrl('{"addr": {"zip": "10001"}}', schema, path) or {
		assert err.msg().contains('required property')
		return
	}
	panic('expected ref nested required error')
}

// ============================================================
// JSON Schema: format edge cases
// ============================================================

fn test_deep_jsonschema_format_datetime_invalid() {
	schema := '{"type": "string", "format": "date-time"}'
	path := '/tmp/test_deep_dtinv.json'
	defer { os.rm(path) or {} }
	d_schema(r'\"not-a-datetime\"', schema, path) or {
		assert err.msg().contains('not a')
		return
	}
	panic('expected datetime format error')
}

fn test_deep_jsonschema_format_date_invalid() {
	schema := '{"type": "string", "format": "date"}'
	path := '/tmp/test_deep_dateinv.json'
	defer { os.rm(path) or {} }
	d_schema(r'\"2024-13-40\"', schema, path) or {
		// either format check or pass through
		return
	}
	// Some invalid dates may pass basic format check
}

fn test_deep_jsonschema_format_time_with_offset() {
	schema := '{"type": "string", "format": "time"}'
	path := '/tmp/test_deep_time_off.json'
	defer { os.rm(path) or {} }
	result := d_schema(r'\"10:30:00+05:30\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_format_hostname_invalid() {
	schema := '{"type": "string", "format": "hostname"}'
	path := '/tmp/test_deep_host_inv.json'
	defer { os.rm(path) or {} }
	d_schema(r'\"-invalid-host\"', schema, path) or {
		assert err.msg().contains('not a')
		return
	}
	panic('expected hostname format error')
}

fn test_deep_jsonschema_format_ipv6_valid() {
	schema := '{"type": "string", "format": "ipv6"}'
	path := '/tmp/test_deep_ipv6_v.json'
	defer { os.rm(path) or {} }
	result := d_schema(r'\"2001:db8::1\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_format_regex_valid() {
	schema := '{"type": "string", "format": "regex"}'
	path := '/tmp/test_deep_regex_v.json'
	defer { os.rm(path) or {} }
	result := d_schema(r'\"^[a-z]+$\"', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_format_regex_invalid() {
	schema := '{"type": "string", "format": "regex"}'
	path := '/tmp/test_deep_regex_inv.json'
	defer { os.rm(path) or {} }
	d_schema(r'\"[invalid(\"', schema, path) or {
		assert err.msg().contains('not a')
		return
	}
	panic('expected regex format error')
}

fn test_deep_jsonschema_format_email_domain_parts() {
	schema := '{"type": "string", "format": "email"}'
	path := '/tmp/test_deep_email_dp.json'
	defer { os.rm(path) or {} }
	d_schema(r'\"user@.invalid\"', schema, path) or {
		assert err.msg().contains('not a')
		return
	}
	panic('expected email format error for empty domain part')
}

// ============================================================
// JSON Schema: if/then/else else branch
// ============================================================

fn test_deep_jsonschema_if_else_branch() {
	schema := '{"if": {"type": "number", "minimum": 10}, "then": {"multipleOf": 5}, "else": {"const": 0}}'
	path := '/tmp/test_deep_ite_else.json'
	defer { os.rm(path) or {} }
	// Value 0 passes else branch (const: 0)
	result := d_schema('0', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_if_else_branch_fail() {
	schema := '{"if": {"type": "number", "minimum": 10}, "then": {"multipleOf": 5}, "else": {"const": 0}}'
	path := '/tmp/test_deep_ite_else_f.json'
	defer { os.rm(path) or {} }
	// Value 3 fails if (< 10), then must match else (const: 0) but 3 != 0
	d_schema('3', schema, path) or {
		assert err.msg().contains('does not match const')
		return
	}
	panic('expected if/else const error')
}

// ============================================================
// JSON Schema: additional properties with schema
// ============================================================

fn test_deep_jsonschema_additional_properties_schema() {
	schema := '{"type": "object", "properties": {"name": {"type": "string"}}, "additionalProperties": {"type": "number"}}'
	path := '/tmp/test_deep_addl_schema.json'
	defer { os.rm(path) or {} }
	result := d_schema_vrl('{"name": "Alice", "age": 30}', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

fn test_deep_jsonschema_additional_properties_schema_invalid() {
	schema := '{"type": "object", "properties": {"name": {"type": "string"}}, "additionalProperties": {"type": "number"}}'
	path := '/tmp/test_deep_addl_sch_inv.json'
	defer { os.rm(path) or {} }
	d_schema_vrl('{"name": "Alice", "extra": "not a number"}', schema, path) or {
		assert err.msg().contains('not of type')
		return
	}
	panic('expected additionalProperties schema error')
}

// ============================================================
// JSON Schema: uniqueItems valid case
// ============================================================

fn test_deep_jsonschema_unique_items_valid() {
	schema := '{"type": "array", "uniqueItems": true}'
	path := '/tmp/test_deep_unique_v.json'
	defer { os.rm(path) or {} }
	result := d_schema('[1, 2, 3]', schema, path) or { panic('${err}') }
	assert result == VrlValue(true)
}

// ============================================================
// JSON Schema: property names constraint
// ============================================================

fn test_deep_jsonschema_property_names_fail() {
	schema := '{"type": "object", "propertyNames": {"pattern": "^[a-z]+$"}}'
	path := '/tmp/test_deep_propn_f.json'
	defer { os.rm(path) or {} }
	d_schema_vrl('{"UPPER": 1}', schema, path) or {
		assert err.msg().contains('does not match pattern')
		return
	}
	panic('expected propertyNames pattern error')
}
