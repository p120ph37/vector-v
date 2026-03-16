module transforms

import event

// TagCardinalityLimitTransform limits the cardinality of metric tags.
// Mirrors Vector's tag_cardinality_limit transform.
//
// When a tag key has more distinct values than the configured limit,
// events with new (unseen) tag values are either dropped or have
// the offending tag replaced with a placeholder value.
//
// Config options:
//   value_limit:    Max distinct values per tag key (default: 500)
//   mode:           "probabilistic" or "exact" (default: exact)
//   limit_exceeded_action:  "drop_tag" or "drop_event" (default: drop_tag)
pub struct TagCardinalityLimitTransform {
	value_limit int
	action      CardinalityAction
mut:
	tag_values  map[string]map[string]bool // tag_key -> set of seen values
}

enum CardinalityAction {
	drop_tag
	drop_event
}

// new_tag_cardinality_limit creates a new TagCardinalityLimitTransform from config options.
pub fn new_tag_cardinality_limit(opts map[string]string) !TagCardinalityLimitTransform {
	mut value_limit := 500
	if vl := opts['value_limit'] {
		value_limit = vl.int()
		if value_limit <= 0 {
			value_limit = 500
		}
	}

	action := match opts['limit_exceeded_action'] or { 'drop_tag' } {
		'drop_event' { CardinalityAction.drop_event }
		else { CardinalityAction.drop_tag }
	}

	return TagCardinalityLimitTransform{
		value_limit: value_limit
		action: action
	}
}

// transform checks metric tag cardinality and enforces limits.
pub fn (mut t TagCardinalityLimitTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.Metric {
			if e.tags.len == 0 {
				return [e]
			}

			mut exceeded := false
			mut tags_to_drop := []string{}

			for tag_key, tag_val in e.tags {
				// Initialize tracking for this tag key if needed
				if tag_key !in t.tag_values {
					t.tag_values[tag_key] = map[string]bool{}
				}

				mut seen := t.tag_values[tag_key].clone()

				if tag_val in seen {
					// Already tracked — fine
					continue
				}

				// New value — check if we're at the limit
				if seen.len >= t.value_limit {
					exceeded = true
					match t.action {
						.drop_event {
							return []
						}
						.drop_tag {
							tags_to_drop << tag_key
						}
					}
				} else {
					seen[tag_val] = true
					t.tag_values[tag_key] = seen.clone()
				}
			}

			if tags_to_drop.len > 0 {
				mut new_metric := event.Metric{
					name: e.name
					namespace: e.namespace
					kind: e.kind
					value: e.value
					timestamp: e.timestamp
					tags: e.tags.clone()
					meta: e.meta
				}
				for tk in tags_to_drop {
					new_metric.tags.delete(tk)
				}
				return [event.Event(new_metric)]
			}

			return [e]
		}
		else {
			// Non-metric events pass through unchanged
			return [e]
		}
	}
}

// tag_value_count returns the number of distinct values tracked for a tag key.
pub fn (t &TagCardinalityLimitTransform) tag_value_count(key string) int {
	if vals := t.tag_values[key] {
		return vals.len
	}
	return 0
}
