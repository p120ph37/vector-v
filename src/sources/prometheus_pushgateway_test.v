module sources

import event
import net
import time

fn test_new_prometheus_pushgateway_defaults() {
	s := new_prometheus_pushgateway({})
	assert s.address == '0.0.0.0:9091'
}

fn test_new_prometheus_pushgateway_custom_address() {
	s := new_prometheus_pushgateway({
		'address': '127.0.0.1:9999'
	})
	assert s.address == '127.0.0.1:9999'
}

fn test_extract_pushgateway_job_basic() {
	job := extract_pushgateway_job('/metrics/job/myapp')
	assert job == 'myapp'
}

fn test_extract_pushgateway_job_with_trailing_slash() {
	job := extract_pushgateway_job('/metrics/job/myapp/')
	assert job == 'myapp'
}

fn test_extract_pushgateway_job_with_labels() {
	job := extract_pushgateway_job('/metrics/job/myapp/instance/localhost:9090')
	assert job == 'myapp'
}

fn test_extract_pushgateway_job_empty() {
	job := extract_pushgateway_job('/metrics/job/')
	assert job == ''
}

fn test_extract_pushgateway_job_wrong_path() {
	job := extract_pushgateway_job('/wrong/path')
	assert job == ''
}

fn test_extract_pushgateway_job_no_prefix() {
	job := extract_pushgateway_job('/metrics')
	assert job == ''
}

fn test_extract_pushgateway_labels_none() {
	labels := extract_pushgateway_labels('/metrics/job/myapp')
	assert labels.len == 0
}

fn test_extract_pushgateway_labels_one_pair() {
	labels := extract_pushgateway_labels('/metrics/job/myapp/instance/localhost:9090')
	assert labels.len == 1
	assert labels['instance'] == 'localhost:9090'
}

fn test_extract_pushgateway_labels_multiple_pairs() {
	labels := extract_pushgateway_labels('/metrics/job/myapp/instance/host1/env/prod')
	assert labels.len == 2
	assert labels['instance'] == 'host1'
	assert labels['env'] == 'prod'
}

fn test_extract_pushgateway_labels_trailing_slash() {
	labels := extract_pushgateway_labels('/metrics/job/myapp/instance/host1/')
	assert labels.len == 1
	assert labels['instance'] == 'host1'
}

// Helper to run a PrometheusPushgatewaySource in a spawned thread.
fn run_pushgateway_source(s &PrometheusPushgatewaySource, output chan event.Event) {
	s.run(output)
}

fn get_free_port_for_pg() string {
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0') or { return '19091' }
	addr := listener.addr() or {
		listener.close() or {}
		return '19091'
	}
	port := addr.str().all_after_last(':')
	listener.close() or {}
	return port
}

// Helper: send a request and collect metrics
fn pg_send_and_collect(address string, request string, output chan event.Event) []event.Metric {
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

fn test_pushgateway_accepts_put() {
	port := get_free_port_for_pg()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_pushgateway({
		'address': address
	})
	spawn run_pushgateway_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := '# TYPE cpu gauge\ncpu 75.0\n'
	request := 'PUT /metrics/job/testjob HTTP/1.1\r\nHost: localhost\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := pg_send_and_collect(address, request, output)
	assert metrics.len >= 1
	assert metrics[0].name == 'cpu'
	assert metrics[0].tags['job'] == 'testjob'
	assert metrics[0].meta.source_type == 'prometheus_pushgateway'
}

fn test_pushgateway_accepts_post() {
	port := get_free_port_for_pg()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_pushgateway({
		'address': address
	})
	spawn run_pushgateway_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := 'mem_usage 512\n'
	request := 'POST /metrics/job/myjob HTTP/1.1\r\nHost: localhost\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := pg_send_and_collect(address, request, output)
	assert metrics.len >= 1
}

fn test_pushgateway_job_label_from_url() {
	port := get_free_port_for_pg()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_pushgateway({
		'address': address
	})
	spawn run_pushgateway_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := '# TYPE requests counter\nrequests_total 42\n'
	request := 'PUT /metrics/job/batch_processor HTTP/1.1\r\nHost: localhost\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := pg_send_and_collect(address, request, output)
	if metrics.len > 0 {
		assert metrics[0].tags['job'] == 'batch_processor'
	}
}

fn test_pushgateway_grouping_labels() {
	port := get_free_port_for_pg()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_pushgateway({
		'address': address
	})
	spawn run_pushgateway_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := 'temp 22\n'
	request := 'PUT /metrics/job/myjob/instance/host1/env/staging HTTP/1.1\r\nHost: localhost\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := pg_send_and_collect(address, request, output)
	if metrics.len > 0 {
		assert metrics[0].tags['job'] == 'myjob'
		assert metrics[0].tags['instance'] == 'host1'
		assert metrics[0].tags['env'] == 'staging'
	}
}

fn test_pushgateway_rejects_get() {
	port := get_free_port_for_pg()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_pushgateway({
		'address': address
	})
	spawn run_pushgateway_source(&src, output)
	time.sleep(100 * time.millisecond)

	request := 'GET /metrics/job/myjob HTTP/1.1\r\nHost: localhost\r\n\r\n'

	metrics := pg_send_and_collect(address, request, output)
	assert metrics.len == 0
}

fn test_pushgateway_rejects_no_job() {
	port := get_free_port_for_pg()
	address := '127.0.0.1:${port}'
	output := chan event.Event{cap: 100}

	src := new_prometheus_pushgateway({
		'address': address
	})
	spawn run_pushgateway_source(&src, output)
	time.sleep(100 * time.millisecond)

	body := 'temp 22\n'
	request := 'PUT /metrics/job/ HTTP/1.1\r\nHost: localhost\r\nContent-Length: ${body.len}\r\n\r\n${body}'

	metrics := pg_send_and_collect(address, request, output)
	assert metrics.len == 0
}
