module transforms

import event

// FilterTransform drops events that don't match a condition.
// Simplified initial implementation - supports basic field matching.
pub struct FilterTransform {
	field string
	value string
}

// new_filter creates a new FilterTransform from config options.
pub fn new_filter(opts map[string]string) !FilterTransform {
	condition := opts['condition'] or { return error('filter transform requires "condition" option') }

	// Parse simple condition like '.level == "error"'
	// For now, support basic equality checks
	mut field := ''
	mut value := ''
	if condition.contains('==') {
		parts := condition.split('==')
		if parts.len == 2 {
			lhs := parts[0].trim_space()
			rhs := parts[1].trim_space()
			if lhs.starts_with('.') {
				field = lhs[1..]
			}
			// Strip quotes
			if rhs.len >= 2
				&& ((rhs[0] == `"` && rhs[rhs.len - 1] == `"`)
				|| (rhs[0] == `'` && rhs[rhs.len - 1] == `'`)) {
				value = rhs[1..rhs.len - 1]
			} else {
				value = rhs
			}
		}
	}

	return FilterTransform{
		field: field
		value: value
	}
}

// transform returns the event if it matches the condition, or empty list to drop it.
pub fn (t &FilterTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			if field_val := e.get(t.field) {
				if event.value_to_string(field_val) == t.value {
					return [e]
				}
			}
			return [] // Drop event
		}
		else {
			return [e]
		}
	}
}
