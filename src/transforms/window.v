module transforms

import event
import time

// WindowTransform groups events into time-based windows and emits them as
// batched arrays when the window closes.
// Mirrors Vector's window transform concept.
//
// Events are accumulated in the current window. When the window duration
// elapses, all accumulated events are emitted with a window metadata field.
//
// Config options:
//   window_ms:     Window duration in milliseconds (default: 5000)
//   group_by:      Comma-separated fields to group events (optional)
//   merge_into:    Field name to store windowed events (default: "events")
pub struct WindowTransform {
	window_ms int
	group_by  []string
	merge_into string
mut:
	windows    map[string]WindowState
	last_flush time.Time
}

struct WindowState {
mut:
	events []event.LogEvent
	start  time.Time
}

// new_window creates a new WindowTransform from config options.
pub fn new_window(opts map[string]string) !WindowTransform {
	mut window_ms := 5000
	if w := opts['window_ms'] {
		window_ms = w.int()
		if window_ms <= 0 {
			window_ms = 5000
		}
	}

	mut group_by := []string{}
	if gb := opts['group_by'] {
		for part in gb.split(',') {
			trimmed := part.trim_space()
			if trimmed.len > 0 {
				group_by << trimmed
			}
		}
	}

	merge_into := opts['merge_into'] or { 'events' }

	return WindowTransform{
		window_ms: window_ms
		group_by: group_by
		merge_into: merge_into
		last_flush: time.now()
	}
}

// transform accumulates events and emits closed windows.
pub fn (mut t WindowTransform) transform(e event.Event) ![]event.Event {
	mut result := []event.Event{}

	// Flush any expired windows
	t.flush_expired(mut result)

	match e {
		event.LogEvent {
			key := t.compute_group_key(e)
			now := time.now()

			if key in t.windows {
				mut ws := t.windows[key]
				ws.events << e
				t.windows[key] = ws
			} else {
				t.windows[key] = WindowState{
					events: [e]
					start: now
				}
			}

			return result
		}
		else {
			result << e
			return result
		}
	}
}

// flush_all emits all accumulated windows (call on shutdown).
pub fn (mut t WindowTransform) flush_all() []event.Event {
	mut result := []event.Event{}
	for key, ws in t.windows {
		if ws.events.len > 0 {
			result << event.Event(t.build_window_event(key, ws))
		}
	}
	t.windows.clear()
	return result
}

fn (mut t WindowTransform) flush_expired(mut result []event.Event) {
	now := time.now()
	window_dur := time.Duration(i64(t.window_ms) * 1_000_000)
	mut expired_keys := []string{}

	for key, ws in t.windows {
		if now - ws.start >= window_dur {
			expired_keys << key
		}
	}

	for key in expired_keys {
		ws := t.windows[key] or { continue }
		if ws.events.len > 0 {
			result << event.Event(t.build_window_event(key, ws))
		}
		t.windows.delete(key)
	}
}

fn (t &WindowTransform) build_window_event(key string, ws WindowState) event.LogEvent {
	mut log := event.new_log('')

	// Create array of event values
	mut event_vals := []event.Value{}
	for ev in ws.events {
		event_vals << event.Value(ev.fields.clone())
	}
	log.set(t.merge_into, event.Value(event_vals))

	// Set window metadata
	log.set('window_start', event.Value(ws.start))
	log.set('window_size', event.Value(ws.events.len))
	log.set('message', event.Value('window: ${ws.events.len} events'))

	// Copy group-by fields from first event for identification
	if ws.events.len > 0 {
		first := ws.events[0]
		for field in t.group_by {
			if val := first.get(field) {
				log.set(field, val)
			}
		}
	}

	return log
}

fn (t &WindowTransform) compute_group_key(e event.LogEvent) string {
	if t.group_by.len == 0 {
		return '_default_'
	}
	mut parts := []string{}
	for field in t.group_by {
		if val := e.get(field) {
			parts << event.value_to_string(val)
		} else {
			parts << ''
		}
	}
	return parts.join('|')
}
