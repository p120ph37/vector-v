module sources

import event
import os

fn test_new_okta_missing_base_url() {
	new_okta(map[string]string{}) or {
		assert err.msg().contains('base_url is required')
		return
	}
	assert false, 'expected error for missing base_url'
}

fn test_new_okta_missing_api_token() {
	os.unsetenv('OKTA_API_TOKEN')
	new_okta({
		'base_url': 'https://myorg.okta.com'
	}) or {
		assert err.msg().contains('api_token is required')
		return
	}
	assert false, 'expected error for missing api_token'
}

fn test_new_okta_minimal() {
	s := new_okta({
		'base_url':  'https://myorg.okta.com'
		'api_token': 'test-token-123'
	})!
	assert s.base_url == 'https://myorg.okta.com'
	assert s.api_token == 'test-token-123'
	assert s.batch_size == 100
	assert s.start_from == 'now'
}

fn test_new_okta_api_token_from_env() {
	os.setenv('OKTA_API_TOKEN', 'env-token-456', true)
	defer {
		os.unsetenv('OKTA_API_TOKEN')
	}
	s := new_okta({
		'base_url': 'https://myorg.okta.com'
	})!
	assert s.api_token == 'env-token-456'
}

fn test_new_okta_explicit_token_overrides_env() {
	os.setenv('OKTA_API_TOKEN', 'env-token-456', true)
	defer {
		os.unsetenv('OKTA_API_TOKEN')
	}
	s := new_okta({
		'base_url':  'https://myorg.okta.com'
		'api_token': 'explicit-token'
	})!
	assert s.api_token == 'explicit-token'
}

fn test_new_okta_custom_interval() {
	s := new_okta({
		'base_url':           'https://myorg.okta.com'
		'api_token':          'tok'
		'poll_interval_secs': '30'
	})!
	assert s.poll_interval > 0
}

fn test_new_okta_negative_interval_clamps() {
	s := new_okta({
		'base_url':           'https://myorg.okta.com'
		'api_token':          'tok'
		'poll_interval_secs': '-5'
	})!
	// Should clamp to default 15s
	assert s.poll_interval > 0
}

fn test_new_okta_custom_batch_size() {
	s := new_okta({
		'base_url':   'https://myorg.okta.com'
		'api_token':  'tok'
		'batch_size': '500'
	})!
	assert s.batch_size == 500
}

fn test_new_okta_batch_size_capped_at_1000() {
	s := new_okta({
		'base_url':   'https://myorg.okta.com'
		'api_token':  'tok'
		'batch_size': '5000'
	})!
	assert s.batch_size == 1000
}

fn test_new_okta_negative_batch_size_clamps() {
	s := new_okta({
		'base_url':   'https://myorg.okta.com'
		'api_token':  'tok'
		'batch_size': '-10'
	})!
	assert s.batch_size == 100
}

fn test_new_okta_all_options() {
	s := new_okta({
		'base_url':           'https://dev-12345.okta.com'
		'api_token':          'my-token'
		'poll_interval_secs': '60'
		'batch_size':         '200'
		'start_from':         '2024-01-01T00:00:00Z'
	})!
	assert s.base_url == 'https://dev-12345.okta.com'
	assert s.api_token == 'my-token'
	assert s.batch_size == 200
	assert s.start_from == '2024-01-01T00:00:00Z'
}

fn test_build_okta_logs_url() {
	url := build_okta_logs_url('https://myorg.okta.com', 100, 'now')
	assert url == 'https://myorg.okta.com/api/v1/logs?limit=100&since=now&sortOrder=ASCENDING'
}

fn test_build_okta_logs_url_custom() {
	url := build_okta_logs_url('https://dev-123.okta.com', 50, '2024-01-01T00:00:00Z')
	assert url == 'https://dev-123.okta.com/api/v1/logs?limit=50&since=2024-01-01T00:00:00Z&sortOrder=ASCENDING'
}

fn test_extract_okta_string_basic() {
	obj := '{"uuid":"abc-123","eventType":"user.session.start"}'
	assert extract_okta_string(obj, 'uuid') == 'abc-123'
	assert extract_okta_string(obj, 'eventType') == 'user.session.start'
}

fn test_extract_okta_string_missing() {
	obj := '{"uuid":"abc-123"}'
	assert extract_okta_string(obj, 'nonexistent') == ''
}

fn test_extract_okta_nested_string_basic() {
	obj := '{"actor":{"id":"user1","type":"User","displayName":"John Doe"}}'
	assert extract_okta_nested_string(obj, 'actor', 'id') == 'user1'
	assert extract_okta_nested_string(obj, 'actor', 'type') == 'User'
	assert extract_okta_nested_string(obj, 'actor', 'displayName') == 'John Doe'
}

fn test_extract_okta_nested_string_missing_parent() {
	obj := '{"uuid":"abc-123"}'
	assert extract_okta_nested_string(obj, 'actor', 'id') == ''
}

fn test_split_okta_array_empty() {
	assert split_okta_array('[]').len == 0
	assert split_okta_array('').len == 0
	assert split_okta_array('  ').len == 0
}

fn test_split_okta_array_single() {
	result := split_okta_array('[{"uuid":"abc"}]')
	assert result.len == 1
	assert result[0] == '{"uuid":"abc"}'
}

fn test_split_okta_array_multiple() {
	result := split_okta_array('[{"uuid":"a"},{"uuid":"b"},{"uuid":"c"}]')
	assert result.len == 3
	assert result[0] == '{"uuid":"a"}'
	assert result[1] == '{"uuid":"b"}'
	assert result[2] == '{"uuid":"c"}'
}

fn test_parse_okta_events_basic() {
	body := '[{"uuid":"evt-1","published":"2024-01-01T00:00:00Z","eventType":"user.session.start","displayMessage":"User login","severity":"INFO","actor":{"id":"user1","type":"User","displayName":"Alice"},"outcome":{"result":"SUCCESS"}}]'
	events := parse_okta_events(body)
	assert events.len == 1
	e := events[0]
	assert e.uuid == 'evt-1'
	assert e.published == '2024-01-01T00:00:00Z'
	assert e.event_type == 'user.session.start'
	assert e.display_message == 'User login'
	assert e.severity == 'INFO'
	assert e.actor_id == 'user1'
	assert e.actor_type == 'User'
	assert e.actor_display_name == 'Alice'
	assert e.outcome_result == 'SUCCESS'
}

fn test_parse_okta_events_empty() {
	events := parse_okta_events('[]')
	assert events.len == 0
}

fn test_validate_okta_severity_known() {
	assert validate_okta_severity('DEBUG') == 'DEBUG'
	assert validate_okta_severity('INFO') == 'INFO'
	assert validate_okta_severity('WARN') == 'WARN'
	assert validate_okta_severity('ERROR') == 'ERROR'
	assert validate_okta_severity('info') == 'INFO'
	assert validate_okta_severity('warn') == 'WARN'
}

fn test_validate_okta_severity_unknown() {
	assert validate_okta_severity('CRITICAL') == 'INFO'
	assert validate_okta_severity('') == 'INFO'
	assert validate_okta_severity('foo') == 'INFO'
}

fn test_okta_event_to_log() {
	evt := OktaLogEvent{
		uuid: 'evt-1'
		published: '2024-01-01T00:00:00Z'
		event_type: 'user.session.start'
		display_message: 'User login'
		severity: 'INFO'
		actor_id: 'user1'
		actor_type: 'User'
		actor_display_name: 'Alice'
		outcome_result: 'SUCCESS'
	}
	log := okta_event_to_log(evt)
	assert log.message() == 'User login'
	assert log.meta.source_type == 'okta'

	assert event.value_to_string(log.get('okta.uuid') or {
		assert false, 'expected okta.uuid field'
		return
	}) == 'evt-1'

	assert event.value_to_string(log.get('okta.event_type') or {
		assert false, 'expected okta.event_type field'
		return
	}) == 'user.session.start'

	assert event.value_to_string(log.get('okta.severity') or {
		assert false, 'expected okta.severity field'
		return
	}) == 'INFO'

	assert event.value_to_string(log.get('okta.published') or {
		assert false, 'expected okta.published field'
		return
	}) == '2024-01-01T00:00:00Z'

	assert event.value_to_string(log.get('okta.actor.id') or {
		assert false, 'expected okta.actor.id field'
		return
	}) == 'user1'

	assert event.value_to_string(log.get('okta.actor.type') or {
		assert false, 'expected okta.actor.type field'
		return
	}) == 'User'

	assert event.value_to_string(log.get('okta.actor.display_name') or {
		assert false, 'expected okta.actor.display_name field'
		return
	}) == 'Alice'

	assert event.value_to_string(log.get('okta.outcome.result') or {
		assert false, 'expected okta.outcome.result field'
		return
	}) == 'SUCCESS'

	assert event.value_to_string(log.get('source_type') or {
		assert false, 'expected source_type field'
		return
	}) == 'okta'
}
