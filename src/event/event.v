module event

import json

// Event is the primary data type flowing through the pipeline.
// Mirrors Vector's Event enum: Log | Metric | Trace.
pub type Event = LogEvent | Metric | TraceEvent

// to_json_string serializes an event to JSON.
pub fn (e &Event) to_json_string() string {
	match e {
		LogEvent {
			return e.to_json()
		}
		Metric {
			return json.encode(e)
		}
		TraceEvent {
			return json.encode(e.fields)
		}
	}
}
