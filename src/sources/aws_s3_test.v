module sources

import aws
import event
import mockserver
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

fn test_new_s3_source_zero_poll_interval_uses_default() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := new_s3_source({
		'bucket':             'test-bucket'
		'poll_interval_secs': '0'
	}) or { panic(err.str()) }
	// Zero is <= 0, so should fall back to 15 seconds default
	assert s.poll_interval == 15_000_000_000
}

fn test_new_s3_source_region_fallback_default() {
	// No AWS_REGION in env, no region in opts -> should default to us-east-1
	os.unsetenv('AWS_REGION')
	os.unsetenv('AWS_DEFAULT_REGION')
	defer { unset_fake_aws_env() }

	s := new_s3_source({
		'bucket':                  'fallback-bucket'
		'auth.access_key_id':     'AKID_TEST'
		'auth.secret_access_key': 'SECRET_TEST'
	}) or { panic(err.str()) }
	assert s.region == 'us-east-1'
	assert s.endpoint == 'https://s3.us-east-1.amazonaws.com'
}

fn test_s3_source_list_objects_with_mock() {
	xml_response := '<?xml version="1.0"?><ListBucketResult><Contents><Key>logs/app.log</Key></Contents><Contents><Key>logs/err.log</Key></Contents></ListBucketResult>'
	mut mock := mockserver.start(
		mockserver.get('/test-bucket/?list-type=2', mockserver.respond(200, xml_response))
	)!
	defer { mock.stop() }

	s := S3Source{
		bucket: 'test-bucket'
		prefix: ''
		region: 'us-east-1'
		endpoint: mock.url()
		creds: fake_aws_creds()
	}

	keys := s.list_objects() or {
		assert false, 'list_objects failed: ${err}'
		return
	}
	assert keys.len == 2
	assert keys[0] == 'logs/app.log'
	assert keys[1] == 'logs/err.log'
}

fn test_s3_source_list_objects_with_prefix() {
	xml_response := '<ListBucketResult><Contents><Key>prefix/file.log</Key></Contents></ListBucketResult>'
	mut mock := mockserver.start(
		mockserver.get('/mybucket/?list-type=2&prefix=prefix%2F', mockserver.respond(200, xml_response))
	)!
	defer { mock.stop() }

	s := S3Source{
		bucket: 'mybucket'
		prefix: 'prefix/'
		region: 'us-east-1'
		endpoint: mock.url()
		creds: fake_aws_creds()
	}

	keys := s.list_objects() or {
		assert false, 'list_objects failed: ${err}'
		return
	}
	assert keys.len == 1
	assert keys[0] == 'prefix/file.log'
}

fn test_s3_source_list_objects_http_error() {
	mut mock := mockserver.start(
		mockserver.get('/err-bucket/?list-type=2', mockserver.respond(403, 'Access Denied'))
	)!
	defer { mock.stop() }

	s := S3Source{
		bucket: 'err-bucket'
		prefix: ''
		region: 'us-east-1'
		endpoint: mock.url()
		creds: fake_aws_creds()
	}

	keys := s.list_objects() or {
		assert err.msg().contains('403')
		return
	}
	assert false, 'expected error for HTTP 403'
}

fn test_s3_source_get_object_with_mock() {
	body := 'line1\nline2\nline3'
	mut mock := mockserver.start(
		mockserver.get('/mybucket/mykey.log', mockserver.respond(200, body))
	)!
	defer { mock.stop() }

	s := S3Source{
		bucket: 'mybucket'
		prefix: ''
		region: 'us-east-1'
		endpoint: mock.url()
		creds: fake_aws_creds()
	}

	result := s.get_object('mykey.log') or {
		assert false, 'get_object failed: ${err}'
		return
	}
	assert result == body
}

fn test_s3_source_get_object_http_error() {
	mut mock := mockserver.start(
		mockserver.get('/mybucket/missing.log', mockserver.respond(404, 'Not Found'))
	)!
	defer { mock.stop() }

	s := S3Source{
		bucket: 'mybucket'
		prefix: ''
		region: 'us-east-1'
		endpoint: mock.url()
		creds: fake_aws_creds()
	}

	result := s.get_object('missing.log') or {
		assert err.msg().contains('404')
		return
	}
	assert false, 'expected error for HTTP 404'
}

fn test_s3_source_poll_emits_events() {
	xml_response := '<ListBucketResult><Contents><Key>data.log</Key></Contents></ListBucketResult>'
	file_body := 'hello world\ngoodbye world'

	mut mock := mockserver.start(
		mockserver.get('/poll-bucket/?list-type=2', mockserver.respond(200, xml_response)),
		mockserver.get('/poll-bucket/data.log', mockserver.respond(200, file_body))
	)!
	defer { mock.stop() }

	s := S3Source{
		bucket: 'poll-bucket'
		prefix: ''
		region: 'us-east-1'
		endpoint: mock.url()
		creds: fake_aws_creds()
	}

	output := chan event.Event{cap: 10}
	mut seen := map[string]bool{}
	s.poll(output, mut seen)

	// Should have emitted 2 events (2 non-empty lines)
	mut ev1 := event.Event(event.new_log(''))
	mut ev2 := event.Event(event.new_log(''))
	assert output.try_pop(mut ev1) == .success
	assert output.try_pop(mut ev2) == .success

	// Verify seen map was updated
	assert seen['data.log'] == true

	// Second poll should skip already-seen key
	s.poll(output, mut seen)
	mut ev3 := event.Event(event.new_log(''))
	assert output.try_pop(mut ev3) != .success
}

fn test_s3_source_poll_handles_list_error() {
	mut mock := mockserver.start(
		mockserver.get('/fail-bucket/?list-type=2', mockserver.respond(500, 'Internal Error'))
	)!
	defer { mock.stop() }

	s := S3Source{
		bucket: 'fail-bucket'
		prefix: ''
		region: 'us-east-1'
		endpoint: mock.url()
		creds: fake_aws_creds()
	}

	output := chan event.Event{cap: 10}
	mut seen := map[string]bool{}
	// Should not panic, just log error and return
	s.poll(output, mut seen)

	mut ev := event.Event(event.new_log(''))
	assert output.try_pop(mut ev) != .success
}

fn test_s3_source_poll_handles_get_object_error() {
	xml_response := '<ListBucketResult><Contents><Key>bad.log</Key></Contents></ListBucketResult>'

	mut mock := mockserver.start(
		mockserver.get('/getfail-bucket/?list-type=2', mockserver.respond(200, xml_response)),
		mockserver.get('/getfail-bucket/bad.log', mockserver.respond(500, 'Error'))
	)!
	defer { mock.stop() }

	s := S3Source{
		bucket: 'getfail-bucket'
		prefix: ''
		region: 'us-east-1'
		endpoint: mock.url()
		creds: fake_aws_creds()
	}

	output := chan event.Event{cap: 10}
	mut seen := map[string]bool{}
	s.poll(output, mut seen)

	// No events should have been emitted due to get_object failure
	mut ev := event.Event(event.new_log(''))
	assert output.try_pop(mut ev) != .success
}

fn test_s3_source_poll_skips_empty_lines() {
	xml_response := '<ListBucketResult><Contents><Key>sparse.log</Key></Contents></ListBucketResult>'
	file_body := 'line1\n\n\nline2\n'

	mut mock := mockserver.start(
		mockserver.get('/sparse-bucket/?list-type=2', mockserver.respond(200, xml_response)),
		mockserver.get('/sparse-bucket/sparse.log', mockserver.respond(200, file_body))
	)!
	defer { mock.stop() }

	s := S3Source{
		bucket: 'sparse-bucket'
		prefix: ''
		region: 'us-east-1'
		endpoint: mock.url()
		creds: fake_aws_creds()
	}

	output := chan event.Event{cap: 10}
	mut seen := map[string]bool{}
	s.poll(output, mut seen)

	// Only 2 non-empty lines
	mut ev1 := event.Event(event.new_log(''))
	mut ev2 := event.Event(event.new_log(''))
	mut ev3 := event.Event(event.new_log(''))
	assert output.try_pop(mut ev1) == .success
	assert output.try_pop(mut ev2) == .success
	assert output.try_pop(mut ev3) != .success
}

fn fake_aws_creds() aws.AwsCredentials {
	return aws.AwsCredentials{
		access_key_id: 'AKIAIOSFODNN7EXAMPLE'
		secret_access_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
		region: 'us-east-1'
	}
}

fn test_s3_source_registry() {
	set_fake_aws_env()
	defer { unset_fake_aws_env() }

	s := build_source('aws_s3', {
		'bucket': 'registry-bucket'
	}) or { panic(err.str()) }
	assert s is S3Source
}
