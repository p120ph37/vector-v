module sources

fn test_build_source_stdin() {
	s := build_source('stdin', map[string]string{}) or { panic(err) }
	assert s is StdinSource
}

fn test_build_source_demo_logs() {
	s := build_source('demo_logs', map[string]string{}) or { panic(err) }
	assert s is DemoLogsSource
}

fn test_build_source_fluent() {
	s := build_source('fluent', map[string]string{}) or { panic(err) }
	assert s is FluentSource
}

fn test_build_source_unknown_errors() {
	if _ := build_source('nonexistent', map[string]string{}) {
		assert false, 'expected error for unknown source type'
	}
}

fn test_build_source_exec() {
	s := build_source('exec', {
		'command': 'echo hello'
	}) or { panic(err) }
	assert s is ExecSource
}

fn test_build_source_file_descriptors() {
	s := build_source('file_descriptors', map[string]string{}) or { panic(err) }
	assert s is FileDescriptorSource
}

fn test_build_source_http_client() {
	s := build_source('http_client', {
		'endpoint': 'http://localhost:8080/test'
	}) or { panic(err) }
	assert s is HttpClientSource
}

fn test_build_source_socket() {
	s := build_source('socket', map[string]string{}) or { panic(err) }
	assert s is SocketSource
}

fn test_build_source_websocket() {
	s := build_source('websocket', {
		'url': 'ws://localhost:9090'
	}) or { panic(err) }
	assert s is WebSocketSource
}

fn test_build_source_vector() {
	s := build_source('vector', map[string]string{}) or { panic(err) }
	assert s is VectorSource
}

fn test_build_source_statsd() {
	s := build_source('statsd', map[string]string{}) or { panic(err) }
	assert s is StatsdSource
}

fn test_build_source_prometheus() {
	s := build_source('prometheus', {
		'endpoints': 'http://localhost:9090/metrics'
	}) or { panic(err) }
	assert s is PrometheusSource
}

fn test_build_source_aws_kinesis_firehose() {
	s := build_source('aws_kinesis_firehose', map[string]string{}) or { panic(err) }
	assert s is KinesisFirehoseSource
}

fn test_build_source_aws_ecs_metrics() {
	s := build_source('aws_ecs_metrics', map[string]string{}) or { panic(err) }
	assert s is EcsMetricsSource
}

fn test_build_source_opentelemetry() {
	s := build_source('opentelemetry', map[string]string{}) or { panic(err) }
	assert s is OpenTelemetrySource
}

fn test_build_source_splunk_hec() {
	s := build_source('splunk_hec', map[string]string{}) or { panic(err) }
	assert s is SplunkHecSource
}

fn test_build_source_datadog_agent() {
	s := build_source('datadog_agent', map[string]string{}) or { panic(err) }
	assert s is DatadogAgentSource
}

fn test_build_source_host_metrics() {
	s := build_source('host_metrics', map[string]string{}) or { panic(err) }
	assert s is HostMetricsSource
}

fn test_build_source_docker_logs() {
	s := build_source('docker_logs', map[string]string{}) or { panic(err) }
	assert s is DockerLogsSource
}

fn test_build_source_kubernetes_logs() {
	s := build_source('kubernetes_logs', map[string]string{}) or { panic(err) }
	assert s is KubernetesLogsSource
}

fn test_build_source_amqp() {
	s := build_source('amqp', map[string]string{}) or { panic(err) }
	assert s is AmqpSource
}

fn test_build_source_eventstoredb_metrics() {
	s := build_source('eventstoredb_metrics', map[string]string{}) or { panic(err) }
	assert s is EventStoreDbMetricsSource
}

fn test_build_source_dnstap() {
	s := build_source('dnstap', map[string]string{}) or { panic(err) }
	assert s is DnstapSource
}

fn test_build_source_apache_metrics() {
	s := build_source('apache_metrics', {
		'endpoints': 'http://localhost:8080/server-status?auto'
	}) or { panic(err) }
	assert s is ApacheMetricsSource
}

fn test_build_source_nginx_metrics() {
	s := build_source('nginx_metrics', {
		'endpoints': 'http://localhost:8080/status'
	}) or { panic(err) }
	assert s is NginxMetricsSource
}

fn test_build_source_mongodb_metrics() {
	s := build_source('mongodb_metrics', {
		'endpoints': 'mongodb://localhost:27017'
	}) or { panic(err) }
	assert s is MongodbMetricsSource
}

fn test_build_source_redis() {
	s := build_source('redis', {
		'url': 'redis://localhost:6379'
		'key': 'test-channel'
	}) or { panic(err) }
	assert s is RedisSource
}

fn test_build_source_kafka() {
	s := build_source('kafka', {
		'bootstrap_servers': 'localhost:9092'
		'group_id':          'test-group'
		'topics':            'test-topic'
	}) or { panic(err) }
	assert s is KafkaSource
}

fn test_build_source_nats() {
	s := build_source('nats', {
		'url':     'nats://localhost:4222'
		'subject': 'test.subject'
	}) or { panic(err) }
	assert s is NatsSource
}

fn test_build_source_pulsar() {
	s := build_source('pulsar', {
		'endpoint': 'pulsar://localhost:6650'
		'topics':   'test-topic'
	}) or { panic(err) }
	assert s is PulsarSource
}

fn test_build_source_gcp_pubsub() {
	s := build_source('gcp_pubsub', {
		'project':      'test-project'
		'subscription': 'test-subscription'
	}) or { panic(err) }
	assert s is GcpPubsubSource
}

fn test_build_source_mqtt() {
	s := build_source('mqtt', {
		'host':  'localhost'
		'topic': 'test/topic'
	}) or { panic(err) }
	assert s is MqttSource
}

fn test_build_source_okta() {
	s := build_source('okta', {
		'base_url':  'https://dev-123456.okta.com'
		'api_token': 'test-token'
	}) or { panic(err) }
	assert s is OktaSource
}
