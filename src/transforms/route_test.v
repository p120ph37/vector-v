module transforms

import event

fn test_route_single_match() {
	mut opts := map[string]string{}
	opts['routes.errors.condition'] = '.level == "error"'
	t := new_route(opts) or { panic(err) }

	mut log := event.new_log('something broke')
	log.set('level', event.Value('error'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	match result[0] {
		event.LogEvent {
			route := result[0].meta.upstream['_route'] or { panic('expected _route') }
			assert event.value_to_string(route) == 'errors'
		}
		else {
			assert false, 'expected LogEvent'
		}
	}
}

fn test_route_multiple_matches() {
	mut opts := map[string]string{}
	opts['routes.errors.condition'] = '.level == "error"'
	opts['routes.important.condition'] = '.priority == "high"'
	t := new_route(opts) or { panic(err) }

	mut log := event.new_log('critical error')
	log.set('level', event.Value('error'))
	log.set('priority', event.Value('high'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	// Should match BOTH routes
	assert result.len == 2

	mut route_names := []string{}
	for r in result {
		match r {
			event.LogEvent {
				route := r.meta.upstream['_route'] or { panic('expected _route') }
				route_names << event.value_to_string(route)
			}
			else { assert false }
		}
	}
	assert 'errors' in route_names
	assert 'important' in route_names
}

fn test_route_no_match_drops_event() {
	mut opts := map[string]string{}
	opts['routes.errors.condition'] = '.level == "error"'
	t := new_route(opts) or { panic(err) }

	mut log := event.new_log('all good')
	log.set('level', event.Value('info'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	// No routes match — event is dropped
	assert result.len == 0
}

fn test_route_inequality_condition() {
	mut opts := map[string]string{}
	opts['routes.not_debug.condition'] = '.level != "debug"'
	t := new_route(opts) or { panic(err) }

	mut log := event.new_log('info message')
	log.set('level', event.Value('info'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	match result[0] {
		event.LogEvent {
			route := result[0].meta.upstream['_route'] or { panic('expected _route') }
			assert event.value_to_string(route) == 'not_debug'
		}
		else { assert false }
	}
}

fn test_route_inequality_no_match() {
	mut opts := map[string]string{}
	opts['routes.not_debug.condition'] = '.level != "debug"'
	t := new_route(opts) or { panic(err) }

	mut log := event.new_log('debug message')
	log.set('level', event.Value('debug'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	// level == "debug" does NOT match != "debug", so event is dropped
	assert result.len == 0
}

fn test_route_exists_condition() {
	mut opts := map[string]string{}
	opts['routes.has_level'] = '.level'
	t := new_route(opts) or { panic(err) }

	mut log := event.new_log('test')
	log.set('level', event.Value('info'))
	ev := event.Event(log)
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	match result[0] {
		event.LogEvent {
			route := result[0].meta.upstream['_route'] or { panic('expected _route') }
			assert event.value_to_string(route) == 'has_level'
		}
		else { assert false }
	}
}

fn test_route_exists_condition_missing_field() {
	mut opts := map[string]string{}
	opts['routes.has_level'] = '.level'
	t := new_route(opts) or { panic(err) }

	ev := event.Event(event.new_log('no level field'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 0
}

fn test_route_missing_field() {
	mut opts := map[string]string{}
	opts['routes.errors.condition'] = '.level == "error"'
	t := new_route(opts) or { panic(err) }

	ev := event.Event(event.new_log('no level'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 0
}

fn test_route_requires_routes() {
	opts := map[string]string{}
	if _ := new_route(opts) {
		assert false, 'expected error for missing routes'
	}
}

fn test_route_non_log_passthrough() {
	mut opts := map[string]string{}
	opts['routes.errors.condition'] = '.level == "error"'
	t := new_route(opts) or { panic(err) }

	ev := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.5})
	})
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1, 'non-log events should pass through'
}

fn test_route_get_route_names() {
	mut opts := map[string]string{}
	opts['routes.errors.condition'] = '.level == "error"'
	opts['routes.warnings.condition'] = '.level == "warn"'
	t := new_route(opts) or { panic(err) }

	names := t.get_route_names()
	assert names.len == 2
	assert 'errors' in names
	assert 'warnings' in names
}

fn test_route_get_route_names_no_unmatched() {
	mut opts := map[string]string{}
	opts['routes.alpha.condition'] = '.level == "error"'
	t := new_route(opts) or { panic(err) }

	names := t.get_route_names()
	// Route does NOT have _unmatched, unlike exclusive_route
	assert '_unmatched' !in names
}

fn test_route_simple_format() {
	// Support routes.name directly (without .condition suffix)
	mut opts := map[string]string{}
	opts['routes.important'] = '.priority == "high"'
	t := new_route(opts) or { panic(err) }

	mut log := event.new_log('test')
	log.set('priority', event.Value('high'))
	ev := event.Event(log)
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
}

fn test_route_three_routes_all_match() {
	mut opts := map[string]string{}
	opts['routes.has_level'] = '.level'
	opts['routes.has_host'] = '.host'
	opts['routes.has_env'] = '.env'
	t := new_route(opts) or { panic(err) }

	mut log := event.new_log('test')
	log.set('level', event.Value('info'))
	log.set('host', event.Value('web-01'))
	log.set('env', event.Value('prod'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 3

	mut route_names := []string{}
	for r in result {
		match r {
			event.LogEvent {
				route := r.meta.upstream['_route'] or { panic('expected _route') }
				route_names << event.value_to_string(route)
			}
			else { assert false }
		}
	}
	assert 'has_level' in route_names
	assert 'has_host' in route_names
	assert 'has_env' in route_names
}

fn test_route_three_routes_partial_match() {
	mut opts := map[string]string{}
	opts['routes.has_level'] = '.level'
	opts['routes.has_host'] = '.host'
	opts['routes.has_env'] = '.env'
	t := new_route(opts) or { panic(err) }

	mut log := event.new_log('test')
	log.set('level', event.Value('info'))
	// No host or env fields
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	match result[0] {
		event.LogEvent {
			route := result[0].meta.upstream['_route'] or { panic('expected _route') }
			assert event.value_to_string(route) == 'has_level'
		}
		else { assert false }
	}
}
