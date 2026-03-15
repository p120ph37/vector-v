# Vector-V Development Guide

Vector-V is a V-language reimplementation of [Vector](https://vector.dev), a high-performance observability data pipeline originally written in Rust. The upstream Rust source is kept in `upstream/` for reference.

## Project Structure

- `src/` — V source code
  - `vrl/` — VRL (Vector Remap Language) interpreter and runtime
  - `sources/` — Data ingestion components (stdin, demo_logs, fluent)
  - `transforms/` — Data processing (remap, filter, reduce, aws_ec2_metadata, dedupe, sample, throttle, exclusive_route, passthrough)
  - `sinks/` — Data output destinations (console, blackhole, loki, opentelemetry, aws_cloudwatch_logs, aws_cloudwatch_metrics)
  - `aws/` — Shared AWS utilities (credentials resolution, SigV4 signing)
  - `event/` — Event types (log, metric, trace)
  - `topology/` — Component graph management with input-based routing
  - `conf/` — TOML configuration parsing
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

### Sources (9 / 27 upstream)
- **stdin** — Reads lines from stdin
- **demo_logs** — Generates sample log events
- **fluent** — Fluent Forward Protocol v1 over TCP (msgpack)
- **exec** — Run external commands and capture output (scheduled or streaming)
- **file_descriptors** — Read from file descriptors (generalized stdin)
- **http_client** — Poll HTTP endpoints at configurable intervals
- **socket** — Listen on TCP/UDP sockets with shared line-buffered framing
- **websocket** — Connect to WebSocket servers and receive messages
- **vector** — Receive events from other Vector instances (JSON-over-TCP)

### Transforms (9 / 15 upstream)
- **remap** — VRL program execution
- **filter** — Condition-based event filtering
- **reduce** — Event accumulation with merge strategies
- **aws_ec2_metadata** — EC2 instance metadata enrichment via IMDSv2
- **dedupe** — Event deduplication with LRU cache
- **sample** — Statistical event sampling (random or key-based)
- **throttle** — Rate limiting with token bucket algorithm
- **exclusive_route** — Route events to first matching output
- **passthrough** — Identity transform (pass events unchanged)

### Sinks (12 / 43 upstream)
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

- **Credential resolution** (`credentials.v`): Standard AWS credential chain — explicit config > environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) > shared credentials file (`~/.aws/credentials`) > EC2 IMDS. Region resolution follows: config > `AWS_REGION` > `AWS_DEFAULT_REGION` > IMDS.
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

Used by: EC2 metadata integration tests (`src/transforms/ec2_mock_test.v`), VRL `http_request` tests (`src/vrl/vrllib_http_mock_test.v`).
