module sinks

import net.http

// HttpBatch collects events and sends them in batches over HTTP.
// Used by Loki, OpenTelemetry, and other HTTP-based sinks.
pub struct HttpBatch {
pub mut:
	endpoint    string
	path        string
	method      http.Method = .post
	headers     map[string]string
	auth_header string // pre-encoded Authorization header
	batch_size  int = 100
	timeout_ms  int = 10000
	buffer      []string
}

// new_http_batch creates a new HttpBatch with the given config.
pub fn new_http_batch(opts map[string]string) HttpBatch {
	mut batch := HttpBatch{
		endpoint: opts['endpoint'] or { 'http://localhost' }
		path: opts['path'] or { '' }
	}

	if bs := opts['batch.max_bytes'] {
		batch.batch_size = bs.int()
		if batch.batch_size <= 0 {
			batch.batch_size = 100
		}
	}
	if bs := opts['batch.max_events'] {
		batch.batch_size = bs.int()
		if batch.batch_size <= 0 {
			batch.batch_size = 100
		}
	}
	if t := opts['request.timeout_secs'] {
		batch.timeout_ms = int(t.f64() * 1000)
		if batch.timeout_ms <= 0 {
			batch.timeout_ms = 10000
		}
	}

	// Basic auth
	if user := opts['auth.user'] {
		password := opts['auth.password'] or { '' }
		batch.auth_header = 'Basic ' + base64_encode('${user}:${password}')
	}
	// Bearer token
	if token := opts['auth.token'] {
		batch.auth_header = 'Bearer ${token}'
	}

	return batch
}

// send_payload sends a payload string to the configured endpoint.
pub fn (b &HttpBatch) send_payload(payload string, extra_headers map[string]string) !string {
	url := '${b.endpoint}${b.path}'

	mut header := http.new_custom_header_from_map({
		'Content-Type': 'application/json'
	})!

	for k, v in b.headers {
		header.add_custom(k, v)!
	}
	for k, v in extra_headers {
		header.add_custom(k, v)!
	}
	if b.auth_header.len > 0 {
		header.add_custom('Authorization', b.auth_header)!
	}

	config := http.FetchConfig{
		url: url
		method: b.method
		data: payload
		header: header
		verbose: false
	}

	resp := http.fetch(config) or {
		return error('HTTP request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('HTTP ${resp.status_code}: ${resp.body}')
	}

	return resp.body
}

// simple_healthcheck performs a basic connection check to the endpoint.
pub fn (b &HttpBatch) simple_healthcheck() !bool {
	url := '${b.endpoint}${b.path}'
	mut header := http.Header{}
	if b.auth_header.len > 0 {
		header.add_custom('Authorization', b.auth_header)!
	}
	config := http.FetchConfig{
		url: url
		method: .get
		header: header
		verbose: false
	}
	http.fetch(config) or {
		return error('healthcheck failed: ${err}')
	}
	return true
}

// base64_encode encodes a string to base64.
fn base64_encode(s string) string {
	alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	mut result := []u8{}
	bytes := s.bytes()
	mut i := 0
	for i < bytes.len {
		b0 := bytes[i]
		b1 := if i + 1 < bytes.len { bytes[i + 1] } else { u8(0) }
		b2 := if i + 2 < bytes.len { bytes[i + 2] } else { u8(0) }

		result << alphabet[b0 >> 2]
		result << alphabet[((b0 & 0x03) << 4) | (b1 >> 4)]
		if i + 1 < bytes.len {
			result << alphabet[((b1 & 0x0f) << 2) | (b2 >> 6)]
		} else {
			result << `=`
		}
		if i + 2 < bytes.len {
			result << alphabet[b2 & 0x3f]
		} else {
			result << `=`
		}
		i += 3
	}
	return result.bytestr()
}
