module sources

import event
import json
import os

// JournaldSource reads log entries from the systemd journal by running
// `journalctl -f -o json` as a subprocess and parsing JSON output.
// Mirrors upstream Vector's journald source.
//
// Config options:
//   current_boot_only: Only read from current boot (default: true)
//   units:             Comma-separated list of systemd units to filter
//   include_matches:   Comma-separated key=value matches for journal fields
pub struct JournaldSource {
	current_boot_only bool   = true
	units             []string
	include_matches   []string
}

// new_journald creates a new JournaldSource from config options.
pub fn new_journald(opts map[string]string) JournaldSource {
	boot_str := opts['current_boot_only'] or { 'true' }
	current_boot_only := boot_str != 'false'

	units_str := opts['units'] or { '' }
	mut units := []string{}
	if units_str.len > 0 {
		for u in units_str.split(',') {
			trimmed := u.trim_space()
			if trimmed.len > 0 {
				units << trimmed
			}
		}
	}

	matches_str := opts['include_matches'] or { '' }
	mut include_matches := []string{}
	if matches_str.len > 0 {
		for m in matches_str.split(',') {
			trimmed := m.trim_space()
			if trimmed.len > 0 {
				include_matches << trimmed
			}
		}
	}

	return JournaldSource{
		current_boot_only: current_boot_only
		units: units
		include_matches: include_matches
	}
}

// run starts the journalctl subprocess and emits log events.
pub fn (s &JournaldSource) run(output chan event.Event) {
	mut args := ['journalctl', '-f', '-o', 'json']

	if s.current_boot_only {
		args << '-b'
	}

	for unit in s.units {
		args << '-u'
		args << unit
	}

	for m in s.include_matches {
		args << m
	}

	eprintln('journald: running ${args.join(" ")}')

	mut proc := os.execute(args.join(' '))
	if proc.exit_code != 0 {
		eprintln('journald: journalctl failed: ${proc.output}')
		return
	}

	// Process output line by line
	for line in proc.output.split('\n') {
		trimmed := line.trim_space()
		if trimmed.len == 0 {
			continue
		}
		ev := parse_journald_line(trimmed) or {
			eprintln('journald: parse error: ${err}')
			continue
		}
		output <- event.Event(ev)
	}
}

// JournaldEntry represents a parsed journald JSON entry.
struct JournaldEntry {
	message           string @[json: 'MESSAGE']
	hostname          string @[json: '_HOSTNAME']
	priority          string @[json: 'PRIORITY']
	systemd_unit      string @[json: '_SYSTEMD_UNIT']
	pid               string @[json: '_PID']
	syslog_identifier string @[json: 'SYSLOG_IDENTIFIER']
	transport         string @[json: '_TRANSPORT']
	uid               string @[json: '_UID']
	gid               string @[json: '_GID']
	comm              string @[json: '_COMM']
	exe               string @[json: '_EXE']
	boot_id           string @[json: '_BOOT_ID']
	machine_id        string @[json: '_MACHINE_ID']
	timestamp_us      string @[json: '__REALTIME_TIMESTAMP']
}

// parse_journald_line parses a single JSON line from journalctl output
// into a LogEvent with mapped fields.
fn parse_journald_line(line string) !event.LogEvent {
	entry := json.decode(JournaldEntry, line) or {
		return error('invalid journald JSON: ${err}')
	}

	message := if entry.message.len > 0 { entry.message } else { '' }
	mut ev := event.new_log(message)
	ev.meta.source_type = 'journald'

	if entry.hostname.len > 0 {
		ev.set('host', event.Value(entry.hostname))
	}
	if entry.priority.len > 0 {
		severity := map_journald_priority(entry.priority)
		ev.set('severity', event.Value(severity))
	}
	if entry.systemd_unit.len > 0 {
		ev.set('unit', event.Value(entry.systemd_unit))
	}
	if entry.pid.len > 0 {
		ev.set('pid', event.Value(entry.pid))
	}
	if entry.syslog_identifier.len > 0 {
		ev.set('syslog_identifier', event.Value(entry.syslog_identifier))
	}
	if entry.transport.len > 0 {
		ev.set('transport', event.Value(entry.transport))
	}
	if entry.uid.len > 0 {
		ev.set('uid', event.Value(entry.uid))
	}
	if entry.gid.len > 0 {
		ev.set('gid', event.Value(entry.gid))
	}
	if entry.comm.len > 0 {
		ev.set('comm', event.Value(entry.comm))
	}
	if entry.exe.len > 0 {
		ev.set('exe', event.Value(entry.exe))
	}
	if entry.boot_id.len > 0 {
		ev.set('boot_id', event.Value(entry.boot_id))
	}
	if entry.machine_id.len > 0 {
		ev.set('machine_id', event.Value(entry.machine_id))
	}
	if entry.timestamp_us.len > 0 {
		ev.set('timestamp_us', event.Value(entry.timestamp_us))
	}

	return ev
}

// map_journald_priority maps a journald numeric priority to a human-readable severity string.
// Uses standard syslog severity levels.
fn map_journald_priority(priority string) string {
	return match priority {
		'0' { 'emergency' }
		'1' { 'alert' }
		'2' { 'critical' }
		'3' { 'error' }
		'4' { 'warning' }
		'5' { 'notice' }
		'6' { 'informational' }
		'7' { 'debug' }
		else { priority }
	}
}
