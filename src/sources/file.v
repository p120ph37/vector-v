module sources

import event
import os
import time

// FileSource reads lines from files matching glob patterns and emits each line
// as a log event. Supports file rotation tracking via simple polling.
// Mirrors Vector's file source.
//
// Config options:
//   include:           Comma-separated glob patterns for files to read (required)
//   exclude:           Comma-separated glob patterns to exclude
//   read_from:         "beginning" or "end" (default: end)
//   ignore_older_secs: Ignore files older than N seconds (default: 0 = disabled)
//   poll_interval_secs: Polling interval in seconds (default: 1)
pub struct FileSource {
	include          []string
	exclude          []string
	read_from        FileReadFrom = .end
	ignore_older     time.Duration
	poll_interval    time.Duration = 1 * time.second
}

enum FileReadFrom {
	beginning
	end
}

// new_file creates a new FileSource from config options.
pub fn new_file(opts map[string]string) !FileSource {
	include_str := opts['include'] or {
		return error('file source: include is required')
	}
	mut include := []string{}
	for part in include_str.split(',') {
		trimmed := part.trim_space()
		if trimmed.len > 0 {
			include << trimmed
		}
	}
	if include.len == 0 {
		return error('file source: include patterns are empty')
	}

	mut exclude := []string{}
	if e := opts['exclude'] {
		for part in e.split(',') {
			trimmed := part.trim_space()
			if trimmed.len > 0 {
				exclude << trimmed
			}
		}
	}

	read_from := match opts['read_from'] or { 'end' } {
		'beginning' { FileReadFrom.beginning }
		else { FileReadFrom.end }
	}

	mut ignore_older_secs := 0.0
	if s := opts['ignore_older_secs'] {
		ignore_older_secs = s.f64()
		if ignore_older_secs < 0 {
			ignore_older_secs = 0.0
		}
	}

	mut poll_secs := 1.0
	if s := opts['poll_interval_secs'] {
		poll_secs = s.f64()
		if poll_secs <= 0 {
			poll_secs = 1.0
		}
	}

	return FileSource{
		include: include
		exclude: exclude
		read_from: read_from
		ignore_older: time.Duration(i64(ignore_older_secs * 1_000_000_000))
		poll_interval: time.Duration(i64(poll_secs * 1_000_000_000))
	}
}

// run starts polling files and emitting log events.
pub fn (s &FileSource) run(output chan event.Event) {
	hostname := os.hostname() or { 'unknown' }

	// Track file positions: path -> offset
	mut offsets := map[string]i64{}

	// Initialize offsets based on read_from
	files := s.discover_files()
	for f in files {
		match s.read_from {
			.end {
				offsets[f] = os.file_size(f)
			}
			.beginning {
				offsets[f] = 0
			}
		}
	}

	for {
		current_files := s.discover_files()
		for f in current_files {
			if f !in offsets {
				// New file discovered
				offsets[f] = match s.read_from {
					.beginning { i64(0) }
					.end { os.file_size(f) }
				}
			}

			// Check ignore_older
			if s.ignore_older > time.Duration(0) {
				mtime := os.file_last_mod_unix(f)
				age := time.Duration(i64((time.now().unix() - mtime)) * 1_000_000_000)
				if age > s.ignore_older {
					continue
				}
			}

			fsize := os.file_size(f)
			offset := offsets[f]

			// Detect truncation (file rotation)
			if fsize < offset {
				offsets[f] = 0
				continue
			}

			if fsize == offset {
				continue
			}

			// Read new content
			content := os.read_file(f) or { continue }
			if content.len <= int(offset) {
				continue
			}
			new_data := content[int(offset)..]
			lines := new_data.split('\n')
			for line in lines {
				trimmed := line.trim_right('\r')
				if trimmed.len == 0 {
					continue
				}
				mut ev := event.new_log(trimmed)
				ev.meta.source_type = 'file'
				ev.set('file', event.Value(f))
				ev.set('host', event.Value(hostname))
				output <- event.Event(ev)
			}
			offsets[f] = fsize
		}
		time.sleep(s.poll_interval)
	}
}

// discover_files finds all files matching include patterns minus excludes.
fn (s &FileSource) discover_files() []string {
	mut result := []string{}
	mut excluded := map[string]bool{}

	for pattern in s.exclude {
		matches := os.glob(pattern) or { continue }
		for m in matches {
			excluded[m] = true
		}
	}

	for pattern in s.include {
		matches := os.glob(pattern) or { continue }
		for m in matches {
			if m !in excluded && os.is_file(m) {
				result << m
			}
		}
	}

	return result
}

// match_glob performs simple glob matching supporting * and ? wildcards.
// Exported for testing.
fn match_glob(pattern string, name string) bool {
	mut pi := 0
	mut ni := 0
	mut star_pi := -1
	mut star_ni := -1

	for ni < name.len || pi < pattern.len {
		if pi < pattern.len && pattern[pi] == `*` {
			star_pi = pi
			star_ni = ni
			pi++
			continue
		}
		if ni < name.len && pi < pattern.len && (pattern[pi] == `?` || pattern[pi] == name[ni]) {
			pi++
			ni++
			continue
		}
		if star_pi >= 0 && star_ni < name.len {
			pi = star_pi + 1
			star_ni++
			ni = star_ni
			continue
		}
		return false
	}
	return true
}
