module sources

import event
import os
import time

// Global channel for internal log messages. Other parts of Vector-V can
// send structured log strings here (format: "level|module|target|message").
__global internal_log_chan = chan string{cap: 1000}

// emit_internal_log sends a log message to the internal logs channel.
// This is a convenience function for other modules to use.
// level: trace, debug, info, warn, error
pub fn emit_internal_log(level string, module_name string, target string, message string) {
	internal_log_chan.try_push('${level}|${module_name}|${target}|${message}')
}

// InternalLogsSource captures Vector-V's own internal log messages and emits
// them as log events. Mirrors Vector's internal_logs source.
//
// Internal logs are delivered via a global channel that other parts of
// Vector-V can write to using emit_internal_log().
//
// Each emitted log event contains:
//   message:              The log text
//   metadata.level:       Log level (trace/debug/info/warn/error)
//   metadata.module:      Module that produced the log
//   metadata.target:      Log target
//   host:                 Hostname string
//   pid:                  Process ID as int
//   source_type:          "internal_logs" in event metadata
//   timestamp:            Ingest time
//
// Config options:
//   host_key:   Field to store hostname (default: "host")
//   pid_key:    Field to store PID (default: "pid")
pub struct InternalLogsSource {
	host_key string = 'host'
	pid_key  string = 'pid'
}

// new_internal_logs creates a new InternalLogsSource from config options.
pub fn new_internal_logs(opts map[string]string) InternalLogsSource {
	host_key := opts['host_key'] or { 'host' }
	pid_key := opts['pid_key'] or { 'pid' }

	return InternalLogsSource{
		host_key: host_key
		pid_key: pid_key
	}
}

// run starts consuming from the global internal log channel and emitting events.
pub fn (s &InternalLogsSource) run(output chan event.Event) {
	hostname := os.hostname() or { 'unknown' }
	pid := C.getpid()

	for {
		// Block waiting for a log message on the global channel
		mut msg := ''
		if internal_log_chan.try_pop(mut msg) == .success {
			ev := s.build_event(msg, hostname, pid)
			output <- event.Event(ev)
		} else {
			time.sleep(10 * time.millisecond)
		}
	}
}

// parse_internal_log_message parses a "level|module|target|message" string.
fn parse_internal_log_message(raw string) (string, string, string, string) {
	parts := raw.split_nth('|', 4)
	level := if parts.len > 0 { parts[0] } else { 'info' }
	module_name := if parts.len > 1 { parts[1] } else { '' }
	target := if parts.len > 2 { parts[2] } else { '' }
	message := if parts.len > 3 { parts[3] } else { raw }
	return level, module_name, target, message
}

// build_event creates a LogEvent from a raw internal log message.
fn (s &InternalLogsSource) build_event(raw string, hostname string, pid int) event.LogEvent {
	level, module_name, target, message := parse_internal_log_message(raw)

	mut ev := event.new_log(message)
	ev.meta.source_type = 'internal_logs'

	// Set metadata map
	mut metadata := map[string]event.Value{}
	metadata['level'] = event.Value(level)
	metadata['module'] = event.Value(module_name)
	metadata['target'] = event.Value(target)
	ev.set('metadata', event.Value(metadata))

	// Set host and pid
	ev.set(s.host_key, event.Value(hostname))
	ev.set(s.pid_key, event.Value(int(pid)))

	// Set timestamp
	ev.set('timestamp', event.Value(time.now()))

	return ev
}
