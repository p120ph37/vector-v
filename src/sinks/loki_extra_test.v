module sinks

import event

fn test_loki_text_codec_encoding() {
	mut s := new_loki({
		'endpoint':         'http://localhost:3100'
		'labels.job':       'test'
		'encoding.codec':   'text'
		'batch.max_events': '1000'
	})
	assert s.codec == .text_codec

	ev := event.Event(event.new_log('hello text codec'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	// With text codec, the line should be just the message
	for _, batch in s.batches {
		assert batch.entries[0].line == 'hello text codec'
	}
}

fn test_loki_logfmt_codec_encoding() {
	mut s := new_loki({
		'endpoint':         'http://localhost:3100'
		'labels.job':       'test'
		'encoding.codec':   'logfmt'
		'batch.max_events': '1000'
	})
	assert s.codec == .logfmt_codec

	mut log := event.new_log('test message')
	log.set('level', event.Value('info'))
	ev := event.Event(log)
	s.send(ev) or {}
	assert s.total_buffered() == 1
	for _, batch in s.batches {
		line := batch.entries[0].line
		// logfmt encodes as key=value pairs
		assert line.contains('message=')
		assert line.contains('level=')
	}
}

fn test_loki_remove_label_fields() {
	mut s := new_loki({
		'endpoint':              'http://localhost:3100'
		'labels.env':            '{{ env }}'
		'remove_label_fields':   'true'
		'encoding.codec':        'json'
		'batch.max_events':      '1000'
	})
	assert s.remove_label_fields == true

	mut log := event.new_log('test')
	log.set('env', event.Value('production'))
	ev := event.Event(log)
	s.send(ev) or {}
	assert s.total_buffered() == 1
	// The 'env' field should be removed from the log line (JSON body)
	for _, batch in s.batches {
		line := batch.entries[0].line
		assert !line.contains('"env"')
	}
}

fn test_loki_dynamic_label_resolution() {
	mut s := new_loki({
		'endpoint':         'http://localhost:3100'
		'labels.host':      '{{ hostname }}'
		'labels.static':    'fixed_value'
		'batch.max_events': '1000'
	})

	mut log := event.new_log('test')
	log.set('hostname', event.Value('server01'))
	ev := event.Event(log)
	s.send(ev) or {}
	assert s.total_buffered() == 1
	for _, batch in s.batches {
		assert batch.labels['host'] == 'server01'
		assert batch.labels['static'] == 'fixed_value'
	}
}

fn test_loki_invalid_batch_defaults() {
	s := new_loki({
		'endpoint':         'http://localhost:3100'
		'batch.max_events': '0'
		'batch.timeout_secs': '-1'
	})
	assert s.batch_max == 100
}

fn test_loki_negative_batch_max_defaults() {
	s := new_loki({
		'endpoint':         'http://localhost:3100'
		'batch.max_events': '-5'
	})
	assert s.batch_max == 100
}

fn test_loki_unknown_codec_defaults_to_json() {
	s := new_loki({
		'endpoint':       'http://localhost:3100'
		'encoding.codec': 'unknown_codec'
	})
	assert s.codec == .json_codec
}

fn test_loki_json_codec_encoding() {
	mut s := new_loki({
		'endpoint':         'http://localhost:3100'
		'labels.job':       'test'
		'encoding.codec':   'json'
		'batch.max_events': '1000'
	})
	assert s.codec == .json_codec

	ev := event.Event(event.new_log('json test'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	for _, batch in s.batches {
		line := batch.entries[0].line
		assert line.contains('"message"')
		assert line.contains('json test')
	}
}

fn test_loki_dynamic_label_missing_field() {
	mut s := new_loki({
		'endpoint':         'http://localhost:3100'
		'labels.host':      '{{ nonexistent }}'
		'batch.max_events': '1000'
	})

	ev := event.Event(event.new_log('test'))
	s.send(ev) or {}
	assert s.total_buffered() == 1
	for _, batch in s.batches {
		assert 'host' !in batch.labels
	}
}

fn test_loki_multiple_events_batching() {
	mut s := new_loki({
		'endpoint':         'http://localhost:3100'
		'labels.job':       'test'
		'batch.max_events': '1000'
	})

	for i in 0 .. 5 {
		ev := event.Event(event.new_log('msg ${i}'))
		s.send(ev) or {}
	}
	assert s.total_buffered() == 5
}
