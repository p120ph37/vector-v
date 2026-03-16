# Unimplemented Vector Components

## VRL Function Coverage: ~201 / 201 upstream (~100%)

All upstream VRL functions are implemented.

---

## Unimplemented Vector Components

### Sources (12 not implemented)
| Source | Notes |
|--------|-------|
| file | File-based log tailing |
| heroku_logplex | Heroku Logplex drain receiver |
| http_server | HTTP endpoint receiver (Vector-V has http_client source) |
| internal_logs | Vector's own internal log events |
| internal_metrics | Vector's own internal metrics |
| journald | systemd journal reader |
| logstash | Logstash protocol receiver |
| postgresql_metrics | PostgreSQL server metrics scraper |
| prometheus_pushgateway | Prometheus Pushgateway receiver (Vector-V has prometheus scrape) |
| prometheus_remote_write | Prometheus remote write receiver |
| static_metrics | Static/fixed metric values |
| syslog | Syslog protocol receiver (RFC 3164/5424) |

### Transforms (4 not implemented)
| Transform | Notes |
|-----------|-------|
| incremental_to_absolute | Convert incremental metrics to absolute |
| lua | Lua scripting (V has no Lua FFI) |
| route | Multi-output conditional routing (Vector-V has exclusive_route) |
| trace_to_log | Convert trace spans to log events |

Note: Vector-V includes `passthrough` (identity transform) which is not in upstream Vector.

### Sinks (31 not implemented)
| Sink | Notes |
|------|-------|
| appsignal | AppSignal metrics/logs |
| aws_sns | AWS SNS message publishing |
| axiom | Axiom log ingestion |
| azure_logs_ingestion | Azure Logs Ingestion API (DCR/DCE) |
| clickhouse | ClickHouse database insert |
| databend | Databend database insert |
| datadog_events | Datadog Events API (Vector-V has datadog logs only) |
| datadog_metrics | Datadog Metrics API |
| datadog_traces | Datadog Traces API |
| doris | Apache Doris database insert |
| elasticsearch | Elasticsearch bulk API |
| gcp_chronicle | GCP Chronicle unstructured log ingestion |
| gcp_cloud_monitoring | GCP Cloud Monitoring (metrics) |
| greptimedb_logs | GreptimeDB log ingestion |
| greptimedb_metrics | GreptimeDB metrics ingestion |
| honeycomb | Honeycomb events API |
| humio_logs | Humio/LogScale logs API |
| humio_metrics | Humio/LogScale metrics API |
| influxdb_logs | InfluxDB log ingestion |
| influxdb_metrics | InfluxDB metrics write |
| keep | Keep alert/event ingestion |
| mezmo | Mezmo (LogDNA) log ingestion |
| new_relic | New Relic log/event API |
| papertrail | Papertrail syslog forwarding |
| postgres | PostgreSQL insert |
| prometheus_remote_write | Prometheus remote write sender (Vector-V has Pushgateway push) |
| sematext_logs | Sematext Logs API |
| sematext_metrics | Sematext Metrics API |
| splunk_hec_metrics | Splunk HEC metrics (Vector-V has splunk_hec logs only) |
| webhdfs | WebHDFS file append |
| websocket_server | WebSocket server sink (Vector-V has websocket client sink) |
