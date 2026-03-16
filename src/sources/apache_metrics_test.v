module sources

fn test_new_apache_metrics_defaults() {
	// No endpoints provided should error
	new_apache_metrics(map[string]string{}) or {
		assert err.msg().contains('endpoints is required')
		return
	}
	assert false, 'expected error when endpoints not provided'
}

fn test_new_apache_metrics_with_endpoints() {
	src := new_apache_metrics({
		'endpoints': 'http://localhost/server-status?auto'
	})!
	assert src.endpoints.len == 1
	assert src.endpoints[0] == 'http://localhost/server-status?auto'
	assert src.namespace == 'apache'
	assert src.scrape_interval == 15_000_000_000 // 15 seconds in nanoseconds
	assert src.auth_header == ''
}

fn test_new_apache_metrics_multiple_endpoints() {
	src := new_apache_metrics({
		'endpoints': 'http://host1/status?auto, http://host2/status?auto, http://host3/status?auto'
	})!
	assert src.endpoints.len == 3
	assert src.endpoints[0] == 'http://host1/status?auto'
	assert src.endpoints[1] == 'http://host2/status?auto'
	assert src.endpoints[2] == 'http://host3/status?auto'
}

fn test_new_apache_metrics_empty_endpoints_error() {
	new_apache_metrics({
		'endpoints': '  ,  , '
	}) or {
		assert err.msg().contains('at least one endpoint is required')
		return
	}
	assert false, 'expected error for empty endpoints after trimming'
}

fn test_new_apache_metrics_custom_interval() {
	src := new_apache_metrics({
		'endpoints':             'http://localhost/server-status?auto'
		'scrape_interval_secs': '30'
	})!
	assert src.scrape_interval == 30_000_000_000
}

fn test_new_apache_metrics_negative_interval_clamps() {
	src := new_apache_metrics({
		'endpoints':             'http://localhost/server-status?auto'
		'scrape_interval_secs': '-5'
	})!
	assert src.scrape_interval == 15_000_000_000
}

fn test_new_apache_metrics_zero_interval_clamps() {
	src := new_apache_metrics({
		'endpoints':             'http://localhost/server-status?auto'
		'scrape_interval_secs': '0'
	})!
	assert src.scrape_interval == 15_000_000_000
}

fn test_new_apache_metrics_custom_namespace() {
	src := new_apache_metrics({
		'endpoints': 'http://localhost/server-status?auto'
		'namespace': 'httpd'
	})!
	assert src.namespace == 'httpd'
}

fn test_new_apache_metrics_all_options() {
	src := new_apache_metrics({
		'endpoints':             'http://host1/status?auto,http://host2/status?auto'
		'scrape_interval_secs': '60'
		'namespace':            'my_apache'
	})!
	assert src.endpoints.len == 2
	assert src.scrape_interval == 60_000_000_000
	assert src.namespace == 'my_apache'
}

fn test_new_apache_metrics_basic_auth() {
	src := new_apache_metrics({
		'endpoints':     'http://localhost/server-status?auto'
		'auth.user':     'admin'
		'auth.password': 'secret'
	})!
	assert src.auth_header.starts_with('Basic ')
	// admin:secret -> YWRtaW46c2VjcmV0
	assert src.auth_header == 'Basic YWRtaW46c2VjcmV0'
}

fn test_new_apache_metrics_bearer_auth() {
	src := new_apache_metrics({
		'endpoints':  'http://localhost/server-status?auto'
		'auth.token': 'my-token-123'
	})!
	assert src.auth_header == 'Bearer my-token-123'
}

fn test_parse_apache_status_basic() {
	content := 'Total Accesses: 1234
Total kBytes: 5678
CPULoad: .5
Uptime: 12345
ReqPerSec: 1.5
BytesPerSec: 456.7
BytesPerReq: 304.5
BusyWorkers: 5
IdleWorkers: 245
Scoreboard: __W_K...'
	entries := parse_apache_status(content)
	assert entries.len == 10

	assert entries[0].key == 'Total Accesses'
	assert entries[0].value_str == '1234'
	assert entries[0].value == 1234.0

	assert entries[1].key == 'Total kBytes'
	assert entries[1].value == 5678.0

	assert entries[2].key == 'CPULoad'
	assert entries[2].value == 0.5

	assert entries[3].key == 'Uptime'
	assert entries[3].value == 12345.0

	assert entries[4].key == 'ReqPerSec'
	assert entries[4].value == 1.5

	assert entries[5].key == 'BytesPerSec'
	assert entries[5].value == 456.7

	assert entries[6].key == 'BytesPerReq'
	assert entries[6].value == 304.5

	assert entries[7].key == 'BusyWorkers'
	assert entries[7].value == 5.0

	assert entries[8].key == 'IdleWorkers'
	assert entries[8].value == 245.0

	assert entries[9].key == 'Scoreboard'
	assert entries[9].value_str == '__W_K...'
}

fn test_parse_apache_status_empty() {
	entries := parse_apache_status('')
	assert entries.len == 0
}

fn test_parse_apache_status_partial() {
	content := 'BusyWorkers: 3
IdleWorkers: 100'
	entries := parse_apache_status(content)
	assert entries.len == 2
	assert entries[0].key == 'BusyWorkers'
	assert entries[0].value == 3.0
	assert entries[1].key == 'IdleWorkers'
	assert entries[1].value == 100.0
}

fn test_apache_scoreboard_counts_basic() {
	counts := apache_scoreboard_counts('__W_K...')
	assert counts['waiting'] == 3
	assert counts['writing'] == 1
	assert counts['keepalive'] == 1
	assert counts['open'] == 3
}

fn test_apache_scoreboard_counts_empty() {
	counts := apache_scoreboard_counts('')
	assert counts.len == 0
}

fn test_apache_scoreboard_counts_all_states() {
	// One of each state character
	counts := apache_scoreboard_counts('_SRWKDCLGI.')
	assert counts['waiting'] == 1
	assert counts['starting'] == 1
	assert counts['reading'] == 1
	assert counts['writing'] == 1
	assert counts['keepalive'] == 1
	assert counts['dns'] == 1
	assert counts['closing'] == 1
	assert counts['logging'] == 1
	assert counts['graceful'] == 1
	assert counts['idle'] == 1
	assert counts['open'] == 1
	assert counts.len == 11
}

fn test_apache_sources_base64() {
	// Standard base64 test vectors
	assert sources_base64('') == ''
	assert sources_base64('f') == 'Zg=='
	assert sources_base64('fo') == 'Zm8='
	assert sources_base64('foo') == 'Zm9v'
	assert sources_base64('foob') == 'Zm9vYg=='
	assert sources_base64('fooba') == 'Zm9vYmE='
	assert sources_base64('foobar') == 'Zm9vYmFy'
	// Auth-relevant test
	assert sources_base64('admin:secret') == 'YWRtaW46c2VjcmV0'
}
