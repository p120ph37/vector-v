module sinks

import crypto.hmac
import crypto.sha256
import event
import json
import net.http
import os
import time

// AzureBlobSink sends events to Azure Blob Storage.
// Mirrors Vector's azure_blob sink.
//
// Events are batched, encoded, and uploaded as blobs using the Azure Blob
// Storage REST API with Shared Key authentication.
//
// Config options:
//   connection_string:     Azure Storage connection string (overrides account/key)
//   storage_account:       Azure Storage account name (required if no connection_string)
//   container_name:        Blob container name (required)
//   auth.storage_access_key: Storage account access key
//   blob_prefix:           Blob name prefix with optional strftime patterns
//                          (default: "date=%Y-%m-%d/")
//   encoding.codec:        json, text, or ndjson (default: ndjson)
//   batch.max_events:      Max events per blob (default: 1000)
//   batch.timeout_secs:    Max seconds before flushing (default: 300)
//   endpoint:              Custom endpoint URL (for Azurite/emulator)
//   blob_time_format:      Time format for blob names (default: %Y-%m-%dT%H:%M:%SZ)
//   content_type:          Blob content type (auto-detected from codec if not set)
pub struct AzureBlobSink {
	storage_account    string
	container_name     string
	access_key         string
	endpoint           string
	blob_prefix        string
	codec              AzureBlobCodec
	content_type       string
	batch_max          int = 1000
	batch_timeout      time.Duration = 300 * time.second
	connection_string  string
mut:
	buffer     []string
	last_flush time.Time
	seq        int
}

enum AzureBlobCodec {
	json_codec
	text_codec
	ndjson_codec
}

// new_azure_blob creates a new AzureBlobSink from config options.
pub fn new_azure_blob(opts map[string]string) !AzureBlobSink {
	container_name := opts['container_name'] or {
		return error('azure_blob: container_name is required')
	}
	if container_name.len == 0 {
		return error('azure_blob: container_name is required')
	}

	mut storage_account := opts['storage_account'] or { '' }
	mut access_key := opts['auth.storage_access_key'] or { '' }
	connection_string := opts['connection_string'] or { '' }

	// Parse connection string if provided
	if connection_string.len > 0 {
		parsed := parse_connection_string(connection_string)
		if sa := parsed['AccountName'] {
			if storage_account.len == 0 {
				storage_account = sa
			}
		}
		if ak := parsed['AccountKey'] {
			if access_key.len == 0 {
				access_key = ak
			}
		}
	}

	// Fall back to environment variables
	if storage_account.len == 0 {
		storage_account = os.getenv('AZURE_STORAGE_ACCOUNT')
	}
	if access_key.len == 0 {
		access_key = os.getenv('AZURE_STORAGE_KEY')
	}

	if storage_account.len == 0 {
		return error('azure_blob: storage_account is required')
	}

	endpoint := opts['endpoint'] or { 'https://${storage_account}.blob.core.windows.net' }
	blob_prefix := opts['blob_prefix'] or { 'date=%Y-%m-%d/' }

	codec := match opts['encoding.codec'] or { 'ndjson' } {
		'json' { AzureBlobCodec.json_codec }
		'text' { AzureBlobCodec.text_codec }
		else { AzureBlobCodec.ndjson_codec }
	}

	content_type := opts['content_type'] or {
		match codec {
			.json_codec { 'application/json' }
			.text_codec { 'text/plain' }
			.ndjson_codec { 'application/x-ndjson' }
		}
	}

	mut batch_max := 1000
	if bm := opts['batch.max_events'] {
		batch_max = bm.int()
		if batch_max <= 0 {
			batch_max = 1000
		}
	}

	mut batch_timeout_secs := 300.0
	if bt := opts['batch.timeout_secs'] {
		batch_timeout_secs = bt.f64()
		if batch_timeout_secs <= 0 {
			batch_timeout_secs = 300.0
		}
	}

	return AzureBlobSink{
		storage_account: storage_account
		container_name: container_name
		access_key: access_key
		endpoint: endpoint
		blob_prefix: blob_prefix
		codec: codec
		content_type: content_type
		batch_max: batch_max
		batch_timeout: time.Duration(i64(batch_timeout_secs * 1_000_000_000))
		connection_string: connection_string
		last_flush: time.now()
	}
}

// send buffers an event and flushes when batch is full or timeout expires.
pub fn (mut s AzureBlobSink) send(e event.Event) ! {
	encoded := s.encode_event(e)
	if encoded.len > 0 {
		s.buffer << encoded
	}

	if s.buffer.len >= s.batch_max {
		s.flush()!
	}

	if time.since(s.last_flush) > s.batch_timeout && s.buffer.len > 0 {
		s.flush()!
	}
}

// flush uploads all buffered events as an Azure blob.
pub fn (mut s AzureBlobSink) flush() ! {
	if s.buffer.len == 0 {
		return
	}

	payload := s.build_payload()
	blob_name := s.generate_blob_name()

	s.put_blob(blob_name, payload) or {
		eprintln('azure_blob: PutBlob failed: ${err}')
		return error(err.msg())
	}

	s.buffer.clear()
	s.last_flush = time.now()
}

// total_buffered returns the number of events currently buffered.
pub fn (s &AzureBlobSink) total_buffered() int {
	return s.buffer.len
}

// build_payload constructs the file content from buffered events.
pub fn (s &AzureBlobSink) build_payload() string {
	return match s.codec {
		.json_codec {
			'[${s.buffer.join(",")}]'
		}
		.ndjson_codec {
			mut p := s.buffer.join('\n')
			if p.len > 0 {
				p += '\n'
			}
			p
		}
		.text_codec {
			s.buffer.join('\n')
		}
	}
}

// generate_blob_name produces a blob name from the prefix template.
pub fn (mut s AzureBlobSink) generate_blob_name() string {
	now := time.now()
	prefix := resolve_file_path(s.blob_prefix, now)
	s.seq++
	ts := now.unix()
	return '${prefix}${ts}-${s.seq}.log'
}

fn (s &AzureBlobSink) encode_event(e event.Event) string {
	match e {
		event.LogEvent {
			return match s.codec {
				.json_codec, .ndjson_codec {
					e.to_json()
				}
				.text_codec {
					e.message()
				}
			}
		}
		event.Metric {
			return json.encode(e)
		}
		event.TraceEvent {
			return json.encode(e.fields)
		}
	}
}

fn (s &AzureBlobSink) put_blob(blob_name string, payload string) ! {
	path := '/${s.container_name}/${blob_name}'
	url := '${s.endpoint}${path}'

	now := time.utc()
	date_str := azure_rfc1123_date(now)

	// Build string to sign for Shared Key authentication
	content_length := payload.len.str()

	mut header := http.Header{}
	header.add_custom('Content-Type', s.content_type) or {}
	header.add_custom('Content-Length', content_length) or {}
	header.add_custom('x-ms-date', date_str) or {}
	header.add_custom('x-ms-version', '2021-12-02') or {}
	header.add_custom('x-ms-blob-type', 'BlockBlob') or {}

	if s.access_key.len > 0 {
		string_to_sign := build_azure_string_to_sign('PUT', s.content_type, content_length,
			date_str, path, s.storage_account)
		signature := azure_sign(s.access_key, string_to_sign)
		header.add_custom('Authorization', 'SharedKey ${s.storage_account}:${signature}') or {}
	}

	resp := http.fetch(http.FetchConfig{
		url: url
		method: .put
		data: payload
		header: header
		verbose: false
	}) or {
		return error('Azure PutBlob HTTP request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('Azure PutBlob HTTP ${resp.status_code}: ${resp.body}')
	}
}

// build_azure_string_to_sign constructs the canonicalized string for Azure Shared Key signing.
pub fn build_azure_string_to_sign(method string, content_type string, content_length string, date string, path string, account string) string {
	// Shared Key format:
	// VERB\nContent-Encoding\nContent-Language\nContent-Length\nContent-MD5\nContent-Type\n
	// Date\nIf-Modified-Since\nIf-Match\nIf-None-Match\nIf-Unmodified-Since\nRange\n
	// CanonicalizedHeaders\nCanonicalizedResource
	mut parts := []string{}
	parts << method // VERB
	parts << '' // Content-Encoding
	parts << '' // Content-Language
	parts << content_length // Content-Length
	parts << '' // Content-MD5
	parts << content_type // Content-Type
	parts << '' // Date (using x-ms-date instead)
	parts << '' // If-Modified-Since
	parts << '' // If-Match
	parts << '' // If-None-Match
	parts << '' // If-Unmodified-Since
	parts << '' // Range
	// Canonicalized headers (sorted, lowercase)
	parts << 'x-ms-blob-type:BlockBlob\nx-ms-date:${date}\nx-ms-version:2021-12-02'
	// Canonicalized resource
	parts << '/${account}${path}'
	return parts.join('\n')
}

// azure_sign computes HMAC-SHA256 of the string to sign using the base64-decoded access key.
pub fn azure_sign(access_key string, string_to_sign string) string {
	decoded_key := decode_base64_bytes(access_key)
	mac := hmac.new(decoded_key, string_to_sign.bytes(), sha256.sum256, sha256.block_size)
	return encode_base64(mac)
}

// azure_rfc1123_date formats a time in RFC 1123 format (e.g., "Mon, 02 Jan 2006 15:04:05 GMT").
pub fn azure_rfc1123_date(t time.Time) string {
	days := ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
	months := ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
		'Dec']
	dow := days[t.day_of_week()]
	mon := months[t.month - 1]
	return '${dow}, ${t.day:02d} ${mon} ${t.year} ${t.hour:02d}:${t.minute:02d}:${t.second:02d} GMT'
}

// parse_connection_string parses an Azure Storage connection string into key-value pairs.
pub fn parse_connection_string(cs string) map[string]string {
	mut result := map[string]string{}
	parts := cs.split(';')
	for part in parts {
		eq := part.index('=') or { continue }
		key := part[..eq]
		value := part[eq + 1..]
		result[key] = value
	}
	return result
}

// decode_base64_bytes decodes a base64 string to bytes.
fn decode_base64_bytes(s string) []u8 {
	alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	mut lookup := [256]u8{}
	for i, c in alphabet.bytes() {
		lookup[c] = u8(i)
	}
	lookup[`=`] = 0

	data := s.bytes()
	mut result := []u8{}
	mut i := 0
	for i + 3 < data.len {
		a := lookup[data[i]]
		b := lookup[data[i + 1]]
		c := lookup[data[i + 2]]
		d := lookup[data[i + 3]]
		result << (a << 2) | (b >> 4)
		if data[i + 2] != `=` {
			result << ((b & 0x0f) << 4) | (c >> 2)
		}
		if data[i + 3] != `=` {
			result << ((c & 0x03) << 6) | d
		}
		i += 4
	}
	return result
}
