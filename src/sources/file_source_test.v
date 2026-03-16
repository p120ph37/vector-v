module sources

import os

fn test_new_file_defaults() {
	s := new_file({
		'include': '/var/log/*.log'
	}) or { panic(err.str()) }
	assert s.include.len == 1
	assert s.include[0] == '/var/log/*.log'
	assert s.exclude.len == 0
	assert s.read_from == .end
}

fn test_new_file_missing_include() {
	if _ := new_file({}) {
		assert false, 'expected error for missing include'
	}
}

fn test_new_file_empty_include() {
	if _ := new_file({'include': '  '}) {
		assert false, 'expected error for empty include'
	}
}

fn test_new_file_multiple_include_patterns() {
	s := new_file({
		'include': '/var/log/*.log, /tmp/*.txt'
	}) or { panic(err.str()) }
	assert s.include.len == 2
	assert s.include[0] == '/var/log/*.log'
	assert s.include[1] == '/tmp/*.txt'
}

fn test_new_file_exclude_patterns() {
	s := new_file({
		'include': '/var/log/*.log'
		'exclude': '/var/log/debug.log, /var/log/trace.log'
	}) or { panic(err.str()) }
	assert s.exclude.len == 2
	assert s.exclude[0] == '/var/log/debug.log'
	assert s.exclude[1] == '/var/log/trace.log'
}

fn test_new_file_read_from_beginning() {
	s := new_file({
		'include':   '/tmp/*.log'
		'read_from': 'beginning'
	}) or { panic(err.str()) }
	assert s.read_from == .beginning
}

fn test_new_file_read_from_end() {
	s := new_file({
		'include':   '/tmp/*.log'
		'read_from': 'end'
	}) or { panic(err.str()) }
	assert s.read_from == .end
}

fn test_new_file_read_from_invalid_defaults_end() {
	s := new_file({
		'include':   '/tmp/*.log'
		'read_from': 'invalid'
	}) or { panic(err.str()) }
	assert s.read_from == .end
}

fn test_new_file_ignore_older() {
	s := new_file({
		'include':          '/tmp/*.log'
		'ignore_older_secs': '3600'
	}) or { panic(err.str()) }
	assert s.ignore_older > 0
}

fn test_new_file_negative_ignore_older() {
	s := new_file({
		'include':          '/tmp/*.log'
		'ignore_older_secs': '-10'
	}) or { panic(err.str()) }
	assert s.ignore_older == 0
}

fn test_new_file_poll_interval() {
	s := new_file({
		'include':            '/tmp/*.log'
		'poll_interval_secs': '5'
	}) or { panic(err.str()) }
	assert s.poll_interval > 0
}

fn test_new_file_negative_poll_interval_defaults() {
	s := new_file({
		'include':            '/tmp/*.log'
		'poll_interval_secs': '-1'
	}) or { panic(err.str()) }
	assert s.poll_interval > 0
}

fn test_new_file_all_options() {
	s := new_file({
		'include':            '/var/log/*.log, /tmp/*.txt'
		'exclude':            '/var/log/debug.log'
		'read_from':          'beginning'
		'ignore_older_secs':  '7200'
		'poll_interval_secs': '2'
	}) or { panic(err.str()) }
	assert s.include.len == 2
	assert s.exclude.len == 1
	assert s.read_from == .beginning
	assert s.ignore_older > 0
	assert s.poll_interval > 0
}

fn test_match_glob_exact() {
	assert match_glob('hello', 'hello') == true
	assert match_glob('hello', 'world') == false
}

fn test_match_glob_star() {
	assert match_glob('*.log', 'access.log') == true
	assert match_glob('*.log', 'access.txt') == false
	assert match_glob('/var/log/*', '/var/log/syslog') == true
}

fn test_match_glob_question() {
	assert match_glob('file?.txt', 'file1.txt') == true
	assert match_glob('file?.txt', 'file12.txt') == false
}

fn test_discover_files_with_real_files() {
	// Create temp files to test discovery
	dir := os.join_path(os.temp_dir(), 'vector_v_file_source_test')
	os.mkdir_all(dir) or {}
	defer { os.rmdir_all(dir) or {} }

	os.write_file(os.join_path(dir, 'app.log'), 'line1\nline2\n') or {}
	os.write_file(os.join_path(dir, 'debug.log'), 'debug\n') or {}
	os.write_file(os.join_path(dir, 'data.txt'), 'data\n') or {}

	s := new_file({
		'include': os.join_path(dir, '*.log')
		'exclude': os.join_path(dir, 'debug.log')
	}) or { panic(err.str()) }

	files := s.discover_files()
	assert files.len == 1
	assert files[0].contains('app.log')
}
