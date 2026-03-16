module aws

import os
import time

fn test_ecs_credential_source_enum() {
	// Verify the new ecs variant exists in the enum
	src := CredentialSource.ecs
	assert src == .ecs
}

fn test_load_ecs_credentials_no_env() {
	// With no ECS env vars set, load_ecs_credentials should fail
	os.unsetenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI')
	os.unsetenv('AWS_CONTAINER_CREDENTIALS_FULL_URI')

	load_ecs_credentials() or {
		assert err.msg().contains('no ECS credential URI set')
		return
	}
	assert false, 'expected error when no ECS env vars set'
}

fn test_resolve_credentials_explicit_overrides_ecs() {
	// Explicit credentials should take priority over ECS
	os.setenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI', '/v2/credentials/test', true)
	defer {
		os.unsetenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI')
	}

	result := resolve_credentials({
		'auth.access_key_id':     'AKIAEXPLICIT'
		'auth.secret_access_key': 'explicit_secret'
		'region':                 'us-west-2'
	})!
	assert result.source == .config_explicit
	assert result.creds.access_key_id == 'AKIAEXPLICIT'
}

fn test_resolve_credentials_env_overrides_ecs() {
	// Env credentials should take priority over ECS
	os.setenv('AWS_ACCESS_KEY_ID', 'AKIAENV', true)
	os.setenv('AWS_SECRET_ACCESS_KEY', 'env_secret', true)
	os.setenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI', '/v2/credentials/test', true)
	defer {
		os.unsetenv('AWS_ACCESS_KEY_ID')
		os.unsetenv('AWS_SECRET_ACCESS_KEY')
		os.unsetenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI')
	}

	result := resolve_credentials({})!
	assert result.source == .environment
	assert result.creds.access_key_id == 'AKIAENV'
}

fn test_resolve_credentials_profile_overrides_ecs() {
	// Profile credentials should take priority over ECS
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.setenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI', '/v2/credentials/test', true)

	tmp_dir := os.temp_dir() + '/aws_ecs_test_${time.now().unix()}'
	os.mkdir_all(tmp_dir) or {}
	defer {
		os.rmdir_all(tmp_dir) or {}
		os.unsetenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI')
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}
	creds_file := '${tmp_dir}/credentials'
	os.write_file(creds_file, '[default]
aws_access_key_id = AKIAPROFILE
aws_secret_access_key = profile_secret
') or { return }

	os.setenv('AWS_SHARED_CREDENTIALS_FILE', creds_file, true)

	result := resolve_credentials({
		'region': 'us-east-1'
	})!
	assert result.source == .profile
	assert result.creds.access_key_id == 'AKIAPROFILE'
}

fn test_credential_chain_order() {
	// Verify the credential chain enum values exist and are distinct
	assert CredentialSource.config_explicit != .ecs
	assert CredentialSource.environment != .ecs
	assert CredentialSource.profile != .ecs
	assert CredentialSource.ecs != .imds
	assert CredentialSource.ecs != .none
}

fn test_ecs_env_var_detection() {
	// Verify that the ECS env vars are checked
	os.unsetenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI')
	os.unsetenv('AWS_CONTAINER_CREDENTIALS_FULL_URI')

	// With nothing set, should get the "no URI" error
	load_ecs_credentials() or {
		assert err.msg() == 'no ECS credential URI set'
		return
	}
	assert false, 'expected error'
}

fn test_ecs_full_uri_env_var_detection() {
	os.unsetenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI')
	os.unsetenv('AWS_CONTAINER_CREDENTIALS_FULL_URI')

	// Relative URI empty, full URI empty — should fail
	os.setenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI', '', true)
	defer {
		os.unsetenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI')
	}

	// Empty string should not trigger relative path (len == 0)
	load_ecs_credentials() or {
		assert err.msg().contains('no ECS credential URI set')
		return
	}
	assert false, 'expected error'
}

fn test_resolve_no_credentials_ecs_skipped() {
	// When no ECS env vars are set, the chain should skip ECS and try IMDS
	os.unsetenv('AWS_ACCESS_KEY_ID')
	os.unsetenv('AWS_SECRET_ACCESS_KEY')
	os.unsetenv('AWS_CONTAINER_CREDENTIALS_RELATIVE_URI')
	os.unsetenv('AWS_CONTAINER_CREDENTIALS_FULL_URI')
	os.setenv('AWS_SHARED_CREDENTIALS_FILE', '/nonexistent/path', true)
	defer {
		os.unsetenv('AWS_SHARED_CREDENTIALS_FILE')
	}

	result := resolve_credentials({
		'auth.imds_endpoint': 'http://127.0.0.1:1'
		'region':             'us-east-1'
	})!
	// Should fall through ECS (no env vars) to IMDS (unreachable) to none
	assert result.source == .none
	assert result.creds.region == 'us-east-1'
}
