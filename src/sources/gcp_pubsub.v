module sources

import event
import os
import time

// GcpPubsubSource polls messages from a Google Cloud Pub/Sub subscription
// via the REST API and emits them as log events. Mirrors Vector's gcp_pubsub source.
//
// Config options:
//   project:              GCP project ID (required)
//   subscription:         Pub/Sub subscription name (required)
//   endpoint:             Pub/Sub API endpoint (default: https://pubsub.googleapis.com)
//   auth.api_key:         API key auth
//   auth.credentials_file: Service account JSON file path (also checks GOOGLE_APPLICATION_CREDENTIALS env)
//   ack_deadline_secs:    Ack deadline in seconds (default: 600)
//   max_concurrency:      Max concurrent pulls (default: 10)
//   poll_time_secs:       Poll interval in seconds (default: 5)
//   full_response:        Include full response metadata (default: false)
//   decoding.codec:       Decoding format (default: "bytes")
pub struct GcpPubsubSource {
	project           string
	subscription      string
	endpoint          string = 'https://pubsub.googleapis.com'
	api_key           string
	credentials_file  string // path to service account JSON
	ack_deadline_secs int = 600
	max_concurrency   int = 10
	poll_time_secs    int = 5
	full_response     bool   // include full pubsub response metadata
	decoding_codec    string = 'bytes'
	message_key       string = 'pubsub_message_id'
	publish_time_key  string = 'pubsub_publish_time'
	attributes_key    string = 'pubsub_attributes'
}

// new_gcp_pubsub_source creates a new GcpPubsubSource from config options.
pub fn new_gcp_pubsub_source(opts map[string]string) !GcpPubsubSource {
	project := opts['project'] or {
		return error('gcp_pubsub source: project is required')
	}
	if project.len == 0 {
		return error('gcp_pubsub source: project is required')
	}

	subscription := opts['subscription'] or {
		return error('gcp_pubsub source: subscription is required')
	}
	if subscription.len == 0 {
		return error('gcp_pubsub source: subscription is required')
	}

	endpoint := opts['endpoint'] or { 'https://pubsub.googleapis.com' }

	api_key := opts['auth.api_key'] or { '' }

	// Resolve credentials file: explicit config > GOOGLE_APPLICATION_CREDENTIALS env
	credentials_file := opts['auth.credentials_file'] or {
		os.getenv('GOOGLE_APPLICATION_CREDENTIALS')
	}

	mut ack_deadline_secs := 600
	if v := opts['ack_deadline_secs'] {
		ack_deadline_secs = v.int()
		if ack_deadline_secs <= 0 {
			ack_deadline_secs = 600
		}
	}

	mut max_concurrency := 10
	if v := opts['max_concurrency'] {
		max_concurrency = v.int()
		if max_concurrency <= 0 {
			max_concurrency = 10
		}
	}

	mut poll_time_secs := 5
	if v := opts['poll_time_secs'] {
		poll_time_secs = v.int()
		if poll_time_secs <= 0 {
			poll_time_secs = 5
		}
	}

	full_response_val := opts['full_response'] or { 'false' }
	decoding_codec := opts['decoding.codec'] or { 'bytes' }

	return GcpPubsubSource{
		project: project
		subscription: subscription
		endpoint: endpoint
		api_key: api_key
		credentials_file: credentials_file
		ack_deadline_secs: ack_deadline_secs
		max_concurrency: max_concurrency
		poll_time_secs: poll_time_secs
		full_response: full_response_val == 'true'
		decoding_codec: decoding_codec
	}
}

// build_pubsub_pull_url constructs the REST API pull URL for a Pub/Sub subscription.
pub fn build_pubsub_pull_url(endpoint string, project string, subscription string) string {
	return '${endpoint}/v1/projects/${project}/subscriptions/${subscription}:pull'
}

// build_pubsub_ack_url constructs the REST API acknowledge URL for a Pub/Sub subscription.
pub fn build_pubsub_ack_url(endpoint string, project string, subscription string) string {
	return '${endpoint}/v1/projects/${project}/subscriptions/${subscription}:acknowledge'
}

// parse_pubsub_message parses message metadata from a Pub/Sub message into a flat map.
pub fn parse_pubsub_message(data string, attributes map[string]string, message_id string, publish_time string) map[string]string {
	mut result := map[string]string{}
	result['data'] = data
	result['message_id'] = message_id
	result['publish_time'] = publish_time
	for k, v in attributes {
		result['attribute.${k}'] = v
	}
	return result
}

// validate_gcp_pubsub_source_config validates that required config options are present.
pub fn validate_gcp_pubsub_source_config(opts map[string]string) !bool {
	project := opts['project'] or {
		return error('gcp_pubsub source: project is required')
	}
	if project.len == 0 {
		return error('gcp_pubsub source: project is required')
	}

	subscription := opts['subscription'] or {
		return error('gcp_pubsub source: subscription is required')
	}
	if subscription.len == 0 {
		return error('gcp_pubsub source: subscription is required')
	}

	return true
}

// run polls Pub/Sub via the REST API for messages and emits them as log events.
// The polling loop:
//   1. POST to :pull endpoint with maxMessages based on max_concurrency
//   2. For each received message, decode data (base64), create LogEvent with
//      message data and metadata (message_id, publish_time, attributes)
//   3. POST to :acknowledge endpoint with ackIds for successfully processed messages
//   4. Sleep for poll_time_secs before next iteration
pub fn (s &GcpPubsubSource) run(output chan event.Event) {
	// Stub: In production, this would poll the Pub/Sub REST API in a loop.
	// The pull URL would be built via build_pubsub_pull_url(), and ack URL
	// via build_pubsub_ack_url(). Auth would use either api_key as a query
	// parameter or credentials_file for OAuth2 bearer token.
	for {
		time.sleep(time.Duration(i64(s.poll_time_secs) * 1_000_000_000))
	}
}
