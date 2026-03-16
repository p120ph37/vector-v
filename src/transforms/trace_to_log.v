module transforms

import event
import time

// TraceToLogTransform converts TraceEvent instances to LogEvent instances.
// Mirrors Vector's trace_to_log transform.
//
// Each trace field is mapped to a log field. The source_type metadata is
// set to "trace" to indicate the origin of the log event.
//
// Config options:
//   fields — comma-separated list of trace fields to include (optional,
//            default: include all fields)
pub struct TraceToLogTransform {
	fields []string // empty means include all
}

// new_trace_to_log creates a new TraceToLogTransform from config options.
pub fn new_trace_to_log(opts map[string]string) !TraceToLogTransform {
	mut fields := []string{}
	if f := opts['fields'] {
		if f.len > 0 {
			for part in f.split(',') {
				trimmed := part.trim_space()
				if trimmed.len > 0 {
					fields << trimmed
				}
			}
		}
	}

	return TraceToLogTransform{
		fields: fields
	}
}

// transform converts a TraceEvent to a LogEvent.
// Non-trace events pass through unchanged.
pub fn (t &TraceToLogTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.TraceEvent {
			mut log := event.LogEvent{
				fields: map[string]event.Value{}
				meta: event.EventMetadata{
					source_type: 'trace'
					ingest_timestamp: time.now()
				}
			}

			if t.fields.len > 0 {
				// Include only specified fields
				for field in t.fields {
					if val := e.fields[field] {
						log.set(field, val)
					}
				}
			} else {
				// Include all fields
				for k, v in e.fields {
					log.set(k, v)
				}
			}

			// Carry over upstream metadata from the trace event
			for k, v in e.meta.upstream {
				log.meta.upstream[k] = v
			}

			return [event.Event(log)]
		}
		else {
			// Non-trace events pass through unchanged
			return [e]
		}
	}
}
