module transforms

import event
import time

// ReduceTransform accumulates events and merges them based on grouping criteria.
// Simplified initial implementation of Vector's reduce transform.
// Mirrors Vector's reduce transform (src/transforms/reduce/).
pub struct ReduceTransform {
	group_by      []string
	ends_when     string // simple field condition
	expire_after  time.Duration
	merge_strategies map[string]MergeStrategy
mut:
	groups map[string]event.LogEvent
	timers map[string]time.Time
}

pub enum MergeStrategy {
	discard
	retain
	array_
	concat
	sum
	max
	min
}

// new_reduce creates a new ReduceTransform from config options.
pub fn new_reduce(opts map[string]string) !ReduceTransform {
	mut group_by := []string{}
	if gb := opts['group_by'] {
		for part in gb.split(',') {
			trimmed := part.trim_space().trim_left('.')
			if trimmed.len > 0 {
				group_by << trimmed
			}
		}
	}

	mut expire_ms := 30000 // 30 second default
	if ea := opts['expire_after_ms'] {
		expire_ms = ea.int()
		if expire_ms <= 0 {
			expire_ms = 30000
		}
	}

	return ReduceTransform{
		group_by: group_by
		ends_when: opts['ends_when'] or { '' }
		expire_after: time.Duration(i64(expire_ms) * 1_000_000)
		groups: map[string]event.LogEvent{}
		timers: map[string]time.Time{}
	}
}

// transform processes an event through the reduce logic.
// Events are accumulated; only emitted when the group ends or expires.
pub fn (mut t ReduceTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			group_key := t.compute_group_key(e)
			now := time.now()

			// Check for expired groups first
			mut result := []event.Event{}
			t.flush_expired(now, mut result)

			// Check if this event ends the group
			if t.ends_when.len > 0 && t.check_ends_when(e) {
				if existing := t.groups[group_key] {
					// Merge and emit
					merged := t.merge_events(existing, e)
					result << event.Event(merged)
					t.groups.delete(group_key)
					t.timers.delete(group_key)
				} else {
					// Just emit as-is
					result << event.Event(e)
				}
				return result
			}

			// Accumulate
			if existing := t.groups[group_key] {
				t.groups[group_key] = t.merge_events(existing, e)
			} else {
				t.groups[group_key] = e
			}
			t.timers[group_key] = now

			return result
		}
		else {
			return [e]
		}
	}
}

// flush_all emits all accumulated groups (call on shutdown).
pub fn (mut t ReduceTransform) flush_all() []event.Event {
	mut result := []event.Event{}
	for _, group_event in t.groups {
		result << event.Event(group_event)
	}
	t.groups.clear()
	t.timers.clear()
	return result
}

fn (t &ReduceTransform) compute_group_key(e event.LogEvent) string {
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

fn (t &ReduceTransform) check_ends_when(e event.LogEvent) bool {
	// Simple check: if ends_when contains "==", check field equality
	if t.ends_when.contains('==') {
		parts := t.ends_when.split('==')
		if parts.len == 2 {
			field := parts[0].trim_space().trim_left('.')
			expected := parts[1].trim_space().trim('"').trim("'")
			if val := e.get(field) {
				return event.value_to_string(val) == expected
			}
		}
	}
	return false
}

fn (mut t ReduceTransform) flush_expired(now time.Time, mut result []event.Event) {
	mut expired_keys := []string{}
	for key, timer in t.timers {
		if now - timer > t.expire_after {
			expired_keys << key
		}
	}
	for key in expired_keys {
		if group_event := t.groups[key] {
			result << event.Event(group_event)
		}
		t.groups.delete(key)
		t.timers.delete(key)
	}
}

fn (t &ReduceTransform) merge_events(existing event.LogEvent, new_event event.LogEvent) event.LogEvent {
	mut merged := existing
	for key, val in new_event.fields {
		strategy := t.merge_strategies[key] or { MergeStrategy.retain }
		match strategy {
			.discard {
				// Keep existing value
			}
			.concat {
				if existing_val := merged.get(key) {
					merged.set(key, event.Value(event.value_to_string(existing_val) +
						event.value_to_string(val)))
				} else {
					merged.set(key, val)
				}
			}
			else {
				// Default: retain (use newest value)
				merged.set(key, val)
			}
		}
	}
	return merged
}
