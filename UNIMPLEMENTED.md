# Unimplemented Vector Components

Tracking what remains to be implemented against upstream [Vector](https://vector.dev) components.

---

## VRL Function Coverage: ~201 / 201 upstream (~100%)

All upstream VRL functions are implemented.

---

## Sources (46 / 46 upstream — 100%)

All 46 upstream sources are implemented.

---

## Transforms (16 / 17 upstream — 94%)

| Transform | Notes |
|-----------|-------|
| lua | Lua scripting (V has no Lua FFI — not planned) |

Note: Vector-V includes `passthrough` (identity transform) which is not in upstream Vector.

---

## Sinks (38 / 61 upstream — 62%)

### Implemented (38)
console, blackhole, http, file, aws_s3, websocket, socket, vector, loki, opentelemetry, aws_cloudwatch_logs, aws_cloudwatch_metrics, statsd, prometheus, prometheus_remote_write, aws_kinesis_streams, aws_kinesis_firehose, aws_sqs, splunk_hec, datadog (logs), datadog_metrics, datadog_traces, influxdb, redis, kafka, nats, amqp, pulsar, gcp_pubsub, mqtt, azure_blob, azure_monitor_logs, gcp_cloud_storage, gcp_stackdriver, aws_sns, azure_logs_ingestion, gcp_chronicle, gcp_cloud_monitoring

### Not implemented (23)

| Sink | Notes |
|------|-------|
| appsignal | AppSignal metrics/logs |
| axiom | Axiom log ingestion |
| clickhouse | ClickHouse database insert |
| databend | Databend database insert |
| datadog_events | Datadog Events API |
| doris | Apache Doris database insert |
| elasticsearch | Elasticsearch bulk API |
| greptimedb_logs | GreptimeDB log ingestion |
| greptimedb_metrics | GreptimeDB metrics ingestion |
| honeycomb | Honeycomb events API |
| humio_logs | Humio/LogScale logs API |
| humio_metrics | Humio/LogScale metrics API |
| keep | Keep alert/event ingestion |
| mezmo | Mezmo (LogDNA) log ingestion |
| new_relic | New Relic log/event API |
| papertrail | Papertrail syslog forwarding |
| postgres | PostgreSQL insert |
| sematext_logs | Sematext Logs API |
| sematext_metrics | Sematext Metrics API |
| splunk_hec_metrics | Splunk HEC metrics (Vector-V has splunk_hec logs only) |
| webhdfs | WebHDFS file append |
| websocket_server | WebSocket server sink (Vector-V has websocket client sink) |

---

## Test Coverage

Coverage is measured per-module using V's built-in `-coverage` instrumentation.

### New/updated sinks (this cycle)
| Module | Coverage |
|--------|----------|
| datadog.v | 100% |
| datadog_metrics.v | 100% |
| datadog_traces.v | 100% |
| influxdb.v | 100% |
| prometheus_remote_write.v | 100% |
| splunk_hec.v | 100% |
| websocket.v | 100% |

### AWS module
| Module | Coverage |
|--------|----------|
| sigv4.v | 100% |
| credentials.v | Tested via unit tests (ECS, env, profile, explicit, IMDS chain) |

### Overall sinks module
- **87.1%** statement coverage across all 39 sink source files
- All new/updated sink files achieve **100%** coverage
- Lower coverage in pre-existing AWS sinks (CloudWatch Logs 46%, CloudWatch Metrics 53%) is due to SigV4-signed HTTP paths requiring live AWS endpoints
