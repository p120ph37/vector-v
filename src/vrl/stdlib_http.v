module vrl

import net.http

// http_request(url, [method], [headers], [body])
// Performs an HTTP request and returns the response body as a string.
//
// Parameters:
//   url      — target URL (required)
//   method   — HTTP method: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS (default: "GET")
//   headers  — object of header key/value pairs (optional)
//   body     — request body string (optional)
//
// Returns: response body as string (fallible)
fn fn_http_request(args []VrlValue) !VrlValue {
	if args.len < 1 {
		return error('http_request requires at least 1 argument')
	}

	url := match args[0] {
		string { args[0] as string }
		else { return error('http_request: url must be a string') }
	}

	if url.len == 0 {
		return error('http_request: url must not be empty')
	}

	// Method (default: GET)
	method_str := if args.len > 1 {
		match args[1] {
			string { (args[1] as string).to_upper() }
			else { 'GET' }
		}
	} else {
		'GET'
	}

	method := match method_str {
		'GET' { http.Method.get }
		'POST' { http.Method.post }
		'PUT' { http.Method.put }
		'DELETE' { http.Method.delete }
		'PATCH' { http.Method.patch }
		'HEAD' { http.Method.head }
		'OPTIONS' { http.Method.options }
		else { return error('Unsupported HTTP method: ${method_str}') }
	}

	// Headers
	mut header := http.Header{}
	if args.len > 2 {
		match args[2] {
			ObjectMap {
				om := args[2] as ObjectMap
				m := om.to_map()
				for k, v in m {
					val_str := match v {
						string { v as string }
						else { vrl_to_string(v) }
					}
					header.add_custom(k, val_str) or {
						return error('Invalid header key: ${k}')
					}
				}
			}
			else {}
		}
	}

	// Body
	body := if args.len > 3 {
		match args[3] {
			string { args[3] as string }
			else { '' }
		}
	} else {
		''
	}

	// Perform request
	mut config := http.FetchConfig{
		url: url
		method: method
		header: header
		data: body
	}

	resp := http.fetch(config) or {
		return error('HTTP request failed: ${err.msg()}')
	}

	return VrlValue(resp.body)
}
