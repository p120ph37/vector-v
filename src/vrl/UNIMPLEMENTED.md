# Unimplemented VRL Functions & Vector Components

## VRL Function Coverage: ~180 / 201 upstream (~90%)

### Unimplemented VRL Functions (21 remaining)

#### Parsing (13)
- `parse_apache_log` — Apache combined/common log format
- `parse_aws_alb_log` — AWS ALB access logs
- `parse_aws_vpc_flow_log` — AWS VPC flow log records
- `parse_cbor` — CBOR binary format
- `parse_cef` — ArcSight Common Event Format
- `parse_glog` — Google glog format
- `parse_groks` — Multi-pattern grok (like parse_grok but with multiple patterns)
- `parse_influxdb` — InfluxDB line protocol
- `parse_nginx_log` — Nginx combined/error log format
- `parse_proto` — Protocol Buffers (requires descriptor files)
- `parse_ruby_hash` — Ruby hash literal syntax
- `parse_user_agent` — User-Agent string parsing (requires UA database)
- `parse_xml` — XML to object conversion

#### Encoding (1)
- `encode_proto` — Protocol Buffers encoding (requires descriptor files)

#### Crypto (4)
- `encrypt` — AES encryption (AES-256-CFB, AES-128-SIV)
- `decrypt` — AES decryption
- `encrypt_ip` — Format-preserving IP encryption (FF1)
- `decrypt_ip` — Format-preserving IP decryption (FF1)

#### Misc (3)
- `validate_json_schema` — JSON Schema validation (requires schema file loading)
- `http_request` — HTTP request from within VRL (side-effecting, security-sensitive)
- `encode_proto` / `parse_proto` — Protobuf encode/decode (requires prost-reflect equivalent)

### Notes
- `validate_json_schema` returns an informative "not implemented" error at runtime
- `http_request` is intentionally excluded as it introduces network side-effects into VRL evaluation
- `encode_proto`/`parse_proto` require protobuf descriptor file infrastructure
- The `encrypt`/`decrypt` family requires AES cipher implementations (AES-256-CFB, AES-256-OFB-NP, AES-128-SIV)
- `encrypt_ip`/`decrypt_ip` require FF1 format-preserving encryption
- `parse_user_agent` requires a UA parser database (woothee or similar)
- Most parsing functions (apache, nginx, alb, vpc_flow, cef, glog, influxdb) are log-format-specific regex/state-machine parsers

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

### Transforms (4 not implemented)
| Transform | Notes |
|-----------|-------|
| dedupe | Event deduplication |
| exclusive_route | Route to first matching output |
| lua | Lua scripting |
| sample | Statistical sampling |
| tag_cardinality_limit | High-cardinality tag limiting |
| throttle | Rate limiting |
| window | Time-window aggregation |

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
