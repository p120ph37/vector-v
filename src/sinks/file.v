module sinks

import event
import json
import os
import time

// FileSink writes events to files on disk.
// Mirrors Vector's file sink (src/sinks/file/).
//
// Supports simple static paths and time-based partitioning via template
// interpolation of strftime patterns.
//
// Config options:
//   path:                Output file path (required). May contain strftime patterns
//                        like /var/log/vector/%Y-%m-%d.log
//   encoding.codec:      json, text, or ndjson (default: ndjson)
pub struct FileSink {
	path_template string
	codec         FileCodec
mut:
	known_paths map[string]bool
}

enum FileCodec {
	json_codec
	text_codec
	ndjson_codec
}

// new_file creates a new FileSink from config options.
pub fn new_file(opts map[string]string) !FileSink {
	path_template := opts['path'] or {
		return error('file sink: path is required')
	}

	codec := match opts['encoding.codec'] or { 'ndjson' } {
		'json' { FileCodec.json_codec }
		'text' { FileCodec.text_codec }
		else { FileCodec.ndjson_codec }
	}

	return FileSink{
		path_template: path_template
		codec: codec
	}
}

// send writes an event to the appropriate file.
pub fn (mut s FileSink) send(e event.Event) ! {
	line := s.encode_event(e)
	if line.len == 0 {
		return
	}

	path := resolve_file_path(s.path_template, time.now())

	// Ensure parent directory exists (only check once per path)
	if path !in s.known_paths {
		dir := os.dir(path)
		if dir.len > 0 && !os.exists(dir) {
			os.mkdir_all(dir) or {
				return error('file sink: cannot create directory ${dir}: ${err}')
			}
		}
		s.known_paths[path] = true
	}

	// Append line to file
	mut fd := os.open_append(path) or {
		return error('file sink: cannot open ${path}: ${err}')
	}
	fd.write_string(line + '\n') or {
		fd.close()
		return error('file sink: write failed for ${path}: ${err}')
	}
	fd.close()
}

fn (s &FileSink) encode_event(e event.Event) string {
	match e {
		event.LogEvent {
			return match s.codec {
				.json_codec, .ndjson_codec {
					e.to_json()
				}
				.text_codec {
					e.message()
				}
			}
		}
		event.Metric {
			return json.encode(e)
		}
		event.TraceEvent {
			return json.encode(e.fields)
		}
	}
}

// total_open returns the number of unique paths written to.
pub fn (s &FileSink) total_open() int {
	return s.known_paths.len
}

// resolve_file_path resolves strftime-style patterns in a path template.
// Supports: %Y (year), %m (month), %d (day), %H (hour), %M (minute), %S (second).
pub fn resolve_file_path(template string, t time.Time) string {
	if !template.contains('%') {
		return template
	}

	mut result := template
	result = result.replace('%Y', '${t.year:04d}')
	result = result.replace('%m', '${t.month:02d}')
	result = result.replace('%d', '${t.day:02d}')
	result = result.replace('%H', '${t.hour:02d}')
	result = result.replace('%M', '${t.minute:02d}')
	result = result.replace('%S', '${t.second:02d}')
	return result
}
