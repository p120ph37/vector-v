module event

import time

// TraceEvent represents a trace/span event in the pipeline, mirroring Vector's TraceEvent.
// It uses the same field-based approach as LogEvent.
pub struct TraceEvent {
pub mut:
	fields map[string]Value
	meta   EventMetadata
}

// new_trace creates a new TraceEvent.
pub fn new_trace() TraceEvent {
	return TraceEvent{
		fields: map[string]Value{}
		meta: EventMetadata{
			ingest_timestamp: time.now()
		}
	}
}

// get retrieves a field value from the trace event.
pub fn (t &TraceEvent) get(key string) ?Value {
	return t.fields[key] or { return none }
}

// set sets a field value on the trace event.
pub fn (mut t TraceEvent) set(key string, val Value) {
	t.fields[key] = val
}
