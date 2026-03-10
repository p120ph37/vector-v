module sinks

import event
import json

// Target specifies which standard stream to write to.
pub enum Target {
	stdout
	stderr
}

// Codec specifies how events are encoded for output.
pub enum Codec {
	json
	text
	logfmt
}

// ConsoleSink writes events to stdout or stderr.
// Mirrors Vector's console sink (src/sinks/console/).
pub struct ConsoleSink {
	target Target
	codec  Codec
}

// new_console creates a new ConsoleSink from config options.
pub fn new_console(opts map[string]string) ConsoleSink {
	target := if t := opts['target'] {
		if t == 'stderr' { Target.stderr } else { Target.stdout }
	} else {
		Target.stdout
	}

	codec_val := opts['encoding.codec'] or { '' }
	codec := match codec_val {
		'text' { Codec.text }
		'logfmt' { Codec.logfmt }
		else { Codec.json }
	}

	return ConsoleSink{
		target: target
		codec: codec
	}
}

// send writes a single event to the configured output stream.
pub fn (s &ConsoleSink) send(e event.Event) ! {
	line := s.encode(e)
	match s.target {
		.stdout {
			println(line)
		}
		.stderr {
			eprintln(line)
		}
	}
}

// encode serializes an event according to the configured codec.
fn (s &ConsoleSink) encode(e event.Event) string {
	match s.codec {
		.json {
			return e.to_json_string()
		}
		.text {
			match e {
				event.LogEvent {
					return e.message()
				}
				event.Metric {
					return json.encode(e)
				}
				event.TraceEvent {
					return json.encode(e.fields)
				}
			}
		}
		.logfmt {
			match e {
				event.LogEvent {
					mut parts := []string{}
					for key, val in e.fields {
						parts << '${key}=${event.value_to_string(val)}'
					}
					return parts.join(' ')
				}
				else {
					return e.to_json_string()
				}
			}
		}
	}
}
