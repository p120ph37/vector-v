module sources

import event
import net.http
import time

// HttpClientSource polls an HTTP endpoint at a configurable interval and
// emits each response as a log event. Mirrors Vector's http_client source.
//
// Config options:
//   endpoint:            URL to poll (required)
//   method:              HTTP method (default: GET)
//   scrape_interval_secs: Polling interval in seconds (default: 15)
//   headers.*:           Custom request headers
//   auth.user/password:  Basic auth
//   auth.token:          Bearer token
//   decoding.codec:      How to interpret the response: bytes (raw), json (default: bytes)
//   max_length:          Max response body length (default: 1048576)
pub struct HttpClientSource {
	endpoint         string
	method           http.Method = .get
	scrape_interval  time.Duration = 15 * time.second
	headers          map[string]string
	auth_header      string
	codec            HttpClientCodec
	max_length       int = 1048576
}

enum HttpClientCodec {
	bytes_codec
	json_codec
}

// new_http_client creates a new HttpClientSource from config options.
pub fn new_http_client(opts map[string]string) !HttpClientSource {
	endpoint := opts['endpoint'] or {
		return error('http_client source: endpoint is required')
	}

	method := match (opts['method'] or { 'GET' }).to_upper() {
		'POST' { http.Method.post }
		'PUT' { http.Method.put }
		else { http.Method.get }
	}

	mut scrape_secs := 15.0
	if s := opts['scrape_interval_secs'] {
		scrape_secs = s.f64()
		if scrape_secs <= 0 {
			scrape_secs = 15.0
		}
	}

	mut custom_headers := map[string]string{}
	for k, v in opts {
		if k.starts_with('headers.') {
			custom_headers[k[8..]] = v
		}
	}

	auth_header := parse_auth_header(opts)

	codec := match opts['decoding.codec'] or { 'bytes' } {
		'json' { HttpClientCodec.json_codec }
		else { HttpClientCodec.bytes_codec }
	}

	mut max_length := 1048576
	if ml := opts['max_length'] {
		max_length = ml.int()
		if max_length <= 0 {
			max_length = 1048576
		}
	}

	return HttpClientSource{
		endpoint: endpoint
		method: method
		scrape_interval: time.Duration(i64(scrape_secs * 1_000_000_000))
		headers: custom_headers
		auth_header: auth_header
		codec: codec
		max_length: max_length
	}
}

// run polls the endpoint at the configured interval and emits events.
pub fn (s &HttpClientSource) run(output chan event.Event) {
	for {
		s.scrape(output)
		time.sleep(s.scrape_interval)
	}
}

fn (s &HttpClientSource) scrape(output chan event.Event) {
	mut header := http.Header{}
	for k, v in s.headers {
		header.add_custom(k, v) or { continue }
	}
	if s.auth_header.len > 0 {
		header.add_custom('Authorization', s.auth_header) or {}
	}

	resp := http.fetch(http.FetchConfig{
		url: s.endpoint
		method: s.method
		header: header
		verbose: false
	}) or {
		eprintln('http_client: request failed: ${err}')
		return
	}

	if resp.status_code >= 400 {
		eprintln('http_client: HTTP ${resp.status_code} from ${s.endpoint}')
		return
	}

	body := if resp.body.len > s.max_length {
		resp.body[..s.max_length]
	} else {
		resp.body
	}

	mut ev := event.new_log(body)
	ev.meta.source_type = 'http_client'
	ev.set('status_code', event.Value(resp.status_code))
	ev.set('endpoint', event.Value(s.endpoint))
	output <- event.Event(ev)
}

