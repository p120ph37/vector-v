module transforms

import event
import time

// ReduceTransform accumulates events and merges them based on grouping criteria.
// Mirrors Vector's reduce transform (src/transforms/reduce/).
//
// Events are grouped by the `group_by` fields and accumulated. Groups are
// flushed when:
//   - `ends_when` condition matches
//   - `starts_when` condition matches (flushes previous, starts new)
//   - `max_events` is reached for a group
//   - `expire_after_ms` of inactivity elapses
pub struct ReduceTransform {
	group_by         []string
	starts_when      string // simple field condition
	ends_when        string // simple field condition
	expire_after     time.Duration
	max_events       int // 0 = unlimited
	merge_strategies map[string]MergeStrategy
mut:
	groups       map[string]ReduceState
	timers       map[string]time.Time
	event_counts map[string]int
}

struct ReduceState {
mut:
	base       event.LogEvent
	arrays     map[string][]event.Value // for array strategy
	sums       map[string]f64           // for sum strategy
	mins       map[string]f64           // for min strategy
	maxs       map[string]f64           // for max strategy
	concats    map[string]string        // for concat strategy
	concat_nls map[string]string        // for concat_newline strategy
	flat_uniq  map[string]map[string]bool // for flat_unique strategy
}

pub enum MergeStrategy {
	discard
	retain
	array_
	concat
	concat_newline
	concat_raw
	sum
	max
	min
	flat_unique
	shortest_array
	longest_array
}

fn parse_merge_strategy(s string) MergeStrategy {
	return match s {
		'discard' { MergeStrategy.discard }
		'retain' { MergeStrategy.retain }
		'array' { MergeStrategy.array_ }
		'concat' { MergeStrategy.concat }
		'concat_newline' { MergeStrategy.concat_newline }
		'concat_raw' { MergeStrategy.concat_raw }
		'sum' { MergeStrategy.sum }
		'max' { MergeStrategy.max }
		'min' { MergeStrategy.min }
		'flat_unique' { MergeStrategy.flat_unique }
		'shortest_array' { MergeStrategy.shortest_array }
		'longest_array' { MergeStrategy.longest_array }
		else { MergeStrategy.retain }
	}
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

	mut max_events := 0
	if me := opts['max_events'] {
		max_events = me.int()
	}

	mut merge_strategies := map[string]MergeStrategy{}
	// Parse merge_strategies.field = strategy from options
	for k, v in opts {
		if k.starts_with('merge_strategies.') {
			field := k[17..] // len("merge_strategies.")
			merge_strategies[field] = parse_merge_strategy(v)
		}
	}

	return ReduceTransform{
		group_by: group_by
		starts_when: opts['starts_when'] or { '' }
		ends_when: opts['ends_when'] or { '' }
		expire_after: time.Duration(i64(expire_ms) * 1_000_000)
		max_events: max_events
		merge_strategies: merge_strategies
		groups: map[string]ReduceState{}
		timers: map[string]time.Time{}
		event_counts: map[string]int{}
	}
}

// transform processes an event through the reduce logic.
pub fn (mut t ReduceTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			group_key := t.compute_group_key(e)
			now := time.now()

			mut result := []event.Event{}
			t.flush_expired(now, mut result)

			// starts_when: flush existing group, start new one
			if t.starts_when.len > 0 && t.check_condition(t.starts_when, e) {
				if _ := t.groups[group_key] {
					merged := t.finalize_group(group_key)
					result << event.Event(merged)
				}
				t.init_group(group_key, e)
				t.timers[group_key] = now
				t.event_counts[group_key] = 1
				return result
			}

			// ends_when: merge current event, flush
			if t.ends_when.len > 0 && t.check_condition(t.ends_when, e) {
				if _ := t.groups[group_key] {
					t.merge_into_group(group_key, e)
					merged := t.finalize_group(group_key)
					result << event.Event(merged)
				} else {
					result << event.Event(e)
				}
				return result
			}

			// Accumulate
			if _ := t.groups[group_key] {
				t.merge_into_group(group_key, e)
				t.event_counts[group_key] = (t.event_counts[group_key] or { 0 }) + 1
			} else {
				t.init_group(group_key, e)
				t.event_counts[group_key] = 1
			}
			t.timers[group_key] = now

			// max_events check
			if t.max_events > 0 {
				count := t.event_counts[group_key] or { 0 }
				if count >= t.max_events {
					merged := t.finalize_group(group_key)
					result << event.Event(merged)
				}
			}

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
	for key, _ in t.groups {
		merged := t.finalize_group(key)
		result << event.Event(merged)
	}
	t.groups.clear()
	t.timers.clear()
	t.event_counts.clear()
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

fn (t &ReduceTransform) check_condition(condition string, e event.LogEvent) bool {
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
	if condition.contains('!=') {
		parts := condition.split('!=')
		if parts.len == 2 {
			field := parts[0].trim_space().trim_left('.')
			expected := parts[1].trim_space().trim('"').trim("'")
			if val := e.get(field) {
				return event.value_to_string(val) != expected
			}
			return true
		}
	}
	return false
}

fn (mut t ReduceTransform) init_group(key string, e event.LogEvent) {
	mut state := ReduceState{
		base: e
	}
	// Initialize strategy accumulators
	for field, strategy in t.merge_strategies {
		if val := e.get(field) {
			match strategy {
				.array_ {
					state.arrays[field] = [val]
				}
				.sum {
					state.sums[field] = value_to_f64(val)
				}
				.min {
					state.mins[field] = value_to_f64(val)
				}
				.max {
					state.maxs[field] = value_to_f64(val)
				}
				.concat {
					state.concats[field] = event.value_to_string(val)
				}
				.concat_newline {
					state.concat_nls[field] = event.value_to_string(val)
				}
				.concat_raw {
					state.concats[field] = event.value_to_string(val)
				}
				.flat_unique {
					mut seen := map[string]bool{}
					seen[event.value_to_string(val)] = true
					state.flat_uniq[field] = seen.clone()
				}
				else {}
			}
		}
	}
	t.groups[key] = state
}

fn (mut t ReduceTransform) merge_into_group(key string, e event.LogEvent) {
	mut state := t.groups[key] or { return }

	for field, val in e.fields {
		strategy := t.merge_strategies[field] or { MergeStrategy.retain }
		match strategy {
			.discard {
				// keep existing
			}
			.retain {
				state.base.set(field, val)
			}
			.array_ {
				if field in state.arrays {
					state.arrays[field] << val
				} else {
					state.arrays[field] = [val]
				}
			}
			.sum {
				state.sums[field] = (state.sums[field] or { 0.0 }) + value_to_f64(val)
			}
			.min {
				v := value_to_f64(val)
				existing := state.mins[field] or { v }
				if v < existing {
					state.mins[field] = v
				}
			}
			.max {
				v := value_to_f64(val)
				existing := state.maxs[field] or { v }
				if v > existing {
					state.maxs[field] = v
				}
			}
			.concat {
				existing := state.concats[field] or { '' }
				state.concats[field] = existing + ' ' + event.value_to_string(val)
			}
			.concat_newline {
				existing := state.concat_nls[field] or { '' }
				state.concat_nls[field] = existing + '\n' + event.value_to_string(val)
			}
			.concat_raw {
				existing := state.concats[field] or { '' }
				state.concats[field] = existing + event.value_to_string(val)
			}
			.flat_unique {
				s := event.value_to_string(val)
				if field in state.flat_uniq {
					mut existing_map := state.flat_uniq[field].clone()
					existing_map[s] = true
					state.flat_uniq[field] = existing_map.clone()
				} else {
					mut seen := map[string]bool{}
					seen[s] = true
					state.flat_uniq[field] = seen.clone()
				}
			}
			.shortest_array {
				match val {
					[]event.Value {
						if existing := state.base.get(field) {
							match existing {
								[]event.Value {
									if val.len < existing.len {
										state.base.set(field, event.Value(val))
									}
								}
								else {
									state.base.set(field, event.Value(val))
								}
							}
						} else {
							state.base.set(field, event.Value(val))
						}
					}
					else {}
				}
			}
			.longest_array {
				match val {
					[]event.Value {
						if existing := state.base.get(field) {
							match existing {
								[]event.Value {
									if val.len > existing.len {
										state.base.set(field, event.Value(val))
									}
								}
								else {
									state.base.set(field, event.Value(val))
								}
							}
						} else {
							state.base.set(field, event.Value(val))
						}
					}
					else {}
				}
			}
		}
	}

	t.groups[key] = state
}

fn (mut t ReduceTransform) finalize_group(key string) event.LogEvent {
	state := t.groups[key] or {
		return event.new_log('')
	}
	mut result := state.base

	// Apply accumulated strategy values
	for field, arr in state.arrays {
		result.set(field, event.Value(arr))
	}
	for field, s in state.sums {
		if s == f64(int(s)) {
			result.set(field, event.Value(int(s)))
		} else {
			result.set(field, event.Value(event.Float(s)))
		}
	}
	for field, m in state.mins {
		if m == f64(int(m)) {
			result.set(field, event.Value(int(m)))
		} else {
			result.set(field, event.Value(event.Float(m)))
		}
	}
	for field, m in state.maxs {
		if m == f64(int(m)) {
			result.set(field, event.Value(int(m)))
		} else {
			result.set(field, event.Value(event.Float(m)))
		}
	}
	for field, s in state.concats {
		result.set(field, event.Value(s))
	}
	for field, s in state.concat_nls {
		result.set(field, event.Value(s))
	}
	for field, seen in state.flat_uniq {
		mut vals := []event.Value{cap: seen.len}
		for v, _ in seen {
			vals << event.Value(v)
		}
		result.set(field, event.Value(vals))
	}

	t.groups.delete(key)
	t.timers.delete(key)
	t.event_counts.delete(key)
	return result
}

fn (mut t ReduceTransform) flush_expired(now time.Time, mut result []event.Event) {
	mut expired_keys := []string{}
	for key, timer in t.timers {
		if now - timer > t.expire_after {
			expired_keys << key
		}
	}
	for key in expired_keys {
		merged := t.finalize_group(key)
		result << event.Event(merged)
	}
}

fn value_to_f64(v event.Value) f64 {
	match v {
		int { return f64(v) }
		event.Float { return f64(v) }
		string { return v.f64() }
		else { return 0.0 }
	}
}
