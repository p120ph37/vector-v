module sources

fn test_new_mongodb_metrics_defaults() {
	opts := map[string]string{}
	if _ := new_mongodb_metrics(opts) {
		assert false, 'expected error when endpoints not provided'
	}
}

fn test_new_mongodb_metrics_with_endpoints() {
	opts := {
		'endpoints': 'http://localhost:27017/serverStatus'
	}
	s := new_mongodb_metrics(opts)!
	assert s.endpoints.len == 1
	assert s.endpoints[0] == 'http://localhost:27017/serverStatus'
	assert s.namespace == 'mongodb'
	assert s.scrape_interval == 15_000_000_000 // 15 seconds in nanoseconds
}

fn test_new_mongodb_metrics_multiple_endpoints() {
	opts := {
		'endpoints': 'http://host1:27017/serverStatus, http://host2:27017/serverStatus'
	}
	s := new_mongodb_metrics(opts)!
	assert s.endpoints.len == 2
	assert s.endpoints[0] == 'http://host1:27017/serverStatus'
	assert s.endpoints[1] == 'http://host2:27017/serverStatus'
}

fn test_new_mongodb_metrics_empty_endpoints_error() {
	opts := {
		'endpoints': '  ,  , '
	}
	if _ := new_mongodb_metrics(opts) {
		assert false, 'expected error for empty endpoints'
	}
}

fn test_new_mongodb_metrics_custom_interval() {
	opts := {
		'endpoints':             'http://localhost:27017/serverStatus'
		'scrape_interval_secs': '30'
	}
	s := new_mongodb_metrics(opts)!
	assert s.scrape_interval == 30_000_000_000 // 30 seconds in nanoseconds
}

fn test_new_mongodb_metrics_negative_interval_clamps() {
	opts := {
		'endpoints':             'http://localhost:27017/serverStatus'
		'scrape_interval_secs': '-5'
	}
	s := new_mongodb_metrics(opts)!
	assert s.scrape_interval == 15_000_000_000 // 15 seconds in nanoseconds
}

fn test_new_mongodb_metrics_zero_interval_clamps() {
	opts := {
		'endpoints':             'http://localhost:27017/serverStatus'
		'scrape_interval_secs': '0'
	}
	s := new_mongodb_metrics(opts)!
	assert s.scrape_interval == 15_000_000_000 // 15 seconds in nanoseconds
}

fn test_new_mongodb_metrics_custom_namespace() {
	opts := {
		'endpoints': 'http://localhost:27017/serverStatus'
		'namespace': 'mongo'
	}
	s := new_mongodb_metrics(opts)!
	assert s.namespace == 'mongo'
}

fn test_new_mongodb_metrics_all_options() {
	opts := {
		'endpoints':             'http://host1:27017/serverStatus,http://host2:27017/serverStatus'
		'scrape_interval_secs': '60'
		'namespace':            'mydb'
	}
	s := new_mongodb_metrics(opts)!
	assert s.endpoints.len == 2
	assert s.scrape_interval == 60_000_000_000 // 60 seconds in nanoseconds
	assert s.namespace == 'mydb'
}

fn test_parse_mongodb_status_basic() {
	content := '{
		"host": "mongo1.example.com:27017",
		"uptimeMillis": 120000,
		"connections": {
			"current": 42,
			"available": 800,
			"totalCreated": 1500
		},
		"mem": {
			"resident": 256,
			"virtual": 1024
		},
		"opcounters": {
			"insert": 100,
			"query": 200,
			"update": 50,
			"delete": 10,
			"getmore": 30,
			"command": 500
		}
	}'
	status := parse_mongodb_status(content)
	assert status.host == 'mongo1.example.com:27017'
	assert status.uptime == 120.0
	assert status.connections_current == 42.0
	assert status.connections_available == 800.0
	assert status.connections_total_created == 1500.0
	assert status.mem_resident == 256.0
	assert status.mem_virtual == 1024.0
	assert status.ops_insert == 100.0
	assert status.ops_query == 200.0
	assert status.ops_update == 50.0
	assert status.ops_delete == 10.0
	assert status.ops_getmore == 30.0
	assert status.ops_command == 500.0
}

fn test_parse_mongodb_status_empty() {
	status := parse_mongodb_status('')
	assert status.host == ''
	assert status.uptime == 0.0
	assert status.connections_current == 0.0
	assert status.ops_insert == 0.0
}

fn test_parse_mongodb_status_partial() {
	content := '{
		"host": "partial.example.com:27017",
		"uptimeMillis": 5000,
		"connections": {
			"current": 10
		}
	}'
	status := parse_mongodb_status(content)
	assert status.host == 'partial.example.com:27017'
	assert status.uptime == 5.0
	assert status.connections_current == 10.0
	assert status.connections_available == 0.0
	assert status.mem_resident == 0.0
	assert status.ops_insert == 0.0
}

fn test_extract_json_f64_basic() {
	content := '{"uptimeMillis": 60000, "current": 42}'
	assert extract_json_f64(content, 'uptimeMillis') == 60000.0
	assert extract_json_f64(content, 'current') == 42.0
}

fn test_extract_json_f64_missing() {
	content := '{"host": "example.com"}'
	assert extract_json_f64(content, 'nonexistent') == 0.0
}

fn test_extract_json_string_basic() {
	content := '{"host": "mongo1.example.com:27017", "version": "6.0.1"}'
	assert extract_json_string(content, 'host') == 'mongo1.example.com:27017'
	assert extract_json_string(content, 'version') == '6.0.1'
}

fn test_extract_json_string_missing() {
	content := '{"host": "example.com"}'
	assert extract_json_string(content, 'nonexistent') == ''
}
