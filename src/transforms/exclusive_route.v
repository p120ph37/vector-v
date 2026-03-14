module transforms

import event

// ExclusiveRouteTransform routes each event to exactly one named output
// based on the first matching condition. Events that match no route are
// sent to the "_unmatched" output.
// Mirrors Vector's exclusive_route (formerly "swimlanes") transform.
//
// Config options:
//   routes.<name>.condition — VRL condition string for each route
//
// Downstream components reference outputs as "<transform_id>.<route_name>"
// in their `inputs` field. Events are sent to the first matching route only.
pub struct ExclusiveRouteTransform {
	routes []Route
}

struct Route {
	name  string
	field string // parsed from condition: field name
	op    string // == or !=
	value string // expected value
}

// new_exclusive_route creates a new ExclusiveRouteTransform from config options.
pub fn new_exclusive_route(opts map[string]string) !ExclusiveRouteTransform {
	mut routes := []Route{}

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
		r := parse_route_condition(name, condition)
		routes << r
	}

	if routes.len == 0 {
		return error('exclusive_route transform requires at least one route')
	}

	return ExclusiveRouteTransform{
		routes: routes
	}
}

// transform routes the event to the first matching route output.
// Returns the event tagged with metadata about which route it matched.
// The topology layer uses the route name to dispatch to the correct output.
pub fn (t &ExclusiveRouteTransform) transform(e event.Event) ![]event.Event {
	match e {
		event.LogEvent {
			for route in t.routes {
				if match_route(route, e) {
					// Tag the event with the route name in metadata
					mut tagged := e
					tagged.meta.upstream['_route'] = event.Value(route.name)
					return [event.Event(tagged)]
				}
			}
			// No route matched — tag as _unmatched
			mut tagged := e
			tagged.meta.upstream['_route'] = event.Value('_unmatched')
			return [event.Event(tagged)]
		}
		else {
			return [e]
		}
	}
}

// get_route_names returns the names of all configured routes.
pub fn (t &ExclusiveRouteTransform) get_route_names() []string {
	mut names := []string{cap: t.routes.len + 1}
	for r in t.routes {
		names << r.name
	}
	names << '_unmatched'
	return names
}

fn parse_route_condition(name string, condition string) Route {
	// Parse simple conditions: .field == "value" or .field != "value"
	if condition.contains('!=') {
		parts := condition.split('!=')
		if parts.len == 2 {
			return Route{
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
			return Route{
				name: name
				field: parts[0].trim_space().trim_left('.')
				op: '=='
				value: parts[1].trim_space().trim('"').trim("'")
			}
		}
	}
	// Fallback: existence check (field is truthy)
	return Route{
		name: name
		field: condition.trim_space().trim_left('.')
		op: 'exists'
		value: ''
	}
}

fn match_route(r Route, e event.LogEvent) bool {
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
