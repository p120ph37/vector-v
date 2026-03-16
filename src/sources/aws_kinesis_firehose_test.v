module sources

fn test_new_kinesis_firehose_defaults() {
	s := new_kinesis_firehose({})
	assert s.address == '0.0.0.0:443'
	assert s.access_key == ''
	assert s.store_access_key == false
}

fn test_new_kinesis_firehose_custom_address() {
	s := new_kinesis_firehose({
		'address': '127.0.0.1:8080'
	})
	assert s.address == '127.0.0.1:8080'
}

fn test_new_kinesis_firehose_custom_access_key() {
	s := new_kinesis_firehose({
		'access_key': 'my-secret-key-123'
	})
	assert s.access_key == 'my-secret-key-123'
	assert s.store_access_key == false
}

fn test_new_kinesis_firehose_store_access_key_true() {
	s := new_kinesis_firehose({
		'access_key':       'key-456'
		'store_access_key': 'true'
	})
	assert s.access_key == 'key-456'
	assert s.store_access_key == true
}

fn test_new_kinesis_firehose_store_access_key_false() {
	s := new_kinesis_firehose({
		'store_access_key': 'false'
	})
	assert s.store_access_key == false
}

fn test_new_kinesis_firehose_store_access_key_invalid() {
	// Non-"true" value should be treated as false
	s := new_kinesis_firehose({
		'store_access_key': 'yes'
	})
	assert s.store_access_key == false
}

fn test_new_kinesis_firehose_all_options() {
	s := new_kinesis_firehose({
		'address':          '0.0.0.0:9000'
		'access_key':       'firehose-key'
		'store_access_key': 'true'
	})
	assert s.address == '0.0.0.0:9000'
	assert s.access_key == 'firehose-key'
	assert s.store_access_key == true
}

fn test_kinesis_firehose_registry() {
	s := build_source('aws_kinesis_firehose', {}) or { panic(err.str()) }
	assert s is KinesisFirehoseSource
}

fn test_kinesis_firehose_registry_with_config() {
	s := build_source('aws_kinesis_firehose', {
		'address':    '0.0.0.0:8443'
		'access_key': 'test-key'
	}) or { panic(err.str()) }
	assert s is KinesisFirehoseSource
}
