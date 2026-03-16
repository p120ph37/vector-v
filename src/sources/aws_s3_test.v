module sources

import os

fn test_parse_s3_keys_basic() {
	xml := '<?xml version="1.0"?><ListBucketResult><Contents><Key>file1.log</Key></Contents><Contents><Key>folder/file2.log</Key></Contents></ListBucketResult>'
	keys := parse_s3_keys(xml)
	assert keys.len == 2
	assert keys[0] == 'file1.log'
	assert keys[1] == 'folder/file2.log'
}

fn test_parse_s3_keys_empty() {
	xml := '<?xml version="1.0"?><ListBucketResult></ListBucketResult>'
	keys := parse_s3_keys(xml)
	assert keys.len == 0
}

fn test_parse_s3_keys_empty_string() {
	keys := parse_s3_keys('')
	assert keys.len == 0
}

fn test_parse_s3_keys_multiple() {
	xml := '<ListBucketResult><Contents><Key>a.log</Key></Contents><Contents><Key>b.log</Key></Contents><Contents><Key>c/d.log</Key></Contents><Contents><Key>e/f/g.log</Key></Contents></ListBucketResult>'
	keys := parse_s3_keys(xml)
	assert keys.len == 4
	assert keys[0] == 'a.log'
	assert keys[1] == 'b.log'
	assert keys[2] == 'c/d.log'
	assert keys[3] == 'e/f/g.log'
}

fn test_parse_s3_keys_single() {
	xml := '<ListBucketResult><Contents><Key>only-one.txt</Key></Contents></ListBucketResult>'
	keys := parse_s3_keys(xml)
	assert keys.len == 1
	assert keys[0] == 'only-one.txt'
}

fn test_parse_s3_keys_no_key_tags() {
	xml := '<ListBucketResult><Contents><Size>1024</Size></Contents></ListBucketResult>'
	keys := parse_s3_keys(xml)
	assert keys.len == 0
}

fn test_parse_s3_keys_special_characters() {
	xml := '<ListBucketResult><Contents><Key>path/with spaces/file.log</Key></Contents><Contents><Key>path/with+plus.log</Key></Contents></ListBucketResult>'
	keys := parse_s3_keys(xml)
	assert keys.len == 2
	assert keys[0] == 'path/with spaces/file.log'
	assert keys[1] == 'path/with+plus.log'
}

fn test_parse_s3_keys_malformed_xml() {
	// Missing closing Key tag - should only parse complete pairs
	xml := '<ListBucketResult><Contents><Key>good.log</Key></Contents><Contents><Key>incomplete</Contents></ListBucketResult>'
	keys := parse_s3_keys(xml)
	assert keys.len == 1
	assert keys[0] == 'good.log'
}

fn set_fake_aws_env() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_REGION', 'us-east-1', true)
}

fn unset_fake_aws_env() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.unsetenv('AWS_REGION')
}

fn test_new_s3_source_defaults() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := new_s3_source({
		'bucket': 'my-bucket'
	}) or { panic(err.str()) }
	assert s.bucket == 'my-bucket'
	assert s.prefix == ''
	assert s.region == 'us-east-1'
	assert s.codec == 'text'
	assert s.creds.access_key_id == 'AKIAIOSFODNN7EXAMPLE'
	assert s.creds.secret_access_key == 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
}

fn test_new_s3_source_missing_bucket() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	result := new_s3_source({}) or {
		assert err.msg().contains('bucket')
		return
	}
	assert false, 'expected error for missing bucket'
}

fn test_new_s3_source_custom_endpoint() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := new_s3_source({
		'bucket':   'test-bucket'
		'endpoint': 'http://localhost:4566'
	}) or { panic(err.str()) }
	assert s.endpoint == 'http://localhost:4566'
	assert s.bucket == 'test-bucket'
}

fn test_new_s3_source_codec_text() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := new_s3_source({
		'bucket': 'test-bucket'
		'codec':  'text'
	}) or { panic(err.str()) }
	assert s.codec == 'text'
}

fn test_new_s3_source_codec_json() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := new_s3_source({
		'bucket': 'test-bucket'
		'codec':  'json'
	}) or { panic(err.str()) }
	assert s.codec == 'json'
}

fn test_new_s3_source_prefix() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := new_s3_source({
		'bucket': 'test-bucket'
		'prefix': 'logs/2024/'
	}) or { panic(err.str()) }
	assert s.prefix == 'logs/2024/'
}

fn test_new_s3_source_custom_region() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := new_s3_source({
		'bucket':              'test-bucket'
		'auth.access_key_id': 'AKIA_CUSTOM'
		'auth.secret_access_key': 'secret_custom'
		'region':              'eu-west-1'
	}) or { panic(err.str()) }
	assert s.region == 'eu-west-1'
	assert s.creds.access_key_id == 'AKIA_CUSTOM'
}

fn test_new_s3_source_custom_poll_interval() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := new_s3_source({
		'bucket':              'test-bucket'
		'poll_interval_secs':  '30'
	}) or { panic(err.str()) }
	// 30 seconds in nanoseconds
	assert s.poll_interval == 30_000_000_000
}

fn test_new_s3_source_negative_poll_interval_uses_default() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := new_s3_source({
		'bucket':              'test-bucket'
		'poll_interval_secs':  '-5'
	}) or { panic(err.str()) }
	// Should fall back to 15 seconds default
	assert s.poll_interval == 15_000_000_000
}

fn test_new_s3_source_explicit_creds() {
	// Don't rely on env, use explicit auth opts
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')

	s := new_s3_source({
		'bucket':                  'cred-bucket'
		'auth.access_key_id':     'AKID_EXPLICIT'
		'auth.secret_access_key': 'SECRET_EXPLICIT'
		'auth.session_token':     'TOKEN_EXPLICIT'
		'region':                  'ap-southeast-1'
	}) or { panic(err.str()) }
	assert s.creds.access_key_id == 'AKID_EXPLICIT'
	assert s.creds.secret_access_key == 'SECRET_EXPLICIT'
	assert s.creds.session_token == 'TOKEN_EXPLICIT'
	assert s.region == 'ap-southeast-1'
}

fn test_new_s3_source_default_endpoint_includes_region() {
	s := new_s3_source({
		'bucket':                  'test-bucket'
		'auth.access_key_id':     'AKID'
		'auth.secret_access_key': 'SECRET'
		'region':                  'us-west-2'
	}) or { panic(err.str()) }
	assert s.endpoint == 'https://s3.us-west-2.amazonaws.com'
}

fn test_s3_source_registry() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := build_source('aws_s3', {
		'bucket': 'registry-bucket'
	}) or { panic(err.str()) }
	assert s is S3Source
}
