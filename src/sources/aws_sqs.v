module sources

import aws
import event
import net.http
import time

// SqsSource polls messages from an AWS SQS queue and emits them as log events.
// Mirrors Vector's aws_sqs source.
//
// Config options:
//   queue_url:              SQS queue URL (required)
//   region:                 AWS region
//   endpoint:               Custom endpoint (for localstack)
//   poll_interval_secs:     Polling interval in seconds (default: 1)
//   max_messages:           Max messages per poll (default: 10, max 10)
//   visibility_timeout:     Visibility timeout in seconds (default: 300)
//   wait_time_seconds:      Long polling wait time (default: 20)
//   delete_message:         Whether to delete messages after receipt (default: true)
//   auth.access_key_id:     Explicit AWS access key
//   auth.secret_access_key: Explicit AWS secret key
//   auth.session_token:     Explicit session token
pub struct SqsSource {
	queue_url          string
	region             string
	endpoint           string
	creds              aws.AwsCredentials
	poll_interval      time.Duration = 1 * time.second
	max_messages       int    = 10
	visibility_timeout int    = 300
	wait_time_seconds  int    = 20
	delete_message     bool   = true
}

// new_sqs creates a new SqsSource from config options.
pub fn new_sqs(opts map[string]string) !SqsSource {
	resolved := aws.resolve_credentials(opts)!
	if resolved.creds.access_key_id.len == 0 && resolved.source != .none {
		return error('aws_sqs source: no AWS credentials found')
	}

	region := if resolved.creds.region.len > 0 {
		resolved.creds.region
	} else {
		opts['region'] or { 'us-east-1' }
	}

	queue_url := opts['queue_url'] or {
		return error('aws_sqs source: queue_url is required')
	}

	endpoint := opts['endpoint'] or { 'https://sqs.${region}.amazonaws.com' }

	mut poll_secs := 1.0
	if s := opts['poll_interval_secs'] {
		poll_secs = s.f64()
		if poll_secs <= 0 {
			poll_secs = 1.0
		}
	}

	mut max_messages := 10
	if m := opts['max_messages'] {
		max_messages = m.int()
		if max_messages <= 0 || max_messages > 10 {
			max_messages = 10
		}
	}

	mut visibility_timeout := 300
	if v := opts['visibility_timeout'] {
		visibility_timeout = v.int()
		if visibility_timeout <= 0 {
			visibility_timeout = 300
		}
	}

	mut wait_time_seconds := 20
	if w := opts['wait_time_seconds'] {
		wait_time_seconds = w.int()
		if wait_time_seconds < 0 || wait_time_seconds > 20 {
			wait_time_seconds = 20
		}
	}

	delete_val := opts['delete_message'] or { 'true' }

	return SqsSource{
		queue_url: queue_url
		region: region
		endpoint: endpoint
		creds: aws.AwsCredentials{
			access_key_id: resolved.creds.access_key_id
			secret_access_key: resolved.creds.secret_access_key
			session_token: resolved.creds.session_token
			region: region
		}
		poll_interval: time.Duration(i64(poll_secs * 1_000_000_000))
		max_messages: max_messages
		visibility_timeout: visibility_timeout
		wait_time_seconds: wait_time_seconds
		delete_message: delete_val == 'true'
	}
}

// run polls SQS for messages and emits them as log events.
pub fn (s &SqsSource) run(output chan event.Event) {
	for {
		s.poll(output)
		time.sleep(s.poll_interval)
	}
}

fn (s &SqsSource) poll(output chan event.Event) {
	body := 'Action=ReceiveMessage&MaxNumberOfMessages=${s.max_messages}&WaitTimeSeconds=${s.wait_time_seconds}&VisibilityTimeout=${s.visibility_timeout}'

	resp := s.send_sqs_request(body) or {
		eprintln('aws_sqs: ReceiveMessage failed: ${err}')
		return
	}

	messages := parse_sqs_messages(resp)
	for msg in messages {
		mut ev := event.new_log(msg.body)
		ev.meta.source_type = 'aws_sqs'
		ev.set('message_id', event.Value(msg.message_id))
		ev.set('receipt_handle', event.Value(msg.receipt_handle))
		output <- event.Event(ev)

		if s.delete_message && msg.receipt_handle.len > 0 {
			s.delete_msg(msg.receipt_handle)
		}
	}
}

fn (s &SqsSource) delete_msg(receipt_handle string) {
	body := 'Action=DeleteMessage&ReceiptHandle=${receipt_handle}'
	s.send_sqs_request(body) or {
		eprintln('aws_sqs: DeleteMessage failed: ${err}')
	}
}

fn (s &SqsSource) send_sqs_request(payload string) !string {
	host := s.endpoint.replace('https://', '').replace('http://', '')

	signed := aws.sign_request(aws.SignConfig{
		creds: s.creds
		method: 'POST'
		host: host
		path: '/'
		region: s.region
		service: 'sqs'
		content_type: 'application/x-www-form-urlencoded'
		payload: payload
	})!

	mut header := http.Header{}
	for k, v in signed.headers {
		header.add_custom(k, v)!
	}

	resp := http.fetch(http.FetchConfig{
		url: s.endpoint
		method: .post
		data: payload
		header: header
		verbose: false
	}) or {
		return error('SQS HTTP request failed: ${err}')
	}

	if resp.status_code >= 400 {
		return error('SQS HTTP ${resp.status_code}: ${resp.body}')
	}

	return resp.body
}

// SqsMessage holds a parsed SQS message.
struct SqsMessage {
	message_id     string
	receipt_handle string
	body           string
}

// parse_sqs_messages extracts <Message> elements from SQS ReceiveMessage XML response.
fn parse_sqs_messages(xml string) []SqsMessage {
	mut messages := []SqsMessage{}
	mut rest := xml

	for {
		msg_start := rest.index('<Message>') or { break }
		after_msg := rest[msg_start + 9..]
		msg_end := after_msg.index('</Message>') or { break }
		msg_xml := after_msg[..msg_end]

		message_id := extract_xml_value(msg_xml, 'MessageId')
		receipt_handle := extract_xml_value(msg_xml, 'ReceiptHandle')
		body := extract_xml_value(msg_xml, 'Body')

		messages << SqsMessage{
			message_id: message_id
			receipt_handle: receipt_handle
			body: body
		}

		rest = after_msg[msg_end + 10..]
	}

	return messages
}

// extract_xml_value extracts the text content of a simple XML element.
fn extract_xml_value(xml string, tag string) string {
	open_tag := '<${tag}>'
	close_tag := '</${tag}>'
	start := xml.index(open_tag) or { return '' }
	after := xml[start + open_tag.len..]
	end := after.index(close_tag) or { return '' }
	return after[..end]
}
