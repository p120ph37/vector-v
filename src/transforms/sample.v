module transforms

import event
import rand

// SampleTransform passes through only a statistical sample of events.
// Mirrors Vector's sample transform.
//
// Config options:
//   rate — pass 1 in every N events (required)
//   key_field — field to use for deterministic sampling (optional)
//   exclude — VRL condition; matching events always pass through (optional)
pub struct SampleTransform {
	rate         int    // pass 1 in N
	key_field    string // optional: deterministic sampling field
	exclude_cond string // optional: condition for events that always pass
}

// new_sample creates a new SampleTransform from config options.
pub fn new_sample(opts map[string]string) !SampleTransform {
	rate_str := opts['rate'] or { return error('sample transform requires "rate" option') }
	rate := rate_str.int()
	if rate < 1 {
		return error('sample transform: rate must be >= 1, got ${rate_str}')
	}

	return SampleTransform{
		rate: rate
		key_field: opts['key_field'] or { '' }
		exclude_cond: opts['exclude'] or { '' }
	}
}

// transform returns the event if it passes the sample, or empty list to drop it.
pub fn (t &SampleTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			// Check exclude condition — always pass matching events
			if t.exclude_cond.len > 0 && check_sample_condition(t.exclude_cond, e) {
				return [e]
			}

			// Deterministic sampling by key_field hash
			if t.key_field.len > 0 {
				if val := e.get(t.key_field) {
					s := event.value_to_string(val)
					h := simple_hash(s)
					if h % u64(t.rate) == 0 {
						return [e]
					}
					return []
				}
			}

			// Random sampling: pass 1 in N
			if rand.intn(t.rate) or { 0 } == 0 {
				return [e]
			}
			return []
		}
		else {
			return [e]
		}
	}
}

fn check_sample_condition(condition string, e event.LogEvent) bool {
	// Simple field == value check
	if condition.contains('==') {
		parts := condition.split('==')
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

fn simple_hash(s string) u64 {
	// FNV-1a hash
	mut h := u64(0xcbf29ce484222325)
	for b in s.bytes() {
		h = h ^ u64(b)
		h = h * u64(0x100000001b3)
	}
	return h
}
