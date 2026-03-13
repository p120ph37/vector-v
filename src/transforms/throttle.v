module transforms

import event
import time

// ThrottleTransform rate-limits events using a token bucket algorithm.
// Mirrors Vector's throttle transform.
//
// Config options:
//   threshold — max events per window (required)
//   window_secs — time window in seconds (default: 1)
//   key_field — field to use for per-key rate limiting (optional)
pub struct ThrottleTransform {
	threshold int
	window    time.Duration
	key_field string
mut:
	buckets map[string]TokenBucket
}

struct TokenBucket {
mut:
	tokens  int
	last_ts time.Time
}

// new_throttle creates a new ThrottleTransform from config options.
pub fn new_throttle(opts map[string]string) !ThrottleTransform {
	threshold_str := opts['threshold'] or {
		return error('throttle transform requires "threshold" option')
	}
	threshold := threshold_str.int()
	if threshold < 1 {
		return error('throttle transform: threshold must be >= 1, got ${threshold_str}')
	}

	mut window_secs := 1
	if ws := opts['window_secs'] {
		n := ws.int()
		if n > 0 {
			window_secs = n
		}
	}

	return ThrottleTransform{
		threshold: threshold
		window: time.Duration(i64(window_secs) * 1_000_000_000)
		key_field: opts['key_field'] or { '' }
		buckets: map[string]TokenBucket{}
	}
}

// transform returns the event if the rate limit allows it, or empty list to drop it.
pub fn (mut t ThrottleTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			now := time.now()
			key := if t.key_field.len > 0 {
				if val := e.get(t.key_field) {
					event.value_to_string(val)
				} else {
					'_default_'
				}
			} else {
				'_default_'
			}

			mut bucket := t.buckets[key] or {
				TokenBucket{
					tokens: t.threshold
					last_ts: now
				}
			}

			// Refill tokens based on elapsed time
			elapsed := now - bucket.last_ts
			if elapsed >= t.window {
				// How many full windows have passed
				windows := int(elapsed / t.window)
				bucket.tokens += windows * t.threshold
				if bucket.tokens > t.threshold {
					bucket.tokens = t.threshold
				}
				bucket.last_ts = time.unix(bucket.last_ts.unix() + i64(windows) * i64(t.window) / 1_000_000_000)
			}

			if bucket.tokens > 0 {
				bucket.tokens--
				t.buckets[key] = bucket
				return [e]
			}

			t.buckets[key] = bucket
			return [] // throttled, drop
		}
		else {
			return [e]
		}
	}
}
