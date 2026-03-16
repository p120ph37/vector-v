module sources

import event
import net
import time

fn test_new_prometheus_remote_write_defaults() {
	s := new_prometheus_remote_write({})
	assert s.address == '0.0.0.0:9090'
	assert s.auth_token == ''
}

fn test_new_prometheus_remote_write_custom() {
	s := new_prometheus_remote_write({
		'address':    '127.0.0.1:9191'
		'auth.token': 'my-secret'
	})
	assert s.address == '127.0.0.1:9191'
	assert s.auth_token == 'my-secret'
}

fn test_new_prometheus_remote_write_default_address() {
	s := new_prometheus_remote_write({
		'auth.token': 'tok'
	})
	assert s.address == '0.0.0.0:9090'
	assert s.auth_token == 'tok'
}

fn test_new_prometheus_remote_write_empty_token() {
	s := new_prometheus_remote_write({
		'address': '0.0.0.0:1234'
	})
	assert s.auth_token == ''
}

// Helper to run a PrometheusRemoteWriteSource in a spawned thread.
fn run_prom_rw_source(s &PrometheusRemoteWriteSource, output chan event.Event) {
	s.run(output)
}

fn get_free_port_for_rw() string {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0') or { return '19090' }
	addr := listener.addr() or {
		listener.close() or {}
		return '19090'
	}
	port := addr.str().all_after_last(':')
	listener.close() or {}
	return port
}

// Helper: send a request to a remote write source and collect events
fn rw_send_and_collect(address string, request string, output chan event.Event) []event.Metric {
	mut conn := net.dial_tcp(address) or { return [] }
	conn.write(request.bytes()) or {}
	time.sleep(200 * time.millisecond)
	conn.close() or {}

	mut metrics := []event.Metric{}
	for {
		mut ev := event.Event(event.LogEvent{})
		if output.try_pop(mut ev) == .success {
			m := ev as event.Metric
			metrics << m
		} else {
			break
		}
	}
	return metrics
}

fn test_prometheus_remote_write_accepts_post() {
	port := get_free_port_for_rw()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_remote_write({
		'address': address
	})
	spawn run_prom_rw_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := '# TYPE http_requests counter\nhttp_requests_total{method="GET"} 100\n'
	request := 'POST /api/v1/write HTTP/1.1\r\nHost: localhost\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := rw_send_and_collect(address, request, output)
	assert metrics.len >= 1
	assert metrics[0].name == 'http_requests_total'
	assert metrics[0].meta.source_type == 'prometheus_remote_write'
	assert metrics[0].tags['method'] == 'GET'
}

fn test_prometheus_remote_write_rejects_wrong_path() {
	port := get_free_port_for_rw()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_remote_write({
		'address': address
	})
	spawn run_prom_rw_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := 'some_metric 42\n'
	request := 'POST /wrong/path HTTP/1.1\r\nHost: localhost\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := rw_send_and_collect(address, request, output)
	assert metrics.len == 0
}

fn test_prometheus_remote_write_auth_valid() {
	port := get_free_port_for_rw()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_remote_write({
		'address':    address
		'auth.token': 'test-token'
	})
	spawn run_prom_rw_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := '# TYPE temp gauge\ntemp 22.5\n'
	request := 'POST /api/v1/write HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer test-token\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := rw_send_and_collect(address, request, output)
	assert metrics.len >= 1
}

fn test_prometheus_remote_write_auth_invalid() {
	port := get_free_port_for_rw()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_remote_write({
		'address':    address
		'auth.token': 'correct-token'
	})
	spawn run_prom_rw_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := '# TYPE temp gauge\ntemp 22.5\n'
	request := 'POST /api/v1/write HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer wrong-token\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := rw_send_and_collect(address, request, output)
	assert metrics.len == 0
}

fn test_prometheus_remote_write_multiple_metrics() {
	port := get_free_port_for_rw()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_remote_write({
		'address': address
	})
	spawn run_prom_rw_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := '# TYPE a gauge\n# TYPE b counter\na 10\nb_total 20\n'
	request := 'POST /api/v1/write HTTP/1.1\r\nHost: localhost\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := rw_send_and_collect(address, request, output)
	assert metrics.len == 2
}

fn test_prometheus_remote_write_source_type() {
	port := get_free_port_for_rw()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_remote_write({
		'address': address
	})
	spawn run_prom_rw_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := 'cpu_usage 75.5\n'
	request := 'POST /api/v1/write HTTP/1.1\r\nHost: localhost\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := rw_send_and_collect(address, request, output)
	if metrics.len > 0 {
		assert metrics[0].meta.source_type == 'prometheus_remote_write'
	}
}
