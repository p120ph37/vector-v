# Unimplemented Vector Components

## VRL Function Coverage: ~201 / 201 upstream (~100%)

All upstream VRL functions are implemented.

---

## Unimplemented Vector Components

### Sources (12 not implemented)
| Source | Notes |
|--------|-------|
| apache_metrics | Prometheus scrape of Apache mod_status |
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
| redis | Redis pub/sub or list |
| splunk_hec | Splunk HEC receiver |

### Transforms (1 not implemented)
| Transform | Notes |
|-----------|-------|
| lua | Lua scripting (V has no Lua FFI) |

### Sinks (27+ not implemented)
Major categories not yet implemented:
- **Azure**: blob, logs_ingestion, monitor_logs
- **GCP**: Cloud Storage, Chronicle, Pub/Sub, Stackdriver
- **Databases**: clickhouse, elasticsearch, postgres, influxdb, greptimedb, databend, doris
- **Messaging**: kafka, nats, mqtt, pulsar, redis, amqp
- **Observability**: datadog, splunk_hec, new_relic, honeycomb, sematext, axiom, appsignal, humio
- **Other**: webhdfs
