module sources

import event
import os
import time

// ExecSource runs an external command and captures its output as log events.
// Mirrors Vector's exec source (src/sources/exec/).
//
// Supports two modes:
//   - scheduled: Re-runs the command on a configurable interval
//   - streaming: Runs the command once and reads stdout continuously
//
// Config options:
//   command:             Command to execute (required), as array or single string
//   mode:                "scheduled" or "streaming" (default: scheduled)
//   scheduled.exec_interval_secs: Interval between runs (default: 60)
//   streaming.respawn_on_exit:    Restart command if it exits (default: true)
//   streaming.respawn_interval_secs: Wait before respawn (default: 5)
//   working_directory:   Working directory for the command
//   include_stderr:      Capture stderr too (default: false)
//   max_length:          Max line length (default: 102400)
pub struct ExecSource {
	command         []string
	mode            ExecMode
	exec_interval   time.Duration = 60 * time.second
	respawn_on_exit bool = true
	respawn_interval time.Duration = 5 * time.second
	working_dir     string
	include_stderr  bool
	max_length      int = 102400
}

enum ExecMode {
	scheduled
	streaming
}

// new_exec creates a new ExecSource from config options.
pub fn new_exec(opts map[string]string) !ExecSource {
	command_str := opts['command'] or {
		return error('exec source: command is required')
	}
	// Split command string into parts (simple space-split)
	command := command_str.split(' ').filter(it.len > 0)
	if command.len == 0 {
		return error('exec source: command is empty')
	}

	mode := match opts['mode'] or { 'scheduled' } {
		'streaming' { ExecMode.streaming }
		else { ExecMode.scheduled }
	}

	mut exec_interval_secs := 60.0
	if s := opts['scheduled.exec_interval_secs'] {
		exec_interval_secs = s.f64()
		if exec_interval_secs <= 0 {
			exec_interval_secs = 60.0
		}
	}

	mut respawn_interval_secs := 5.0
	if s := opts['streaming.respawn_interval_secs'] {
		respawn_interval_secs = s.f64()
		if respawn_interval_secs <= 0 {
			respawn_interval_secs = 5.0
		}
	}

	respawn_val := opts['streaming.respawn_on_exit'] or { 'true' }
	include_stderr_val := opts['include_stderr'] or { 'false' }

	mut max_length := 102400
	if ml := opts['max_length'] {
		max_length = ml.int()
		if max_length <= 0 {
			max_length = 102400
		}
	}

	return ExecSource{
		command: command
		mode: mode
		exec_interval: time.Duration(i64(exec_interval_secs * 1_000_000_000))
		respawn_on_exit: respawn_val == 'true'
		respawn_interval: time.Duration(i64(respawn_interval_secs * 1_000_000_000))
		working_dir: opts['working_directory'] or { '' }
		include_stderr: include_stderr_val == 'true'
		max_length: max_length
	}
}

// run executes the command and sends output lines as events.
pub fn (s &ExecSource) run(output chan event.Event) {
	match s.mode {
		.scheduled {
			s.run_scheduled(output)
		}
		.streaming {
			s.run_streaming(output)
		}
	}
}

fn (s &ExecSource) run_scheduled(output chan event.Event) {
	for {
		s.exec_once(output)
		time.sleep(s.exec_interval)
	}
}

fn (s &ExecSource) run_streaming(output chan event.Event) {
	for {
		s.exec_once(output)
		if !s.respawn_on_exit {
			break
		}
		time.sleep(s.respawn_interval)
	}
}

fn (s &ExecSource) exec_once(output chan event.Event) {
	cmd := s.command.join(' ')
	result := os.execute(cmd)

	if result.output.len > 0 {
		lines := result.output.split('\n')
		for line in lines {
			trimmed := line.trim_right('\r\n')
			if trimmed.len == 0 {
				continue
			}
			msg := if trimmed.len > s.max_length {
				trimmed[..s.max_length]
			} else {
				trimmed
			}
			mut ev := event.new_log(msg)
			ev.meta.source_type = 'exec'
			ev.set('command', event.Value(cmd))
			ev.set('exit_code', event.Value(result.exit_code))
			ev.set('stream', event.Value('stdout'))
			output <- event.Event(ev)
		}
	}
}

// get_command returns the command that will be executed.
pub fn (s &ExecSource) get_command() string {
	return s.command.join(' ')
}
