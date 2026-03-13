module transforms

import event
import net.http
import time

// Ec2MetadataTransform enriches events with AWS EC2 instance metadata.
// Mirrors Vector's aws_ec2_metadata transform.
//
// Uses IMDSv2 (token-based) to fetch metadata from the EC2 instance
// metadata service at http://169.254.169.254. Metadata is cached and
// refreshed periodically.
//
// DIVERGENCE FROM UPSTREAM: Simplified to fetch a fixed set of common
// fields. Does not support custom instance tags or IAM role arrays.
// Uses periodic re-fetch rather than lock-free ArcSwap.
//
// If the initial metadata fetch fails (and required=false), subsequent
// refresh attempts are skipped entirely — we assume the process is not
// running in an EC2 environment.
pub struct Ec2MetadataTransform {
	namespace    string
	fields       []string
	endpoint     string
	refresh_secs int
mut:
	values       map[string]string
	last_refresh time.Time
	ec2_unavail  bool // set once IMDS is unreachable; disables further fetches
}

const ec2_default_endpoint = 'http://169.254.169.254'

const ec2_default_fields = [
	'instance-id',
	'instance-type',
	'ami-id',
	'region',
	'availability-zone',
	'local-hostname',
	'local-ipv4',
	'public-hostname',
	'public-ipv4',
	'account-id',
	'vpc-id',
	'subnet-id',
]

// new_ec2_metadata creates a new Ec2MetadataTransform.
pub fn new_ec2_metadata(opts map[string]string) !Ec2MetadataTransform {
	namespace := opts['namespace'] or { '' }

	mut fields := []string{}
	if f := opts['fields'] {
		for part in f.split(',') {
			trimmed := part.trim_space()
			if trimmed.len > 0 {
				fields << trimmed
			}
		}
	}
	if fields.len == 0 {
		fields = transforms.ec2_default_fields.clone()
	}

	endpoint := opts['endpoint'] or { transforms.ec2_default_endpoint }
	refresh_secs := (opts['refresh_interval_secs'] or { '10' }).int()
	refresh_interval := if refresh_secs > 0 { refresh_secs } else { 10 }

	// Do initial fetch
	mut ec2_unavail := false
	initial := fetch_all_metadata(endpoint, fields) or {
		required := opts['required'] or { 'true' }
		if required == 'true' {
			return error('ec2_metadata: failed to fetch metadata: ${err}')
		}
		// Not in EC2 — mark unavailable so we never retry
		ec2_unavail = true
		map[string]string{}
	}

	return Ec2MetadataTransform{
		namespace: namespace
		fields: fields
		endpoint: endpoint
		refresh_secs: refresh_interval
		values: initial.clone()
		last_refresh: time.now()
		ec2_unavail: ec2_unavail
	}
}

fn fetch_all_metadata(endpoint string, fields []string) !map[string]string {
	// Get IMDSv2 token
	token := fetch_imds_token(endpoint)!

	mut result := map[string]string{}

	// Fetch identity document for account-id, region, instance-id, etc.
	identity := fetch_metadata_path(endpoint, '/latest/dynamic/instance-identity/document',
		token) or { '' }
	mut id_doc := map[string]string{}
	if identity.len > 0 {
		id_doc = parse_identity_document(identity)
	}

	// Fetch MAC for vpc/subnet
	mac := fetch_metadata_path(endpoint, '/latest/meta-data/mac', token) or { '' }

	for field in fields {
		val := match field {
			'instance-id' {
				id_doc['instanceId'] or {
					fetch_metadata_path(endpoint, '/latest/meta-data/instance-id', token) or {
						''
					}
				}
			}
			'instance-type' {
				id_doc['instanceType'] or {
					fetch_metadata_path(endpoint, '/latest/meta-data/instance-type',
						token) or { '' }
				}
			}
			'ami-id' {
				id_doc['imageId'] or {
					fetch_metadata_path(endpoint, '/latest/meta-data/ami-id', token) or {
						''
					}
				}
			}
			'region' {
				id_doc['region'] or { '' }
			}
			'account-id' {
				id_doc['accountId'] or { '' }
			}
			'availability-zone' {
				fetch_metadata_path(endpoint, '/latest/meta-data/placement/availability-zone',
					token) or { '' }
			}
			'local-hostname' {
				fetch_metadata_path(endpoint, '/latest/meta-data/local-hostname', token) or {
					''
				}
			}
			'local-ipv4' {
				fetch_metadata_path(endpoint, '/latest/meta-data/local-ipv4', token) or {
					''
				}
			}
			'public-hostname' {
				fetch_metadata_path(endpoint, '/latest/meta-data/public-hostname', token) or {
					''
				}
			}
			'public-ipv4' {
				fetch_metadata_path(endpoint, '/latest/meta-data/public-ipv4', token) or {
					''
				}
			}
			'vpc-id' {
				if mac.len > 0 {
					fetch_metadata_path(endpoint, '/latest/meta-data/network/interfaces/macs/${mac}/vpc-id',
						token) or { '' }
				} else {
					''
				}
			}
			'subnet-id' {
				if mac.len > 0 {
					fetch_metadata_path(endpoint, '/latest/meta-data/network/interfaces/macs/${mac}/subnet-id',
						token) or { '' }
				} else {
					''
				}
			}
			'role-name' {
				fetch_metadata_path(endpoint, '/latest/meta-data/iam/security-credentials/',
					token) or { '' }
			}
			else {
				''
			}
		}
		if val.len > 0 {
			result[field] = val
		}
	}

	return result
}

// imds_timeout is the HTTP read/write timeout for all IMDS requests.
// 1 second is sufficient — the metadata service is on the local link.
const imds_timeout = i64(1 * time.second)

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
	req.read_timeout = transforms.imds_timeout
	req.write_timeout = transforms.imds_timeout

	resp := req.do() or {
		return error('failed to get IMDSv2 token: ${err}')
	}
	if resp.status_code != 200 {
		return error('IMDSv2 token request returned ${resp.status_code}')
	}
	return resp.body.trim_space()
}

fn fetch_metadata_path(endpoint string, path string, token string) !string {
	mut header := http.new_custom_header_from_map({
		'X-aws-ec2-metadata-token': token
	})!

	mut req := http.prepare(http.FetchConfig{
		url: '${endpoint}${path}'
		method: .get
		header: header
		verbose: false
	})!
	req.read_timeout = transforms.imds_timeout
	req.write_timeout = transforms.imds_timeout

	resp := req.do() or {
		return error('metadata fetch failed: ${err}')
	}
	if resp.status_code == 404 {
		return ''
	}
	if resp.status_code != 200 {
		return error('metadata returned ${resp.status_code}')
	}
	return resp.body.trim_space()
}

fn parse_identity_document(body string) map[string]string {
	mut result := map[string]string{}
	trimmed := body.trim_space()
	if trimmed.len < 2 {
		return result
	}
	inner := trimmed[1..trimmed.len - 1]
	parts := inner.split(',')
	for part in parts {
		colon_idx := part.index(':') or { continue }
		key := part[..colon_idx].trim_space().trim('"')
		val := part[colon_idx + 1..].trim_space().trim('"')
		result[key] = val
	}
	return result
}

// transform enriches an event with cached EC2 metadata.
// Refreshes metadata if the cache has expired.
pub fn (mut t Ec2MetadataTransform) transform(e event.Event) ![]event.Event {
	// Refresh if stale — but skip entirely if IMDS was already unreachable
	if !t.ec2_unavail && time.since(t.last_refresh) > time.Duration(i64(t.refresh_secs) * 1_000_000_000) {
		new_values := fetch_all_metadata(t.endpoint, t.fields) or {
			// First refresh failure means we're not on EC2; stop trying
			t.ec2_unavail = true
			t.values.clone()
		}
		t.values = new_values.clone()
		t.last_refresh = time.now()
	}

	match e {
		event.LogEvent {
			mut log := e
			for field, val in t.values {
				key := if t.namespace.len > 0 { '${t.namespace}.${field}' } else { field }
				log.set(key, event.Value(val))
			}
			return [event.Event(log)]
		}
		event.Metric {
			mut m := e
			for field, val in t.values {
				tag_key := if t.namespace.len > 0 {
					'${t.namespace}.${field}'
				} else {
					field
				}
				m.tags[tag_key] = val
			}
			return [event.Event(m)]
		}
		else {
			return [e]
		}
	}
}
