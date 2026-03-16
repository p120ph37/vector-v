module sources

// Tests for DockerLogsSource: constructor, log line parsing, container filtering,
// and metadata building. No actual Docker daemon connection is needed.

fn test_new_docker_logs_defaults() {
	s := new_docker_logs(map[string]string{})
	assert s.docker_host == 'unix:///var/run/docker.sock'
	assert s.include_containers.len == 0
	assert s.exclude_containers.len == 0
	assert s.include_images.len == 0
	assert s.include_labels.len == 0
	assert s.auto_partial_merge == true
	assert s.host_key == 'host'
	assert s.partial_merge_field == '_partial'
	assert s.retry_backoff_secs == 2.0
	assert s.since == ''
}

fn test_new_docker_logs_custom_docker_host() {
	s := new_docker_logs({
		'docker_host': 'tcp://localhost:2375'
	})
	assert s.docker_host == 'tcp://localhost:2375'
}

fn test_new_docker_logs_custom_filters() {
	s := new_docker_logs({
		'include_containers': 'web, api, worker'
		'exclude_containers': 'sidecar'
		'include_images':     'nginx, redis'
		'include_labels':     'env=prod, tier'
	})
	assert s.include_containers == ['web', 'api', 'worker']
	assert s.exclude_containers == ['sidecar']
	assert s.include_images == ['nginx', 'redis']
	assert s.include_labels == ['env=prod', 'tier']
}

fn test_new_docker_logs_empty_filter_items_skipped() {
	s := new_docker_logs({
		'include_containers': 'web, , api, '
	})
	assert s.include_containers == ['web', 'api']
}

fn test_new_docker_logs_auto_partial_merge_false() {
	s := new_docker_logs({
		'auto_partial_merge': 'false'
	})
	assert s.auto_partial_merge == false
}

fn test_new_docker_logs_custom_host_key() {
	s := new_docker_logs({
		'host_key': 'hostname'
	})
	assert s.host_key == 'hostname'
}

fn test_new_docker_logs_custom_retry_backoff() {
	s := new_docker_logs({
		'retry_backoff_secs': '5.0'
	})
	assert s.retry_backoff_secs == 5.0
}

fn test_new_docker_logs_invalid_retry_backoff_uses_default() {
	s := new_docker_logs({
		'retry_backoff_secs': '-1'
	})
	assert s.retry_backoff_secs == 2.0
}

fn test_new_docker_logs_since() {
	s := new_docker_logs({
		'since': '2024-01-01T00:00:00Z'
	})
	assert s.since == '2024-01-01T00:00:00Z'
}

fn test_new_docker_logs_all_options() {
	s := new_docker_logs({
		'docker_host':         'tcp://10.0.0.1:2375'
		'include_containers':  'app'
		'exclude_containers':  'debug'
		'include_images':      'myimage'
		'include_labels':      'env=staging'
		'auto_partial_merge':  'false'
		'host_key':            'node'
		'partial_merge_field': '_partial_flag'
		'retry_backoff_secs':  '10'
		'since':               '1704067200'
	})
	assert s.docker_host == 'tcp://10.0.0.1:2375'
	assert s.include_containers == ['app']
	assert s.exclude_containers == ['debug']
	assert s.include_images == ['myimage']
	assert s.include_labels == ['env=staging']
	assert s.auto_partial_merge == false
	assert s.host_key == 'node'
	assert s.partial_merge_field == '_partial_flag'
	assert s.retry_backoff_secs == 10.0
	assert s.since == '1704067200'
}

// --- parse_docker_log_line tests ---

fn test_parse_docker_log_line_stdout() {
	ts, stream, msg := parse_docker_log_line('2024-01-15T10:30:00.123456789Z stdout F hello world') or {
		assert false, 'expected parse to succeed'
		return
	}
	assert ts == '2024-01-15T10:30:00.123456789Z'
	assert stream == 'stdout'
	assert msg == 'hello world'
}

fn test_parse_docker_log_line_stderr() {
	ts, stream, msg := parse_docker_log_line('2024-06-01T00:00:00Z stderr F error occurred') or {
		assert false, 'expected parse to succeed'
		return
	}
	assert ts == '2024-06-01T00:00:00Z'
	assert stream == 'stderr'
	assert msg == 'error occurred'
}

fn test_parse_docker_log_line_partial() {
	ts, stream, msg := parse_docker_log_line('2024-01-15T10:30:00Z stdout P partial line') or {
		assert false, 'expected parse to succeed'
		return
	}
	assert ts == '2024-01-15T10:30:00Z'
	assert stream == 'stdout'
	assert msg == 'partial line'
}

fn test_parse_docker_log_line_without_fp_indicator() {
	// Some Docker versions or log drivers may not include F/P
	ts, stream, msg := parse_docker_log_line('2024-01-15T10:30:00Z stdout message without indicator') or {
		assert false, 'expected parse to succeed'
		return
	}
	assert ts == '2024-01-15T10:30:00Z'
	assert stream == 'stdout'
	assert msg == 'message without indicator'
}

fn test_parse_docker_log_line_empty_message() {
	ts, stream, msg := parse_docker_log_line('2024-01-15T10:30:00Z stdout F ') or {
		assert false, 'expected parse to succeed'
		return
	}
	assert ts == '2024-01-15T10:30:00Z'
	assert stream == 'stdout'
	assert msg == ''
}

fn test_parse_docker_log_line_invalid_no_spaces() {
	if _, _, _ := parse_docker_log_line('nospaces') {
		assert false, 'expected parse to fail for input without spaces'
	}
}

fn test_parse_docker_log_line_invalid_bad_timestamp() {
	if _, _, _ := parse_docker_log_line('notadate stdout F hello') {
		assert false, 'expected parse to fail for bad timestamp'
	}
}

fn test_parse_docker_log_line_invalid_bad_stream() {
	if _, _, _ := parse_docker_log_line('2024-01-15T10:30:00Z badstream F hello') {
		assert false, 'expected parse to fail for bad stream'
	}
}

fn test_parse_docker_log_line_empty_string() {
	if _, _, _ := parse_docker_log_line('') {
		assert false, 'expected parse to fail for empty string'
	}
}

fn test_parse_docker_log_line_only_timestamp() {
	if _, _, _ := parse_docker_log_line('2024-01-15T10:30:00Z') {
		assert false, 'expected parse to fail for timestamp only'
	}
}

fn test_parse_docker_log_line_message_with_spaces() {
	ts, stream, msg := parse_docker_log_line('2024-01-15T10:30:00Z stdout F multi word message with spaces') or {
		assert false, 'expected parse to succeed'
		return
	}
	assert ts == '2024-01-15T10:30:00Z'
	assert stream == 'stdout'
	assert msg == 'multi word message with spaces'
}

fn test_parse_docker_log_line_json_message() {
	ts, stream, msg := parse_docker_log_line('2024-01-15T10:30:00Z stdout F {"level":"info","msg":"started"}') or {
		assert false, 'expected parse to succeed'
		return
	}
	assert ts == '2024-01-15T10:30:00Z'
	assert stream == 'stdout'
	assert msg == '{"level":"info","msg":"started"}'
}

// --- matches_container_filter tests ---

fn test_matches_container_filter_no_filters() {
	assert matches_container_filter('web', 'nginx', map[string]string{}, []string{},
		[]string{}, []string{}, []string{}) == true
}

fn test_matches_container_filter_include_containers_match() {
	assert matches_container_filter('web', 'nginx', map[string]string{}, ['web'],
		[]string{}, []string{}, []string{}) == true
}

fn test_matches_container_filter_include_containers_no_match() {
	assert matches_container_filter('api', 'nginx', map[string]string{}, ['web'],
		[]string{}, []string{}, []string{}) == false
}

fn test_matches_container_filter_exclude_containers() {
	assert matches_container_filter('sidecar', 'envoy', map[string]string{}, []string{},
		['sidecar'], []string{}, []string{}) == false
}

fn test_matches_container_filter_exclude_takes_priority() {
	// Container is in both include and exclude — exclude wins
	assert matches_container_filter('web', 'nginx', map[string]string{}, ['web'],
		['web'], []string{}, []string{}) == false
}

fn test_matches_container_filter_include_images_match() {
	assert matches_container_filter('web', 'nginx:latest', map[string]string{}, []string{},
		[]string{}, ['nginx:latest'], []string{}) == true
}

fn test_matches_container_filter_include_images_no_match() {
	assert matches_container_filter('web', 'nginx:latest', map[string]string{}, []string{},
		[]string{}, ['redis'], []string{}) == false
}

fn test_matches_container_filter_include_images_prefix_match() {
	assert matches_container_filter('web', 'nginx:latest', map[string]string{}, []string{},
		[]string{}, ['nginx'], []string{}) == true
}

fn test_matches_container_filter_include_labels_key_only() {
	labels := {
		'env': 'prod'
	}
	assert matches_container_filter('web', 'nginx', labels, []string{}, []string{},
		[]string{}, ['env']) == true
}

fn test_matches_container_filter_include_labels_key_value() {
	labels := {
		'env': 'prod'
	}
	assert matches_container_filter('web', 'nginx', labels, []string{}, []string{},
		[]string{}, ['env=prod']) == true
}

fn test_matches_container_filter_include_labels_key_value_mismatch() {
	labels := {
		'env': 'staging'
	}
	assert matches_container_filter('web', 'nginx', labels, []string{}, []string{},
		[]string{}, ['env=prod']) == false
}

fn test_matches_container_filter_include_labels_missing_key() {
	labels := {
		'tier': 'frontend'
	}
	assert matches_container_filter('web', 'nginx', labels, []string{}, []string{},
		[]string{}, ['env']) == false
}

fn test_matches_container_filter_combined_filters() {
	labels := {
		'env': 'prod'
	}
	// Must match include_containers AND include_images AND include_labels
	assert matches_container_filter('web', 'nginx', labels, ['web'], []string{},
		['nginx'], ['env=prod']) == true
}

fn test_matches_container_filter_combined_filters_partial_fail() {
	labels := {
		'env': 'prod'
	}
	// Container matches but image doesn't
	assert matches_container_filter('web', 'redis', labels, ['web'], []string{},
		['nginx'], ['env=prod']) == false
}

fn test_matches_container_filter_exclude_prefix_match() {
	assert matches_container_filter('sidecar-proxy', 'envoy', map[string]string{}, []string{},
		['sidecar'], []string{}, []string{}) == false
}

fn test_matches_container_filter_multiple_include_labels() {
	labels := {
		'tier': 'backend'
	}
	// Only need one label to match
	assert matches_container_filter('web', 'nginx', labels, []string{}, []string{},
		[]string{}, ['env=prod', 'tier']) == true
}

// --- build_container_metadata tests ---

fn test_build_container_metadata_basic() {
	c := DockerContainer{
		id: 'abc123def456'
		names: ['/my-web-app']
		image: 'nginx:latest'
		labels: map[string]string{}
		state: 'running'
		status: 'Up 2 hours'
	}
	meta := build_container_metadata(c)
	assert meta['container_id'] == 'abc123def456'
	assert meta['container_name'] == 'my-web-app'
	assert meta['image'] == 'nginx:latest'
	assert meta['container_state'] == 'running'
	assert meta['container_status'] == 'Up 2 hours'
}

fn test_build_container_metadata_with_labels() {
	c := DockerContainer{
		id: 'abc123'
		names: ['/app']
		image: 'myapp:v1'
		labels: {
			'env':  'prod'
			'tier': 'backend'
		}
		state: 'running'
		status: 'Up 5 minutes'
	}
	meta := build_container_metadata(c)
	assert meta['label.env'] == 'prod'
	assert meta['label.tier'] == 'backend'
}

fn test_build_container_metadata_no_names() {
	c := DockerContainer{
		id: 'abc123def456'
		names: []string{}
		image: 'nginx'
		labels: map[string]string{}
		state: 'running'
		status: 'Up 1 hour'
	}
	meta := build_container_metadata(c)
	// When no names, container_name key should not be set
	assert 'container_name' !in meta
}

fn test_build_container_metadata_name_leading_slash() {
	c := DockerContainer{
		id: 'xyz789'
		names: ['/my-container']
		image: 'alpine'
		labels: map[string]string{}
		state: 'running'
		status: 'Up 10 seconds'
	}
	meta := build_container_metadata(c)
	// Leading slash from Docker API should be trimmed
	assert meta['container_name'] == 'my-container'
}

// --- docker_api_url tests ---

fn test_docker_api_url_unix() {
	url := docker_api_url('unix:///var/run/docker.sock', '/containers/json')
	assert url == 'http://localhost/containers/json'
}

fn test_docker_api_url_tcp() {
	url := docker_api_url('tcp://localhost:2375', '/containers/json')
	assert url == 'http://localhost:2375/containers/json'
}

fn test_docker_api_url_http() {
	url := docker_api_url('http://docker.local:2375', '/containers/json')
	assert url == 'http://docker.local:2375/containers/json'
}

fn test_docker_api_url_https() {
	url := docker_api_url('https://docker.local:2376', '/v1.41/containers/json')
	assert url == 'https://docker.local:2376/v1.41/containers/json'
}

fn test_docker_api_url_bare_host() {
	url := docker_api_url('myhost:2375', '/containers/json')
	assert url == 'http://myhost:2375/containers/json'
}
