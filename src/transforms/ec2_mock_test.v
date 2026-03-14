module transforms

import event
import mockserver

// --- EC2 Metadata integration tests using the mock server ---
// These tests validate the full IMDSv2 flow: token acquisition,
// identity document parsing, per-field metadata fetches, and
// event enrichment — all against a real HTTP server on loopback.

const test_identity_doc = '{"instanceId":"i-0abcdef1234567890","instanceType":"t3.micro","imageId":"ami-12345678","region":"us-east-1","accountId":"123456789012"}'

fn build_ec2_routes() []mockserver.Route {
	return [
		// IMDSv2 token endpoint
		mockserver.put('/latest/api/token', mockserver.respond(200, 'test-imds-token-v2')),
		// Identity document
		mockserver.get('/latest/dynamic/instance-identity/document',
			mockserver.respond(200, transforms.test_identity_doc)),
		// MAC address (for vpc/subnet lookups)
		mockserver.get('/latest/meta-data/mac', mockserver.respond(200, '0a:1b:2c:3d:4e:5f')),
		// Individual metadata paths
		mockserver.get('/latest/meta-data/placement/availability-zone',
			mockserver.respond(200, 'us-east-1a')),
		mockserver.get('/latest/meta-data/local-hostname', mockserver.respond(200,
			'ip-10-0-0-42.ec2.internal')),
		mockserver.get('/latest/meta-data/local-ipv4', mockserver.respond(200, '10.0.0.42')),
		mockserver.get('/latest/meta-data/public-hostname', mockserver.respond(200,
			'ec2-54-0-0-1.compute-1.amazonaws.com')),
		mockserver.get('/latest/meta-data/public-ipv4', mockserver.respond(200, '54.0.0.1')),
		mockserver.get('/latest/meta-data/network/interfaces/macs/0a:1b:2c:3d:4e:5f/vpc-id',
			mockserver.respond(200, 'vpc-abc123')),
		mockserver.get('/latest/meta-data/network/interfaces/macs/0a:1b:2c:3d:4e:5f/subnet-id',
			mockserver.respond(200, 'subnet-def456')),
	]
}

fn test_ec2_full_metadata_enrichment() {
	mut mock := mockserver.start_with_routes(build_ec2_routes()) or { panic(err) }
	defer {
		mock.stop()
	}

	mut t := new_ec2_metadata({
		'endpoint': mock.url()
	}) or { panic(err) }

	// Transform an event — metadata should be applied
	ev := event.Event(event.new_log('test message'))
	result := t.transform(ev) or { panic(err) }

	assert result.len == 1
	log := result[0] as event.LogEvent

	// Fields from identity document
	assert log.get('instance-id') or { event.Value('') } == event.Value('i-0abcdef1234567890')
	assert log.get('instance-type') or { event.Value('') } == event.Value('t3.micro')
	assert log.get('ami-id') or { event.Value('') } == event.Value('ami-12345678')
	assert log.get('region') or { event.Value('') } == event.Value('us-east-1')
	assert log.get('account-id') or { event.Value('') } == event.Value('123456789012')

	// Fields from individual metadata paths
	assert log.get('availability-zone') or { event.Value('') } == event.Value('us-east-1a')
	assert log.get('local-hostname') or { event.Value('') } == event.Value('ip-10-0-0-42.ec2.internal')
	assert log.get('local-ipv4') or { event.Value('') } == event.Value('10.0.0.42')
	assert log.get('public-hostname') or { event.Value('') } == event.Value('ec2-54-0-0-1.compute-1.amazonaws.com')
	assert log.get('public-ipv4') or { event.Value('') } == event.Value('54.0.0.1')

	// MAC-dependent fields
	assert log.get('vpc-id') or { event.Value('') } == event.Value('vpc-abc123')
	assert log.get('subnet-id') or { event.Value('') } == event.Value('subnet-def456')
}

fn test_ec2_token_request_uses_put() {
	mut mock := mockserver.start_with_routes(build_ec2_routes()) or { panic(err) }
	defer {
		mock.stop()
	}

	_ := new_ec2_metadata({
		'endpoint': mock.url()
	}) or { panic(err) }

	// Check that the token request used PUT with the correct TTL header
	reqs := mock.wait_for_requests(1, 3000)
	assert reqs.len >= 1
	token_req := reqs[0]
	assert token_req.method == 'PUT'
	assert token_req.path == '/latest/api/token'
	assert token_req.headers['x-aws-ec2-metadata-token-ttl-seconds'] == '21600'
}

fn test_ec2_metadata_requests_carry_token() {
	mut mock := mockserver.start_with_routes(build_ec2_routes()) or { panic(err) }
	defer {
		mock.stop()
	}

	_ := new_ec2_metadata({
		'endpoint': mock.url()
	}) or { panic(err) }

	// All requests after the token request should carry the token header
	reqs := mock.wait_for_requests(5, 3000)
	for i in 1 .. reqs.len {
		assert reqs[i].headers['x-aws-ec2-metadata-token'] == 'test-imds-token-v2', 'request ${i} (${reqs[i].path}) missing token header'
	}
}

fn test_ec2_custom_namespace() {
	mut mock := mockserver.start_with_routes(build_ec2_routes()) or { panic(err) }
	defer {
		mock.stop()
	}

	mut t := new_ec2_metadata({
		'endpoint':  mock.url()
		'namespace': 'aws.ec2'
	}) or { panic(err) }

	ev := event.Event(event.new_log('namespaced'))
	result := t.transform(ev) or { panic(err) }

	log := result[0] as event.LogEvent

	// Fields should be namespaced
	assert log.get('aws.ec2.instance-id') or { event.Value('') } == event.Value('i-0abcdef1234567890')
	assert log.get('aws.ec2.region') or { event.Value('') } == event.Value('us-east-1')
	assert log.get('aws.ec2.vpc-id') or { event.Value('') } == event.Value('vpc-abc123')
}

fn test_ec2_custom_field_subset() {
	mut mock := mockserver.start_with_routes(build_ec2_routes()) or { panic(err) }
	defer {
		mock.stop()
	}

	mut t := new_ec2_metadata({
		'endpoint': mock.url()
		'fields':   'instance-id,region'
	}) or { panic(err) }

	ev := event.Event(event.new_log('subset'))
	result := t.transform(ev) or { panic(err) }

	log := result[0] as event.LogEvent

	// Only requested fields should be present
	assert log.get('instance-id') or { event.Value('') } == event.Value('i-0abcdef1234567890')
	assert log.get('region') or { event.Value('') } == event.Value('us-east-1')

	// Fields NOT in the subset should be absent
	val := log.get('vpc-id') or { event.Value('MISSING') }
	assert val == event.Value('MISSING')
}

fn test_ec2_token_failure_with_required_false() {
	// Server returns 500 for the token endpoint — non-required should still create the transform
	mut mock := mockserver.start(
		mockserver.put('/latest/api/token', mockserver.respond(500, 'internal error')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	t := new_ec2_metadata({
		'endpoint': mock.url()
		'required': 'false'
	}) or { panic(err) }

	// Should have no cached values but not panic
	assert t.values.len == 0
}

fn test_ec2_token_failure_with_required_true() {
	// Server returns 500 for the token endpoint — required=true should error
	mut mock := mockserver.start(
		mockserver.put('/latest/api/token', mockserver.respond(500, 'internal error')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	new_ec2_metadata({
		'endpoint': mock.url()
		'required': 'true'
	}) or {
		assert err.msg().contains('failed')
		return
	}

	assert false, 'expected error for required=true with failing IMDS'
}

fn test_ec2_404_field_skipped() {
	// availability-zone returns 404 — should be treated as empty
	mut mock := mockserver.start(
		mockserver.put('/latest/api/token', mockserver.respond(200, 'token')),
		mockserver.get('/latest/dynamic/instance-identity/document', mockserver.respond(200,
			'{}')),
		mockserver.get('/latest/meta-data/mac', mockserver.respond(200, 'aa:bb:cc:dd:ee:ff')),
		mockserver.get('/latest/meta-data/placement/availability-zone',
			mockserver.respond(404, 'not found')),
		mockserver.get('/latest/meta-data/local-hostname', mockserver.respond(200, 'myhost')),
		mockserver.get('/latest/meta-data/local-ipv4', mockserver.respond(404, '')),
		mockserver.get('/latest/meta-data/public-hostname', mockserver.respond(404, '')),
		mockserver.get('/latest/meta-data/public-ipv4', mockserver.respond(404, '')),
		mockserver.get('/latest/meta-data/network/interfaces/macs/aa:bb:cc:dd:ee:ff/vpc-id',
			mockserver.respond(404, '')),
		mockserver.get('/latest/meta-data/network/interfaces/macs/aa:bb:cc:dd:ee:ff/subnet-id',
			mockserver.respond(404, '')),
	) or { panic(err) }
	defer {
		mock.stop()
	}

	mut t := new_ec2_metadata({
		'endpoint': mock.url()
		'fields':   'availability-zone,local-hostname'
	}) or { panic(err) }

	ev := event.Event(event.new_log('test'))
	result := t.transform(ev) or { panic(err) }
	log := result[0] as event.LogEvent

	// 404 fields should be absent, successful ones present
	assert log.get('local-hostname') or { event.Value('') } == event.Value('myhost')

	az := log.get('availability-zone') or { event.Value('MISSING') }
	assert az == event.Value('MISSING')
}

fn test_ec2_metric_enrichment() {
	mut mock := mockserver.start_with_routes(build_ec2_routes()) or { panic(err) }
	defer {
		mock.stop()
	}

	mut t := new_ec2_metadata({
		'endpoint': mock.url()
		'fields':   'instance-id,region'
	}) or { panic(err) }

	// Metrics should get tags instead of log fields
	m := event.new_counter('cpu.usage', 42.0, .incremental)
	result := t.transform(event.Event(m)) or { panic(err) }
	assert result.len == 1

	metric := result[0] as event.Metric
	assert metric.tags['instance-id'] == 'i-0abcdef1234567890'
	assert metric.tags['region'] == 'us-east-1'
}

fn test_ec2_request_count() {
	mut mock := mockserver.start_with_routes(build_ec2_routes()) or { panic(err) }
	defer {
		mock.stop()
	}

	_ := new_ec2_metadata({
		'endpoint': mock.url()
	}) or { panic(err) }

	// Constructor triggers: 1 token + 1 identity doc + 1 mac + N individual fields
	// With default 12 fields, some come from identity doc so fewer HTTP requests
	reqs := mock.wait_for_requests(3, 3000)
	count := mock.request_count()
	assert count >= 3, 'expected at least 3 requests (token + identity + mac), got ${count}'
}
