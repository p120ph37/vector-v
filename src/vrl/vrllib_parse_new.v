module vrl

import pcre2
import math
import time

// ============================================================================
// parse_apache_log(value, format, [timestamp_format])
// Parses Apache access and error log formats.
// format: "common", "combined", or "error"
// ============================================================================

fn fn_parse_apache_log(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('parse_apache_log requires at least 2 arguments')
	}
	s := match args[0] {
		string { args[0] as string }
		else { return error('parse_apache_log: value must be a string') }
	}
	format := match args[1] {
		string { args[1] as string }
		else { return error('parse_apache_log: format must be a string') }
	}
	ts_format := if args.len > 2 {
		match args[2] {
			string { args[2] as string }
			else { '%d/%b/%Y:%T %z' }
		}
	} else {
		if format == 'error' { '%a %b %d %T%.f %Y' } else { '%d/%b/%Y:%T %z' }
	}

	pattern := match format {
		'common' { log_regex_apache_common() }
		'combined' { log_regex_apache_combined() }
		'error' { log_regex_apache_error() }
		else { return error("parse_apache_log: unknown format '${format}', expected common, combined, or error") }
	}

	return log_parse_with_regex(s, pattern, ts_format)
}

// ============================================================================
// parse_nginx_log(value, format, [timestamp_format])
// Parses Nginx access and error log formats.
// format: "combined", "error", "ingress_upstreaminfo", or "main"
// ============================================================================

fn fn_parse_nginx_log(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('parse_nginx_log requires at least 2 arguments')
	}
	s := match args[0] {
		string { args[0] as string }
		else { return error('parse_nginx_log: value must be a string') }
	}
	format := match args[1] {
		string { args[1] as string }
		else { return error('parse_nginx_log: format must be a string') }
	}
	ts_format := if args.len > 2 {
		match args[2] {
			string { args[2] as string }
			else { '%d/%b/%Y:%T %z' }
		}
	} else {
		if format == 'error' { '%Y/%m/%d %H:%M:%S' } else { '%d/%b/%Y:%T %z' }
	}

	pattern := match format {
		'combined' { log_regex_nginx_combined() }
		'error' { log_regex_nginx_error() }
		'ingress_upstreaminfo' { log_regex_nginx_ingress_upstreaminfo() }
		'main' { log_regex_nginx_main() }
		else { return error("parse_nginx_log: unknown format '${format}', expected combined, error, ingress_upstreaminfo, or main") }
	}

	return log_parse_with_regex(s, pattern, ts_format)
}

// Shared log parsing with PCRE2 named capture groups
fn log_parse_with_regex(input string, pattern string, ts_format string) !VrlValue {
	re := pcre2.compile(pattern) or {
		return error('failed to compile log regex: ${err.msg()}')
	}
	m := re.find(input) or {
		return error('failed parsing log line')
	}

	mut result := new_object_map()
	for i, grp in m.groups {
		if i >= re.group_names.len {
			continue
		}
		name := re.group_names[i]
		if name.len == 0 || grp.len == 0 || grp == '-' {
			continue
		}

		val := log_capture_value(name, grp, ts_format)
		result.set(name, val)
	}

	return VrlValue(result)
}

// Convert a named capture to the appropriate VRL type
fn log_capture_value(name string, value string, ts_format string) VrlValue {
	// Integer fields
	if name in ['status', 'size', 'pid', 'tid', 'cid', 'port', 'body_bytes_size',
		'request_length', 'upstream_response_length', 'upstream_status'] {
		v := value.int()
		return VrlValue(i64(v))
	}
	// Float fields
	if name in ['excess', 'request_time', 'upstream_response_time'] {
		v := value.f64()
		return VrlValue(v)
	}
	// Timestamp field
	if name == 'timestamp' {
		ts := clf_parse_timestamp_flexible(value) or { return VrlValue(value) }
		return VrlValue(ts)
	}
	return VrlValue(value)
}

fn clf_parse_timestamp_flexible(s string) !Timestamp {
	// Try common log format: DD/Mon/YYYY:HH:MM:SS ±HHMM
	if r := clf_parse_timestamp(s) {
		return r
	}
	// Try ISO-like: YYYY/MM/DD HH:MM:SS
	if r := parse_nginx_error_timestamp(s) {
		return r
	}
	// Try Apache error: ddd Mon DD HH:MM:SS.ffffff YYYY
	if r := parse_apache_error_timestamp(s) {
		return r
	}
	return error('unable to parse timestamp: ${s}')
}

fn parse_nginx_error_timestamp(s string) !Timestamp {
	// Format: YYYY/MM/DD HH:MM:SS
	if s.len < 19 {
		return error('too short')
	}
	year := s[0..4].int()
	month := s[5..7].int()
	day := s[8..10].int()
	hour := s[11..13].int()
	minute := s[14..16].int()
	second := s[17..19].int()
	if year < 1900 || month < 1 || month > 12 || day < 1 || day > 31 {
		return error('invalid date')
	}
	t := time.Time{
		year: year
		month: month
		day: day
		hour: hour
		minute: minute
		second: second
	}
	return Timestamp{t: t}
}

fn parse_apache_error_timestamp(s string) !Timestamp {
	// Try: Mon DD HH:MM:SS[.ffffff] YYYY or similar
	// Simplified: just try the common format
	parts := s.split(' ')
	if parts.len < 4 {
		return error('not apache error format')
	}
	return error('unable to parse apache error timestamp')
}

// --- Apache regex patterns ---

fn log_regex_apache_common() string {
	return r'^\s*(?P<host>\S+)\s+(?P<identity>\S+)\s+(?P<user>\S+)\s+\[(?P<timestamp>[^\]]+)\]\s+"(?P<message>(?P<method>\w+)\s+(?P<path>\S+)\s*(?P<protocol>\S*))"\s+(?P<status>\d+)\s+(?P<size>\d+|-)\s*$'
}

fn log_regex_apache_combined() string {
	return r'^\s*(?P<host>\S+)\s+(?P<identity>\S+)\s+(?P<user>\S+)\s+\[(?P<timestamp>[^\]]+)\]\s+"(?P<message>(?P<method>\w+)\s+(?P<path>\S+)\s*(?P<protocol>\S*))"\s+(?P<status>\d+)\s+(?P<size>\d+|-)\s+"(?P<referrer>[^"]*)"\s+"(?P<agent>[^"]*)"\s*$'
}

fn log_regex_apache_error() string {
	return r'^\s*\[(?P<timestamp>[^\]]+)\]\s+\[(?:(?P<module>[^:]+):)?(?P<severity>[^\]]+)\]\s+\[pid\s+(?P<pid>\d+)(?::tid\s+(?P<thread>\d+))?\]\s+(?:\[client\s+(?P<client>[^:]+):(?P<port>\d+)\]\s+)?(?P<message>.*?)\s*$'
}

// --- Nginx regex patterns ---

fn log_regex_nginx_combined() string {
	return r'^\s*(?P<client>\S+)\s+\-\s+(?P<user>\S+)\s+\[(?P<timestamp>[^\]]+)\]\s+"(?P<request>[^"]*)"\s+(?P<status>\d+)\s+(?P<size>\d+)\s+"(?P<referer>[^"]*)"\s+"(?P<agent>[^"]*)"(?:\s+"(?P<compression>[^"]*)")?\s*$'
}

fn log_regex_nginx_error() string {
	return r'^\s*(?P<timestamp>[^ ]+\s+[^ ]+)\s+\[(?P<severity>\w+)\]\s+(?P<pid>\d+)#(?P<tid>\d+):\s+(?:\*(?P<cid>\d+)\s+)?(?P<message>.+?)(?:,\s+excess:\s+(?P<excess>[^\s,]+),?\s+by\s+zone\s+"(?P<zone>[^"]+)")?(?:,\s+client:\s+(?P<client>[^,]+))?(?:,\s+server:\s+(?P<server>[^,]*))?(?:,\s+request:\s+"(?P<request>[^"]*)")?(?:,\s+upstream:\s+"(?P<upstream>[^"]*)")?(?:,\s+host:\s+"(?P<host>[^"]*)")?(?:,\s+refer?rer:\s+"(?P<referer>[^"]*)")?\s*$'
}

fn log_regex_nginx_ingress_upstreaminfo() string {
	return r'^\s*(?P<remote_addr>\S+)\s+\-\s+(?P<remote_user>\S+)\s+\[(?P<timestamp>[^\]]+)\]\s+"(?P<request>[^"]*)"\s+(?P<status>\d+)\s+(?P<body_bytes_size>\d+)\s+"(?P<http_referer>[^"]*)"\s+"(?P<http_user_agent>[^"]+)"\s+(?P<request_length>\d+)\s+(?P<request_time>\d+\.\d+)\s+\[(?P<proxy_upstream_name>[^\]]+)\]\s+\[(?P<proxy_alternative_upstream_name>[^\]]*)\]\s+(?P<upstream_addr>\S+)\s+(?P<upstream_response_length>\d+|-)\s+(?P<upstream_response_time>\d+\.\d+|-)\s+(?P<upstream_status>\d+|-)\s+(?P<req_id>\S+)\s*$'
}

fn log_regex_nginx_main() string {
	return r'^\s*(?P<remote_addr>\S+)\s+\-\s+(?P<remote_user>\S+)\s+\[(?P<timestamp>[^\]]+)\]\s+"(?P<request>[^"]*)"\s+(?P<status>\d+)\s+(?P<body_bytes_size>\d+)\s+"(?P<http_referer>[^"]*)"\s+"(?P<http_user_agent>[^"]+)"\s+"(?P<http_x_forwarded_for>[^"]+)"\s*$'
}

// ============================================================================
// parse_aws_alb_log(value)
// Parses AWS Application Load Balancer access log entries.
// ============================================================================

fn fn_parse_aws_alb_log(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_aws_alb_log requires 1 argument')
	}
	s := match args[0] {
		string { args[0] as string }
		else { return error('parse_aws_alb_log: value must be a string') }
	}

	// ALB log fields are space-separated, with some fields quoted
	fields := alb_split_fields(s)

	if fields.len < 25 {
		return error('parse_aws_alb_log: expected at least 25 fields, got ${fields.len}')
	}

	mut result := new_object_map()
	result.set('type', alb_field_str(fields[0]))
	result.set('timestamp', alb_field_str(fields[1]))
	result.set('elb', alb_field_str(fields[2]))

	// client:port
	client_parts := fields[3].split(':')
	if client_parts.len >= 2 {
		result.set('client_host', alb_field_str(client_parts[0]))
		result.set('client_port', alb_field_int(client_parts[1]))
	}

	// target:port
	target_parts := fields[4].split(':')
	if target_parts.len >= 2 {
		result.set('target_host', alb_field_str(target_parts[0]))
		result.set('target_port', alb_field_int(target_parts[1]))
	} else {
		result.set('target_host', alb_field_str(fields[4]))
	}

	result.set('request_processing_time', alb_field_float(fields[5]))
	result.set('target_processing_time', alb_field_float(fields[6]))
	result.set('response_processing_time', alb_field_float(fields[7]))
	result.set('elb_status_code', alb_field_int(fields[8]))
	result.set('target_status_code', alb_field_int(fields[9]))
	result.set('received_bytes', alb_field_int(fields[10]))
	result.set('sent_bytes', alb_field_int(fields[11]))

	// request field (quoted, contains "METHOD URL PROTOCOL")
	request := fields[12]
	req_parts := request.split(' ')
	if req_parts.len >= 1 {
		result.set('request_method', alb_field_str(req_parts[0]))
	}
	if req_parts.len >= 2 {
		result.set('request_url', alb_field_str(req_parts[1]))
	}
	if req_parts.len >= 3 {
		result.set('request_protocol', alb_field_str(req_parts[2]))
	}

	result.set('user_agent', alb_field_str(fields[13]))
	result.set('ssl_cipher', alb_field_str(fields[14]))
	result.set('ssl_protocol', alb_field_str(fields[15]))
	result.set('target_group_arn', alb_field_str(fields[16]))
	result.set('trace_id', alb_field_str(fields[17]))
	result.set('domain_name', alb_field_str(fields[18]))
	result.set('chosen_cert_arn', alb_field_str(fields[19]))
	result.set('matched_rule_priority', alb_field_str(fields[20]))
	result.set('request_creation_time', alb_field_str(fields[21]))
	result.set('actions_executed', alb_field_str(fields[22]))
	result.set('redirect_url', alb_field_str(fields[23]))
	result.set('error_reason', alb_field_str(fields[24]))

	if fields.len > 25 {
		result.set('target_port_list', alb_field_str(fields[25]))
	}
	if fields.len > 26 {
		result.set('target_status_code_list', alb_field_str(fields[26]))
	}
	if fields.len > 27 {
		result.set('classification', alb_field_str(fields[27]))
	}
	if fields.len > 28 {
		result.set('classification_reason', alb_field_str(fields[28]))
	}
	if fields.len > 29 {
		result.set('conn_trace_id', alb_field_str(fields[29]))
	}

	return VrlValue(result)
}

fn alb_split_fields(s string) []string {
	mut fields := []string{}
	mut pos := 0
	bytes := s.bytes()

	for pos < bytes.len {
		// Skip spaces
		for pos < bytes.len && bytes[pos] == ` ` {
			pos++
		}
		if pos >= bytes.len {
			break
		}
		if bytes[pos] == `"` {
			// Quoted field
			pos++ // skip opening quote
			mut start := pos
			for pos < bytes.len && bytes[pos] != `"` {
				pos++
			}
			fields << bytes[start..pos].bytestr()
			if pos < bytes.len {
				pos++ // skip closing quote
			}
		} else {
			// Unquoted field
			mut start := pos
			for pos < bytes.len && bytes[pos] != ` ` {
				pos++
			}
			fields << bytes[start..pos].bytestr()
		}
	}
	return fields
}

fn alb_field_str(s string) VrlValue {
	if s == '-' {
		return VrlValue(VrlNull{})
	}
	return VrlValue(s)
}

fn alb_field_int(s string) VrlValue {
	if s == '-' {
		return VrlValue(VrlNull{})
	}
	return VrlValue(i64(s.int()))
}

fn alb_field_float(s string) VrlValue {
	if s == '-' || s == '-1' {
		return VrlValue(VrlNull{})
	}
	return VrlValue(s.f64())
}

// ============================================================================
// parse_aws_vpc_flow_log(value, [format])
// Parses AWS VPC Flow Log records.
// ============================================================================

fn fn_parse_aws_vpc_flow_log(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_aws_vpc_flow_log requires at least 1 argument')
	}
	s := match args[0] {
		string { args[0] as string }
		else { return error('parse_aws_vpc_flow_log: value must be a string') }
	}
	format := if args.len > 1 {
		match args[1] {
			string { args[1] as string }
			else { 'version account_id interface_id srcaddr dstaddr srcport dstport protocol packets bytes start end action log_status' }
		}
	} else {
		'version account_id interface_id srcaddr dstaddr srcport dstport protocol packets bytes start end action log_status'
	}

	field_names := format.split(' ')
	values := s.split(' ')

	// Integer fields in VPC flow logs
	int_fields := ['version', 'srcport', 'dstport', 'protocol', 'packets', 'bytes', 'start',
		'end', 'tcp_flags', 'type', 'pkt_srcaddr', 'pkt_dstaddr']

	mut result := new_object_map()
	for i, name in field_names {
		if i >= values.len {
			break
		}
		val := values[i]
		if val == '-' {
			result.set(name, VrlValue(VrlNull{}))
		} else if name in int_fields {
			result.set(name, VrlValue(i64(val.i64())))
		} else {
			result.set(name, VrlValue(val))
		}
	}

	return VrlValue(result)
}

// ============================================================================
// parse_cef(value, [translate_custom_fields])
// Parses ArcSight Common Event Format (CEF) strings.
// ============================================================================

fn fn_parse_cef(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_cef requires 1 argument')
	}
	s := match args[0] {
		string { args[0] as string }
		else { return error('parse_cef: value must be a string') }
	}
	translate := if args.len > 1 {
		match args[1] {
			bool { args[1] as bool }
			else { false }
		}
	} else {
		false
	}

	// Find "CEF:" prefix (may have syslog header before it)
	cef_idx := s.index('CEF:') or { return error('parse_cef: input does not contain CEF header') }
	cef_str := s[cef_idx..]

	// Parse CEF:version|...
	if !cef_str.starts_with('CEF:') {
		return error('parse_cef: invalid CEF header')
	}
	remaining := cef_str[4..]

	// Extract 7 pipe-delimited header fields
	header_fields, ext_start := cef_parse_header(remaining)!

	if header_fields.len < 7 {
		return error('parse_cef: expected 7 header fields, got ${header_fields.len}')
	}

	mut result := new_object_map()
	result.set('cefVersion', VrlValue(header_fields[0]))
	result.set('deviceVendor', VrlValue(header_fields[1]))
	result.set('deviceProduct', VrlValue(header_fields[2]))
	result.set('deviceVersion', VrlValue(header_fields[3]))
	result.set('deviceEventClassId', VrlValue(header_fields[4]))
	result.set('name', VrlValue(header_fields[5]))
	result.set('severity', VrlValue(header_fields[6]))

	// Parse extension key=value pairs
	if ext_start < remaining.len {
		ext_str := remaining[ext_start..].trim_space()
		if ext_str.len > 0 {
			extensions := cef_parse_extensions(ext_str)
			if translate {
				translated := cef_translate_custom_fields(extensions)
				for k, v in translated {
					result.set(k, VrlValue(v))
				}
			} else {
				for k, v in extensions {
					result.set(k, VrlValue(v))
				}
			}
		}
	}

	return VrlValue(result)
}

fn cef_parse_header(s string) !([]string, int) {
	mut fields := []string{}
	mut pos := 0
	bytes := s.bytes()

	for fields.len < 7 {
		mut field := []u8{}
		for pos < bytes.len {
			if bytes[pos] == `\\` && pos + 1 < bytes.len {
				// Escape sequence
				next := bytes[pos + 1]
				if next == `|` {
					field << `|`
					pos += 2
					continue
				} else if next == `\\` {
					field << `\\`
					pos += 2
					continue
				}
			}
			if bytes[pos] == `|` {
				pos++ // skip pipe
				break
			}
			field << bytes[pos]
			pos++
		}
		fields << field.bytestr()
	}

	// Skip leading space in extensions
	for pos < bytes.len && bytes[pos] == ` ` {
		pos++
	}

	return fields, pos
}

fn cef_parse_extensions(s string) map[string]string {
	mut result := map[string]string{}
	// CEF extensions are key=value pairs. Keys are alphanumeric.
	// Values continue until the next key= pattern or end of string.
	mut pos := 0
	bytes := s.bytes()

	for pos < bytes.len {
		// Skip whitespace
		for pos < bytes.len && bytes[pos] == ` ` {
			pos++
		}
		if pos >= bytes.len {
			break
		}

		// Read key (alphanumeric characters)
		mut key_start := pos
		for pos < bytes.len && bytes[pos] != `=` && bytes[pos] != ` ` {
			pos++
		}
		if pos >= bytes.len || bytes[pos] != `=` {
			break
		}
		key := bytes[key_start..pos].bytestr()
		pos++ // skip =

		// Read value: continues until we find a space followed by an alphanumeric key=
		mut val := []u8{}
		for pos < bytes.len {
			// Check if this is the start of a new key=value pair
			if bytes[pos] == ` ` {
				// Look ahead for key=
				mut look := pos + 1
				for look < bytes.len && bytes[look] != `=` && bytes[look] != ` ` {
					if !(is_alpha_num(bytes[look]) || bytes[look] == `_`) {
						break
					}
					look++
				}
				if look < bytes.len && bytes[look] == `=` && look > pos + 1 {
					// This is a new key=value pair
					break
				}
			}
			// Handle escape sequences
			if bytes[pos] == `\\` && pos + 1 < bytes.len {
				next := bytes[pos + 1]
				match next {
					`=` { val << `=`; pos += 2; continue }
					`\\` { val << `\\`; pos += 2; continue }
					`n` { val << `\n`; pos += 2; continue }
					`r` { val << `\r`; pos += 2; continue }
					else {}
				}
			}
			val << bytes[pos]
			pos++
		}
		result[key] = val.bytestr()
	}
	return result
}

fn is_alpha_num(b u8) bool {
	return (b >= `a` && b <= `z`) || (b >= `A` && b <= `Z`) || (b >= `0` && b <= `9`)
}

fn cef_translate_custom_fields(extensions map[string]string) map[string]string {
	// Custom field label prefixes
	label_prefixes := ['c6a', 'cfp', 'cn', 'cs', 'deviceCustomDate', 'flexDate', 'flexString',
		'flexNumber']
	label_suffix := 'Label'

	mut result := map[string]string{}
	mut translated_keys := map[string]bool{}

	for key, value in extensions {
		if key.ends_with(label_suffix) {
			// This is a label field
			base_key := key[..key.len - label_suffix.len]
			mut is_custom := false
			for prefix in label_prefixes {
				if base_key.starts_with(prefix) {
					is_custom = true
					break
				}
			}
			if is_custom {
				// Look for the corresponding value field
				if data_value := extensions[base_key] {
					result[value] = data_value
					translated_keys[key] = true
					translated_keys[base_key] = true
				}
			}
		}
	}

	// Add non-translated fields
	for key, value in extensions {
		if key !in translated_keys {
			result[key] = value
		}
	}

	return result
}

// ============================================================================
// parse_glog(value)
// Parses Google glog format log lines.
// Format: Lmmdd hh:mm:ss.ffffff threadid file:line] msg
// ============================================================================

fn fn_parse_glog(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_glog requires 1 argument')
	}
	s := match args[0] {
		string { args[0] as string }
		else { return error('parse_glog: value must be a string') }
	}

	trimmed := s.trim_space()
	if trimmed.len < 2 {
		return error('unable to parse glog: input too short')
	}

	// Parse level character
	level_char := trimmed[0]
	level := match level_char {
		`I` { 'info' }
		`W` { 'warning' }
		`E` { 'error' }
		`F` { 'fatal' }
		else { return error('unable to parse glog: unknown level character: ${[level_char].bytestr()}') }
	}

	// Parse: MMDD HH:MM:SS.ffffff
	if trimmed.len < 18 {
		return error('unable to parse glog: input too short for timestamp')
	}
	month_str := trimmed[1..3]
	day_str := trimmed[3..5]
	// Skip space
	if trimmed[5] != ` ` {
		return error('unable to parse glog: expected space after date')
	}
	// Find space after time
	mut time_end := 6
	for time_end < trimmed.len && trimmed[time_end] != ` ` {
		time_end++
	}
	time_str := trimmed[6..time_end]
	mut i := time_end

	// Skip spaces
	for i < trimmed.len && trimmed[i] == ` ` {
		i++
	}

	// Parse thread ID
	mut id_end := i
	for id_end < trimmed.len && id_end < trimmed.len && trimmed[id_end] >= `0`
		&& trimmed[id_end] <= `9` {
		id_end++
	}
	thread_id := trimmed[i..id_end]
	i = id_end

	// Skip space
	for i < trimmed.len && trimmed[i] == ` ` {
		i++
	}

	// Parse file:line]
	mut bracket_pos := i
	for bracket_pos < trimmed.len && trimmed[bracket_pos] != `]` {
		bracket_pos++
	}
	if bracket_pos >= trimmed.len {
		return error('unable to parse glog: missing ] delimiter')
	}
	file_line := trimmed[i..bracket_pos]

	// Split file:line
	mut file := file_line
	mut line := ''
	if colon_idx := file_line.last_index(':') {
		file = file_line[..colon_idx]
		line = file_line[colon_idx + 1..]
	}

	i = bracket_pos + 1
	// Skip space after ]
	if i < trimmed.len && trimmed[i] == ` ` {
		i++
	}
	message := if i < trimmed.len { trimmed[i..].trim_right(' \t\n\r') } else { '' }

	// Build timestamp (use current year like upstream)
	month_val := month_str.int()
	day_val := day_str.int()
	now := time.now()
	year := now.year

	// Parse time: HH:MM:SS.ffffff
	time_parts := time_str.split('.')
	hms := time_parts[0].split(':')
	hour := if hms.len > 0 { hms[0].int() } else { 0 }
	minute := if hms.len > 1 { hms[1].int() } else { 0 }
	second := if hms.len > 2 { hms[2].int() } else { 0 }
	microsecond := if time_parts.len > 1 { time_parts[1].int() } else { 0 }

	t := time.Time{
		year: year
		month: month_val
		day: day_val
		hour: hour
		minute: minute
		second: second
	}
	ts := Timestamp{t: time.unix_microsecond(int(t.unix()), microsecond)}

	mut result := new_object_map()
	result.set('level', VrlValue(level))
	result.set('timestamp', VrlValue(ts))
	result.set('id', VrlValue(i64(thread_id.int())))
	result.set('file', VrlValue(file))
	result.set('line', VrlValue(i64(line.int())))
	result.set('message', VrlValue(message))

	return VrlValue(result)
}

// ============================================================================
// parse_groks(value, patterns)
// Tries multiple grok patterns in order and returns the first match.
// ============================================================================

fn fn_parse_groks(args []VrlValue) !VrlValue {
	if args.len < 2 {
		return error('parse_groks requires 2 arguments')
	}
	input := match args[0] {
		string { args[0] as string }
		else { return error('parse_groks: value must be a string') }
	}
	patterns := match args[1] {
		[]VrlValue { args[1] as []VrlValue }
		else { return error('parse_groks: patterns must be an array') }
	}

	builtin := grok_builtin_patterns()

	for pat_val in patterns {
		pattern := match pat_val {
			string { pat_val as string }
			else { continue }
		}

		expanded := grok_expand_pattern(pattern, builtin, 0) or { continue }
		full_pattern := '^${expanded}\$'

		re := pcre2.compile(full_pattern) or { continue }
		m := re.find(input) or { continue }

		mut result := new_object_map()
		for i, grp in m.groups {
			if i < re.group_names.len && re.group_names[i].len > 0 {
				result.set(re.group_names[i], VrlValue(grp))
			}
		}
		return VrlValue(result)
	}

	return error('unable to parse input with grok patterns')
}

// ============================================================================
// parse_influxdb(value)
// Parses InfluxDB line protocol format.
// Format: measurement[,tag=val...] field=val[,field=val...] [timestamp]
// Returns an array of metric objects.
// ============================================================================

fn fn_parse_influxdb(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_influxdb requires 1 argument')
	}
	s := match args[0] {
		string { args[0] as string }
		else { return error('parse_influxdb: value must be a string') }
	}

	mut metrics := []VrlValue{}

	// Split measurement+tags from fields and timestamp
	// Format: measurement[,tag_key=tag_value]* field_key=field_value[,field_key=field_value]* [timestamp]
	trimmed := s.trim_space()
	if trimmed.len == 0 {
		return VrlValue(metrics)
	}

	// Find first unescaped space (separates measurement+tags from fields)
	mut meas_end := 0
	for meas_end < trimmed.len {
		if trimmed[meas_end] == `\\` && meas_end + 1 < trimmed.len {
			meas_end += 2
			continue
		}
		if trimmed[meas_end] == ` ` {
			break
		}
		meas_end++
	}
	meas_tags := trimmed[..meas_end]

	// Parse measurement name and tags
	mut comma_pos := -1
	for ci in 0 .. meas_tags.len {
		if meas_tags[ci] == `\\` && ci + 1 < meas_tags.len {
			continue
		}
		if meas_tags[ci] == `,` {
			comma_pos = ci
			break
		}
	}

	measurement := if comma_pos >= 0 { meas_tags[..comma_pos] } else { meas_tags }

	// Parse tags
	mut tags := new_object_map()
	if comma_pos >= 0 {
		tag_str := meas_tags[comma_pos + 1..]
		tag_pairs := tag_str.split(',')
		for pair in tag_pairs {
			eq_pos := pair.index('=') or { continue }
			tk := pair[..eq_pos]
			tv := pair[eq_pos + 1..]
			tags.set(tk, VrlValue(tv))
		}
	}

	// Skip space
	mut fields_start := meas_end
	for fields_start < trimmed.len && trimmed[fields_start] == ` ` {
		fields_start++
	}

	// Find fields end (next space is timestamp)
	mut fields_end := fields_start
	mut in_quotes := false
	for fields_end < trimmed.len {
		if trimmed[fields_end] == `"` {
			in_quotes = !in_quotes
		}
		if !in_quotes && trimmed[fields_end] == ` ` {
			break
		}
		fields_end++
	}

	fields_str := trimmed[fields_start..fields_end]

	// Parse optional timestamp
	mut timestamp := VrlValue(VrlNull{})
	if fields_end < trimmed.len {
		ts_str := trimmed[fields_end..].trim_space()
		if ts_str.len > 0 {
			ts_ns := ts_str.i64()
			secs := ts_ns / 1_000_000_000
			micros := (ts_ns % 1_000_000_000) / 1000
			ts := Timestamp{t: time.unix_microsecond(int(secs), int(micros))}
			timestamp = VrlValue(ts)
		}
	}

	// Parse field pairs and create one metric per field
	field_pairs := influxdb_split_fields(fields_str)
	for pair in field_pairs {
		eq_pos := pair.index('=') or { continue }
		field_key := pair[..eq_pos]
		field_val_str := pair[eq_pos + 1..]

		// Parse field value
		field_val := influxdb_parse_field_value(field_val_str)

		// Check for NaN
		match field_val {
			f64 {
				if math.is_nan(field_val) {
					continue
				}
			}
			else {}
		}
		fv := field_val

		mut metric := new_object_map()
		metric.set('name', VrlValue('${measurement}_${field_key}'))

		if tags.len() > 0 {
			metric.set('tags', VrlValue(tags))
		}

		match timestamp {
			VrlNull {}
			else { metric.set('timestamp', timestamp) }
		}

		metric.set('kind', VrlValue('absolute'))

		mut gauge := new_object_map()
		gauge.set('value', fv)
		metric.set('gauge', VrlValue(gauge))

		metrics << VrlValue(metric)
	}

	return VrlValue(metrics)
}

fn influxdb_split_fields(s string) []string {
	mut fields := []string{}
	mut start := 0
	mut in_quotes := false

	for i in 0 .. s.len {
		if s[i] == `"` {
			in_quotes = !in_quotes
		}
		if !in_quotes && s[i] == `,` {
			fields << s[start..i]
			start = i + 1
		}
	}
	if start < s.len {
		fields << s[start..]
	}
	return fields
}

fn influxdb_parse_field_value(s string) VrlValue {
	if s.len == 0 {
		return VrlValue(VrlNull{})
	}

	// String value (quoted)
	if s.starts_with('"') && s.ends_with('"') && s.len >= 2 {
		return VrlValue(s[1..s.len - 1])
	}

	// Boolean
	if s == 'true' || s == 't' || s == 'T' || s == 'True' || s == 'TRUE' {
		return VrlValue(f64(1.0))
	}
	if s == 'false' || s == 'f' || s == 'F' || s == 'False' || s == 'FALSE' {
		return VrlValue(f64(0.0))
	}

	// Integer (ends with 'i')
	if s.ends_with('i') {
		v := s[..s.len - 1].i64()
		return VrlValue(f64(v))
	}

	// Unsigned integer (ends with 'u')
	if s.ends_with('u') {
		v := s[..s.len - 1].u64()
		return VrlValue(f64(v))
	}

	// Float
	v := s.f64()
	return VrlValue(v)
}

// ============================================================================
// parse_ruby_hash(value)
// Parses a Ruby hash literal into a VRL object.
// Supports: { key => value }, { key: value }, nested hashes, arrays, nil, booleans
// ============================================================================

fn fn_parse_ruby_hash(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_ruby_hash requires 1 argument')
	}
	s := match args[0] {
		string { args[0] as string }
		else { return error('parse_ruby_hash: value must be a string') }
	}

	trimmed := s.trim_space()
	if !trimmed.starts_with('{') {
		return error('parse_ruby_hash: input must start with {')
	}

	result, _ := ruby_parse_value(trimmed, 0)!
	return result
}

fn ruby_parse_value(s string, pos int) !(VrlValue, int) {
	mut p := ruby_skip_ws(s, pos)
	if p >= s.len {
		return error('unexpected end of input')
	}

	ch := s[p]
	match ch {
		`{` { return ruby_parse_hash(s, p) }
		`[` { return ruby_parse_array(s, p) }
		`"` { return ruby_parse_string(s, p, `"`) }
		`'` { return ruby_parse_string(s, p, `'`) }
		`:` {
			// Symbol :key or :"key" or :'key'
			p++
			if p < s.len && (s[p] == `"` || s[p] == `'`) {
				str_val, np := ruby_parse_string(s, p, s[p])!
				return str_val, np
			}
			// Symbol word
			mut end := p
			for end < s.len && (is_alpha_num(s[end]) || s[end] == `_`) {
				end++
			}
			return VrlValue(s[p..end]), end
		}
		else {
			// nil, true, false, number, or symbol key
			if s[p..].starts_with('nil') && (p + 3 >= s.len || !is_alpha_num(s[p + 3])) {
				return VrlValue(VrlNull{}), p + 3
			}
			if s[p..].starts_with('true') && (p + 4 >= s.len || !is_alpha_num(s[p + 4])) {
				return VrlValue(true), p + 4
			}
			if s[p..].starts_with('false') && (p + 5 >= s.len || !is_alpha_num(s[p + 5])) {
				return VrlValue(false), p + 5
			}
			// Number
			if (ch >= `0` && ch <= `9`) || ch == `-` || ch == `+` {
				return ruby_parse_number(s, p)
			}
			// Word (symbol key without colon)
			mut end := p
			for end < s.len && (is_alpha_num(s[end]) || s[end] == `_`) {
				end++
			}
			if end > p {
				return VrlValue(s[p..end]), end
			}
			return error('unexpected character at position ${p}: ${[ch].bytestr()}')
		}
	}
}

fn ruby_parse_hash(s string, pos int) !(VrlValue, int) {
	mut p := pos + 1 // skip {
	mut result := new_object_map()

	p = ruby_skip_ws(s, p)
	if p < s.len && s[p] == `}` {
		return VrlValue(result), p + 1
	}

	for p < s.len {
		p = ruby_skip_ws(s, p)
		if p >= s.len {
			break
		}
		if s[p] == `}` {
			p++
			break
		}

		// Parse key
		key_val, kp := ruby_parse_value(s, p)!
		key := match key_val {
			string { key_val as string }
			f64 { '${key_val}' }
			i64 { '${key_val}' }
			else { return error('hash key must be a string or symbol') }
		}
		p = ruby_skip_ws(s, kp)

		// Expect => or :
		if p + 1 < s.len && s[p] == `=` && s[p + 1] == `>` {
			p += 2
		} else if s[p] == `:` {
			p++
		} else {
			return error('expected => or : after hash key at position ${p}')
		}

		// Parse value
		val, vp := ruby_parse_value(s, p)!
		p = vp
		result.set(key, val)

		// Skip comma
		p = ruby_skip_ws(s, p)
		if p < s.len && s[p] == `,` {
			p++
		}
	}

	return VrlValue(result), p
}

fn ruby_parse_array(s string, pos int) !(VrlValue, int) {
	mut p := pos + 1 // skip [
	mut result := []VrlValue{}

	p = ruby_skip_ws(s, p)
	if p < s.len && s[p] == `]` {
		return VrlValue(result), p + 1
	}

	for p < s.len {
		p = ruby_skip_ws(s, p)
		if p >= s.len {
			break
		}
		if s[p] == `]` {
			p++
			break
		}

		val, vp := ruby_parse_value(s, p)!
		result << val
		p = vp

		p = ruby_skip_ws(s, p)
		if p < s.len && s[p] == `,` {
			p++
		}
	}

	return VrlValue(result), p
}

fn ruby_parse_string(s string, pos int, delim u8) !(VrlValue, int) {
	mut p := pos + 1 // skip opening delimiter
	mut result := []u8{}

	for p < s.len {
		if s[p] == `\\` && p + 1 < s.len {
			next := s[p + 1]
			if next == delim || next == `\\` {
				result << next
				p += 2
				continue
			}
			// Keep other escape sequences as-is
			result << s[p]
			result << next
			p += 2
			continue
		}
		if s[p] == delim {
			p++ // skip closing delimiter
			return VrlValue(result.bytestr()), p
		}
		result << s[p]
		p++
	}
	return error('unterminated string')
}

fn ruby_parse_number(s string, pos int) !(VrlValue, int) {
	mut p := pos
	if p < s.len && (s[p] == `-` || s[p] == `+`) {
		p++
	}
	mut has_dot := false
	mut has_e := false
	for p < s.len {
		ch := s[p]
		if ch >= `0` && ch <= `9` {
			p++
		} else if ch == `.` && !has_dot {
			has_dot = true
			p++
		} else if (ch == `e` || ch == `E`) && !has_e {
			has_e = true
			p++
			if p < s.len && (s[p] == `+` || s[p] == `-`) {
				p++
			}
		} else {
			break
		}
	}

	num_str := s[pos..p]
	// Ruby hash parser returns all numbers as floats (matching upstream)
	v := num_str.f64()
	return VrlValue(v), p
}

fn ruby_skip_ws(s string, pos int) int {
	mut p := pos
	for p < s.len && (s[p] == ` ` || s[p] == `\t` || s[p] == `\n` || s[p] == `\r`) {
		p++
	}
	return p
}

// ============================================================================
// parse_xml(value, [options...])
// Parses an XML document into a VRL object.
// Options: trim, include_attr, attr_prefix, text_key, always_use_text_key,
//          parse_bool, parse_null, parse_number
//
// Aims for 100% feature parity with upstream VRL parse_xml which uses
// roxmltree for parsing.  roxmltree supports: elements, text, CDATA,
// comments (silently discarded), processing instructions (silently
// discarded but counted for child-count), namespaces (preserved as
// prefix in tag names), the five predefined XML entities plus numeric
// character references (&#NNN; / &#xHH;), and DOCTYPE (skipped).
// ============================================================================

fn fn_parse_xml(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_xml requires 1 argument')
	}
	s := match args[0] {
		string { args[0] as string }
		else { return error('parse_xml: value must be a string') }
	}

	// Default options
	mut do_trim := true
	mut include_attr := true
	mut attr_prefix := '@'
	mut text_key := 'text'
	mut always_use_text_key := false
	mut do_parse_bool := true
	mut do_parse_null := true
	mut do_parse_number := true

	// Named args would be handled by eval_fn_call_named
	// For positional overrides:
	if args.len > 1 {
		match args[1] {
			bool { do_trim = args[1] as bool }
			else {}
		}
	}
	if args.len > 2 {
		match args[2] {
			bool { include_attr = args[2] as bool }
			else {}
		}
	}
	if args.len > 3 {
		match args[3] {
			string { attr_prefix = args[3] as string }
			else {}
		}
	}
	if args.len > 4 {
		match args[4] {
			string { text_key = args[4] as string }
			else {}
		}
	}
	if args.len > 5 {
		match args[5] {
			bool { always_use_text_key = args[5] as bool }
			else {}
		}
	}
	if args.len > 6 {
		match args[6] {
			bool { do_parse_bool = args[6] as bool }
			else {}
		}
	}
	if args.len > 7 {
		match args[7] {
			bool { do_parse_null = args[7] as bool }
			else {}
		}
	}
	if args.len > 8 {
		match args[8] {
			bool { do_parse_number = args[8] as bool }
			else {}
		}
	}

	opts := XmlParseOpts{
		trim: do_trim
		include_attr: include_attr
		attr_prefix: attr_prefix
		text_key: text_key
		always_use_text_key: always_use_text_key
		parse_bool: do_parse_bool
		parse_null: do_parse_null
		parse_number: do_parse_number
	}

	result := xml_parse(s, opts)!
	return result
}

struct XmlParseOpts {
	trim                bool = true
	include_attr        bool = true
	attr_prefix         string = '@'
	text_key            string = 'text'
	always_use_text_key bool
	parse_bool          bool = true
	parse_null          bool = true
	parse_number        bool = true
}

struct XmlElement {
	tag        string
	attributes map[string]string
	children   []XmlNode
}

// XmlNonContent represents comments and processing instructions.
// They count toward children (affecting flattening decisions) but
// produce no output — matching upstream roxmltree behaviour where
// node.children().count() includes all node types but recurse()
// filters to element + text only.
struct XmlNonContent {}

type XmlNode = XmlElement | XmlNonContent | string

// xml_trim_whitespace removes whitespace-only runs between XML tags,
// replicating the upstream Rust regex  r">\s+?<"  →  "><".
fn xml_trim_whitespace(s string) string {
	if !s.contains_any_substr(['>\n', '> ', '>\t', '>\r']) {
		return s
	}
	mut result := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		result << s[i]
		if s[i] == `>` {
			// Scan ahead: if only whitespace until next '<', skip it.
			mut j := i + 1
			for j < s.len && (s[j] == ` ` || s[j] == `\n` || s[j] == `\r` || s[j] == `\t`) {
				j++
			}
			if j < s.len && s[j] == `<` && j > i + 1 {
				i = j // skip whitespace; next iteration appends '<'
				continue
			}
		}
		i++
	}
	return result.bytestr()
}

// xml_line_col computes 1-based line and column from a byte offset.
fn xml_line_col(s string, pos int) (int, int) {
	mut line := 1
	mut col := 1
	limit := if pos < s.len { pos } else { s.len }
	for i in 0 .. limit {
		if s[i] == `\n` {
			line++
			col = 1
		} else {
			col++
		}
	}
	return line, col
}

fn xml_parse(input string, opts XmlParseOpts) !VrlValue {
	trimmed := input.trim_space()
	if trimmed.len == 0 {
		return error('unable to parse xml: empty input')
	}

	// Apply trim pre-processing: collapse whitespace between tags.
	// This matches upstream behaviour where the regex  >\s+?<  → ><
	// is applied to the whole string BEFORE parsing.
	mut content := if opts.trim { xml_trim_whitespace(trimmed) } else { trimmed }

	mut pos := 0

	// Skip leading non-element content (XML declaration, comments, DOCTYPE, PIs)
	for pos < content.len {
		// Skip whitespace
		for pos < content.len
			&& (content[pos] == ` ` || content[pos] == `\n` || content[pos] == `\r`
			|| content[pos] == `\t`) {
			pos++
		}
		if pos >= content.len {
			break
		}

		// XML declaration or processing instruction  <?...?>
		if pos + 1 < content.len && content[pos] == `<` && content[pos + 1] == `?` {
			end := content.index_after_('?>', pos + 2)
			if end < 0 {
				return error('unable to parse xml: unterminated processing instruction')
			}
			pos = end + 2
			continue
		}

		// Comment  <!--...-->
		if pos + 3 < content.len && content[pos..pos + 4] == '<!--' {
			end := content.index_after_('-->', pos + 4)
			if end < 0 {
				return error('unable to parse xml: unterminated comment')
			}
			pos = end + 3
			continue
		}

		// DOCTYPE  <!DOCTYPE ...>  (may contain internal subset in [...])
		if pos + 8 < content.len && content[pos..pos + 9].to_upper() == '<!DOCTYPE' {
			pos = xml_skip_doctype(content, pos)!
			continue
		}

		break
	}

	if pos >= content.len || content[pos] != `<` {
		line, col := xml_line_col(content, pos)
		return error('unable to parse xml: unknown token at ${line}:${col}')
	}

	// Parse root element
	element, _ := xml_parse_element(content, pos)!
	return xml_element_to_vrl(element, opts)
}

// xml_skip_doctype advances past a <!DOCTYPE ...> declaration,
// handling an optional internal subset delimited by [...].
fn xml_skip_doctype(s string, start int) !int {
	mut p := start + 9 // skip "<!DOCTYPE"
	mut depth := 0
	for p < s.len {
		if s[p] == `[` {
			depth++
		} else if s[p] == `]` {
			depth--
		} else if s[p] == `>` && depth == 0 {
			return p + 1
		}
		p++
	}
	return error('unable to parse xml: unterminated DOCTYPE')
}

fn xml_parse_element(s string, pos int) !(XmlElement, int) {
	mut p := pos

	// Skip whitespace
	for p < s.len && (s[p] == ` ` || s[p] == `\n` || s[p] == `\r` || s[p] == `\t`) {
		p++
	}

	// Expect <
	if p >= s.len || s[p] != `<` {
		line, col := xml_line_col(s, p)
		return error('unable to parse xml: unknown token at ${line}:${col}')
	}
	p++ // skip <

	// Read tag name  (may include namespace prefix like  ns:tag)
	mut tag_end := p
	for tag_end < s.len && s[tag_end] != ` ` && s[tag_end] != `>` && s[tag_end] != `/`
		&& s[tag_end] != `\n` && s[tag_end] != `\r` && s[tag_end] != `\t` {
		tag_end++
	}
	if tag_end == p {
		line, col := xml_line_col(s, p)
		return error('unable to parse xml: unknown token at ${line}:${col}')
	}
	tag := s[p..tag_end]
	p = tag_end

	// Parse attributes
	mut attrs := map[string]string{}
	for p < s.len && s[p] != `>` && s[p] != `/` {
		// Skip whitespace
		for p < s.len && (s[p] == ` ` || s[p] == `\n` || s[p] == `\r` || s[p] == `\t`) {
			p++
		}
		if p >= s.len || s[p] == `>` || s[p] == `/` {
			break
		}

		// Read attribute name
		mut attr_end := p
		for attr_end < s.len && s[attr_end] != `=` && s[attr_end] != ` ` && s[attr_end] != `>`
			&& s[attr_end] != `\n` && s[attr_end] != `\r` && s[attr_end] != `\t` {
			attr_end++
		}
		attr_name := s[p..attr_end]
		p = attr_end

		// Skip whitespace before =
		for p < s.len && (s[p] == ` ` || s[p] == `\n` || s[p] == `\r` || s[p] == `\t`) {
			p++
		}

		// Skip =
		if p < s.len && s[p] == `=` {
			p++
		}

		// Skip whitespace after =
		for p < s.len && (s[p] == ` ` || s[p] == `\n` || s[p] == `\r` || s[p] == `\t`) {
			p++
		}

		// Read attribute value
		if p < s.len && (s[p] == `"` || s[p] == `'`) {
			delim := s[p]
			p++ // skip opening quote
			mut val_end := p
			for val_end < s.len && s[val_end] != delim {
				val_end++
			}
			attrs[attr_name] = xml_unescape(s[p..val_end])
			p = val_end
			if p < s.len {
				p++ // skip closing quote
			}
		}
	}

	// Self-closing tag?
	if p < s.len && s[p] == `/` {
		p++ // skip /
		if p < s.len && s[p] == `>` {
			p++ // skip >
		}
		return XmlElement{
			tag: tag
			attributes: attrs
			children: []XmlNode{}
		}, p
	}

	// Skip >
	if p < s.len && s[p] == `>` {
		p++
	}

	// Parse children
	mut children := []XmlNode{}
	for p < s.len {
		// Check for closing tag  </tag>
		if p + 1 < s.len && s[p] == `<` && s[p + 1] == `/` {
			mut close_end := p + 2
			for close_end < s.len && s[close_end] != `>` {
				close_end++
			}
			p = close_end + 1
			break
		}

		// Comment  <!--...-->
		if p + 3 < s.len && s[p..p + 4] == '<!--' {
			end := s.index_after_('-->', p + 4)
			if end < 0 {
				return error('unable to parse xml: unterminated comment')
			}
			children << XmlNode(XmlNonContent{})
			p = end + 3
			continue
		}

		// CDATA  <![CDATA[...]]>
		if p + 8 < s.len && s[p..p + 9] == '<![CDATA[' {
			end := s.index_after_(']]>', p + 9)
			if end < 0 {
				return error('unable to parse xml: unterminated CDATA')
			}
			cdata := s[p + 9..end]
			children << XmlNode(cdata)
			p = end + 3
			continue
		}

		// Processing instruction  <?...?>
		if p + 1 < s.len && s[p] == `<` && s[p + 1] == `?` {
			end := s.index_after_('?>', p + 2)
			if end < 0 {
				return error('unable to parse xml: unterminated processing instruction')
			}
			children << XmlNode(XmlNonContent{})
			p = end + 2
			continue
		}

		// DOCTYPE inside element (rare but legal in some contexts)
		if p + 8 < s.len && s[p..p + 9].to_upper() == '<!DOCTYPE' {
			p = xml_skip_doctype(s, p)!
			children << XmlNode(XmlNonContent{})
			continue
		}

		// Child element
		if s[p] == `<` {
			child_elem, np := xml_parse_element(s, p)!
			children << XmlNode(child_elem)
			p = np
			continue
		}

		// Text node — collect everything up to the next '<'
		mut text_end := p
		for text_end < s.len && s[text_end] != `<` {
			text_end++
		}
		text := s[p..text_end]
		// Always include text nodes; whitespace handling is done by
		// the trim pre-processing step and the VRL conversion layer.
		children << XmlNode(text)
		p = text_end
	}

	return XmlElement{
		tag: tag
		attributes: attrs
		children: children
	}, p
}

fn xml_element_to_vrl(elem XmlElement, opts XmlParseOpts) !VrlValue {
	mut outer := new_object_map()
	inner := xml_element_content_to_vrl(elem, opts)!
	outer.set(elem.tag, inner)
	return VrlValue(outer)
}

// xml_element_content_to_vrl converts an XmlElement's content to a VrlValue.
// This mirrors the upstream process_node() logic for NodeType::Element:
//   - If attrs present and include_attr → recurse (object)
//   - If always_use_text_key → recurse (object)
//   - If exactly 1 child that is an element → wrap { child_tag: process(child) }
//   - If exactly 1 child that is text → flatten to scalar
//   - Otherwise (0 or 2+ children) → recurse (object)
fn xml_element_content_to_vrl(elem XmlElement, opts XmlParseOpts) !VrlValue {
	has_attrs := opts.include_attr && elem.attributes.len > 0
	total_children := elem.children.len

	// If attributes present, always recurse to expand attribute keys
	if has_attrs {
		return xml_recurse(elem, opts)
	}

	// If always_use_text_key, always recurse
	if opts.always_use_text_key {
		return xml_recurse(elem, opts)
	}

	// Check total children count (including non-content like comments/PIs)
	if total_children == 1 {
		child := elem.children[0]
		match child {
			XmlElement {
				// Single element child — wrap it
				mut m := new_object_map()
				inner := xml_element_content_to_vrl(child, opts)!
				m.set(child.tag, inner)
				return VrlValue(m)
			}
			string {
				// Single text child — flatten to scalar
				return xml_parse_scalar(xml_unescape(child), opts)
			}
			XmlNonContent {
				// Single non-content child (comment/PI only) — empty object
				return xml_recurse(elem, opts)
			}
		}
	}

	// 0 or 2+ children — recurse
	return xml_recurse(elem, opts)
}

// xml_recurse builds an ObjectMap from an element's attributes and children.
// Mirrors upstream recurse() closure: processes only element + text children,
// uses entry-based logic for duplicate keys (converting to arrays).
fn xml_recurse(elem XmlElement, opts XmlParseOpts) !VrlValue {
	mut obj := new_object_map()

	// Add attributes as string values (upstream does NOT parse attrs as scalars)
	if opts.include_attr {
		for attr_name, attr_val in elem.attributes {
			obj.set('${opts.attr_prefix}${attr_name}', VrlValue(attr_val))
		}
	}

	// Process children in order (only element and text, skip XmlNonContent)
	for child in elem.children {
		match child {
			XmlElement {
				child_vrl := xml_element_content_to_vrl(child, opts)!
				key := child.tag
				existing := obj.get(key)
				if existing != none {
					ex := existing
					match ex {
						[]VrlValue {
							mut arr := ex.clone()
							arr << child_vrl
							obj.set(key, VrlValue(arr))
						}
						else {
							obj.set(key, VrlValue([ex, child_vrl]))
						}
					}
				} else {
					obj.set(key, child_vrl)
				}
			}
			string {
				txt := xml_unescape(child)
				key := opts.text_key
				val := xml_parse_scalar(txt, opts)
				existing := obj.get(key)
				if existing != none {
					ex := existing
					match ex {
						[]VrlValue {
							mut arr := ex.clone()
							arr << val
							obj.set(key, VrlValue(arr))
						}
						else {
							obj.set(key, VrlValue([ex, val]))
						}
					}
				} else {
					obj.set(key, val)
				}
			}
			XmlNonContent {} // silently ignored
		}
	}

	return VrlValue(obj)
}

fn xml_parse_scalar(s string, opts XmlParseOpts) VrlValue {
	if opts.parse_null && (s == 'null' || s.len == 0) {
		return VrlValue(VrlNull{})
	}
	if opts.parse_bool {
		if s == 'true' {
			return VrlValue(true)
		}
		if s == 'false' {
			return VrlValue(false)
		}
	}
	if opts.parse_number {
		// Try integer
		trimmed := s.trim_space()
		if (trimmed.len > 0 && (trimmed[0] >= `0` && trimmed[0] <= `9`))
			|| (trimmed.len > 1 && trimmed[0] == `-`) {
			mut all_digits := true
			start := if trimmed[0] == `-` { 1 } else { 0 }
			for ci in start .. trimmed.len {
				if trimmed[ci] < `0` || trimmed[ci] > `9` {
					all_digits = false
					break
				}
			}
			if all_digits && trimmed.len > 0 {
				return VrlValue(i64(trimmed.i64()))
			}
			// Try float
			if trimmed.contains('.') || trimmed.contains('e') || trimmed.contains('E') {
				v := trimmed.f64()
				if v != 0.0 || trimmed == '0.0' || trimmed == '0' {
					return VrlValue(v)
				}
			}
		}
	}
	return VrlValue(s)
}

// xml_unescape resolves XML entity references and numeric character
// references.  Handles the five predefined entities (&amp; &lt; &gt;
// &quot; &apos;) plus decimal (&#NNN;) and hexadecimal (&#xHH;) forms.
fn xml_unescape(s string) string {
	if !s.contains('&') {
		return s
	}
	mut result := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		if s[i] == `&` {
			// Find the closing semicolon
			mut end := i + 1
			for end < s.len && s[end] != `;` && end - i < 12 {
				end++
			}
			if end < s.len && s[end] == `;` {
				ref := s[i + 1..end]
				if ref == 'amp' {
					result << `&`
					i = end + 1
					continue
				} else if ref == 'lt' {
					result << `<`
					i = end + 1
					continue
				} else if ref == 'gt' {
					result << `>`
					i = end + 1
					continue
				} else if ref == 'quot' {
					result << `"`
					i = end + 1
					continue
				} else if ref == 'apos' {
					result << `'`
					i = end + 1
					continue
				} else if ref.len > 1 && ref[0] == `#` {
					// Numeric character reference
					mut codepoint := u32(0)
					mut valid := true
					if ref.len > 2 && (ref[1] == `x` || ref[1] == `X`) {
						// Hexadecimal  &#xHH;
						hex := ref[2..]
						for hc in hex.bytes() {
							codepoint = codepoint * 16
							if hc >= `0` && hc <= `9` {
								codepoint += u32(hc - `0`)
							} else if hc >= `a` && hc <= `f` {
								codepoint += u32(hc - `a` + 10)
							} else if hc >= `A` && hc <= `F` {
								codepoint += u32(hc - `A` + 10)
							} else {
								valid = false
								break
							}
						}
					} else {
						// Decimal  &#NNN;
						dec := ref[1..]
						for dc in dec.bytes() {
							if dc >= `0` && dc <= `9` {
								codepoint = codepoint * 10 + u32(dc - `0`)
							} else {
								valid = false
								break
							}
						}
					}
					if valid && codepoint > 0 && codepoint <= 0x10FFFF {
						// Encode as UTF-8
						if codepoint < 0x80 {
							result << u8(codepoint)
						} else if codepoint < 0x800 {
							result << u8(0xC0 | (codepoint >> 6))
							result << u8(0x80 | (codepoint & 0x3F))
						} else if codepoint < 0x10000 {
							result << u8(0xE0 | (codepoint >> 12))
							result << u8(0x80 | ((codepoint >> 6) & 0x3F))
							result << u8(0x80 | (codepoint & 0x3F))
						} else {
							result << u8(0xF0 | (codepoint >> 18))
							result << u8(0x80 | ((codepoint >> 12) & 0x3F))
							result << u8(0x80 | ((codepoint >> 6) & 0x3F))
							result << u8(0x80 | (codepoint & 0x3F))
						}
						i = end + 1
						continue
					}
				}
			}
		}
		result << s[i]
		i++
	}
	return result.bytestr()
}

// ============================================================================
// parse_cbor(value)
// Parses a CBOR binary payload into a VRL value.
// CBOR is a binary format similar to JSON (RFC 7049 / 8949).
// ============================================================================

fn fn_parse_cbor(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_cbor requires 1 argument')
	}
	bytes := match args[0] {
		string { (args[0] as string).bytes() }
		else { return error('parse_cbor: value must be a string (bytes)') }
	}

	result, _ := cbor_decode(bytes, 0)!
	return result
}

fn cbor_decode(data []u8, pos int) !(VrlValue, int) {
	if pos >= data.len {
		return error('unexpected end of CBOR data')
	}

	initial_byte := data[pos]
	major_type := (initial_byte >> 5) & 0x7
	additional := initial_byte & 0x1F

	match major_type {
		0 {
			// Unsigned integer
			val, new_pos := cbor_decode_uint(data, pos)!
			return VrlValue(i64(val)), new_pos
		}
		1 {
			// Negative integer
			val, new_pos := cbor_decode_uint(data, pos)!
			return VrlValue(i64(-1 - i64(val))), new_pos
		}
		2 {
			// Byte string
			length, new_pos := cbor_decode_uint(data, pos)!
			end := new_pos + int(length)
			if end > data.len {
				return error('truncated CBOR byte string')
			}
			return VrlValue(data[new_pos..end].bytestr()), end
		}
		3 {
			// Text string
			length, new_pos := cbor_decode_uint(data, pos)!
			end := new_pos + int(length)
			if end > data.len {
				return error('truncated CBOR text string')
			}
			return VrlValue(data[new_pos..end].bytestr()), end
		}
		4 {
			// Array
			count, mut new_pos := cbor_decode_uint(data, pos)!
			mut arr := []VrlValue{}
			for _ in 0 .. int(count) {
				item, ip := cbor_decode(data, new_pos)!
				arr << item
				new_pos = ip
			}
			return VrlValue(arr), new_pos
		}
		5 {
			// Map
			count, mut new_pos := cbor_decode_uint(data, pos)!
			mut obj := new_object_map()
			for _ in 0 .. int(count) {
				key_val, kp := cbor_decode(data, new_pos)!
				val, vp := cbor_decode(data, kp)!
				key := match key_val {
					string { key_val as string }
					i64 { '${key_val}' }
					else { 'unknown' }
				}
				obj.set(key, val)
				new_pos = vp
			}
			return VrlValue(obj), new_pos
		}
		6 {
			// Tagged value - skip the tag and decode the value
			_, new_pos := cbor_decode_uint(data, pos)!
			return cbor_decode(data, new_pos)
		}
		7 {
			// Simple values and floats
			match additional {
				20 {
					// false
					return VrlValue(false), pos + 1
				}
				21 {
					// true
					return VrlValue(true), pos + 1
				}
				22 {
					// null
					return VrlValue(VrlNull{}), pos + 1
				}
				23 {
					// undefined -> null
					return VrlValue(VrlNull{}), pos + 1
				}
				25 {
					// half-precision float (16-bit)
					if pos + 3 > data.len {
						return error('truncated CBOR float16')
					}
					half := (u16(data[pos + 1]) << 8) | u16(data[pos + 2])
					f := cbor_decode_half(half)
					return VrlValue(f), pos + 3
				}
				26 {
					// single-precision float (32-bit)
					if pos + 5 > data.len {
						return error('truncated CBOR float32')
					}
					bits := (u32(data[pos + 1]) << 24) | (u32(data[pos + 2]) << 16) | (u32(data[pos + 3]) << 8) | u32(data[pos + 4])
					f := unsafe { *(&f32(&bits)) }
					return VrlValue(f64(f)), pos + 5
				}
				27 {
					// double-precision float (64-bit)
					if pos + 9 > data.len {
						return error('truncated CBOR float64')
					}
					mut bits := u64(0)
					for i in 0 .. 8 {
						bits = (bits << 8) | u64(data[pos + 1 + i])
					}
					f := unsafe { *(&f64(&bits)) }
					return VrlValue(f), pos + 9
				}
				else {
					return VrlValue(VrlNull{}), pos + 1
				}
			}
		}
		else {
			return error('unsupported CBOR major type: ${major_type}')
		}
	}
}

fn cbor_decode_uint(data []u8, pos int) !(u64, int) {
	if pos >= data.len {
		return error('unexpected end of CBOR data')
	}
	additional := data[pos] & 0x1F
	if additional < 24 {
		return u64(additional), pos + 1
	}
	match additional {
		24 {
			if pos + 2 > data.len {
				return error('truncated CBOR uint8')
			}
			return u64(data[pos + 1]), pos + 2
		}
		25 {
			if pos + 3 > data.len {
				return error('truncated CBOR uint16')
			}
			val := (u64(data[pos + 1]) << 8) | u64(data[pos + 2])
			return val, pos + 3
		}
		26 {
			if pos + 5 > data.len {
				return error('truncated CBOR uint32')
			}
			val := (u64(data[pos + 1]) << 24) | (u64(data[pos + 2]) << 16) | (u64(data[pos + 3]) << 8) | u64(data[pos + 4])
			return val, pos + 5
		}
		27 {
			if pos + 9 > data.len {
				return error('truncated CBOR uint64')
			}
			mut val := u64(0)
			for i in 0 .. 8 {
				val = (val << 8) | u64(data[pos + 1 + i])
			}
			return val, pos + 9
		}
		else {
			return error('unsupported CBOR additional info: ${additional}')
		}
	}
}

fn cbor_decode_half(half u16) f64 {
	exp := int((half >> 10) & 0x1F)
	mant := int(half & 0x3FF)
	sign := if (half & 0x8000) != 0 { f64(-1.0) } else { f64(1.0) }

	if exp == 0 {
		// Subnormal
		return sign * math.ldexp(f64(mant), -24)
	} else if exp == 31 {
		// Inf or NaN
		if mant == 0 {
			return sign * math.inf(1)
		}
		return math.nan()
	}
	return sign * math.ldexp(f64(mant + 1024), exp - 25)
}

// ============================================================================
// parse_user_agent(value, [mode])
// Parses a User-Agent string into browser, OS, and device components.
// mode: "fast" (default), "reliable", or "enriched"
// This is a simplified implementation using regex-based heuristics.
// ============================================================================

fn fn_parse_user_agent(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('parse_user_agent requires 1 argument')
	}
	ua := match args[0] {
		string { args[0] as string }
		else { return error('parse_user_agent: value must be a string') }
	}
	mode := if args.len > 1 {
		match args[1] {
			string { args[1] as string }
			else { 'fast' }
		}
	} else {
		'fast'
	}

	// Extract browser info
	browser_family, browser_version := ua_detect_browser(ua)
	// Extract OS info
	os_family, os_version := ua_detect_os(ua)
	// Detect device category
	device_category := ua_detect_device(ua)

	mut browser := new_object_map()
	browser.set('family', if browser_family.len > 0 {
		VrlValue(browser_family)
	} else {
		VrlValue(VrlNull{})
	})
	browser.set('version', if browser_version.len > 0 {
		VrlValue(browser_version)
	} else {
		VrlValue(VrlNull{})
	})

	mut os_obj := new_object_map()
	os_obj.set('family', if os_family.len > 0 {
		VrlValue(os_family)
	} else {
		VrlValue(VrlNull{})
	})
	os_obj.set('version', if os_version.len > 0 {
		VrlValue(os_version)
	} else {
		VrlValue(VrlNull{})
	})

	mut device := new_object_map()
	device.set('category', if device_category.len > 0 {
		VrlValue(device_category)
	} else {
		VrlValue(VrlNull{})
	})

	if mode == 'enriched' {
		// Add major/minor/patch fields
		parts := browser_version.split('.')
		browser.set('major', if parts.len > 0 && parts[0].len > 0 {
			VrlValue(parts[0])
		} else {
			VrlValue(VrlNull{})
		})
		browser.set('minor', if parts.len > 1 {
			VrlValue(parts[1])
		} else {
			VrlValue(VrlNull{})
		})
		browser.set('patch', if parts.len > 2 {
			VrlValue(parts[2])
		} else {
			VrlValue(VrlNull{})
		})

		os_parts := os_version.split('.')
		os_obj.set('major', if os_parts.len > 0 && os_parts[0].len > 0 {
			VrlValue(os_parts[0])
		} else {
			VrlValue(VrlNull{})
		})
		os_obj.set('minor', if os_parts.len > 1 {
			VrlValue(os_parts[1])
		} else {
			VrlValue(VrlNull{})
		})
		os_obj.set('patch', if os_parts.len > 2 {
			VrlValue(os_parts[2])
		} else {
			VrlValue(VrlNull{})
		})
		os_obj.set('patch_minor', VrlValue(VrlNull{}))

		device.set('family', VrlValue(VrlNull{}))
		device.set('brand', VrlValue(VrlNull{}))
		device.set('model', VrlValue(VrlNull{}))
	}

	mut result := new_object_map()
	result.set('browser', VrlValue(browser))
	result.set('os', VrlValue(os_obj))
	result.set('device', VrlValue(device))

	return VrlValue(result)
}

fn ua_detect_browser(ua string) (string, string) {
	// Order matters: check more specific before generic
	ua_lower := ua.to_lower()

	// Edge
	if ua_lower.contains('edg/') || ua_lower.contains('edge/') {
		v := ua_extract_version(ua, 'Edg/') or {
			ua_extract_version(ua, 'Edge/') or { '' }
		}
		return 'Edge', v
	}
	// Chrome
	if ua_lower.contains('chrome/') && !ua_lower.contains('chromium/') {
		v := ua_extract_version(ua, 'Chrome/') or { '' }
		return 'Chrome', v
	}
	// Firefox
	if ua_lower.contains('firefox/') {
		v := ua_extract_version(ua, 'Firefox/') or { '' }
		return 'Firefox', v
	}
	// Safari
	if ua_lower.contains('safari/') && !ua_lower.contains('chrome/') {
		v := ua_extract_version(ua, 'Version/') or { '' }
		return 'Safari', v
	}
	// Opera
	if ua_lower.contains('opr/') || ua_lower.contains('opera/') {
		v := ua_extract_version(ua, 'OPR/') or {
			ua_extract_version(ua, 'Opera/') or { '' }
		}
		return 'Opera', v
	}
	// IE
	if ua_lower.contains('msie') || ua_lower.contains('trident/') {
		if idx := ua.index('MSIE ') {
			mut end := idx + 5
			for end < ua.len && ua[end] != `;` && ua[end] != `)` && ua[end] != ` ` {
				end++
			}
			return 'Internet Explorer', ua[idx + 5..end]
		}
		if ua_lower.contains('rv:') {
			v := ua_extract_version(ua, 'rv:') or { '' }
			return 'Internet Explorer', v
		}
		return 'Internet Explorer', ''
	}
	// Bot/crawler
	if ua_lower.contains('bot') || ua_lower.contains('crawler') || ua_lower.contains('spider') {
		return 'Bot', ''
	}
	return '', ''
}

fn ua_extract_version(ua string, prefix string) ?string {
	idx := ua.index(prefix)?
	mut end := idx + prefix.len
	for end < ua.len && ua[end] != ` ` && ua[end] != `;` && ua[end] != `)` {
		end++
	}
	v := ua[idx + prefix.len..end]
	if v.len > 0 {
		return v
	}
	return none
}

fn ua_detect_os(ua string) (string, string) {
	ua_lower := ua.to_lower()

	if ua_lower.contains('windows nt') {
		v := ua_extract_version(ua, 'Windows NT ') or { '' }
		name := match v {
			'10.0' { 'Windows 10' }
			'6.3' { 'Windows 8.1' }
			'6.2' { 'Windows 8' }
			'6.1' { 'Windows 7' }
			'6.0' { 'Windows Vista' }
			'5.1' { 'Windows XP' }
			'5.2' { 'Windows XP' }
			else { 'Windows' }
		}
		return name, 'NT ${v}'
	}
	if ua_lower.contains('mac os x') {
		if idx := ua.index('Mac OS X ') {
			mut end := idx + 9
			for end < ua.len && ua[end] != `)` && ua[end] != `;` {
				end++
			}
			v := ua[idx + 9..end].replace('_', '.')
			return 'Mac OS X', v
		}
		return 'Mac OS X', ''
	}
	if ua_lower.contains('android') {
		v := ua_extract_version(ua, 'Android ') or { '' }
		return 'Android', v
	}
	if ua_lower.contains('iphone os') || ua_lower.contains('cpu os') {
		v := if idx := ua.index('OS ') {
			mut end := idx + 3
			for end < ua.len && ua[end] != ` ` && ua[end] != `)` {
				end++
			}
			ua[idx + 3..end].replace('_', '.')
		} else {
			''
		}
		return 'iOS', v
	}
	if ua_lower.contains('linux') {
		return 'Linux', ''
	}
	return '', ''
}

fn ua_detect_device(ua string) string {
	ua_lower := ua.to_lower()

	if ua_lower.contains('mobile') || ua_lower.contains('iphone')
		|| (ua_lower.contains('android') && !ua_lower.contains('tablet')) {
		return 'smartphone'
	}
	if ua_lower.contains('tablet') || ua_lower.contains('ipad') {
		return 'tablet'
	}
	if ua_lower.contains('bot') || ua_lower.contains('crawler') || ua_lower.contains('spider') {
		return 'spider'
	}
	if ua_lower.contains('windows') || ua_lower.contains('macintosh') || ua_lower.contains('linux')
		|| ua_lower.contains('x11') {
		return 'pc'
	}
	return ''
}
