module transforms

import event

fn test_exclusive_route_equality() {
	mut opts := map[string]string{}
	opts['routes.errors.condition'] = '.level == "error"'
	t := new_exclusive_route(opts) or { panic(err) }

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

fn test_exclusive_route_inequality() {
	mut opts := map[string]string{}
	opts['routes.not_error.condition'] = '.level != "error"'
	t := new_exclusive_route(opts) or { panic(err) }

	mut log := event.new_log('all good')
	log.set('level', event.Value('info'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	match result[0] {
		event.LogEvent {
			route := result[0].meta.upstream['_route'] or { panic('expected _route') }
			assert event.value_to_string(route) == 'not_error'
		}
		else {
			assert false, 'expected LogEvent'
		}
	}
}

fn test_exclusive_route_first_match_wins() {
	mut opts := map[string]string{}
	opts['routes.alpha.condition'] = '.level == "error"'
	opts['routes.beta.condition'] = '.level == "error"'
	t := new_exclusive_route(opts) or { panic(err) }

	mut log := event.new_log('test')
	log.set('level', event.Value('error'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	match result[0] {
		event.LogEvent {
			route := result[0].meta.upstream['_route'] or { panic('expected _route') }
			// Routes are sorted alphabetically, so "alpha" comes first
			assert event.value_to_string(route) == 'alpha'
		}
		else {
			assert false, 'expected LogEvent'
		}
	}
}

fn test_exclusive_route_unmatched() {
	mut opts := map[string]string{}
	opts['routes.errors.condition'] = '.level == "error"'
	t := new_exclusive_route(opts) or { panic(err) }

	mut log := event.new_log('all good')
	log.set('level', event.Value('info'))
	ev := event.Event(log)

	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	match result[0] {
		event.LogEvent {
			route := result[0].meta.upstream['_route'] or { panic('expected _route') }
			assert event.value_to_string(route) == '_unmatched'
		}
		else {
			assert false, 'expected LogEvent'
		}
	}
}

fn test_exclusive_route_missing_field() {
	mut opts := map[string]string{}
	opts['routes.has_level.condition'] = '.level == "error"'
	t := new_exclusive_route(opts) or { panic(err) }

	// Event without the 'level' field
	ev := event.Event(event.new_log('no level'))
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	match result[0] {
		event.LogEvent {
			route := result[0].meta.upstream['_route'] or { panic('expected _route') }
			assert event.value_to_string(route) == '_unmatched'
		}
		else {
			assert false, 'expected LogEvent'
		}
	}
}

fn test_exclusive_route_get_route_names() {
	mut opts := map[string]string{}
	opts['routes.errors.condition'] = '.level == "error"'
	opts['routes.warnings.condition'] = '.level == "warn"'
	t := new_exclusive_route(opts) or { panic(err) }

	names := t.get_route_names()
	assert names.len == 3, 'should have 2 routes + _unmatched'
	assert 'errors' in names
	assert 'warnings' in names
	assert '_unmatched' in names
}

fn test_exclusive_route_non_log_passthrough() {
	mut opts := map[string]string{}
	opts['routes.errors.condition'] = '.level == "error"'
	t := new_exclusive_route(opts) or { panic(err) }

	ev := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.5})
	})
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1, 'non-log events should pass through'
}

fn test_exclusive_route_requires_routes() {
	opts := map[string]string{}
	if _ := new_exclusive_route(opts) {
		assert false, 'expected error for missing routes'
	}
}

fn test_exclusive_route_exists_condition() {
	mut opts := map[string]string{}
	// Condition without == or != means "exists" check
	opts['routes.has_level'] = '.level'
	t := new_exclusive_route(opts) or { panic(err) }

	// Event with the level field
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

fn test_exclusive_route_not_equal_no_match() {
	mut opts := map[string]string{}
	opts['routes.not_debug'] = '.level != "debug"'
	t := new_exclusive_route(opts) or { panic(err) }

	// Event with level = "debug" should NOT match != "debug"
	mut log := event.new_log('test')
	log.set('level', event.Value('debug'))
	ev := event.Event(log)
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	match result[0] {
		event.LogEvent {
			route := result[0].meta.upstream['_route'] or { panic('expected _route') }
			assert event.value_to_string(route) == '_unmatched'
		}
		else { assert false }
	}
}

fn test_exclusive_route_simple_route_format() {
	// Support routes.name directly (without .condition suffix)
	mut opts := map[string]string{}
	opts['routes.important'] = '.priority == "high"'
	t := new_exclusive_route(opts) or { panic(err) }

	mut log := event.new_log('test')
	log.set('priority', event.Value('high'))
	ev := event.Event(log)
	result := t.transform(ev) or { panic(err) }
	assert result.len == 1
	match result[0] {
		event.LogEvent {
			route := result[0].meta.upstream['_route'] or { panic('expected _route') }
			assert event.value_to_string(route) == 'important'
		}
		else { assert false }
	}
}
