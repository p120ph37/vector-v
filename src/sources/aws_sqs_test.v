module sources

import os

fn test_parse_sqs_messages_basic() {
	xml := '<ReceiveMessageResponse><ReceiveMessageResult><Message><MessageId>msg-123</MessageId><ReceiptHandle>rh-abc</ReceiptHandle><Body>hello world</Body></Message></ReceiveMessageResult></ReceiveMessageResponse>'
	msgs := parse_sqs_messages(xml)
	assert msgs.len == 1
	assert msgs[0].message_id == 'msg-123'
	assert msgs[0].receipt_handle == 'rh-abc'
	assert msgs[0].body == 'hello world'
}

fn test_parse_sqs_messages_empty() {
	xml := '<ReceiveMessageResponse><ReceiveMessageResult></ReceiveMessageResult></ReceiveMessageResponse>'
	msgs := parse_sqs_messages(xml)
	assert msgs.len == 0
}

fn test_parse_sqs_messages_empty_string() {
	msgs := parse_sqs_messages('')
	assert msgs.len == 0
}

fn test_parse_sqs_messages_multiple() {
	xml := '<ReceiveMessageResponse><ReceiveMessageResult>' +
		'<Message><MessageId>m1</MessageId><ReceiptHandle>rh1</ReceiptHandle><Body>body1</Body></Message>' +
		'<Message><MessageId>m2</MessageId><ReceiptHandle>rh2</ReceiptHandle><Body>body2</Body></Message>' +
		'<Message><MessageId>m3</MessageId><ReceiptHandle>rh3</ReceiptHandle><Body>body3</Body></Message>' +
		'</ReceiveMessageResult></ReceiveMessageResponse>'
	msgs := parse_sqs_messages(xml)
	assert msgs.len == 3
	assert msgs[0].message_id == 'm1'
	assert msgs[0].body == 'body1'
	assert msgs[1].message_id == 'm2'
	assert msgs[1].receipt_handle == 'rh2'
	assert msgs[2].message_id == 'm3'
	assert msgs[2].body == 'body3'
}

fn test_parse_sqs_messages_missing_fields() {
	// Message with only Body, missing MessageId and ReceiptHandle
	xml := '<ReceiveMessageResponse><ReceiveMessageResult><Message><Body>just a body</Body></Message></ReceiveMessageResult></ReceiveMessageResponse>'
	msgs := parse_sqs_messages(xml)
	assert msgs.len == 1
	assert msgs[0].body == 'just a body'
	assert msgs[0].message_id == ''
	assert msgs[0].receipt_handle == ''
}

fn test_parse_sqs_messages_special_chars_in_body() {
	xml := '<ReceiveMessageResponse><ReceiveMessageResult><Message><MessageId>m-special</MessageId><ReceiptHandle>rh-special</ReceiptHandle><Body>{"key":"value","num":42}</Body></Message></ReceiveMessageResult></ReceiveMessageResponse>'
	msgs := parse_sqs_messages(xml)
	assert msgs.len == 1
	assert msgs[0].body == '{"key":"value","num":42}'
}

fn test_extract_xml_value() {
	xml := '<Root><Name>test-value</Name><Other>other-val</Other></Root>'
	assert extract_xml_value(xml, 'Name') == 'test-value'
	assert extract_xml_value(xml, 'Other') == 'other-val'
}

fn test_extract_xml_value_missing() {
	xml := '<Root><Name>test</Name></Root>'
	assert extract_xml_value(xml, 'Missing') == ''
}

fn test_extract_xml_value_empty() {
	xml := '<Root><Name></Name></Root>'
	assert extract_xml_value(xml, 'Name') == ''
}

fn test_extract_xml_value_empty_input() {
	assert extract_xml_value('', 'Name') == ''
}

fn set_fake_sqs_env() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAIOSFODNN7EXAMPLE', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY', true)
	os.setenv('AWS_REGION', 'us-east-1', true)
}

fn unset_fake_sqs_env() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.unsetenv('AWS_REGION')
}

fn test_new_sqs_source_defaults() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url': 'https://sqs.us-east-1.amazonaws.com/123456789/my-queue'
	}) or { panic(err.str()) }
	assert s.queue_url == 'https://sqs.us-east-1.amazonaws.com/123456789/my-queue'
	assert s.region == 'us-east-1'
	assert s.max_messages == 10
	assert s.visibility_timeout == 300
	assert s.wait_time_seconds == 20
	assert s.delete_message == true
	assert s.creds.access_key_id == 'AKIAIOSFODNN7EXAMPLE'
}

fn test_new_sqs_source_missing_queue_url() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	result := new_sqs({}) or {
		assert err.msg().contains('queue_url')
		return
	}
	assert false, 'expected error for missing queue_url'
}

fn test_new_sqs_source_custom() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url':           'https://sqs.eu-west-1.amazonaws.com/123/q'
		'endpoint':            'http://localhost:4566'
		'max_messages':        '5'
		'visibility_timeout':  '60'
		'wait_time_seconds':   '10'
		'delete_message':      'false'
		'poll_interval_secs':  '3'
	}) or { panic(err.str()) }
	assert s.endpoint == 'http://localhost:4566'
	assert s.max_messages == 5
	assert s.visibility_timeout == 60
	assert s.wait_time_seconds == 10
	assert s.delete_message == false
	// 3 seconds in nanoseconds
	assert s.poll_interval == 3_000_000_000
}

fn test_new_sqs_source_max_messages_clamped() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	// Over 10 should clamp to 10
	s := new_sqs({
		'queue_url':    'https://sqs.us-east-1.amazonaws.com/123/q'
		'max_messages': '15'
	}) or { panic(err.str()) }
	assert s.max_messages == 10
}

fn test_new_sqs_source_max_messages_negative_clamped() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url':    'https://sqs.us-east-1.amazonaws.com/123/q'
		'max_messages': '-1'
	}) or { panic(err.str()) }
	assert s.max_messages == 10
}

fn test_new_sqs_source_visibility_timeout_negative() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'visibility_timeout': '-10'
	}) or { panic(err.str()) }
	assert s.visibility_timeout == 300
}

fn test_new_sqs_source_wait_time_clamped() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	// Over 20 should clamp to 20
	s := new_sqs({
		'queue_url':         'https://sqs.us-east-1.amazonaws.com/123/q'
		'wait_time_seconds': '30'
	}) or { panic(err.str()) }
	assert s.wait_time_seconds == 20
}

fn test_new_sqs_source_wait_time_negative_clamped() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url':         'https://sqs.us-east-1.amazonaws.com/123/q'
		'wait_time_seconds': '-5'
	}) or { panic(err.str()) }
	assert s.wait_time_seconds == 20
}

fn test_new_sqs_source_poll_interval_negative() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'poll_interval_secs': '-1'
	}) or { panic(err.str()) }
	// Falls back to 1 second default
	assert s.poll_interval == 1_000_000_000
}

fn test_new_sqs_source_explicit_creds() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')

	s := new_sqs({
		'queue_url':               'https://sqs.us-east-1.amazonaws.com/123/q'
		'auth.access_key_id':     'AKID_SQS'
		'auth.secret_access_key': 'SECRET_SQS'
		'auth.session_token':     'TOKEN_SQS'
		'region':                  'ap-northeast-1'
	}) or { panic(err.str()) }
	assert s.creds.access_key_id == 'AKID_SQS'
	assert s.creds.secret_access_key == 'SECRET_SQS'
	assert s.creds.session_token == 'TOKEN_SQS'
	assert s.region == 'ap-northeast-1'
}

fn test_new_sqs_source_default_endpoint() {
	s := new_sqs({
		'queue_url':               'https://sqs.us-east-1.amazonaws.com/123/q'
		'auth.access_key_id':     'AKID'
		'auth.secret_access_key': 'SECRET'
		'region':                  'us-west-2'
	}) or { panic(err.str()) }
	assert s.endpoint == 'https://sqs.us-west-2.amazonaws.com'
}

fn test_new_sqs_source_zero_poll_interval() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'poll_interval_secs': '0'
	}) or { panic(err.str()) }
	// Falls back to 1 second default
	assert s.poll_interval == 1_000_000_000
}

fn test_new_sqs_source_zero_visibility_timeout() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url':          'https://sqs.us-east-1.amazonaws.com/123/q'
		'visibility_timeout': '0'
	}) or { panic(err.str()) }
	assert s.visibility_timeout == 300
}

fn test_new_sqs_source_zero_max_messages() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url':    'https://sqs.us-east-1.amazonaws.com/123/q'
		'max_messages': '0'
	}) or { panic(err.str()) }
	assert s.max_messages == 10
}

fn test_new_sqs_source_delete_message_true_explicit() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url':       'https://sqs.us-east-1.amazonaws.com/123/q'
		'delete_message': 'true'
	}) or { panic(err.str()) }
	assert s.delete_message == true
}

fn test_new_sqs_source_zero_wait_time() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	// Zero wait_time_seconds should be valid (short polling)
	// wait_time_seconds < 0 || > 20 => clamped. 0 is valid.
	s := new_sqs({
		'queue_url':         'https://sqs.us-east-1.amazonaws.com/123/q'
		'wait_time_seconds': '0'
	}) or { panic(err.str()) }
	assert s.wait_time_seconds == 0
}

fn test_new_sqs_source_valid_wait_time_in_range() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := new_sqs({
		'queue_url':         'https://sqs.us-east-1.amazonaws.com/123/q'
		'wait_time_seconds': '15'
	}) or { panic(err.str()) }
	assert s.wait_time_seconds == 15
}

fn test_extract_xml_value_missing_close_tag() {
	// Has open tag but no close tag
	assert extract_xml_value('<Name>test', 'Name') == ''
}

fn test_parse_sqs_messages_malformed_no_close_message() {
	// <Message> without </Message> - should not crash
	xml := '<ReceiveMessageResponse><Message><MessageId>m1</MessageId><Body>body1</Body>'
	msgs := parse_sqs_messages(xml)
	assert msgs.len == 0
}

fn test_sqs_source_registry() {
	set_fake_sqs_env()
	defer { unset_fake_sqs_env() }

	s := build_source('aws_sqs', {
		'queue_url': 'https://sqs.us-east-1.amazonaws.com/123/q'
	}) or { panic(err.str()) }
	assert s is SqsSource
}
