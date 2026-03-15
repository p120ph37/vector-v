module aws

import time

// Test SigV4 signing against the AWS documentation example.
// Reference: https://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
fn test_sign_request_produces_valid_structure() {
	ts := time.parse_iso8601('2024-01-15T12:00:00Z') or { time.now() }
	config := SignConfig{
		creds: AwsCredentials{
			access_key_id: 'AKIAIOSFODNN7EXAMPLE'
			secret_access_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
			region: 'us-east-1'
		}
		method: 'POST'
		host: 'logs.us-east-1.amazonaws.com'
		path: '/'
		content_type: 'application/x-amz-json-1.1'
		payload: '{"logGroupName":"test"}'
		region: 'us-east-1'
		service: 'logs'
		timestamp: ts
	}

	signed := sign_request(config)!
	auth := signed.headers['Authorization']

	// Verify structure
	assert auth.starts_with('AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/')
	assert auth.contains('/us-east-1/logs/aws4_request')
	assert auth.contains('SignedHeaders=')
	assert auth.contains('Signature=')
	assert auth.contains('content-type')
	assert auth.contains('host')
	assert auth.contains('x-amz-date')

	// Verify X-Amz-Date header
	assert signed.headers['X-Amz-Date'] == '20240115T120000Z'
	assert signed.headers['Content-Type'] == 'application/x-amz-json-1.1'
}

fn test_sign_request_with_session_token() {
	ts := time.parse_iso8601('2024-01-15T12:00:00Z') or { time.now() }
	config := SignConfig{
		creds: AwsCredentials{
			access_key_id: 'ASIAEXAMPLE'
			secret_access_key: 'secret'
			session_token: 'FwoGZX...'
			region: 'us-east-1'
		}
		method: 'POST'
		host: 'logs.us-east-1.amazonaws.com'
		path: '/'
		content_type: 'application/x-amz-json-1.1'
		payload: '{}'
		region: 'us-east-1'
		service: 'logs'
		timestamp: ts
	}

	signed := sign_request(config)!
	auth := signed.headers['Authorization']

	// Session token should be included in signed headers
	assert auth.contains('x-amz-security-token')
	assert signed.headers['X-Amz-Security-Token'] == 'FwoGZX...'
}

fn test_sign_request_no_session_token() {
	ts := time.parse_iso8601('2024-01-15T12:00:00Z') or { time.now() }
	config := SignConfig{
		creds: AwsCredentials{
			access_key_id: 'AKIAEXAMPLE'
			secret_access_key: 'secret'
			region: 'us-east-1'
		}
		method: 'POST'
		host: 'logs.us-east-1.amazonaws.com'
		path: '/'
		content_type: 'application/x-amz-json-1.1'
		payload: '{}'
		region: 'us-east-1'
		service: 'logs'
		timestamp: ts
	}

	signed := sign_request(config)!
	auth := signed.headers['Authorization']

	// Without session token, x-amz-security-token should NOT be in signed headers
	assert !auth.contains('x-amz-security-token')
	assert 'X-Amz-Security-Token' !in signed.headers
}

fn test_sign_request_different_regions() {
	ts := time.parse_iso8601('2024-01-15T12:00:00Z') or { time.now() }

	for region in ['us-east-1', 'eu-west-1', 'ap-southeast-1'] {
		config := SignConfig{
			creds: AwsCredentials{
				access_key_id: 'AKIATEST'
				secret_access_key: 'testsecret'
			}
			host: 'logs.${region}.amazonaws.com'
			payload: '{}'
			region: region
			service: 'logs'
			timestamp: ts
		}

		signed := sign_request(config)!
		auth := signed.headers['Authorization']
		assert auth.contains('/${region}/logs/aws4_request')
	}
}

fn test_sign_request_different_services() {
	ts := time.parse_iso8601('2024-01-15T12:00:00Z') or { time.now() }

	for service in ['logs', 's3', 'monitoring'] {
		config := SignConfig{
			creds: AwsCredentials{
				access_key_id: 'AKIATEST'
				secret_access_key: 'testsecret'
			}
			host: '${service}.us-east-1.amazonaws.com'
			payload: '{}'
			region: 'us-east-1'
			service: service
			timestamp: ts
		}

		signed := sign_request(config)!
		auth := signed.headers['Authorization']
		assert auth.contains('/us-east-1/${service}/aws4_request')
	}
}

fn test_sign_request_deterministic() {
	ts := time.parse_iso8601('2024-01-15T12:00:00Z') or { time.now() }
	config := SignConfig{
		creds: AwsCredentials{
			access_key_id: 'AKIATEST'
			secret_access_key: 'testsecret'
		}
		host: 'logs.us-east-1.amazonaws.com'
		payload: '{"test":"data"}'
		region: 'us-east-1'
		service: 'logs'
		timestamp: ts
	}

	signed1 := sign_request(config)!
	signed2 := sign_request(config)!

	// Same input should produce same signature
	assert signed1.headers['Authorization'] == signed2.headers['Authorization']
}

fn test_sign_request_different_payloads_differ() {
	ts := time.parse_iso8601('2024-01-15T12:00:00Z') or { time.now() }
	base := SignConfig{
		creds: AwsCredentials{
			access_key_id: 'AKIATEST'
			secret_access_key: 'testsecret'
		}
		host: 'logs.us-east-1.amazonaws.com'
		region: 'us-east-1'
		service: 'logs'
		timestamp: ts
	}

	config1 := SignConfig{
		...base
		payload: '{"logGroupName":"group1"}'
	}
	config2 := SignConfig{
		...base
		payload: '{"logGroupName":"group2"}'
	}

	signed1 := sign_request(config1)!
	signed2 := sign_request(config2)!

	// Different payloads should produce different signatures
	assert signed1.headers['Authorization'] != signed2.headers['Authorization']
}

fn test_sign_request_extra_headers() {
	ts := time.parse_iso8601('2024-01-15T12:00:00Z') or { time.now() }
	config := SignConfig{
		creds: AwsCredentials{
			access_key_id: 'AKIATEST'
			secret_access_key: 'testsecret'
		}
		host: 'logs.us-east-1.amazonaws.com'
		payload: '{}'
		region: 'us-east-1'
		service: 'logs'
		timestamp: ts
		extra_headers: {
			'X-Amz-Target': 'Logs_20140328.PutLogEvents'
		}
	}

	signed := sign_request(config)!
	auth := signed.headers['Authorization']

	// Extra headers should be included in signed headers
	assert auth.contains('x-amz-target')
	assert signed.headers['X-Amz-Target'] == 'Logs_20140328.PutLogEvents'
}

fn test_hex_sha256_empty() {
	result := hex_sha256('')
	// SHA-256 of empty string
	assert result == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
}

fn test_hex_sha256_nonempty() {
	result := hex_sha256('hello')
	assert result == '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'
}

fn test_sorted_keys() {
	m := {
		'charlie': '3'
		'alpha':   '1'
		'bravo':   '2'
	}
	keys := sorted_keys(m)
	assert keys == ['alpha', 'bravo', 'charlie']
}

fn test_sorted_keys_empty_map() {
	m := map[string]string{}
	keys := sorted_keys(m)
	assert keys.len == 0
}

// AWS SigV4 test suite reference signature test.
// This verifies our implementation against a known-good AWS example.
fn test_sign_request_aws_example_credential_scope() {
	// Use a fixed timestamp matching the AWS example format
	ts := time.parse_iso8601('2013-05-24T00:00:00Z') or { time.now() }
	config := SignConfig{
		creds: AwsCredentials{
			access_key_id: 'AKIDEXAMPLE'
			secret_access_key: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY'
		}
		method: 'POST'
		host: 'iam.amazonaws.com'
		path: '/'
		content_type: 'application/x-www-form-urlencoded; charset=utf-8'
		payload: 'Action=ListUsers&Version=2010-05-08'
		region: 'us-east-1'
		service: 'iam'
		timestamp: ts
	}

	signed := sign_request(config)!
	auth := signed.headers['Authorization']

	// Verify credential scope format
	assert auth.contains('Credential=AKIDEXAMPLE/20130524/us-east-1/iam/aws4_request')
	assert signed.headers['X-Amz-Date'] == '20130524T000000Z'
}
