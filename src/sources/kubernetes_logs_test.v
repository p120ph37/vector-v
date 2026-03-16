module sources

import os

// --- Constructor tests ---

fn test_new_kubernetes_logs_defaults() {
	s := new_kubernetes_logs(map[string]string{})
	assert s.data_dir == '/var/log/pods'
	assert s.glob_pattern == '**/*.log'
	assert s.max_line_bytes == 32768
	assert s.max_read_bytes == 2048
	assert s.glob_cooldown_ms == 5000
	assert s.read_from == 'beginning'
	assert s.ignore_older_secs == 0
	assert s.namespace_labels == true
	assert s.pod_annotations == true
	assert s.kube_api_url == 'https://kubernetes.default.svc'
	assert s.kube_token_path == '/var/run/secrets/kubernetes.io/serviceaccount/token'
	assert s.kube_ca_path == '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
	assert s.exclude_paths.len == 0
}

fn test_new_kubernetes_logs_custom_config() {
	s := new_kubernetes_logs({
		'data_dir':          '/tmp/pods'
		'glob_pattern':      '*.log'
		'max_line_bytes':    '65536'
		'max_read_bytes':    '4096'
		'glob_cooldown_ms':  '10000'
		'read_from':         'end'
		'ignore_older_secs': '3600'
		'namespace_labels':  'false'
		'pod_annotations':   'false'
		'kube_api_url':      'https://my-cluster:6443'
		'kube_token_path':   '/tmp/token'
		'kube_ca_path':      '/tmp/ca.crt'
		'self_node_name':    'node-1'
		'exclude_paths':     '/var/log/pods/kube-system,/var/log/pods/monitoring'
	})
	assert s.data_dir == '/tmp/pods'
	assert s.glob_pattern == '*.log'
	assert s.max_line_bytes == 65536
	assert s.max_read_bytes == 4096
	assert s.glob_cooldown_ms == 10000
	assert s.read_from == 'end'
	assert s.ignore_older_secs == 3600
	assert s.namespace_labels == false
	assert s.pod_annotations == false
	assert s.kube_api_url == 'https://my-cluster:6443'
	assert s.kube_token_path == '/tmp/token'
	assert s.kube_ca_path == '/tmp/ca.crt'
	assert s.self_node_name == 'node-1'
	assert s.exclude_paths.len == 2
	assert s.exclude_paths[0] == '/var/log/pods/kube-system'
	assert s.exclude_paths[1] == '/var/log/pods/monitoring'
}

fn test_new_kubernetes_logs_invalid_max_line_bytes() {
	s := new_kubernetes_logs({
		'max_line_bytes': '-1'
	})
	assert s.max_line_bytes == 32768
}

fn test_new_kubernetes_logs_invalid_max_read_bytes() {
	s := new_kubernetes_logs({
		'max_read_bytes': '0'
	})
	assert s.max_read_bytes == 2048
}

fn test_new_kubernetes_logs_invalid_glob_cooldown() {
	s := new_kubernetes_logs({
		'glob_cooldown_ms': '-100'
	})
	assert s.glob_cooldown_ms == 5000
}

fn test_new_kubernetes_logs_invalid_ignore_older() {
	s := new_kubernetes_logs({
		'ignore_older_secs': '-10'
	})
	assert s.ignore_older_secs == 0
}

fn test_new_kubernetes_logs_read_from_invalid() {
	s := new_kubernetes_logs({
		'read_from': 'middle'
	})
	assert s.read_from == 'beginning'
}

fn test_new_kubernetes_logs_self_node_name_from_config() {
	s := new_kubernetes_logs({
		'self_node_name': 'my-node'
	})
	assert s.self_node_name == 'my-node'
}

fn test_new_kubernetes_logs_self_node_name_from_env() {
	// Set VECTOR_SELF_NODE_NAME env
	os.setenv('VECTOR_SELF_NODE_NAME', 'env-node', true)
	defer {
		os.unsetenv('VECTOR_SELF_NODE_NAME')
	}
	s := new_kubernetes_logs(map[string]string{})
	assert s.self_node_name == 'env-node'
}

fn test_new_kubernetes_logs_self_node_name_from_node_name_env() {
	// Make sure VECTOR_SELF_NODE_NAME is not set
	os.unsetenv('VECTOR_SELF_NODE_NAME')
	os.setenv('NODE_NAME', 'fallback-node', true)
	defer {
		os.unsetenv('NODE_NAME')
	}
	s := new_kubernetes_logs(map[string]string{})
	assert s.self_node_name == 'fallback-node'
}

fn test_new_kubernetes_logs_self_node_name_config_overrides_env() {
	os.setenv('VECTOR_SELF_NODE_NAME', 'env-node', true)
	defer {
		os.unsetenv('VECTOR_SELF_NODE_NAME')
	}
	s := new_kubernetes_logs({
		'self_node_name': 'config-node'
	})
	assert s.self_node_name == 'config-node'
}

fn test_new_kubernetes_logs_empty_exclude_paths() {
	s := new_kubernetes_logs({
		'exclude_paths': ''
	})
	assert s.exclude_paths.len == 0
}

// --- parse_pod_log_path tests ---

fn test_parse_pod_log_path_standard() {
	ns, pod, container := parse_pod_log_path('/var/log/pods/default_nginx-abc123_uid123/nginx/0.log') or {
		assert false, 'expected successful parse'
		return
	}
	assert ns == 'default'
	assert pod == 'nginx-abc123'
	assert container == 'nginx'
}

fn test_parse_pod_log_path_kube_system() {
	ns, pod, container := parse_pod_log_path('/var/log/pods/kube-system_coredns-5644d7b6d9-abcde_12345678-1234-1234-1234-123456789012/coredns/0.log') or {
		assert false, 'expected successful parse'
		return
	}
	assert ns == 'kube-system'
	assert pod == 'coredns-5644d7b6d9-abcde'
	assert container == 'coredns'
}

fn test_parse_pod_log_path_restart_count() {
	ns, pod, container := parse_pod_log_path('/var/log/pods/production_web-server-xyz_uid456/app/3.log') or {
		assert false, 'expected successful parse'
		return
	}
	assert ns == 'production'
	assert pod == 'web-server-xyz'
	assert container == 'app'
}

fn test_parse_pod_log_path_pod_name_with_underscores() {
	ns, pod, container := parse_pod_log_path('/var/log/pods/default_my_special_pod_uid789/main/0.log') or {
		assert false, 'expected successful parse'
		return
	}
	assert ns == 'default'
	assert pod == 'my_special_pod'
	assert container == 'main'
}

fn test_parse_pod_log_path_too_short() {
	parse_pod_log_path('0.log') or {
		return // expected
	}
	assert false, 'expected none for too-short path'
}

fn test_parse_pod_log_path_empty() {
	parse_pod_log_path('') or {
		return // expected
	}
	assert false, 'expected none for empty path'
}

fn test_parse_pod_log_path_no_underscores_in_pod_dir() {
	parse_pod_log_path('/var/log/pods/invalidpoddir/container/0.log') or {
		return // expected
	}
	assert false, 'expected none for missing underscores'
}

fn test_parse_pod_log_path_only_two_underscores() {
	// Minimum valid: ns_pod_uid
	ns, pod, container := parse_pod_log_path('/var/log/pods/ns_pod_uid/ctr/0.log') or {
		assert false, 'expected successful parse'
		return
	}
	assert ns == 'ns'
	assert pod == 'pod'
	assert container == 'ctr'
}

fn test_parse_pod_log_path_missing_namespace() {
	parse_pod_log_path('/var/log/pods/_pod_uid/container/0.log') or {
		return // expected
	}
	assert false, 'expected none for missing namespace'
}

// --- parse_kubernetes_log_line tests ---

fn test_parse_kubernetes_log_line_full() {
	ts, stream, msg := parse_kubernetes_log_line('2024-01-15T10:30:00.123456789Z stdout F Hello, World!') or {
		assert false, 'expected successful parse'
		return
	}
	assert ts == '2024-01-15T10:30:00.123456789Z'
	assert stream == 'stdout'
	assert msg == 'Hello, World!'
}

fn test_parse_kubernetes_log_line_stderr() {
	ts, stream, msg := parse_kubernetes_log_line('2024-06-01T00:00:00Z stderr F error: something failed') or {
		assert false, 'expected successful parse'
		return
	}
	assert ts == '2024-06-01T00:00:00Z'
	assert stream == 'stderr'
	assert msg == 'error: something failed'
}

fn test_parse_kubernetes_log_line_partial() {
	ts, stream, msg := parse_kubernetes_log_line('2024-01-15T10:30:00Z stdout P partial message part') or {
		assert false, 'expected successful parse'
		return
	}
	assert ts == '2024-01-15T10:30:00Z'
	assert stream == 'stdout'
	assert msg == 'partial message part'
}

fn test_parse_kubernetes_log_line_empty_message() {
	ts, stream, msg := parse_kubernetes_log_line('2024-01-15T10:30:00Z stdout F ') or {
		assert false, 'expected successful parse'
		return
	}
	assert ts == '2024-01-15T10:30:00Z'
	assert stream == 'stdout'
	assert msg == ''
}

fn test_parse_kubernetes_log_line_message_with_spaces() {
	ts, stream, msg := parse_kubernetes_log_line('2024-01-15T10:30:00Z stdout F multiple words with spaces') or {
		assert false, 'expected successful parse'
		return
	}
	assert ts == '2024-01-15T10:30:00Z'
	assert stream == 'stdout'
	assert msg == 'multiple words with spaces'
}

fn test_parse_kubernetes_log_line_empty() {
	parse_kubernetes_log_line('') or {
		return // expected
	}
	assert false, 'expected none for empty line'
}

fn test_parse_kubernetes_log_line_no_spaces() {
	parse_kubernetes_log_line('nospaces') or {
		return // expected
	}
	assert false, 'expected none for no-space line'
}

fn test_parse_kubernetes_log_line_invalid_flag() {
	parse_kubernetes_log_line('2024-01-15T10:30:00Z stdout X some message') or {
		return // expected
	}
	assert false, 'expected none for invalid flag'
}

fn test_parse_kubernetes_log_line_only_timestamp() {
	parse_kubernetes_log_line('2024-01-15T10:30:00Z') or {
		return // expected
	}
	assert false, 'expected none for timestamp-only line'
}

fn test_parse_kubernetes_log_line_json_message() {
	_, _, msg := parse_kubernetes_log_line('2024-01-15T10:30:00Z stdout F {"level":"info","msg":"started"}') or {
		assert false, 'expected successful parse'
		return
	}
	assert msg == '{"level":"info","msg":"started"}'
}

// --- is_partial_line tests ---

fn test_is_partial_line_true() {
	assert is_partial_line('2024-01-15T10:30:00Z stdout P partial data') == true
}

fn test_is_partial_line_false_full() {
	assert is_partial_line('2024-01-15T10:30:00Z stdout F full line') == false
}

fn test_is_partial_line_false_empty() {
	assert is_partial_line('') == false
}

fn test_is_partial_line_false_malformed() {
	assert is_partial_line('not a valid log line') == false
}

fn test_is_partial_line_false_no_flag() {
	assert is_partial_line('2024-01-15T10:30:00Z stdout') == false
}

// --- merge_partial_lines tests ---

fn test_merge_partial_lines_single_full() {
	result := merge_partial_lines([
		'2024-01-15T10:30:00Z stdout F complete message',
	])
	assert result == 'complete message'
}

fn test_merge_partial_lines_two_partials_and_full() {
	result := merge_partial_lines([
		'2024-01-15T10:30:00Z stdout P hello ',
		'2024-01-15T10:30:01Z stdout P world ',
		'2024-01-15T10:30:02Z stdout F end',
	])
	assert result == 'hello world end'
}

fn test_merge_partial_lines_empty() {
	result := merge_partial_lines([]string{})
	assert result == ''
}

fn test_merge_partial_lines_single_partial() {
	result := merge_partial_lines([
		'2024-01-15T10:30:00Z stdout P only partial',
	])
	assert result == 'only partial'
}

fn test_merge_partial_lines_multiple_partials() {
	result := merge_partial_lines([
		'2024-01-15T10:30:00Z stdout P aaa',
		'2024-01-15T10:30:01Z stdout P bbb',
		'2024-01-15T10:30:02Z stdout P ccc',
	])
	assert result == 'aaabbbccc'
}
