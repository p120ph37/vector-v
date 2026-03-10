module sinks

import event

fn test_new_loki_defaults() {
	s := new_loki({
		'endpoint': 'http://localhost:3100'
	})
	assert s.http.endpoint == 'http://localhost:3100'
	assert s.http.path == '/loki/api/v1/push'
	assert s.batch_max == 100
}

fn test_new_loki_with_labels() {
	s := new_loki({
		'endpoint':   'http://loki:3100'
		'labels.job': 'vector'
		'labels.env': 'prod'
	})
	assert s.labels['job'] == 'vector'
	assert s.labels['env'] == 'prod'
}

fn test_new_loki_with_tenant_id() {
	s := new_loki({
		'endpoint':  'http://loki:3100'
		'tenant_id': 'my-tenant'
	})
	assert s.tenant_id == 'my-tenant'
}

fn test_loki_format_label_key() {
	key := format_label_key({
		'job':  'vector'
		'host': 'server1'
	})
	// Should be sorted
	assert key.contains('host=server1')
	assert key.contains('job=vector')
}

fn test_loki_buffering() {
	mut s := new_loki({
		'endpoint':         'http://localhost:3100'
		'labels.job':       'test'
		'batch.max_events': '1000' // large batch to prevent auto-flush
	})

	ev := event.Event(event.new_log('test message'))
	// This won't actually send since batch is large
	s.send(ev) or {}
	assert s.total_buffered() == 1
}
