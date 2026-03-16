# vector-v

A V-lang re-implementation of [Vector](https://github.com/vectordotdev/vector) — the high-performance observability data pipeline by Datadog.

## Status

**Active development** — the core pipeline, VRL interpreter, and many components are fully functional.

### What works today

- **Core event model**: `LogEvent`, `Metric`, `TraceEvent` (mirroring Vector's event types)
- **Config system**: TOML configuration parsing with topology validation
- **Pipeline runtime**: Multi-threaded source → transform → sink pipeline with channel-based communication and input-based routing (fan-in/fan-out)
- **VRL**: Full Vector Remap Language interpreter with ~201 stdlib functions implemented
- **Sources** (34): stdin, demo_logs, fluent, exec, file_descriptors, http_client, socket, websocket, vector, statsd, prometheus, aws_s3, aws_sqs, aws_kinesis_firehose, aws_ecs_metrics, opentelemetry, splunk_hec, redis, datadog_agent, host_metrics, docker_logs, kubernetes_logs, kafka, nats, amqp, pulsar, gcp_pubsub, mqtt, apache_metrics, nginx_metrics, mongodb_metrics, eventstoredb_metrics, dnstap, okta
- **Transforms** (14): remap, filter, reduce, aws_ec2_metadata, dedupe, sample, throttle, exclusive_route, passthrough, log_to_metric, metric_to_log, aggregate, tag_cardinality_limit, window
- **Sinks** (30): console, blackhole, http, file, aws_s3, websocket, socket, vector, loki, opentelemetry, aws_cloudwatch_logs, aws_cloudwatch_metrics, statsd, prometheus, aws_kinesis_streams, aws_kinesis_firehose, aws_sqs, splunk_hec, datadog, redis, kafka, nats, amqp, pulsar, gcp_pubsub, mqtt, azure_blob, azure_monitor_logs, gcp_cloud_storage, gcp_stackdriver
- **API**: REST health/readiness endpoints (`GET /health`, `GET /ready`)
- **CLI**: `--config`, `--validate`, `--verbose`, `--version`, `--help`

## Quick start

### Prerequisites

- [V compiler](https://vlang.io) (v0.4.7+ recommended)
- System libraries: `clang`, `libxxhash-dev`, `libpcre2-dev`, `libsnappy-dev`, `liblz4-dev`

### Build

```bash
v -enable-globals .
# or
make build
```

### Run

```bash
# Simple stdin → stdout pipeline
echo "hello world" | ./vector-v -c examples/stdin_to_stdout.toml

# With a remap transform
echo "hello world" | ./vector-v -c examples/stdin_remap_stdout.toml

# Demo log generator
./vector-v -c examples/demo_logs.toml

# Validate config without running
./vector-v --validate -c examples/stdin_to_stdout.toml
```

### Test

```bash
v -enable-globals test src/      # Run all tests
v -enable-globals test src/vrl/  # VRL tests only
make test-all                    # All test modules via Makefile
make test-vrl                    # VRL tests via Makefile
```

## Configuration

Vector-V uses the same TOML configuration format as Vector:

```toml
[sources.in]
type = "stdin"

[transforms.enrich]
type = "remap"
inputs = ["in"]
source = ".environment = \"production\""

[sinks.out]
type = "console"
inputs = ["enrich"]
encoding.codec = "json"
```

## Architecture

```
src/
├── main.v                  # Entry point and CLI
├── cliargs/args.v          # Command-line argument parsing
├── conf/config.v           # TOML config parser and topology validation
├── event/                  # Core event model
│   ├── event.v             # Event sum type (Log | Metric | Trace)
│   ├── log.v               # LogEvent, Value type, metadata
│   ├── metric.v            # Metric types (counter, gauge, histogram, etc.)
│   └── trace.v             # TraceEvent
├── vrl/                    # VRL interpreter and runtime
│   ├── lexer.v             # Tokenizer
│   ├── parser.v            # Recursive descent parser
│   ├── runtime.v           # AST interpreter
│   ├── objectmap.v         # Adaptive flat-array/hashmap
│   └── stdlib*.v           # ~201 standard library functions
├── sources/                # Data ingestion (34 components)
│   └── registry.v          # Source type registry
├── transforms/             # Data processing (14 components)
│   └── registry.v          # Transform type registry
├── sinks/                  # Data output (30 components)
│   ├── http_client.v       # Shared HTTP batching infrastructure
│   └── registry.v          # Sink type registry
├── aws/                    # Shared AWS utilities (credentials, SigV4)
├── topology/pipeline.v     # Pipeline runtime (wiring + event loop)
├── api/api.v               # REST API server (health/ready endpoints)
├── mockserver/             # Mock HTTP/TCP/UDP servers for testing
└── pcre2/                  # PCRE2 C interop for regex support
```

## Upstream references

The `upstream/` directory contains git submodules of the original projects for reference and test vectors:

- `upstream/vector` — [vectordotdev/vector](https://github.com/vectordotdev/vector)
- `upstream/vrl` — [vectordotdev/vrl](https://github.com/vectordotdev/vrl)

To initialize them:

```bash
git submodule update --init --recursive
```

## License

MPL-2.0 (same as upstream Vector)
