module sources

import event
import os

// StdinSource reads lines from stdin and emits them as LogEvents.
// Mirrors Vector's stdin source (src/sources/file_descriptors/stdin.rs).
pub struct StdinSource {
	max_length int    = 102400
	host_key   string = 'host'
}

// new_stdin creates a new StdinSource from config options.
pub fn new_stdin(opts map[string]string) StdinSource {
	mut max_len := 102400
	if ml := opts['max_length'] {
		max_len = ml.int()
		if max_len <= 0 {
			max_len = 102400
		}
	}
	return StdinSource{
		max_length: max_len
	}
}

// run reads from stdin line by line and sends events to the output channel.
pub fn (s &StdinSource) run(output chan event.Event) {
	hostname := os.hostname() or { 'unknown' }

	for {
		line := os.get_raw_line()
		if line.len == 0 {
			break
		}

		trimmed := line.trim_right('\r\n')

		msg := if trimmed.len > s.max_length {
			trimmed[..s.max_length]
		} else {
			trimmed
		}

		mut ev := event.new_log(msg)
		ev.meta.source_type = 'stdin'
		ev.set(s.host_key, event.Value(hostname))
		output <- event.Event(ev)
	}
}
