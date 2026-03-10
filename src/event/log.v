module event

import json
import time

// LogEvent represents a log event in the pipeline, mirroring Vector's LogEvent.
pub struct LogEvent {
pub mut:
	fields map[string]Value
	meta   EventMetadata
}

// Float is a wrapper for f64 to avoid V json sum type limitations.
pub type Float = f64

// Value represents a dynamically-typed value, mirroring Vector/VRL's Value type.
pub type Value = string | int | Float | bool | []Value | map[string]Value | time.Time

// EventMetadata holds metadata about an event.
pub struct EventMetadata {
pub mut:
	source_type      string
	ingest_timestamp time.Time
	upstream         map[string]Value
}

// new_log creates a new LogEvent with an initial message field.
pub fn new_log(message string) LogEvent {
	mut fields := map[string]Value{}
	fields['message'] = Value(message)
	return LogEvent{
		fields: fields
		meta: EventMetadata{
			ingest_timestamp: time.now()
		}
	}
}

// get retrieves a field value from the log event by key.
pub fn (l &LogEvent) get(key string) ?Value {
	return l.fields[key] or { return none }
}

// set sets a field value on the log event.
pub fn (mut l LogEvent) set(key string, val Value) {
	l.fields[key] = val
}

// remove deletes a field from the log event.
pub fn (mut l LogEvent) remove(key string) {
	l.fields.delete(key)
}

// message returns the 'message' field if present.
pub fn (l &LogEvent) message() string {
	if v := l.get('message') {
		return value_to_string(v)
	}
	return ''
}

// to_json serializes the log event fields to JSON.
pub fn (l &LogEvent) to_json() string {
	return json.encode(l.fields)
}

// value_to_string converts a Value to its string representation.
pub fn value_to_string(v Value) string {
	match v {
		string {
			return v
		}
		int {
			return '${v}'
		}
		Float {
			return '${f64(v)}'
		}
		bool {
			if v {
				return 'true'
			}
			return 'false'
		}
		time.Time {
			return v.format_rfc3339()
		}
		[]Value {
			return json.encode(v)
		}
		map[string]Value {
			return json.encode(v)
		}
	}
}
