module transforms

import event
import hash

// DedupeTransform drops duplicate events based on a set of fields.
// Mirrors Vector's dedupe transform.
//
// Config options:
//   fields.match — list of fields (comma-separated) to check for duplicates
//   fields.ignore — list of fields to ignore when deduplicating (all other fields are used)
//   cache.num_events — max number of recent events to track (LRU eviction), default 5000
pub struct DedupeTransform {
	match_fields  []string // fields to check (empty = use ignore mode)
	ignore_fields []string // fields to ignore (empty = use match mode)
	cache_size    int      // max cache entries
mut:
	// Simple LRU cache: ring buffer of hashes
	cache     []u64
	cache_pos int
	cache_set map[u64]bool
}

// new_dedupe creates a new DedupeTransform from config options.
pub fn new_dedupe(opts map[string]string) !DedupeTransform {
	mut match_fields := []string{}
	mut ignore_fields := []string{}

	if mf := opts['fields.match'] {
		for part in mf.split(',') {
			trimmed := part.trim_space().trim_left('.')
			if trimmed.len > 0 {
				match_fields << trimmed
			}
		}
	}

	if igf := opts['fields.ignore'] {
		for part in igf.split(',') {
			trimmed := part.trim_space().trim_left('.')
			if trimmed.len > 0 {
				ignore_fields << trimmed
			}
		}
	}

	// Default: match on all fields (ignore none)
	if match_fields.len == 0 && ignore_fields.len == 0 {
		ignore_fields = ['timestamp']
	}

	mut cache_size := 5000
	if cs := opts['cache.num_events'] {
		n := cs.int()
		if n > 0 {
			cache_size = n
		}
	}

	return DedupeTransform{
		match_fields: match_fields
		ignore_fields: ignore_fields
		cache_size: cache_size
		cache: []u64{len: cache_size}
		cache_pos: 0
		cache_set: map[u64]bool{}
	}
}

// transform returns the event if it's not a duplicate, or empty list to drop it.
pub fn (mut t DedupeTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			h := t.compute_hash(e)
			if h in t.cache_set {
				return [] // duplicate, drop
			}
			// Evict oldest entry if cache is full
			if t.cache_set.len >= t.cache_size {
				old := t.cache[t.cache_pos]
				if old != 0 {
					t.cache_set.delete(old)
				}
			}
			t.cache[t.cache_pos] = h
			t.cache_set[h] = true
			t.cache_pos = (t.cache_pos + 1) % t.cache_size
			return [e]
		}
		else {
			return [e]
		}
	}
}

fn (t &DedupeTransform) compute_hash(e event.LogEvent) u64 {
	mut parts := []string{}
	if t.match_fields.len > 0 {
		// Match mode: hash only specified fields
		for field in t.match_fields {
			if val := e.get(field) {
				parts << '${field}=${event.value_to_string(val)}'
			} else {
				parts << '${field}=<absent>'
			}
		}
	} else {
		// Ignore mode: hash all fields except ignored ones
		mut sorted_keys := e.fields.keys()
		sorted_keys.sort()
		for key in sorted_keys {
			if key in t.ignore_fields {
				continue
			}
			val := e.fields[key] or { continue }
			parts << '${key}=${event.value_to_string(val)}'
		}
	}
	data := parts.join('|')
	return hash.sum64_string(data, 0)
}
