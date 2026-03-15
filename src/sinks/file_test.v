module sinks

import event
import os
import time

fn test_new_file_defaults() {
	s := new_file({
		'path': '/tmp/vector-test/output.log'
	})!
	assert s.path_template == '/tmp/vector-test/output.log'
	assert s.codec == .ndjson_codec
}

fn test_new_file_text_codec() {
	s := new_file({
		'path':           '/tmp/vector-test/output.log'
		'encoding.codec': 'text'
	})!
	assert s.codec == .text_codec
}

fn test_new_file_json_codec() {
	s := new_file({
		'path':           '/tmp/vector-test/output.log'
		'encoding.codec': 'json'
	})!
	assert s.codec == .json_codec
}

fn test_new_file_missing_path() {
	new_file(map[string]string{}) or {
		assert err.msg().contains('path is required')
		return
	}
	assert false, 'expected error for missing path'
}

fn test_resolve_file_path_no_template() {
	result := resolve_file_path('/var/log/app.log', time.now())
	assert result == '/var/log/app.log'
}

fn test_resolve_file_path_with_date() {
	t := time.Time{
		year: 2025
		month: 3
		day: 15
		hour: 10
		minute: 30
		second: 45
	}
	result := resolve_file_path('/var/log/%Y-%m-%d/app.log', t)
	assert result == '/var/log/2025-03-15/app.log'
}

fn test_resolve_file_path_with_time() {
	t := time.Time{
		year: 2025
		month: 1
		day: 5
		hour: 8
		minute: 5
		second: 2
	}
	result := resolve_file_path('/var/log/%Y/%m/%d/%H-%M-%S.log', t)
	assert result == '/var/log/2025/01/05/08-05-02.log'
}

fn test_file_write_and_read() {
	test_dir := '/tmp/vector-v-test-file-sink-${time.now().unix()}'
	defer { os.rmdir_all(test_dir) or {} }

	mut s := new_file({
		'path':           '${test_dir}/output.log'
		'encoding.codec': 'text'
	})!

	ev1 := event.Event(event.new_log('hello world'))
	ev2 := event.Event(event.new_log('second line'))
	s.send(ev1)!
	s.send(ev2)!

	content := os.read_file('${test_dir}/output.log') or { '' }
	lines := content.trim_right('\n').split('\n')
	assert lines.len == 2
	assert lines[0] == 'hello world'
	assert lines[1] == 'second line'
}

fn test_file_write_json() {
	test_dir := '/tmp/vector-v-test-file-json-${time.now().unix()}'
	defer { os.rmdir_all(test_dir) or {} }

	mut s := new_file({
		'path':           '${test_dir}/output.json'
		'encoding.codec': 'json'
	})!

	ev := event.Event(event.new_log('json test'))
	s.send(ev)!

	content := os.read_file('${test_dir}/output.json') or { '' }
	assert content.contains('"message"')
	assert content.contains('json test')
}

fn test_file_write_ndjson() {
	test_dir := '/tmp/vector-v-test-file-ndjson-${time.now().unix()}'
	defer { os.rmdir_all(test_dir) or {} }

	mut s := new_file({
		'path': '${test_dir}/output.ndjson'
	})!

	ev1 := event.Event(event.new_log('first'))
	ev2 := event.Event(event.new_log('second'))
	s.send(ev1)!
	s.send(ev2)!

	content := os.read_file('${test_dir}/output.ndjson') or { '' }
	lines := content.trim_right('\n').split('\n')
	assert lines.len == 2
	assert lines[0].contains('"message"')
	assert lines[0].contains('first')
	assert lines[1].contains('second')
}

fn test_file_creates_directories() {
	test_dir := '/tmp/vector-v-test-file-mkdir-${time.now().unix()}'
	defer { os.rmdir_all(test_dir) or {} }

	mut s := new_file({
		'path':           '${test_dir}/sub/dir/output.log'
		'encoding.codec': 'text'
	})!

	ev := event.Event(event.new_log('nested'))
	s.send(ev)!

	assert os.exists('${test_dir}/sub/dir/output.log')
}

fn test_file_total_open() {
	test_dir := '/tmp/vector-v-test-file-open-${time.now().unix()}'
	defer { os.rmdir_all(test_dir) or {} }

	mut s := new_file({
		'path':           '${test_dir}/output.log'
		'encoding.codec': 'text'
	})!

	assert s.total_open() == 0

	ev := event.Event(event.new_log('test'))
	s.send(ev)!
	assert s.total_open() == 1
}

fn test_file_multiple_events() {
	test_dir := '/tmp/vector-v-test-file-multi-${time.now().unix()}'
	defer { os.rmdir_all(test_dir) or {} }

	mut s := new_file({
		'path':           '${test_dir}/output.log'
		'encoding.codec': 'text'
	})!

	for i in 0 .. 10 {
		ev := event.Event(event.new_log('line ${i}'))
		s.send(ev)!
	}

	content := os.read_file('${test_dir}/output.log') or { '' }
	lines := content.trim_right('\n').split('\n')
	assert lines.len == 10
	assert lines[0] == 'line 0'
	assert lines[9] == 'line 9'
}

fn test_file_metric_events() {
	test_dir := '/tmp/vector-v-test-file-metric-${time.now().unix()}'
	defer { os.rmdir_all(test_dir) or {} }

	mut s := new_file({
		'path': '${test_dir}/metrics.log'
	})!

	metric := event.Event(event.Metric{
		name: 'cpu.usage'
		kind: .incremental
		value: event.MetricValue(event.CounterValue{ value: 42.0 })
	})
	s.send(metric)!

	content := os.read_file('${test_dir}/metrics.log') or { '' }
	assert content.contains('cpu.usage')
}
