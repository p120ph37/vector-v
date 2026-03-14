# Unimplemented Vector Components

## VRL Function Coverage: ~201 / 201 upstream (~100%)

All upstream VRL functions are implemented.

---

## Unimplemented Vector Components

### Sources (24 not implemented)
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
| exec | Execute external commands |
| file_descriptors | Read from file descriptors |
| host_metrics | System metrics (CPU, memory, disk) |
| http_client | HTTP polling source |
| kubernetes_logs | K8s pod log collection |
| mongodb_metrics | MongoDB server stats |
| mqtt | MQTT subscription |
| nats | NATS subscription |
| nginx_metrics | Nginx stub_status metrics |
| okta | Okta system log API |
| opentelemetry | OTLP receiver |
| prometheus | Prometheus remote-write/scrape |
| redis | Redis pub/sub or list |
| socket | TCP/UDP/Unix socket |
| splunk_hec | Splunk HEC receiver |
| statsd | StatsD protocol |
| vector | Vector-to-Vector protocol |
| websocket | WebSocket client |

### Transforms (6 not implemented)
| Transform | Notes |
|-----------|-------|
| lua | Lua scripting |
| tag_cardinality_limit | High-cardinality tag limiting |
| window | Time-window aggregation |
| log_to_metric | Convert log events to metrics |
| metric_to_log | Convert metrics to log events |
| aggregate | Aggregate metrics over time |

### Sinks (38+ not implemented)
Major categories not yet implemented:
- **AWS**: cloudwatch_logs, cloudwatch_metrics, kinesis, s3, sqs
- **Azure**: blob, logs_ingestion, monitor_logs
- **GCP**: Cloud Storage, Chronicle, Pub/Sub, Stackdriver
- **Databases**: clickhouse, elasticsearch, postgres, influxdb, greptimedb, databend, doris
- **Messaging**: kafka, nats, mqtt, pulsar, redis, amqp
- **Observability**: datadog, splunk_hec, new_relic, honeycomb, sematext, axiom, appsignal, humio
- **File/Storage**: file, webhdfs, s3
- **Other**: http, statsd, prometheus, vector, websocket
