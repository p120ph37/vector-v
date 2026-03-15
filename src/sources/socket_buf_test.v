module sources

fn test_socket_buffer_simple_line() {
	mut sb := new_socket_buffer(1024)
	sb.feed('hello world\n'.bytes())
	lines := sb.read_lines()
	assert lines.len == 1
	assert lines[0] == 'hello world'
}

fn test_socket_buffer_multiple_lines() {
	mut sb := new_socket_buffer(1024)
	sb.feed('line1\nline2\nline3\n'.bytes())
	lines := sb.read_lines()
	assert lines.len == 3
	assert lines[0] == 'line1'
	assert lines[1] == 'line2'
	assert lines[2] == 'line3'
}

fn test_socket_buffer_partial_line() {
	mut sb := new_socket_buffer(1024)
	sb.feed('partial'.bytes())
	lines := sb.read_lines()
	assert lines.len == 0
	assert sb.remaining() == 'partial'
}

fn test_socket_buffer_incremental_feed() {
	mut sb := new_socket_buffer(1024)
	sb.feed('hel'.bytes())
	assert sb.read_lines().len == 0
	sb.feed('lo\n'.bytes())
	lines := sb.read_lines()
	assert lines.len == 1
	assert lines[0] == 'hello'
}

fn test_socket_buffer_crlf() {
	mut sb := new_socket_buffer(1024)
	sb.feed('windows\r\n'.bytes())
	lines := sb.read_lines()
	assert lines.len == 1
	assert lines[0] == 'windows'
}

fn test_socket_buffer_max_length() {
	mut sb := new_socket_buffer(5)
	sb.feed('toolongline\n'.bytes())
	lines := sb.read_lines()
	assert lines.len == 1
	assert lines[0] == 'toolo' // truncated to max_length
}

fn test_socket_buffer_max_length_no_newline() {
	mut sb := new_socket_buffer(5)
	sb.feed('abcdefghij'.bytes())
	lines := sb.read_lines()
	assert lines.len == 1
	assert lines[0] == 'abcde' // force-flushed at max_length
}

fn test_socket_buffer_empty_lines() {
	mut sb := new_socket_buffer(1024)
	sb.feed('a\n\nb\n'.bytes())
	lines := sb.read_lines()
	assert lines.len == 3
	assert lines[0] == 'a'
	assert lines[1] == ''
	assert lines[2] == 'b'
}

fn test_socket_buffer_clear() {
	mut sb := new_socket_buffer(1024)
	sb.feed('data'.bytes())
	sb.clear()
	assert sb.remaining() == ''
}

fn test_new_socket_buffer_defaults() {
	sb := new_socket_buffer(0)
	assert sb.max_length == 102400
}

fn test_new_socket_buffer_custom() {
	sb := new_socket_buffer(500)
	assert sb.max_length == 500
}

fn test_socket_buffer_large_input() {
	mut sb := new_socket_buffer(102400)
	mut data := ''
	for i in 0 .. 100 {
		data += 'line${i}\n'
	}
	sb.feed(data.bytes())
	lines := sb.read_lines()
	assert lines.len == 100
	assert lines[0] == 'line0'
	assert lines[99] == 'line99'
}
