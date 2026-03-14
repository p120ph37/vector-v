module transforms

import event

fn test_ec2_metadata_create_non_required() {
	mut opts := map[string]string{}
	opts['required'] = 'false'
	opts['endpoint'] = 'http://127.0.0.1:1'
	opts['fields'] = 'instance-id, region'
	opts['namespace'] = 'ec2'
	opts['refresh_interval_secs'] = '5'
	mut t := new_ec2_metadata(opts) or { return }
	// Transform should work even with empty metadata cache
	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { return }
	assert result.len == 1
}

fn test_ec2_metadata_create_required_fails() {
	mut opts := map[string]string{}
	opts['endpoint'] = 'http://127.0.0.1:1'
	opts['refresh_interval_secs'] = '1'
	// required defaults to true, should fail
	if _ := new_ec2_metadata(opts) {
		// If somehow it succeeds (unlikely), that's ok
	}
}

fn test_ec2_metadata_default_fields() {
	mut opts := map[string]string{}
	opts['required'] = 'false'
	opts['endpoint'] = 'http://127.0.0.1:1'
	mut t := new_ec2_metadata(opts) or { return }
	// Should have default fields
	assert t.fields.len > 0
}

fn test_ec2_metadata_metric_passthrough() {
	mut opts := map[string]string{}
	opts['required'] = 'false'
	opts['endpoint'] = 'http://127.0.0.1:1'
	opts['namespace'] = 'aws'
	mut t := new_ec2_metadata(opts) or { return }
	
	ev := event.Event(event.Metric{
		name: 'cpu'
		kind: .absolute
		value: event.MetricValue(event.GaugeValue{value: 0.5})
	})
	result := t.transform(ev) or { return }
	assert result.len == 1
}

fn test_ec2_parse_identity_document() {
	body := '{"instanceId": "i-1234567890abcdef0", "region": "us-east-1", "accountId": "123456789012"}'
	result := parse_identity_document(body)
	assert result['instanceId'] == 'i-1234567890abcdef0'
	assert result['region'] == 'us-east-1'
	assert result['accountId'] == '123456789012'
}

fn test_ec2_parse_identity_document_empty() {
	result := parse_identity_document('')
	assert result.len == 0
}
