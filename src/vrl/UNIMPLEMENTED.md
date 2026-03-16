# Unimplemented Vector Components

## VRL Function Coverage: ~201 / 201 upstream (~100%)

All upstream VRL functions are implemented.

---

## Unimplemented Vector Components

### Sources (18 not implemented)
| Source | Notes |
|--------|-------|
| apache_metrics | Prometheus scrape of Apache mod_status |
| aws_ecs_metrics | ECS task metadata endpoint |
| aws_kinesis_firehose | HTTP endpoint for Firehose delivery |
| aws_s3 | S3 bucket polling/notifications |
| aws_sqs | SQS message consumption |
| datadog_agent | Datadog Agent forwarding |
| dnstap | DNS tap protocol |
| docker_logs | Docker container log collection |
| eventstoredb_metrics | EventStoreDB stats |
| host_metrics | System metrics (CPU, memory, disk) |
| kubernetes_logs | K8s pod log collection |
| mongodb_metrics | MongoDB server stats |
| mqtt | MQTT subscription |
| nats | NATS subscription |
| nginx_metrics | Nginx stub_status metrics |
| okta | Okta system log API |
| opentelemetry | OTLP receiver |
| prometheus | Prometheus remote-write/scrape |
| redis | Redis pub/sub or list |
| splunk_hec | Splunk HEC receiver |
| statsd | StatsD protocol |

### Transforms (1 not implemented)
| Transform | Notes |
|-----------|-------|
| lua | Lua scripting (V has no Lua FFI) |

### Sinks (31+ not implemented)
Major categories not yet implemented:
- **AWS**: kinesis, sqs
- **Azure**: blob, logs_ingestion, monitor_logs
- **GCP**: Cloud Storage, Chronicle, Pub/Sub, Stackdriver
- **Databases**: clickhouse, elasticsearch, postgres, influxdb, greptimedb, databend, doris
- **Messaging**: kafka, nats, mqtt, pulsar, redis, amqp
- **Observability**: datadog, splunk_hec, new_relic, honeycomb, sematext, axiom, appsignal, humio
- **Other**: statsd, prometheus, webhdfs
