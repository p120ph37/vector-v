module aws

import net.http
import os
import time

// AwsCredentials holds resolved AWS access credentials.
pub struct AwsCredentials {
pub:
	access_key_id     string
	secret_access_key string
	session_token     string // optional, from STS/IMDS
	region            string
}

// CredentialSource tracks where credentials were loaded from.
pub enum CredentialSource {
	config_explicit // explicitly provided in component config
	environment     // AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
	profile         // ~/.aws/credentials file
	imds            // EC2 instance metadata service
	none            // no credentials found
}

// ResolvedCredentials bundles credentials with their source.
pub struct ResolvedCredentials {
pub:
	creds  AwsCredentials
	source CredentialSource
}

// resolve_credentials implements the standard AWS credential resolution chain:
//   1. Explicit config (access_key_id + secret_access_key in opts)
//   2. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN)
//   3. Shared credentials file (~/.aws/credentials)
//   4. EC2 instance metadata (IMDSv2)
//
// Region is resolved separately: opts["region"] > AWS_REGION > AWS_DEFAULT_REGION > IMDS.
pub fn resolve_credentials(opts map[string]string) !ResolvedCredentials {
	region := resolve_region(opts)

	// 1. Explicit config
	if ak := opts['auth.access_key_id'] {
		sk := opts['auth.secret_access_key'] or {
			return error('aws: access_key_id provided without secret_access_key')
		}
		token := opts['auth.session_token'] or { '' }
		return ResolvedCredentials{
			creds: AwsCredentials{
				access_key_id: ak
				secret_access_key: sk
				session_token: token
				region: region
			}
			source: .config_explicit
		}
	}

	// 2. Environment variables
	env_ak := os.getenv('AWS_ACCESS_KEY_ID')
	env_sk := os.getenv('AWS_SECRET_ACCESS_KEY')
	if env_ak.len > 0 && env_sk.len > 0 {
		return ResolvedCredentials{
			creds: AwsCredentials{
				access_key_id: env_ak
				secret_access_key: env_sk
				session_token: os.getenv('AWS_SESSION_TOKEN')
				region: region
			}
			source: .environment
		}
	}

	// 3. Shared credentials file
	profile_creds := load_shared_credentials(opts['auth.profile'] or { '' })
	if profile_creds.access_key_id.len > 0 {
		return ResolvedCredentials{
			creds: AwsCredentials{
				access_key_id: profile_creds.access_key_id
				secret_access_key: profile_creds.secret_access_key
				session_token: profile_creds.session_token
				region: if region.len > 0 { region } else { profile_creds.region }
			}
			source: .profile
		}
	}

	// 4. IMDS (EC2 instance metadata)
	imds_endpoint := opts['auth.imds_endpoint'] or { 'http://169.254.169.254' }
	imds_creds := load_imds_credentials(imds_endpoint) or {
		return ResolvedCredentials{
			creds: AwsCredentials{ region: region }
			source: .none
		}
	}
	return ResolvedCredentials{
		creds: AwsCredentials{
			access_key_id: imds_creds.access_key_id
			secret_access_key: imds_creds.secret_access_key
			session_token: imds_creds.session_token
			region: if region.len > 0 { region } else { imds_creds.region }
		}
		source: .imds
	}
}

// resolve_region determines the AWS region from config, env, or empty string.
pub fn resolve_region(opts map[string]string) string {
	if r := opts['region'] {
		return r
	}
	env_region := os.getenv('AWS_REGION')
	if env_region.len > 0 {
		return env_region
	}
	env_default := os.getenv('AWS_DEFAULT_REGION')
	if env_default.len > 0 {
		return env_default
	}
	return ''
}

// --- Shared credentials file ---

struct ProfileCredentials {
	access_key_id     string
	secret_access_key string
	session_token     string
	region            string
}

fn load_shared_credentials(profile_name string) ProfileCredentials {
	target_profile := if profile_name.len > 0 { profile_name } else { 'default' }

	// Try credentials file first
	creds_path := credentials_file_path()
	creds := parse_ini_profile(creds_path, target_profile)
	if creds.access_key_id.len > 0 {
		// Also check config file for region
		config_path := config_file_path()
		// In config file, non-default profiles are prefixed with "profile "
		config_section := if target_profile == 'default' {
			'default'
		} else {
			'profile ${target_profile}'
		}
		config := parse_ini_profile(config_path, config_section)
		return ProfileCredentials{
			access_key_id: creds.access_key_id
			secret_access_key: creds.secret_access_key
			session_token: creds.session_token
			region: config.region
		}
	}
	return ProfileCredentials{}
}

fn credentials_file_path() string {
	env_path := os.getenv('AWS_SHARED_CREDENTIALS_FILE')
	if env_path.len > 0 {
		return env_path
	}
	home := os.getenv('HOME')
	if home.len > 0 {
		return '${home}/.aws/credentials'
	}
	return ''
}

fn config_file_path() string {
	env_path := os.getenv('AWS_CONFIG_FILE')
	if env_path.len > 0 {
		return env_path
	}
	home := os.getenv('HOME')
	if home.len > 0 {
		return '${home}/.aws/config'
	}
	return ''
}

// parse_ini_profile reads a simple INI file and extracts keys from the target section.
pub fn parse_ini_profile(path string, section string) ProfileCredentials {
	content := os.read_file(path) or { return ProfileCredentials{} }
	return parse_ini_content(content, section)
}

// parse_ini_content parses INI content string for a given section.
pub fn parse_ini_content(content string, section string) ProfileCredentials {
	mut in_section := false
	mut ak := ''
	mut sk := ''
	mut token := ''
	mut region := ''

	for line in content.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.len == 0 || trimmed.starts_with('#') || trimmed.starts_with(';') {
			continue
		}
		if trimmed.starts_with('[') && trimmed.ends_with(']') {
			current := trimmed[1..trimmed.len - 1].trim_space()
			in_section = current == section
			continue
		}
		if in_section {
			eq := trimmed.index('=') or { continue }
			key := trimmed[..eq].trim_space()
			val := trimmed[eq + 1..].trim_space()
			match key {
				'aws_access_key_id' { ak = val }
				'aws_secret_access_key' { sk = val }
				'aws_session_token' { token = val }
				'region' { region = val }
				else {}
			}
		}
	}
	return ProfileCredentials{
		access_key_id: ak
		secret_access_key: sk
		session_token: token
		region: region
	}
}

// --- IMDS (Instance Metadata Service v2) ---

const imds_timeout = i64(1 * time.second)

fn load_imds_credentials(endpoint string) !AwsCredentials {
	token := fetch_imds_token(endpoint)!

	// Get IAM role name
	role_name := imds_get(endpoint, '/latest/meta-data/iam/security-credentials/', token)!
	if role_name.len == 0 {
		return error('no IAM role attached to instance')
	}

	// Get credentials for role
	creds_json := imds_get(endpoint, '/latest/meta-data/iam/security-credentials/${role_name}',
		token)!

	ak := json_extract(creds_json, 'AccessKeyId')
	sk := json_extract(creds_json, 'SecretAccessKey')
	token_val := json_extract(creds_json, 'Token')
	if ak.len == 0 || sk.len == 0 {
		return error('IMDS returned empty credentials')
	}

	// Get region from identity document
	identity := imds_get(endpoint, '/latest/dynamic/instance-identity/document', token) or { '' }
	region := json_extract(identity, 'region')

	return AwsCredentials{
		access_key_id: ak
		secret_access_key: sk
		session_token: token_val
		region: region
	}
}

fn fetch_imds_token(endpoint string) !string {
	mut header := http.new_custom_header_from_map({
		'X-aws-ec2-metadata-token-ttl-seconds': '21600'
	})!

	mut req := http.prepare(http.FetchConfig{
		url: '${endpoint}/latest/api/token'
		method: .put
		header: header
		verbose: false
	})!
	req.read_timeout = aws.imds_timeout
	req.write_timeout = aws.imds_timeout

	resp := req.do() or {
		return error('failed to get IMDSv2 token: ${err}')
	}
	if resp.status_code != 200 {
		return error('IMDSv2 token request returned ${resp.status_code}')
	}
	return resp.body.trim_space()
}

fn imds_get(endpoint string, path string, token string) !string {
	mut header := http.new_custom_header_from_map({
		'X-aws-ec2-metadata-token': token
	})!

	mut req := http.prepare(http.FetchConfig{
		url: '${endpoint}${path}'
		method: .get
		header: header
		verbose: false
	})!
	req.read_timeout = aws.imds_timeout
	req.write_timeout = aws.imds_timeout

	resp := req.do() or {
		return error('IMDS fetch failed: ${err}')
	}
	if resp.status_code == 404 {
		return ''
	}
	if resp.status_code != 200 {
		return error('IMDS returned ${resp.status_code}')
	}
	return resp.body.trim_space()
}

// json_extract extracts a simple string value for the given key from JSON.
// Uses simple string scanning — sufficient for flat IMDS responses.
pub fn json_extract(json_str string, key string) string {
	needle := '"${key}"'
	idx := json_str.index(needle) or { return '' }
	rest := json_str[idx + needle.len..]
	// Skip :\s*"
	colon := rest.index(':') or { return '' }
	after_colon := rest[colon + 1..].trim_left(' \t')
	if after_colon.len == 0 || after_colon[0] != `"` {
		return ''
	}
	end_quote := after_colon[1..].index('"') or { return '' }
	return after_colon[1..end_quote + 1]
}
