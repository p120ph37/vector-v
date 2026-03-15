module aws

import os
import time

fn test_resolve_region_from_opts() {
	r := resolve_region({
		'region': 'us-west-2'
	})
	assert r == 'us-west-2'
}

fn test_resolve_region_from_env() {
	os.setenv('AWS_REGION', 'eu-west-1', true)
	defer {
		os.unsetenv('AWS_REGION')
	}
	r := resolve_region({})
	assert r == 'eu-west-1'
}

fn test_resolve_region_from_default_env() {
	os.unsetenv('AWS_REGION')
	os.setenv('AWS_DEFAULT_REGION', 'ap-southeast-1', true)
	defer {
		os.unsetenv('AWS_DEFAULT_REGION')
	}
	r := resolve_region({})
	assert r == 'ap-southeast-1'
}

fn test_resolve_region_opts_overrides_env() {
	os.setenv('AWS_REGION', 'eu-west-1', true)
	defer {
		os.unsetenv('AWS_REGION')
	}
	r := resolve_region({
		'region': 'us-east-1'
	})
	assert r == 'us-east-1'
}

fn test_resolve_region_empty_when_nothing_set() {
	os.unsetenv('AWS_REGION')
	os.unsetenv('AWS_DEFAULT_REGION')
	r := resolve_region({})
	assert r == ''
}

fn test_parse_ini_content_default_profile() {
	content := '[default]
aws_access_key_id = AKIAEXAMPLE
aws_secret_access_key = secret123
aws_session_token = token456
'
	creds := parse_ini_content(content, 'default')
	assert creds.access_key_id == 'AKIAEXAMPLE'
	assert creds.secret_access_key == 'secret123'
	assert creds.session_token == 'token456'
}

fn test_parse_ini_content_named_profile() {
	content := '[default]
aws_access_key_id = AKIADEFAULT
aws_secret_access_key = default_secret

[myprofile]
aws_access_key_id = AKIAMYPROFILE
aws_secret_access_key = profile_secret
region = us-west-2
'
	creds := parse_ini_content(content, 'myprofile')
	assert creds.access_key_id == 'AKIAMYPROFILE'
	assert creds.secret_access_key == 'profile_secret'
	assert creds.region == 'us-west-2'
}

fn test_parse_ini_content_missing_profile() {
	content := '[default]
aws_access_key_id = AKIADEFAULT
aws_secret_access_key = default_secret
'
	creds := parse_ini_content(content, 'nonexistent')
	assert creds.access_key_id == ''
	assert creds.secret_access_key == ''
}

fn test_parse_ini_content_comments_and_blanks() {
	content := '# This is a comment
; Another comment

[default]
aws_access_key_id = AKIACOMMENT
aws_secret_access_key = secret

# inline comment ignored
'
	creds := parse_ini_content(content, 'default')
	assert creds.access_key_id == 'AKIACOMMENT'
	assert creds.secret_access_key == 'secret'
}

fn test_parse_ini_content_spaces_around_equals() {
	content := '[default]
aws_access_key_id  =  AKIASPACES
aws_secret_access_key=nosecret
'
	creds := parse_ini_content(content, 'default')
	assert creds.access_key_id == 'AKIASPACES'
	assert creds.secret_access_key == 'nosecret'
}

fn test_parse_ini_content_config_file_profile_prefix() {
	// In ~/.aws/config, non-default profiles use [profile name] syntax
	content := '[default]
region = us-east-1

[profile myprofile]
region = eu-central-1
'
	creds := parse_ini_content(content, 'profile myprofile')
	assert creds.region == 'eu-central-1'
}

fn test_json_extract_simple() {
	json := '{"AccessKeyId": "AKIA123", "SecretAccessKey": "secret", "Token": "tok"}'
	assert json_extract(json, 'AccessKeyId') == 'AKIA123'
	assert json_extract(json, 'SecretAccessKey') == 'secret'
	assert json_extract(json, 'Token') == 'tok'
}

fn test_json_extract_missing_key() {
	json := '{"AccessKeyId": "AKIA123"}'
	assert json_extract(json, 'Missing') == ''
}

fn test_json_extract_empty_string() {
	assert json_extract('', 'key') == ''
}

fn test_json_extract_region_from_identity_doc() {
	json := '{"region": "us-east-1", "instanceId": "i-12345"}'
	assert json_extract(json, 'region') == 'us-east-1'
	assert json_extract(json, 'instanceId') == 'i-12345'
}

fn test_resolve_explicit_credentials() {
	// Clear env to prevent env creds from being picked up
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	result := resolve_credentials({
		'auth.access_key_id':     'AKIAEXPLICIT'
		'auth.secret_access_key': 'explicit_secret'
		'auth.session_token':     'explicit_token'
		'region':                 'us-west-2'
	})!
	assert result.source == .config_explicit
	assert result.creds.access_key_id == 'AKIAEXPLICIT'
	assert result.creds.secret_access_key == 'explicit_secret'
	assert result.creds.session_token == 'explicit_token'
	assert result.creds.region == 'us-west-2'
}

fn test_resolve_explicit_missing_secret_key_errors() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	result := resolve_credentials({
		'auth.access_key_id': 'AKIAEXPLICIT'
	}) or {
		assert err.msg().contains('secret_access_key')
		return
	}
	assert false, 'expected error for missing secret key'
}

fn test_resolve_env_credentials() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAENV', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'env_secret', true)
	os.setenv('AWS_SESSION_TOKEN', 'env_token', true)
	os.setenv('AWS_REGION', 'eu-west-1', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_SESSION_TOKEN')
		os.unsetenv('AWS_REGION')
	}

	result := resolve_credentials({})!
	assert result.source == .environment
	assert result.creds.access_key_id == 'AKIAENV'
	assert result.creds.secret_access_key == 'env_secret'
	assert result.creds.session_token == 'env_token'
	assert result.creds.region == 'eu-west-1'
}

fn test_resolve_profile_credentials() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')

	// Create temporary credentials file
	tmp_dir := os.temp_dir() + '/aws_test_${time.now().unix()}'
	os.mkdir_all(tmp_dir) or {}
	defer {
		os.rmdir_all(tmp_dir) or {}
	}
	creds_file := '${tmp_dir}/credentials'
	os.write_file(creds_file, '[default]
aws_access_key_id = AKIAPROFILE
aws_secret_access_key = profile_secret
') or { return }

	os.setenv('AWS_SHARED_CREDENTIALS_FILE', creds_file, true)
	defer {
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	result := resolve_credentials({
		'region': 'us-east-1'
	})!
	assert result.source == .profile
	assert result.creds.access_key_id == 'AKIAPROFILE'
	assert result.creds.secret_access_key == 'profile_secret'
	assert result.creds.region == 'us-east-1'
}

fn test_resolve_no_credentials_found() {
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent/path', true)
	defer {
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	// IMDS will fail because there's no metadata service
	// This should still return (with source=none or imds error handled)
	result := resolve_credentials({
		'auth.imds_endpoint': 'http://127.0.0.1:1' // unreachable
		'region':             'us-east-1'
	})!
	assert result.source == .none
	assert result.creds.region == 'us-east-1'
}

fn test_explicit_overrides_env() {
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAENV', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'env_secret', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
	}

	result := resolve_credentials({
		'auth.access_key_id':     'AKIAEXPLICIT'
		'auth.secret_access_key': 'explicit_secret'
		'region':                 'us-west-2'
	})!
	// Explicit config takes priority over env
	assert result.source == .config_explicit
	assert result.creds.access_key_id == 'AKIAEXPLICIT'
}
