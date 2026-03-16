module sources

import os

fn test_new_gcp_pubsub_source_defaults() {
	s := new_gcp_pubsub_source({
		'project':      'my-project'
		'subscription': 'my-sub'
	}) or { panic(err.str()) }
	assert s.project == 'my-project'
	assert s.subscription == 'my-sub'
	assert s.endpoint == 'https://pubsub.googleapis.com'
	assert s.api_key == ''
	assert s.credentials_file == ''
	assert s.ack_deadline_secs == 600
	assert s.max_concurrency == 10
	assert s.poll_time_secs == 5
	assert s.full_response == false
	assert s.decoding_codec == 'bytes'
	assert s.message_key == 'pubsub_message_id'
	assert s.publish_time_key == 'pubsub_publish_time'
	assert s.attributes_key == 'pubsub_attributes'
}

fn test_new_gcp_pubsub_source_missing_project() {
	new_gcp_pubsub_source({
		'subscription': 'my-sub'
	}) or {
		assert err.msg().contains('project is required')
		return
	}
	assert false, 'expected error for missing project'
}

fn test_new_gcp_pubsub_source_missing_subscription() {
	new_gcp_pubsub_source({
		'project': 'my-project'
	}) or {
		assert err.msg().contains('subscription is required')
		return
	}
	assert false, 'expected error for missing subscription'
}

fn test_new_gcp_pubsub_source_custom() {
	s := new_gcp_pubsub_source({
		'project':           'custom-proj'
		'subscription':      'custom-sub'
		'endpoint':          'http://localhost:8085'
		'auth.api_key':      'my-api-key'
		'ack_deadline_secs': '300'
		'max_concurrency':   '5'
		'poll_time_secs':    '10'
		'full_response':     'true'
		'decoding.codec':    'json'
	}) or { panic(err.str()) }
	assert s.project == 'custom-proj'
	assert s.subscription == 'custom-sub'
	assert s.endpoint == 'http://localhost:8085'
	assert s.api_key == 'my-api-key'
	assert s.ack_deadline_secs == 300
	assert s.max_concurrency == 5
	assert s.poll_time_secs == 10
	assert s.full_response == true
	assert s.decoding_codec == 'json'
}

fn test_build_pubsub_pull_url() {
	url := build_pubsub_pull_url('https://pubsub.googleapis.com', 'my-project', 'my-sub')
	assert url == 'https://pubsub.googleapis.com/v1/projects/my-project/subscriptions/my-sub:pull'

	// Custom endpoint
	url2 := build_pubsub_pull_url('http://localhost:8085', 'proj', 'sub')
	assert url2 == 'http://localhost:8085/v1/projects/proj/subscriptions/sub:pull'
}

fn test_build_pubsub_ack_url() {
	url := build_pubsub_ack_url('https://pubsub.googleapis.com', 'my-project', 'my-sub')
	assert url == 'https://pubsub.googleapis.com/v1/projects/my-project/subscriptions/my-sub:acknowledge'

	url2 := build_pubsub_ack_url('http://localhost:8085', 'proj', 'sub')
	assert url2 == 'http://localhost:8085/v1/projects/proj/subscriptions/sub:acknowledge'
}

fn test_parse_pubsub_message() {
	attrs := {
		'env':    'prod'
		'region': 'us-east1'
	}
	result := parse_pubsub_message('hello world', attrs, 'msg-123', '2024-01-15T10:30:00Z')
	assert result['data'] == 'hello world'
	assert result['message_id'] == 'msg-123'
	assert result['publish_time'] == '2024-01-15T10:30:00Z'
	assert result['attribute.env'] == 'prod'
	assert result['attribute.region'] == 'us-east1'
}

fn test_parse_pubsub_message_no_attributes() {
	result := parse_pubsub_message('test data', map[string]string{}, 'msg-456', '2024-01-15T12:00:00Z')
	assert result['data'] == 'test data'
	assert result['message_id'] == 'msg-456'
	assert result['publish_time'] == '2024-01-15T12:00:00Z'
	assert result.len == 3
}

fn test_validate_gcp_pubsub_source_config() {
	// Valid config
	valid := validate_gcp_pubsub_source_config({
		'project':      'my-project'
		'subscription': 'my-sub'
	}) or { panic(err.str()) }
	assert valid == true

	// Missing project
	validate_gcp_pubsub_source_config({
		'subscription': 'my-sub'
	}) or {
		assert err.msg().contains('project is required')
		// Missing subscription
		validate_gcp_pubsub_source_config({
			'project': 'my-project'
		}) or {
			assert err.msg().contains('subscription is required')
			return
		}
		assert false, 'expected error for missing subscription'
		return
	}
	assert false, 'expected error for missing project'
}

fn test_gcp_pubsub_source_credentials_env() {
	os.setenv('GOOGLE_APPLICATION_CREDENTIALS', '/path/to/service-account.json', true)
	defer { os.unsetenv('GOOGLE_APPLICATION_CREDENTIALS') }

	s := new_gcp_pubsub_source({
		'project':      'env-proj'
		'subscription': 'env-sub'
	}) or { panic(err.str()) }
	assert s.credentials_file == '/path/to/service-account.json'
}

fn test_gcp_pubsub_source_credentials_env_override() {
	os.setenv('GOOGLE_APPLICATION_CREDENTIALS', '/path/to/env-creds.json', true)
	defer { os.unsetenv('GOOGLE_APPLICATION_CREDENTIALS') }

	// Explicit config should take precedence over env
	s := new_gcp_pubsub_source({
		'project':              'env-proj'
		'subscription':         'env-sub'
		'auth.credentials_file': '/explicit/creds.json'
	}) or { panic(err.str()) }
	assert s.credentials_file == '/explicit/creds.json'
}

fn test_gcp_pubsub_source_api_key() {
	s := new_gcp_pubsub_source({
		'project':      'key-proj'
		'subscription': 'key-sub'
		'auth.api_key': 'AIzaSyTestKey123'
	}) or { panic(err.str()) }
	assert s.api_key == 'AIzaSyTestKey123'
	assert s.credentials_file == ''
}

fn test_gcp_pubsub_source_negative_ack_deadline() {
	s := new_gcp_pubsub_source({
		'project':           'proj'
		'subscription':      'sub'
		'ack_deadline_secs': '-10'
	}) or { panic(err.str()) }
	assert s.ack_deadline_secs == 600
}

fn test_gcp_pubsub_source_negative_poll_time() {
	s := new_gcp_pubsub_source({
		'project':        'proj'
		'subscription':   'sub'
		'poll_time_secs': '-1'
	}) or { panic(err.str()) }
	assert s.poll_time_secs == 5
}

fn test_new_gcp_pubsub_source_empty_project() {
	new_gcp_pubsub_source({
		'project':      ''
		'subscription': 'sub'
	}) or {
		assert err.msg().contains('project is required')
		return
	}
	assert false, 'expected error for empty project'
}

fn test_new_gcp_pubsub_source_empty_subscription() {
	new_gcp_pubsub_source({
		'project':      'proj'
		'subscription': ''
	}) or {
		assert err.msg().contains('subscription is required')
		return
	}
	assert false, 'expected error for empty subscription'
}

fn test_new_gcp_pubsub_source_zero_ack_deadline() {
	s := new_gcp_pubsub_source({
		'project':           'proj'
		'subscription':      'sub'
		'ack_deadline_secs': '0'
	}) or { panic(err.str()) }
	assert s.ack_deadline_secs == 600
}

fn test_new_gcp_pubsub_source_zero_poll_time() {
	s := new_gcp_pubsub_source({
		'project':        'proj'
		'subscription':   'sub'
		'poll_time_secs': '0'
	}) or { panic(err.str()) }
	assert s.poll_time_secs == 5
}

fn test_validate_gcp_pubsub_source_config_empty_project() {
	validate_gcp_pubsub_source_config({
		'project':      ''
		'subscription': 'sub'
	}) or {
		assert err.msg().contains('project is required')
		return
	}
	assert false, 'expected error for empty project'
}

fn test_validate_gcp_pubsub_source_config_empty_subscription() {
	validate_gcp_pubsub_source_config({
		'project':      'proj'
		'subscription': ''
	}) or {
		assert err.msg().contains('subscription is required')
		return
	}
	assert false, 'expected error for empty subscription'
}

fn test_new_gcp_pubsub_source_full_response_false() {
	s := new_gcp_pubsub_source({
		'project':       'proj'
		'subscription':  'sub'
		'full_response': 'false'
	}) or { panic(err.str()) }
	assert s.full_response == false
}

fn test_gcp_pubsub_source_negative_max_concurrency() {
	s := new_gcp_pubsub_source({
		'project':         'proj'
		'subscription':    'sub'
		'max_concurrency': '0'
	}) or { panic(err.str()) }
	assert s.max_concurrency == 10
}
