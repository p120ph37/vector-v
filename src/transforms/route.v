module transforms

import event

// RouteTransform routes each event to ALL matching named outputs.
// Unlike exclusive_route (first match only), route sends copies of the
// event to every route whose condition matches.
// Mirrors Vector's route transform.
//
// Config options:
//   routes.<name>.condition — VRL condition string for each route
//
// Downstream components reference outputs as "<transform_id>.<route_name>"
// in their `inputs` field. Events matching multiple routes are duplicated
// to each matching output. If no routes match, the event is dropped.
pub struct RouteTransform {
	routes []RouteEntry
}

struct RouteEntry {
	name  string
	field string // parsed from condition: field name
	op    string // == or !=
	value string // expected value
}

// new_route creates a new RouteTransform from config options.
pub fn new_route(opts map[string]string) !RouteTransform {
	mut routes := []RouteEntry{}

	// Parse routes.<name>.condition from options
	// Also support routes.<name> directly for simple conditions
	mut route_names := map[string]string{}
	for k, v in opts {
		if k.starts_with('routes.') {
			rest := k[7..]
			// routes.foo.condition or routes.foo
			if rest.ends_with('.condition') {
				name := rest[..rest.len - 10] // strip ".condition"
				route_names[name] = v
			} else if !rest.contains('.') {
				route_names[rest] = v
			}
		}
	}

	// Sort route names to maintain deterministic order
	mut names := route_names.keys()
	names.sort()

	for name in names {
		condition := route_names[name]
		r := parse_route_entry(name, condition)
		routes << r
	}

	if routes.len == 0 {
		return error('route transform requires at least one route')
	}

	return RouteTransform{
		routes: routes
	}
}

// transform routes the event to ALL matching route outputs.
// Returns copies of the event, each tagged with a different route name.
// If no routes match, the event is dropped (empty list returned).
pub fn (t &RouteTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			mut result := []event.Event{}
			for route in t.routes {
				if match_route_entry(route, e) {
					mut tagged := event.LogEvent{
						fields: e.fields.clone()
						meta: event.EventMetadata{
							source_type: e.meta.source_type
							ingest_timestamp: e.meta.ingest_timestamp
							upstream: e.meta.upstream.clone()
						}
					}
					tagged.meta.upstream['_route'] = event.Value(route.name)
					result << event.Event(tagged)
				}
			}
			// If no routes match, event is dropped
			return result
		}
		else {
			// Non-log events pass through unchanged
			return [e]
		}
	}
}

// get_route_names returns the names of all configured routes.
pub fn (t &RouteTransform) get_route_names() []string {
	mut names := []string{cap: t.routes.len}
	for r in t.routes {
		names << r.name
	}
	return names
}

fn parse_route_entry(name string, condition string) RouteEntry {
	// Parse simple conditions: .field == "value" or .field != "value"
	if condition.contains('!=') {
		parts := condition.split('!=')
		if parts.len == 2 {
			return RouteEntry{
				name: name
				field: parts[0].trim_space().trim_left('.')
				op: '!='
				value: parts[1].trim_space().trim('"').trim("'")
			}
		}
	}
	if condition.contains('==') {
		parts := condition.split('==')
		if parts.len == 2 {
			return RouteEntry{
				name: name
				field: parts[0].trim_space().trim_left('.')
				op: '=='
				value: parts[1].trim_space().trim('"').trim("'")
			}
		}
	}
	// Fallback: existence check (field is truthy)
	return RouteEntry{
		name: name
		field: condition.trim_space().trim_left('.')
		op: 'exists'
		value: ''
	}
}

fn match_route_entry(r RouteEntry, e event.LogEvent) bool {
	match r.op {
		'==' {
			if val := e.get(r.field) {
				return event.value_to_string(val) == r.value
			}
			return false
		}
		'!=' {
			if val := e.get(r.field) {
				return event.value_to_string(val) != r.value
			}
			return true
		}
		'exists' {
			if _ := e.get(r.field) {
				return true
			}
			return false
		}
		else {
			return false
		}
	}
}
