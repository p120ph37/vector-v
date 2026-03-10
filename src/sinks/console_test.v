module sinks

import event

fn test_console_default_opts() {
	opts := map[string]string{}
	s := new_console(opts)
	assert s.target == .stdout
	assert s.codec == .json
}

fn test_console_stderr_target() {
	mut opts := map[string]string{}
	opts['target'] = 'stderr'
	s := new_console(opts)
	assert s.target == .stderr
}

fn test_console_text_codec() {
	mut opts := map[string]string{}
	opts['encoding.codec'] = 'text'
	s := new_console(opts)
	assert s.codec == .text
}

fn test_console_logfmt_codec() {
	mut opts := map[string]string{}
	opts['encoding.codec'] = 'logfmt'
	s := new_console(opts)
	assert s.codec == .logfmt
}

fn test_console_json_encode() {
	opts := map[string]string{}
	s := new_console(opts)
	ev := event.Event(event.new_log('hello'))
	encoded := s.encode(ev)
	assert encoded.contains('"message"')
	assert encoded.contains('hello')
}

fn test_console_text_encode() {
	mut opts := map[string]string{}
	opts['encoding.codec'] = 'text'
	s := new_console(opts)
	ev := event.Event(event.new_log('hello world'))
	encoded := s.encode(ev)
	assert encoded == 'hello world'
}

fn test_console_logfmt_encode() {
	mut opts := map[string]string{}
	opts['encoding.codec'] = 'logfmt'
	s := new_console(opts)

	mut log := event.new_log('test')
	log.set('level', event.Value('info'))
	ev := event.Event(log)
	encoded := s.encode(ev)
	assert encoded.contains('message=test')
	assert encoded.contains('level=info')
}
