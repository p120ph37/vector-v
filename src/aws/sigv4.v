module aws

import crypto.hmac
import crypto.sha256
import net.http
import time

// sign_request signs an HTTP request using AWS Signature Version 4.
// Returns the Authorization header value and additional headers to add.
//
// Reference: https://docs.aws.amazon.com/general/latest/gr/sigv4_signing.html
pub fn sign_request(config SignConfig) !SignedHeaders {
	amz_date := config.timestamp.custom_format('YYYYMMDDTHHmmss') + 'Z'
	date_stamp := config.timestamp.custom_format('YYYYMMDD')

	mut headers_to_sign := {
		'host':         config.host
		'x-amz-date':   amz_date
		'content-type': config.content_type
	}
	if config.creds.session_token.len > 0 {
		headers_to_sign['x-amz-security-token'] = config.creds.session_token
	}
	for k, v in config.extra_headers {
		headers_to_sign[k.to_lower()] = v
	}

	// Step 1: Create canonical request
	signed_header_keys := sorted_keys(headers_to_sign)
	signed_headers_str := signed_header_keys.join(';')

	mut canonical_headers := ''
	for k in signed_header_keys {
		canonical_headers += '${k}:${headers_to_sign[k]}\n'
	}

	payload_hash := hex_sha256(config.payload)

	canonical_request := '${config.method}\n${config.path}\n${config.query}\n${canonical_headers}\n${signed_headers_str}\n${payload_hash}'

	// Step 2: Create string to sign
	credential_scope := '${date_stamp}/${config.region}/${config.service}/aws4_request'
	string_to_sign := 'AWS4-HMAC-SHA256\n${amz_date}\n${credential_scope}\n${hex_sha256(canonical_request)}'

	// Step 3: Calculate signature
	k_date := hmac_sha256('AWS4${config.creds.secret_access_key}'.bytes(), date_stamp.bytes())
	k_region := hmac_sha256(k_date, config.region.bytes())
	k_service := hmac_sha256(k_region, config.service.bytes())
	k_signing := hmac_sha256(k_service, 'aws4_request'.bytes())
	signature := hmac_sha256(k_signing, string_to_sign.bytes()).hex()

	// Step 4: Build Authorization header
	auth_header := 'AWS4-HMAC-SHA256 Credential=${config.creds.access_key_id}/${credential_scope}, SignedHeaders=${signed_headers_str}, Signature=${signature}'

	mut result_headers := {
		'Authorization':  auth_header
		'X-Amz-Date':     amz_date
		'Content-Type':   config.content_type
	}
	if config.creds.session_token.len > 0 {
		result_headers['X-Amz-Security-Token'] = config.creds.session_token
	}
	for k, v in config.extra_headers {
		result_headers[k] = v
	}

	return SignedHeaders{
		headers: result_headers
	}
}

// SignConfig holds the parameters needed for SigV4 signing.
pub struct SignConfig {
pub:
	creds         AwsCredentials
	method        string = 'POST'
	host          string
	path          string = '/'
	query         string // canonical query string (pre-sorted, URL-encoded)
	content_type  string = 'application/x-amz-json-1.1'
	payload       string
	region        string
	service       string
	timestamp     time.Time = time.now()
	extra_headers map[string]string
}

// SignedHeaders is the result of signing: headers to add to the HTTP request.
pub struct SignedHeaders {
pub:
	headers map[string]string
}

// send_signed sends a signed HTTP request to an AWS service endpoint.
pub fn send_signed(config SignConfig, endpoint string) !http.Response {
	signed := sign_request(config)!

	url := '${endpoint}${config.path}'
	if config.query.len > 0 {
		// query already included in url if needed
	}

	mut header := http.Header{}
	for k, v in signed.headers {
		header.add_custom(k, v)!
	}

	mut req := http.prepare(http.FetchConfig{
		url: url
		method: match config.method {
			'GET' { http.Method.get }
			'PUT' { http.Method.put }
			'DELETE' { http.Method.delete }
			else { http.Method.post }
		}
		data: config.payload
		header: header
		verbose: false
	})!

	resp := req.do() or {
		return error('AWS request failed: ${err}')
	}

	return resp
}

// --- Helpers ---

fn hmac_sha256(key []u8, data []u8) []u8 {
	return hmac.new(key, data, sha256.sum, sha256.block_size)
}

fn hex_sha256(data string) string {
	digest := sha256.sum(data.bytes())
	return digest[..].hex()
}

fn sorted_keys(m map[string]string) []string {
	mut keys := []string{}
	for k, _ in m {
		keys << k
	}
	keys.sort()
	return keys
}
