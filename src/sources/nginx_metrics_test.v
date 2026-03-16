module sources

fn test_new_nginx_metrics_defaults() {
	opts := map[string]string{}
	if _ := new_nginx_metrics(opts) {
		assert false, 'expected error for missing endpoints'
	}
}

fn test_new_nginx_metrics_with_endpoints() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost/nginx_status'
	src := new_nginx_metrics(opts) or { panic(err.str()) }
	assert src.endpoints.len == 1
	assert src.endpoints[0] == 'http://localhost/nginx_status'
	assert src.namespace == 'nginx'
	assert src.scrape_interval == 15_000_000_000
	assert src.auth_header == ''
}

fn test_new_nginx_metrics_multiple_endpoints() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://host1/status, http://host2/status, http://host3/status'
	src := new_nginx_metrics(opts) or { panic(err.str()) }
	assert src.endpoints.len == 3
	assert src.endpoints[0] == 'http://host1/status'
	assert src.endpoints[1] == 'http://host2/status'
	assert src.endpoints[2] == 'http://host3/status'
}

fn test_new_nginx_metrics_empty_string_error() {
	mut opts := map[string]string{}
	opts['endpoints'] = '  ,  ,  '
	if _ := new_nginx_metrics(opts) {
		assert false, 'expected error for empty endpoints'
	}
}

fn test_new_nginx_metrics_custom_interval() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost/nginx_status'
	opts['scrape_interval_secs'] = '30'
	src := new_nginx_metrics(opts) or { panic(err.str()) }
	assert src.scrape_interval == 30_000_000_000
}

fn test_new_nginx_metrics_negative_interval_clamps() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost/nginx_status'
	opts['scrape_interval_secs'] = '-5'
	src := new_nginx_metrics(opts) or { panic(err.str()) }
	assert src.scrape_interval == 15_000_000_000
}

fn test_new_nginx_metrics_zero_interval_clamps() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost/nginx_status'
	opts['scrape_interval_secs'] = '0'
	src := new_nginx_metrics(opts) or { panic(err.str()) }
	assert src.scrape_interval == 15_000_000_000
}

fn test_new_nginx_metrics_custom_namespace() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost/nginx_status'
	opts['namespace'] = 'my_nginx'
	src := new_nginx_metrics(opts) or { panic(err.str()) }
	assert src.namespace == 'my_nginx'
}

fn test_new_nginx_metrics_all_options() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://host1/status, http://host2/status'
	opts['scrape_interval_secs'] = '60'
	opts['namespace'] = 'custom'
	opts['auth.token'] = 'my-token'
	src := new_nginx_metrics(opts) or { panic(err.str()) }
	assert src.endpoints.len == 2
	assert src.scrape_interval == 60_000_000_000
	assert src.namespace == 'custom'
	assert src.auth_header == 'Bearer my-token'
}

fn test_new_nginx_metrics_basic_auth() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost/nginx_status'
	opts['auth.user'] = 'admin'
	opts['auth.password'] = 'secret'
	src := new_nginx_metrics(opts) or { panic(err.str()) }
	assert src.auth_header.starts_with('Basic ')
	assert src.auth_header == 'Basic ' + sources_base64('admin:secret')
}

fn test_new_nginx_metrics_bearer_auth() {
	mut opts := map[string]string{}
	opts['endpoints'] = 'http://localhost/nginx_status'
	opts['auth.token'] = 'my-bearer-token'
	src := new_nginx_metrics(opts) or { panic(err.str()) }
	assert src.auth_header == 'Bearer my-bearer-token'
}

fn test_parse_nginx_stub_status_standard() {
	content := 'Active connections: 291
server accepts handled requests
 16630948 16630948 31070465
Reading: 6 Writing: 179 Waiting: 106
'
	status := parse_nginx_stub_status(content)
	assert status.active == 291
	assert status.accepts == 16630948
	assert status.handled == 16630948
	assert status.requests == 31070465
	assert status.reading == 6
	assert status.writing == 179
	assert status.waiting == 106
}

fn test_parse_nginx_stub_status_empty() {
	status := parse_nginx_stub_status('')
	assert status.active == 0
	assert status.accepts == 0
	assert status.handled == 0
	assert status.requests == 0
	assert status.reading == 0
	assert status.writing == 0
	assert status.waiting == 0
}

fn test_parse_nginx_stub_status_partial() {
	content := 'Active connections: 5
server accepts handled requests
'
	status := parse_nginx_stub_status(content)
	assert status.active == 5
	assert status.accepts == 0
	assert status.handled == 0
	assert status.requests == 0
	assert status.reading == 0
	assert status.writing == 0
	assert status.waiting == 0
}

fn test_parse_nginx_stub_status_zero_values() {
	content := 'Active connections: 0
server accepts handled requests
 0 0 0
Reading: 0 Writing: 0 Waiting: 0
'
	status := parse_nginx_stub_status(content)
	assert status.active == 0
	assert status.accepts == 0
	assert status.handled == 0
	assert status.requests == 0
	assert status.reading == 0
	assert status.writing == 0
	assert status.waiting == 0
}

fn test_nginx_sources_base64() {
	assert sources_base64('') == ''
	assert sources_base64('f') == 'Zg=='
	assert sources_base64('fo') == 'Zm8='
	assert sources_base64('foo') == 'Zm9v'
	assert sources_base64('foobar') == 'Zm9vYmFy'
	assert sources_base64('admin:secret') == 'YWRtaW46c2VjcmV0'
}
