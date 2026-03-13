module transforms

fn test_parse_identity_document_basic() {
	body := '{"instanceId":"i-12345","region":"us-east-1","accountId":"123456789"}'
	result := parse_identity_document(body)
	assert result['instanceId'] == 'i-12345'
	assert result['region'] == 'us-east-1'
	assert result['accountId'] == '123456789'
}

fn test_parse_identity_document_empty() {
	result := parse_identity_document('')
	assert result.len == 0
}

fn test_parse_identity_document_too_short() {
	result := parse_identity_document('x')
	assert result.len == 0
}

fn test_parse_identity_document_minimal() {
	body := '{"key":"value"}'
	result := parse_identity_document(body)
	assert result['key'] == 'value'
}

fn test_new_ec2_metadata_non_required() {
	// When required=false and metadata fetch fails (no EC2 endpoint),
	// it should succeed with empty metadata.
	// Use localhost with unlikely port so the connection fails fast.
	t := new_ec2_metadata({
		'required': 'false'
		'endpoint': 'http://127.0.0.1:19'
	}) or { panic(err) }
	assert t.fields.len > 0 // should have default fields
	assert t.endpoint == 'http://127.0.0.1:19'
}

fn test_new_ec2_metadata_custom_fields() {
	t := new_ec2_metadata({
		'required': 'false'
		'endpoint': 'http://127.0.0.1:19'
		'fields':   'instance-id,region'
	}) or { panic(err) }
	assert t.fields.len == 2
	assert t.fields[0] == 'instance-id'
	assert t.fields[1] == 'region'
}

fn test_new_ec2_metadata_custom_namespace() {
	t := new_ec2_metadata({
		'required':  'false'
		'endpoint':  'http://127.0.0.1:19'
		'namespace': 'ec2'
	}) or { panic(err) }
	assert t.namespace == 'ec2'
}

fn test_new_ec2_metadata_custom_refresh() {
	t := new_ec2_metadata({
		'required':               'false'
		'endpoint':               'http://127.0.0.1:19'
		'refresh_interval_secs': '60'
	}) or { panic(err) }
	assert t.refresh_secs == 60
}
