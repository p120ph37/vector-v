# Vector-V Development Guide

Vector-V is a V-language reimplementation of [Vector](https://vector.dev), a high-performance observability data pipeline originally written in Rust. The upstream Rust source is kept in `upstream/` for reference.

## Project Structure

- `src/` — V source code
  - `vrl/` — VRL (Vector Remap Language) interpreter and runtime
  - `sources/` — Data ingestion components (stdin, demo_logs, fluent, exec, file_descriptors, http_client, socket, websocket, vector, statsd, prometheus, aws_s3, aws_sqs, aws_kinesis_firehose, aws_ecs_metrics, opentelemetry, splunk_hec, redis, datadog_agent, host_metrics, docker_logs, kubernetes_logs, kafka, nats, amqp, pulsar, gcp_pubsub, mqtt, apache_metrics, nginx_metrics, mongodb_metrics, eventstoredb_metrics, dnstap, okta, file, syslog, http_server, static_metrics, internal_logs, internal_metrics, prometheus_remote_write, prometheus_pushgateway, heroku_logplex, journald, logstash, postgresql_metrics)
  - `transforms/` — Data processing (remap, filter, reduce, aws_ec2_metadata, dedupe, sample, throttle, exclusive_route, passthrough, log_to_metric, metric_to_log, aggregate, tag_cardinality_limit, window, route, trace_to_log, incremental_to_absolute)
  - `sinks/` — Data output destinations (console, blackhole, http, file, loki, opentelemetry, aws_cloudwatch_logs, aws_cloudwatch_metrics, aws_s3, aws_kinesis_streams, aws_kinesis_firehose, aws_sqs, socket, vector, websocket, statsd, prometheus, prometheus_remote_write, splunk_hec, datadog, datadog_metrics, datadog_traces, influxdb, redis, kafka, nats, amqp, pulsar, gcp_pubsub, mqtt, azure_blob, azure_monitor_logs, gcp_cloud_storage, gcp_stackdriver, aws_sns, azure_logs_ingestion, gcp_chronicle, gcp_cloud_monitoring)
  - `aws/` — Shared AWS utilities (credentials resolution with ECS task role support, SigV4 signing)
  - `event/` — Event types (log, metric, trace)
  - `topology/` — Component graph management with input-based routing
  - `conf/` — Configuration parsing (TOML, YAML, JSON with auto-detection)
  - `api/` — REST API server (health/ready endpoints)
  - `cliargs/` — Command-line argument parsing
  - `mockserver/` — Declarative mock HTTP server for testing network components
  - `main.v` — Entry point
- `upstream/` — Upstream Rust source for Vector and VRL (read-only reference, git submodules)

## Setup

```bash
git submodule update --init          # Fetch upstream Vector and VRL source into upstream/
```

## Environment Setup

The V compiler (>= 0.4.7) must be installed with clang as the C backend. If missing, install from source:

```bash
apt-get install -y clang libxxhash-dev libpcre2-dev libsnappy-dev liblz4-dev
git clone https://github.com/vlang/v /opt/vlang
cd /opt/vlang && make && ./v -cc clang self
ln -sf /opt/vlang/v /usr/local/bin/v
v version  # verify
```

## Build & Test

```bash
v -enable-globals .              # Build (globals required for PSL cache, UUID counter)
v -enable-globals test src/vrl/  # Run VRL tests
v -enable-globals test src/      # Run all tests
make build                       # Build via Makefile
make test-all                    # Run all test modules
make test-vrl                    # VRL tests via Makefile
```

## Code Coverage

Uses V's built-in `-coverage` instrumentation (available since V 0.4.7). The compiler inserts statement-level counters during C codegen, and `v cover` produces per-file line coverage reports.

```bash
make coverage                                    # Run with default 20% threshold
./scripts/runtime_coverage.sh --threshold 90     # Custom threshold
./scripts/runtime_coverage.sh --verbose          # Detailed output
./scripts/runtime_coverage.sh --filter transforms # Filter report by module
make coverage-clean                              # Remove .coverage/ artifacts
```

## Implemented Components

### Sources (46 / 46 upstream)
- **stdin** — Reads lines from stdin
- **demo_logs** — Generates sample log events
- **fluent** — Fluent Forward Protocol v1 over TCP (msgpack)
- **exec** — Run external commands and capture output (scheduled or streaming)
- **file_descriptors** — Read from file descriptors (generalized stdin)
- **http_client** — Poll HTTP endpoints at configurable intervals
- **socket** — Listen on TCP/UDP sockets with shared line-buffered framing
- **websocket** — Connect to WebSocket servers and receive messages
- **vector** — Receive events from other Vector instances (JSON-over-TCP)
- **statsd** — StatsD protocol receiver (UDP/TCP, DogStatsD tag extension)
- **prometheus** — Prometheus exposition format scraper (counter, gauge, histogram, summary)
- **aws_s3** — S3 bucket polling via ListObjectsV2/GetObject (SigV4-signed)
- **aws_sqs** — SQS message consumption via ReceiveMessage/DeleteMessage (SigV4-signed)
- **aws_kinesis_firehose** — HTTP endpoint for Kinesis Data Firehose delivery streams
- **aws_ecs_metrics** — ECS task metadata endpoint scraper (container CPU, memory, network)
- **opentelemetry** — OTLP HTTP receiver for logs (JSON ExportLogsServiceRequest)
- **splunk_hec** — Splunk HTTP Event Collector receiver (token auth, health check)
- **redis** — Redis pub/sub subscription and list polling (RESP protocol)
- **datadog_agent** — Datadog Agent HTTP log receiver (/api/v2/logs)
- **host_metrics** — System metrics from /proc (CPU, memory, disk, filesystem, load, network, uptime)
- **docker_logs** — Docker container log collection via Docker Engine API
- **kubernetes_logs** — Kubernetes pod log collection from node filesystem (CRI log format)
- **kafka** — Apache Kafka consumer (consumer groups, SASL/TLS auth)
- **nats** — NATS subject subscription (JetStream, queue groups)
- **amqp** — AMQP 0-9-1 consumer (RabbitMQ, exchange binding, prefetch)
- **pulsar** — Apache Pulsar topic subscription (OAuth2 auth, dead letter queue)
- **gcp_pubsub** — Google Cloud Pub/Sub subscription polling (REST API, ack management)
- **mqtt** — MQTT topic subscription (QoS 0-2, wildcard topics)
- **apache_metrics** — Apache mod_status metrics scraper (worker stats, scoreboard, request rates)
- **nginx_metrics** — Nginx stub_status metrics scraper (connections, requests, reading/writing/waiting)
- **mongodb_metrics** — MongoDB serverStatus metrics (connections, opcounters, memory)
- **eventstoredb_metrics** — EventStoreDB stats endpoint scraper (process, system, queue metrics)
- **dnstap** — DNS tap protocol receiver (Frame Streams, protobuf wire format)
- **okta** — Okta System Log API poller (security/audit events, actor/outcome tracking)
- **file** — File-based log tailing with glob patterns
- **syslog** — RFC 3164/5424 syslog receiver (TCP/UDP)
- **http_server** — HTTP POST endpoint for event ingestion
- **static_metrics** — Fixed metric value emitter
- **internal_logs** — Captures Vector-V's own logs (message, level, module, target)
- **internal_metrics** — Vector-V internal telemetry (component_received/sent_events_total, errors, uptime)
- **prometheus_remote_write** — HTTP /api/v1/write endpoint for Prometheus remote write
- **prometheus_pushgateway** — HTTP /metrics/job/{job} endpoint for Prometheus Pushgateway
- **heroku_logplex** — Heroku Logplex drain receiver
- **journald** — systemd journal via `journalctl -f -o json`
- **logstash** — JSON-over-TCP receiver (Logstash protocol)
- **postgresql_metrics** — PostgreSQL metrics scraper (connections, transactions, tuple ops)

### Transforms (16 / 17 upstream)
- **remap** — VRL program execution
- **filter** — Condition-based event filtering
- **reduce** — Event accumulation with merge strategies
- **aws_ec2_metadata** — EC2 instance metadata enrichment via IMDSv2
- **dedupe** — Event deduplication with LRU cache
- **sample** — Statistical event sampling (random or key-based)
- **throttle** — Rate limiting with token bucket algorithm
- **exclusive_route** — Route events to first matching output
- **passthrough** — Identity transform (pass events unchanged; not in upstream, Vector-V addition)
- **log_to_metric** — Convert log events to metrics (counter, gauge, set, histogram, summary)
- **metric_to_log** — Convert metric events to structured log events
- **aggregate** — Aggregate metrics over time intervals (sum counters, latest gauge, union sets)
- **tag_cardinality_limit** — Limit high-cardinality metric tags (drop_tag or drop_event)
- **window** — Group log events into time-based windows with optional group_by
- **route** — Multi-output routing (sends to all matching routes)
- **trace_to_log** — Convert trace events to structured log events
- **incremental_to_absolute** — Convert incremental metrics to absolute with running state

### Sinks (38 / 61 upstream)
- **console** — Write to stdout/stderr (json, text, logfmt)
- **blackhole** — Discard events (benchmarking)
- **http** — Generic HTTP sink (json, text, ndjson); shared base layer for protocol-specific HTTP sinks
- **file** — Write events to files with strftime-based path partitioning
- **aws_s3** — AWS S3 object upload via PutObject API (SigV4-signed, batched)
- **websocket** — WebSocket client sink (RFC 6455 text frames, auto-reconnect)
- **socket** — Send events over TCP/UDP sockets (shared connection management with vector sink)
- **vector** — Send events to other Vector instances (JSON-over-TCP, batched)
- **loki** — Grafana Loki push API (JSON, label-based batching)
- **opentelemetry** — OTLP HTTP logs export
- **aws_cloudwatch_logs** — AWS CloudWatch Logs via PutLogEvents API (SigV4-signed)
- **aws_cloudwatch_metrics** — AWS CloudWatch Metrics via Embedded Metric Format (EMF over CloudWatch Logs)
- **statsd** — StatsD line protocol sender (UDP/TCP, DogStatsD tags)
- **prometheus** — Prometheus Pushgateway text format push (counter, gauge, histogram, summary)
- **prometheus_remote_write** — Prometheus remote write HTTP endpoint (exposition text, multi-tenant via X-Scope-OrgID)
- **aws_kinesis_streams** — Kinesis Data Streams via PutRecords API (SigV4-signed, base64-encoded)
- **aws_kinesis_firehose** — Kinesis Data Firehose via PutRecordBatch API (SigV4-signed, base64-encoded)
- **aws_sqs** — SQS message sending via SendMessageBatch API (SigV4-signed, FIFO support)
- **splunk_hec** — Splunk HEC logs sender (token auth, /services/collector/event)
- **datadog** — Datadog logs API sender (DD-API-KEY auth, /api/v2/logs)
- **datadog_metrics** — Datadog metrics API sender (DD-API-KEY auth, /api/v2/series)
- **datadog_traces** — Datadog traces API sender (DD-API-KEY auth, /api/v0.2/traces)
- **influxdb** — InfluxDB v2 write API (line protocol, Token auth, org/bucket targeting)
- **redis** — Redis list push and pub/sub publish (RESP protocol)
- **kafka** — Apache Kafka producer (batched, compression, SASL/TLS auth)
- **nats** — NATS subject publisher (JetStream support)
- **amqp** — AMQP 0-9-1 exchange publisher (RabbitMQ, routing keys, persistent delivery)
- **pulsar** — Apache Pulsar topic producer (compression, partition keys)
- **gcp_pubsub** — Google Cloud Pub/Sub topic publisher (REST API, ordering keys)
- **mqtt** — MQTT topic publisher (QoS 0-2, retain support)
- **azure_blob** — Azure Blob Storage upload via REST API (Shared Key auth, batched, strftime partitioning)
- **azure_monitor_logs** — Azure Monitor Logs via Data Collector API (Shared Key auth, Log Analytics workspace)
- **gcp_cloud_storage** — Google Cloud Storage object upload via JSON API (batched, strftime partitioning)
- **gcp_stackdriver** — Google Cloud Logging (Stackdriver) via entries.write REST API (batched, resource labels)
- **aws_sns** — AWS SNS message publishing via Publish API (SigV4-signed)
- **azure_logs_ingestion** — Azure Logs Ingestion API (DCR/DCE, Bearer token auth)
- **gcp_chronicle** — GCP Chronicle unstructured log ingestion (regional endpoints, batch API)
- **gcp_cloud_monitoring** — GCP Cloud Monitoring timeSeries.create API (gauge, counter, distribution)

### API
- `GET /health` — Liveness check
- `GET /ready` — Readiness check

See [src/vrl/UNIMPLEMENTED.md](src/vrl/UNIMPLEMENTED.md) for VRL function coverage and unimplemented component tracking.

## Topology & Routing

The pipeline routes events based on the `inputs` field in transform/sink config. Each component only receives events from its declared inputs, supporting fan-in and fan-out.

## Key Design Decisions

### ObjectMap: Unsorted adaptive map (diverges from upstream)

Upstream Rust VRL uses `BTreeMap<KeyString, Value>` for `ObjectMap`, which iterates keys in sorted (lexicographic) order. Our V implementation (`src/vrl/objectmap.v`) uses an adaptive flat-array/hashmap that does **not** maintain sorted order:

- **Small maps (≤32 keys):** Flat parallel arrays, approximate insertion order. Swap-remove on delete can reorder entries.
- **Large maps (>32 keys):** V built-in `map[string]VrlValue`, arbitrary iteration order.

This is acceptable because JSON serialization (`vrl_to_json`) sorts keys explicitly at the output boundary. No VRL program can observe internal iteration order in a way that affects correctness of event processing. If sorted iteration is needed at a call site, sort there rather than adding overhead to every map operation.

### VRL Interpretation Strategy

VRL programs are interpreted rather than compiled to native code. The runtime walks an AST representation of VRL expressions. This trades some execution speed for implementation simplicity compared to the upstream Rust approach of compiling VRL to native Rust.

### C Interop Dependencies

- **xxhash** — System `libxxhash-dev` with thin wrapper in `src/vrl/xxhash_wrapper.{c,h}` to isolate from V's bundled zstd `XXH_NAMESPACE` pollution
- **pcre2** — System `libpcre2-dev` via `src/pcre2/` C interop for regex support
- **snappy/lz4** — System `libsnappy-dev`/`liblz4-dev` for codec functions
- **iconv** — System libc `iconv` for `encode_charset`/`decode_charset`

### Fluent Source: Simplified msgpack decoder

We implement a minimal msgpack decoder directly in V rather than depending on an external library. Only the subset of msgpack needed for the Fluent Forward Protocol is supported (fixstr, str8-32, fixint, uint8-64, fixmap, fixarray, bin, ext type 0 for EventTime).

### AWS Shared Module: Credentials and SigV4 signing

`src/aws/` provides shared AWS infrastructure used by CloudWatch sinks and future AWS sinks (S3, Kinesis, etc.):

- **Credential resolution** (`credentials.v`): Standard AWS credential chain — explicit config > environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) > shared credentials file (`~/.aws/credentials`) > ECS container credentials (`AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` / `AWS_CONTAINER_CREDENTIALS_FULL_URI`) > EC2 IMDS. Region resolution follows: config > `AWS_REGION` > `AWS_DEFAULT_REGION` > IMDS.
- **SigV4 signing** (`sigv4.v`): AWS Signature Version 4 implementation using V's `crypto.hmac` and `crypto.sha256`. No external SDK dependency.

### CloudWatch Metrics: EMF via CloudWatch Logs

Rather than calling the CloudWatch PutMetricData API directly, metrics are sent as Embedded Metric Format (EMF) JSON through the CloudWatch Logs PutLogEvents API. CloudWatch automatically extracts metric data from EMF-formatted log entries. This unifies the transport layer (both logs and metrics use the same CloudWatch Logs API) and avoids implementing a second API surface.

### EC2 Metadata: Synchronous refresh (diverges from upstream)

Upstream uses `ArcSwap` for lock-free atomic metadata updates via a background task. Our implementation refreshes metadata lazily during `transform()` when the cache expires, avoiding the complexity of V's shared memory primitives. This is simpler but means the first event after a refresh interval may see slightly higher latency.

All IMDS HTTP requests use a 1-second timeout (the metadata service is on the local link). On fetch failure, the transform keeps its cached values (possibly empty) and defers the next retry until the refresh interval expires again, avoiding frequent retries while still allowing recovery from transient failures.

### Shared Socket Buffering Layer

Like upstream Vector, socket-based sources share a common framing/buffering layer (`src/sources/socket_buf.v`). `SocketBuffer` provides line-delimited framing over TCP with configurable max line length, `\r\n` handling, and force-flush for oversized data. This is reused by SocketSource, VectorSource, and any future TCP-based sources.

Similarly, socket-based sinks (SocketSink and VectorSink) share the same TCP connection management and reconnect-on-failure pattern, paralleling how upstream Vector's socket components share transport infrastructure.

### Shared HTTP Sink Transport Layer

Like upstream Vector, HTTP-based sinks share a common transport layer (`src/sinks/http_client.v`). `HttpBatch` provides batched HTTP sending with configurable auth (Basic/Bearer), headers, and timeouts. Protocol-specific sinks (Loki, OTLP, generic HTTP) compose `HttpBatch` and add their own encoding/payload logic.

For AWS sinks, `aws_send_payload()` in `http_client.v` provides SigV4-signed HTTP transport shared by CloudWatch Logs, CloudWatch Metrics, and S3 sinks, eliminating duplicated HTTP + signing code. The generic `HttpSink` (`src/sinks/http.v`) wraps `HttpBatch` with multi-codec encoding (json/ndjson/text) and serves as the direct equivalent of upstream's generic HTTP sink.

### Mock Server Testing Framework

`src/mockserver/` provides a declarative mock HTTP server for testing network-dependent components (sinks, sources, transforms, VRL functions). The server runs on `127.0.0.1` in a background thread with a kernel-assigned port (bind to port 0).

```v
import mockserver

mut mock := mockserver.start(
    mockserver.get('/health', mockserver.respond(200, '{"status":"ok"}')),
    mockserver.put('/token',  mockserver.respond(200, 'my-token')),
    mockserver.post('/push',  mockserver.respond(204, '')),
)!
defer { mock.stop() }

// Make requests to mock.url() ...

reqs := mock.wait_for_requests(2, 5000)  // count, timeout_ms
assert reqs[0].method == 'PUT'
assert reqs[0].headers['x-custom'] == 'value'
assert reqs[0].body == '{"data":"payload"}'
```

Features: route matching by method+path, response cycling via `sequence()` for retry/refresh testing, full request capture (method, path, headers, body), `respond_with_headers()` for custom response headers, multiple concurrent servers on different ports.

#### TCP/UDP Socket Mock Servers

For testing socket-based components (SocketSink, VectorSink, SocketSource, VectorSource, WebSocketSink), the mockserver also provides `MockTcpServer` and `MockUdpServer`:

```v
import mockserver

// TCP mock server
mut tcp := mockserver.start_tcp()!  // or start_tcp_with_config(...)
defer { tcp.stop() }
// Connect sinks to tcp.address(), then:
msgs := tcp.wait_for_messages(2, 5000)
assert msgs[0].data.contains('expected')

// UDP mock server
mut udp := mockserver.start_udp()!
defer { udp.stop() }
// Send datagrams to udp.address(), then:
pkts := udp.wait_for_datagrams(1, 3000)
assert pkts[0].data == 'hello'

// TCP with WebSocket upgrade support
mut ws := mockserver.start_tcp_with_config(mockserver.TcpServerConfig{
    ws_upgrade: true  // responds with 101 upgrade, decodes WS frames
})!
```

`TcpServerConfig` options: `response` (echo back data), `close_after_read` (close after first read), `reject` (close immediately, simulates connection refused), `ws_upgrade` (WebSocket upgrade handshake + frame decoding), `accept_count` (limit accepted connections).

Used by: EC2 metadata integration tests (`src/transforms/ec2_mock_test.v`), VRL `http_request` tests (`src/vrl/vrllib_http_mock_test.v`), Loki/OTLP/HTTP sink integration tests, HttpClient source integration tests, Socket/Vector/WebSocket sink mock tests, HTTP error simulation tests.
