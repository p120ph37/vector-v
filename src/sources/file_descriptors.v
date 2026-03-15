module sources

import event
import os

// FileDescriptorSource reads from a file descriptor (fd 0 = stdin, etc).
// Mirrors Vector's file_descriptors source. This generalizes StdinSource
// to work with any file descriptor.
//
// In practice, fd=0 is stdin (equivalent to StdinSource). Other FDs can be
// used when processes are launched with redirected file descriptors.
//
// Config options:
//   fd:           File descriptor number (default: 0 = stdin)
//   max_length:   Max line length (default: 102400)
//   host_key:     Field name for hostname (default: "host")
pub struct FileDescriptorSource {
	fd         int
	max_length int    = 102400
	host_key   string = 'host'
}

// new_file_descriptor creates a new FileDescriptorSource from config options.
pub fn new_file_descriptor(opts map[string]string) FileDescriptorSource {
	mut fd := 0
	if f := opts['fd'] {
		fd = f.int()
		if fd < 0 {
			fd = 0
		}
	}

	mut max_length := 102400
	if ml := opts['max_length'] {
		max_length = ml.int()
		if max_length <= 0 {
			max_length = 102400
		}
	}

	host_key := opts['host_key'] or { 'host' }

	return FileDescriptorSource{
		fd: fd
		max_length: max_length
		host_key: host_key
	}
}

// run reads lines from the file descriptor and sends events.
// For fd=0, reads stdin line by line (same as StdinSource).
pub fn (s &FileDescriptorSource) run(output chan event.Event) {
	hostname := os.hostname() or { 'unknown' }

	// For fd 0 (stdin), use the same approach as StdinSource
	if s.fd == 0 {
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
			ev.meta.source_type = 'file_descriptors'
			ev.set(s.host_key, event.Value(hostname))
			ev.set('fd', event.Value(s.fd))
			output <- event.Event(ev)
		}
		return
	}

	// For other FDs, try to read from /dev/fd/<n>
	fd_path := '/dev/fd/${s.fd}'
	content := os.read_file(fd_path) or {
		eprintln('file_descriptors: cannot read fd ${s.fd}: ${err}')
		return
	}
	for line in content.split('\n') {
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
		ev.meta.source_type = 'file_descriptors'
		ev.set(s.host_key, event.Value(hostname))
		ev.set('fd', event.Value(s.fd))
		output <- event.Event(ev)
	}
}
