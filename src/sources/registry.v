module sources

import event

// Source is a tagged union of all source types.
pub type Source = StdinSource
	| DemoLogsSource
	| FluentSource
	| ExecSource
	| FileDescriptorSource
	| HttpClientSource
	| SocketSource
	| WebSocketSource
	| VectorSource
	| StatsdSource
	| PrometheusSource
	| S3Source
	| SqsSource
	| KinesisFirehoseSource
	| EcsMetricsSource
	| OpenTelemetrySource
	| SplunkHecSource
	| RedisSource
	| DatadogAgentSource
	| HostMetricsSource
	| DockerLogsSource
	| KubernetesLogsSource
	| KafkaSource
	| NatsSource
	| AmqpSource
	| PulsarSource
	| GcpPubsubSource
	| MqttSource
	| ApacheMetricsSource
	| NginxMetricsSource
	| MongodbMetricsSource
	| EventStoreDbMetricsSource
	| DnstapSource
	| OktaSource
	| FileSource
	| SyslogSource
	| HttpServerSource
	| StaticMetricsSource
	| HerokuLogplexSource
	| JournaldSource
	| LogstashSource
	| PostgresqlMetricsSource
	| InternalLogsSource
	| InternalMetricsSource
	| PrometheusRemoteWriteSource
	| PrometheusPushgatewaySource

// build_source creates a Source from a type name and config options.
pub fn build_source(typ string, opts map[string]string) !Source {
	match typ {
		'stdin' {
			return Source(new_stdin(opts))
		}
		'demo_logs' {
			return Source(new_demo_logs(opts))
		}
		'fluent' {
			return Source(new_fluent(opts))
		}
		'exec' {
			return Source(new_exec(opts)!)
		}
		'file_descriptors' {
			return Source(new_file_descriptor(opts))
		}
		'http_client' {
			return Source(new_http_client(opts)!)
		}
		'socket' {
			return Source(new_socket(opts))
		}
		'websocket' {
			return Source(new_websocket_source(opts)!)
		}
		'vector' {
			return Source(new_vector_source(opts))
		}
		'statsd' {
			return Source(new_statsd(opts))
		}
		'prometheus', 'prometheus_scrape' {
			return Source(new_prometheus(opts)!)
		}
		'aws_s3' {
			return Source(new_s3_source(opts)!)
		}
		'aws_sqs' {
			return Source(new_sqs(opts)!)
		}
		'aws_kinesis_firehose' {
			return Source(new_kinesis_firehose(opts))
		}
		'aws_ecs_metrics' {
			return Source(new_ecs_metrics(opts))
		}
		'opentelemetry' {
			return Source(new_opentelemetry_source(opts))
		}
		'splunk_hec' {
			return Source(new_splunk_hec_source(opts))
		}
		'redis' {
			return Source(new_redis_source(opts)!)
		}
		'datadog_agent' {
			return Source(new_datadog_agent(opts))
		}
		'host_metrics' {
			return Source(new_host_metrics(opts))
		}
		'docker_logs' {
			return Source(new_docker_logs(opts))
		}
		'kubernetes_logs' {
			return Source(new_kubernetes_logs(opts))
		}
		'kafka' {
			return Source(new_kafka_source(opts)!)
		}
		'nats' {
			return Source(new_nats_source(opts)!)
		}
		'amqp' {
			return Source(new_amqp_source(opts))
		}
		'pulsar' {
			return Source(new_pulsar_source(opts)!)
		}
		'gcp_pubsub' {
			return Source(new_gcp_pubsub_source(opts)!)
		}
		'mqtt' {
			return Source(new_mqtt_source(opts)!)
		}
		'apache_metrics' {
			return Source(new_apache_metrics(opts)!)
		}
		'nginx_metrics' {
			return Source(new_nginx_metrics(opts)!)
		}
		'mongodb_metrics' {
			return Source(new_mongodb_metrics(opts)!)
		}
		'eventstoredb_metrics' {
			return Source(new_eventstoredb_metrics(opts))
		}
		'dnstap' {
			return Source(new_dnstap(opts)!)
		}
		'okta' {
			return Source(new_okta(opts)!)
		}
		'file' {
			return Source(new_file(opts)!)
		}
		'syslog' {
			return Source(new_syslog(opts))
		}
		'http_server' {
			return Source(new_http_server(opts))
		}
		'static_metrics' {
			return Source(new_static_metrics(opts))
		}
		'heroku_logplex' {
			return Source(new_heroku_logplex(opts))
		}
		'journald' {
			return Source(new_journald(opts))
		}
		'logstash' {
			return Source(new_logstash(opts))
		}
		'postgresql_metrics' {
			return Source(new_postgresql_metrics(opts))
		}
		'internal_logs' {
			return Source(new_internal_logs(opts))
		}
		'internal_metrics' {
			return Source(new_internal_metrics(opts))
		}
		'prometheus_remote_write' {
			return Source(new_prometheus_remote_write(opts))
		}
		'prometheus_pushgateway' {
			return Source(new_prometheus_pushgateway(opts))
		}
		else {
			return error('unknown source type: "${typ}"')
		}
	}
}

// run_source dispatches to the appropriate source's run method.
pub fn run_source(s Source, output chan event.Event) {
	match s {
		StdinSource {
			s.run(output)
		}
		DemoLogsSource {
			s.run(output)
		}
		FluentSource {
			s.run(output)
		}
		ExecSource {
			s.run(output)
		}
		FileDescriptorSource {
			s.run(output)
		}
		HttpClientSource {
			s.run(output)
		}
		SocketSource {
			s.run(output)
		}
		WebSocketSource {
			s.run(output)
		}
		VectorSource {
			s.run(output)
		}
		StatsdSource {
			s.run(output)
		}
		PrometheusSource {
			s.run(output)
		}
		S3Source {
			s.run(output)
		}
		SqsSource {
			s.run(output)
		}
		KinesisFirehoseSource {
			s.run(output)
		}
		EcsMetricsSource {
			s.run(output)
		}
		OpenTelemetrySource {
			s.run(output)
		}
		SplunkHecSource {
			s.run(output)
		}
		RedisSource {
			s.run(output)
		}
		DatadogAgentSource {
			s.run(output)
		}
		HostMetricsSource {
			s.run(output)
		}
		DockerLogsSource {
			s.run(output)
		}
		KubernetesLogsSource {
			s.run(output)
		}
		KafkaSource {
			s.run(output)
		}
		NatsSource {
			s.run(output)
		}
		AmqpSource {
			s.run(output)
		}
		PulsarSource {
			s.run(output)
		}
		GcpPubsubSource {
			s.run(output)
		}
		MqttSource {
			s.run(output)
		}
		ApacheMetricsSource {
			s.run(output)
		}
		NginxMetricsSource {
			s.run(output)
		}
		MongodbMetricsSource {
			s.run(output)
		}
		EventStoreDbMetricsSource {
			s.run(output)
		}
		DnstapSource {
			s.run(output)
		}
		OktaSource {
			s.run(output)
		}
		FileSource {
			s.run(output)
		}
		SyslogSource {
			s.run(output)
		}
		HttpServerSource {
			s.run(output)
		}
		StaticMetricsSource {
			s.run(output)
		}
		HerokuLogplexSource {
			s.run(output)
		}
		JournaldSource {
			s.run(output)
		}
		LogstashSource {
			s.run(output)
		}
		PostgresqlMetricsSource {
			s.run(output)
		}
		InternalLogsSource {
			s.run(output)
		}
		InternalMetricsSource {
			s.run(output)
		}
		PrometheusRemoteWriteSource {
			s.run(output)
		}
		PrometheusPushgatewaySource {
			s.run(output)
		}
	}
}
