module sources

import event
import os
import time

// OktaSource polls the Okta System Log API for security and audit events.
// Mirrors the Okta system log API: https://developer.okta.com/docs/reference/api/system-log/
//
// Config options:
//   base_url:            Okta org URL, e.g. https://myorg.okta.com (required)
//   api_token:           Okta API token (required; fallback to OKTA_API_TOKEN env var)
//   poll_interval_secs:  Polling interval in seconds (default: 15)
//   batch_size:          Number of events per request, max 1000 (default: 100)
//   start_from:          'now' or ISO8601 timestamp (default: 'now')
pub struct OktaSource {
	base_url      string
	api_token     string
	poll_interval time.Duration = 15 * time.second
	batch_size    int    = 100
	start_from    string = 'now'
}

// OktaLogEvent represents a single event from the Okta System Log API.
pub struct OktaLogEvent {
pub:
	uuid               string
	published          string
	event_type         string
	display_message    string
	severity           string
	actor_id           string
	actor_type         string
	actor_display_name string
	outcome_result     string
}

// new_okta creates a new OktaSource from config options.
pub fn new_okta(opts map[string]string) !OktaSource {
	base_url := opts['base_url'] or {
		return error('okta source: base_url is required')
	}

	mut api_token := opts['api_token'] or { '' }
	if api_token == '' {
		api_token = os.getenv('OKTA_API_TOKEN')
	}
	if api_token == '' {
		return error('okta source: api_token is required (set in config or OKTA_API_TOKEN env var)')
	}

	mut poll_secs := 15
	if s := opts['poll_interval_secs'] {
		poll_secs = s.int()
		if poll_secs <= 0 {
			poll_secs = 15
		}
	}

	mut batch_size := 100
	if b := opts['batch_size'] {
		batch_size = b.int()
		if batch_size <= 0 {
			batch_size = 100
		}
		if batch_size > 1000 {
			batch_size = 1000
		}
	}

	start_from := opts['start_from'] or { 'now' }

	return OktaSource{
		base_url: base_url
		api_token: api_token
		poll_interval: time.Duration(i64(poll_secs) * 1_000_000_000)
		batch_size: batch_size
		start_from: start_from
	}
}

// run polls the Okta System Log API and sends events to the output channel.
pub fn (s &OktaSource) run(output chan event.Event) {
	mut since := s.start_from
	if since == 'now' {
		since = time.now().format_rfc3339()
	}

	for {
		url := build_okta_logs_url(s.base_url, s.batch_size, since)
		_ = url
		// TODO: HTTP fetch with Authorization: SSWS {api_token}
		// Parse response, emit events, update `since` cursor from last event's published timestamp
		time.sleep(s.poll_interval)
	}
}

// build_okta_logs_url constructs the Okta System Log API URL with query parameters.
pub fn build_okta_logs_url(base_url string, batch_size int, since string) string {
	return '${base_url}/api/v1/logs?limit=${batch_size}&since=${since}&sortOrder=ASCENDING'
}

// parse_okta_events parses a JSON array of Okta log events from the response body.
pub fn parse_okta_events(body string) []OktaLogEvent {
	objects := split_okta_array(body)
	mut events := []OktaLogEvent{}
	for obj in objects {
		events << OktaLogEvent{
			uuid: extract_okta_string(obj, 'uuid')
			published: extract_okta_string(obj, 'published')
			event_type: extract_okta_string(obj, 'eventType')
			display_message: extract_okta_string(obj, 'displayMessage')
			severity: validate_okta_severity(extract_okta_string(obj, 'severity'))
			actor_id: extract_okta_nested_string(obj, 'actor', 'id')
			actor_type: extract_okta_nested_string(obj, 'actor', 'type')
			actor_display_name: extract_okta_nested_string(obj, 'actor', 'displayName')
			outcome_result: extract_okta_nested_string(obj, 'outcome', 'result')
		}
	}
	return events
}

// extract_okta_string extracts a JSON string value by key from an object string.
pub fn extract_okta_string(obj string, key string) string {
	needle := '"${key}"'
	idx := obj.index(needle) or { return '' }
	// Find the colon after the key
	rest := obj[idx + needle.len..]
	colon_idx := rest.index(':') or { return '' }
	after_colon := rest[colon_idx + 1..].trim_left(' \t')
	if after_colon.len == 0 || after_colon[0] != `"` {
		return ''
	}
	// Find closing quote (handle simple case, no escaped quotes)
	end_idx := after_colon[1..].index('"') or { return '' }
	return after_colon[1..end_idx + 1]
}

// extract_okta_nested_string extracts a nested JSON string value (parent.child) from an object string.
pub fn extract_okta_nested_string(obj string, parent_key string, child_key string) string {
	needle := '"${parent_key}"'
	idx := obj.index(needle) or { return '' }
	rest := obj[idx + needle.len..]
	// Find the opening brace of the nested object
	brace_idx := rest.index('{') or { return '' }
	// Find matching closing brace
	mut depth := 0
	mut end := brace_idx
	for i := brace_idx; i < rest.len; i++ {
		if rest[i] == `{` {
			depth++
		} else if rest[i] == `}` {
			depth--
			if depth == 0 {
				end = i
				break
			}
		}
	}
	nested := rest[brace_idx..end + 1]
	return extract_okta_string(nested, child_key)
}

// split_okta_array splits a JSON array string into individual object strings.
pub fn split_okta_array(body string) []string {
	trimmed := body.trim_space()
	if trimmed.len < 2 || trimmed[0] != `[` || trimmed[trimmed.len - 1] != `]` {
		return []
	}
	inner := trimmed[1..trimmed.len - 1].trim_space()
	if inner.len == 0 {
		return []
	}

	mut objects := []string{}
	mut depth := 0
	mut start := -1
	for i := 0; i < inner.len; i++ {
		ch := inner[i]
		if ch == `{` {
			if depth == 0 {
				start = i
			}
			depth++
		} else if ch == `}` {
			depth--
			if depth == 0 && start >= 0 {
				objects << inner[start..i + 1]
				start = -1
			}
		}
	}
	return objects
}

// okta_event_to_log converts an OktaLogEvent to a LogEvent.
pub fn okta_event_to_log(evt OktaLogEvent) event.LogEvent {
	mut ev := event.new_log(evt.display_message)
	ev.meta.source_type = 'okta'
	ev.set('okta.uuid', event.Value(evt.uuid))
	ev.set('okta.event_type', event.Value(evt.event_type))
	ev.set('okta.severity', event.Value(evt.severity))
	ev.set('okta.published', event.Value(evt.published))
	ev.set('okta.actor.id', event.Value(evt.actor_id))
	ev.set('okta.actor.type', event.Value(evt.actor_type))
	ev.set('okta.actor.display_name', event.Value(evt.actor_display_name))
	ev.set('okta.outcome.result', event.Value(evt.outcome_result))
	ev.set('source_type', event.Value('okta'))
	return ev
}

// validate_okta_severity returns the normalized severity or 'INFO' for unknown values.
pub fn validate_okta_severity(s string) string {
	upper := s.to_upper()
	return match upper {
		'DEBUG' { 'DEBUG' }
		'INFO' { 'INFO' }
		'WARN' { 'WARN' }
		'ERROR' { 'ERROR' }
		else { 'INFO' }
	}
}
