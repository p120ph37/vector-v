# Unimplemented Vector Components

## VRL Function Coverage: ~201 / 201 upstream (~100%)

All upstream VRL functions are implemented.

---

## Unimplemented Vector Components

### Sources (0 not implemented)

All 46 upstream sources are implemented.

### Transforms (1 not implemented)
| Transform | Notes |
|-----------|-------|
| lua | Lua scripting (V has no Lua FFI — not planned) |

Note: Vector-V includes `passthrough` (identity transform) which is not in upstream Vector.

### Sinks (27 not implemented)
| Sink | Notes |
|------|-------|
| appsignal | AppSignal metrics/logs |
| axiom | Axiom log ingestion |
| clickhouse | ClickHouse database insert |
| databend | Databend database insert |
| datadog_events | Datadog Events API (Vector-V has datadog logs only) |
| datadog_metrics | Datadog Metrics API |
| datadog_traces | Datadog Traces API |
| doris | Apache Doris database insert |
| elasticsearch | Elasticsearch bulk API |
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
