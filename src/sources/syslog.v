module sources

import event
import net
import time

// SyslogSource receives syslog messages over TCP or UDP and parses them into
// log events. Supports RFC 3164 (BSD) and RFC 5424 syslog formats.
// Mirrors Vector's syslog source.
//
// Config options:
//   mode:    "tcp" or "udp" (default: tcp)
//   address: Listen address (default: 0.0.0.0:514)
pub struct SyslogSource {
	mode    SyslogMode = .tcp
	address string     = '0.0.0.0:514'
}

enum SyslogMode {
	tcp
	udp
}

// new_syslog creates a new SyslogSource from config options.
pub fn new_syslog(opts map[string]string) SyslogSource {
	mode := match opts['mode'] or { 'tcp' } {
		'udp' { SyslogMode.udp }
		else { SyslogMode.tcp }
	}

	address := opts['address'] or { '0.0.0.0:514' }

	return SyslogSource{
		mode: mode
		address: address
	}
}

// run starts listening for syslog messages and emitting log events.
pub fn (s &SyslogSource) run(output chan event.Event) {
	match s.mode {
		.tcp { s.run_tcp(output) }
		.udp { s.run_udp(output) }
	}
}

fn (s &SyslogSource) run_tcp(output chan event.Event) {
	mut listener := net.listen_tcp(.ip, s.address) or {
		eprintln('syslog: failed to bind TCP ${s.address}: ${err}')
		return
	}
	eprintln('syslog: listening TCP on ${s.address}')

	for {
		mut conn := listener.accept() or {
			time.sleep(10 * time.millisecond)
			continue
		}
		spawn handle_syslog_tcp(mut conn, output)
	}
}

fn handle_syslog_tcp(mut conn net.TcpConn, output chan event.Event) {
	defer { conn.close() or {} }
	conn.set_read_timeout(30 * time.second)

	mut sb := new_socket_buffer(102400)

	for {
		mut buf := []u8{len: 8192}
		n := conn.read(mut buf) or { break }
		if n == 0 {
			break
		}
		sb.feed(buf[..n])
		for line in sb.read_lines() {
			if line.len == 0 {
				continue
			}
			mut ev := parse_syslog_message(line)
			output <- event.Event(ev)
		}
	}

	remaining := sb.remaining()
	if remaining.len > 0 {
		mut ev := parse_syslog_message(remaining)
		output <- event.Event(ev)
	}
}

fn (s &SyslogSource) run_udp(output chan event.Event) {
	mut conn := net.listen_udp(s.address) or {
		eprintln('syslog: failed to bind UDP ${s.address}: ${err}')
		return
	}
	eprintln('syslog: listening UDP on ${s.address}')

	for {
		mut buf := []u8{len: 65536}
		n, _ := conn.read(mut buf) or {
			time.sleep(10 * time.millisecond)
			continue
		}
		if n == 0 {
			continue
		}
		data := buf[..n].bytestr().trim_right('\r\n')
		if data.len == 0 {
			continue
		}
		for line in data.split('\n') {
			trimmed := line.trim_right('\r')
			if trimmed.len == 0 {
				continue
			}
			mut ev := parse_syslog_message(trimmed)
			output <- event.Event(ev)
		}
	}
}

// Syslog severity names (RFC 5424 Section 6.2.1)
const syslog_severities = ['emerg', 'alert', 'crit', 'err', 'warning', 'notice', 'info', 'debug']

// Syslog facility names (RFC 5424 Section 6.2.1)
const syslog_facilities = [
	'kern', 'user', 'mail', 'daemon', 'auth', 'syslog', 'lpr', 'news',
	'uucp', 'cron', 'authpriv', 'ftp', 'ntp', 'audit', 'alert2', 'clock',
	'local0', 'local1', 'local2', 'local3', 'local4', 'local5', 'local6', 'local7',
]

// parse_syslog_message parses a syslog line (RFC 3164 or RFC 5424) into a LogEvent.
fn parse_syslog_message(line string) event.LogEvent {
	mut ev := event.new_log(line)
	ev.meta.source_type = 'syslog'

	if line.len == 0 || line[0] != `<` {
		return ev
	}

	// Parse priority: <PRI>
	close := line.index('>') or { return ev }
	pri_str := line[1..close]
	pri := pri_str.int()
	if pri_str.len == 0 || pri < 0 || pri > 191 {
		return ev
	}

	facility := pri / 8
	severity := pri % 8

	if severity < sources.syslog_severities.len {
		ev.set('severity', event.Value(sources.syslog_severities[severity]))
	}
	if facility < sources.syslog_facilities.len {
		ev.set('facility', event.Value(sources.syslog_facilities[facility]))
	}

	rest := line[close + 1..]

	// Try RFC 5424: <PRI>VERSION SP TIMESTAMP SP HOSTNAME SP APP-NAME SP PROCID SP MSGID SP ...
	if rest.len > 0 && rest[0] >= `1` && rest[0] <= `9` {
		parsed := parse_rfc5424(rest)
		if parsed.valid {
			ev.set('message', event.Value(parsed.message))
			if parsed.hostname.len > 0 && parsed.hostname != '-' {
				ev.set('hostname', event.Value(parsed.hostname))
			}
			if parsed.appname.len > 0 && parsed.appname != '-' {
				ev.set('appname', event.Value(parsed.appname))
			}
			if parsed.timestamp.len > 0 && parsed.timestamp != '-' {
				ev.set('timestamp', event.Value(parsed.timestamp))
			}
			if parsed.procid.len > 0 && parsed.procid != '-' {
				ev.set('procid', event.Value(parsed.procid))
			}
			if parsed.msgid.len > 0 && parsed.msgid != '-' {
				ev.set('msgid', event.Value(parsed.msgid))
			}
			ev.set('version', event.Value(parsed.version))
			return ev
		}
	}

	// Fall back to RFC 3164: <PRI>TIMESTAMP HOSTNAME APP-NAME[PID]: MESSAGE
	parsed := parse_rfc3164(rest)
	ev.set('message', event.Value(parsed.message))
	if parsed.hostname.len > 0 {
		ev.set('hostname', event.Value(parsed.hostname))
	}
	if parsed.appname.len > 0 {
		ev.set('appname', event.Value(parsed.appname))
	}
	if parsed.timestamp.len > 0 {
		ev.set('timestamp', event.Value(parsed.timestamp))
	}

	return ev
}

// Rfc5424Parsed holds parsed RFC 5424 fields.
struct Rfc5424Parsed {
	valid     bool
	version   int
	timestamp string
	hostname  string
	appname   string
	procid    string
	msgid     string
	message   string
}

// parse_rfc5424 parses the portion after <PRI> for RFC 5424 format.
// Format: VERSION SP TIMESTAMP SP HOSTNAME SP APP-NAME SP PROCID SP MSGID SP [SD] MSG
fn parse_rfc5424(s string) Rfc5424Parsed {
	parts := s.split_nth(' ', 7)
	if parts.len < 7 {
		return Rfc5424Parsed{}
	}

	version := parts[0].int()
	if version < 1 {
		return Rfc5424Parsed{}
	}

	mut message := parts[6]
	// Skip structured data if present
	if message.len > 0 && message[0] == `[` {
		// Find closing bracket for structured data
		mut depth := 0
		mut end_idx := 0
		for i, c in message {
			if c == `[` {
				depth++
			} else if c == `]` {
				depth--
				if depth == 0 {
					end_idx = i + 1
					break
				}
			}
		}
		if end_idx > 0 && end_idx < message.len {
			message = message[end_idx..].trim_left(' ')
		} else if end_idx > 0 {
			message = ''
		}
	} else if message.starts_with('- ') {
		message = message[2..]
	} else if message == '-' {
		message = ''
	}

	return Rfc5424Parsed{
		valid: true
		version: version
		timestamp: parts[1]
		hostname: parts[2]
		appname: parts[3]
		procid: parts[4]
		msgid: parts[5]
		message: message
	}
}

// Rfc3164Parsed holds parsed RFC 3164 fields.
struct Rfc3164Parsed {
	timestamp string
	hostname  string
	appname   string
	message   string
}

// parse_rfc3164 parses the portion after <PRI> for RFC 3164 format.
// Format: TIMESTAMP HOSTNAME APP-NAME[PID]: MESSAGE
// Timestamp: "Mmm dd HH:MM:SS" (15 chars)
fn parse_rfc3164(s string) Rfc3164Parsed {
	// Try to match RFC 3164 timestamp format: "Jan  1 12:00:00" or "Jan 01 12:00:00"
	if s.len < 16 {
		return Rfc3164Parsed{
			message: s
		}
	}

	// Check for month abbreviation at start
	months := ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
	first3 := s[..3]
	mut is_timestamp := false
	for m in months {
		if first3 == m {
			is_timestamp = true
			break
		}
	}

	if !is_timestamp {
		return Rfc3164Parsed{
			message: s
		}
	}

	// Find the end of timestamp (after "Mmm dd HH:MM:SS")
	// Timestamp is 15 chars: "Jan  1 12:00:00" or "Jan 01 12:00:00"
	timestamp := s[..15]
	rest := s[15..].trim_left(' ')

	// Next token is hostname
	space_idx := rest.index(' ') or {
		return Rfc3164Parsed{
			timestamp: timestamp
			message: rest
		}
	}
	hostname := rest[..space_idx]
	after_host := rest[space_idx + 1..]

	// Next is app-name, possibly with [PID]:
	mut appname := ''
	mut message := after_host

	colon_idx := after_host.index(':') or { -1 }
	if colon_idx >= 0 {
		tag := after_host[..colon_idx]
		// Tag may contain [PID]
		bracket := tag.index('[') or { -1 }
		if bracket >= 0 {
			appname = tag[..bracket]
		} else {
			appname = tag
		}
		message = after_host[colon_idx + 1..].trim_left(' ')
	}

	return Rfc3164Parsed{
		timestamp: timestamp
		hostname: hostname
		appname: appname
		message: message
	}
}
