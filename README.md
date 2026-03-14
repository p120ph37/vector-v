# vector-v

A V-lang re-implementation of [Vector](https://github.com/vectordotdev/vector) — the high-performance observability data pipeline by Datadog.

## Status

**Active development** — the core pipeline, VRL interpreter, and many components are fully functional.

### What works today

- **Core event model**: `LogEvent`, `Metric`, `TraceEvent` (mirroring Vector's event types)
- **Config system**: TOML configuration parsing with topology validation
- **Pipeline runtime**: Multi-threaded source → transform → sink pipeline with channel-based communication and input-based routing (fan-in/fan-out)
- **VRL**: Full Vector Remap Language interpreter with ~201 stdlib functions implemented
- **Sources** (3): `stdin`, `demo_logs`, `fluent` (Fluentd Forward Protocol v1 over TCP)
- **Transforms** (9): `remap`, `filter`, `reduce`, `aws_ec2_metadata`, `dedupe`, `sample`, `throttle`, `exclusive_route`, `passthrough`
- **Sinks** (4): `console` (stdout/stderr, json/text/logfmt), `blackhole`, `loki` (Grafana Loki push API), `opentelemetry` (OTLP HTTP logs)
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
├── sources/                # Data ingestion (3 components)
│   ├── stdin.v             # stdin source
│   ├── demo_logs.v         # Demo log generator
│   ├── fluent.v            # Fluent Forward Protocol v1 (TCP/msgpack)
│   └── registry.v          # Source type registry
├── transforms/             # Data processing (9 components)
│   ├── remap.v             # VRL program execution
│   ├── filter.v            # Condition-based event filtering
│   ├── reduce.v            # Event accumulation with merge strategies
│   ├── aws_ec2_metadata.v  # EC2 metadata enrichment (IMDSv2)
│   ├── dedupe.v            # Event deduplication (LRU cache)
│   ├── sample.v            # Statistical sampling
│   ├── throttle.v          # Rate limiting (token bucket)
│   ├── exclusive_route.v   # Route to first matching output
│   ├── passthrough.v       # Identity transform
│   └── registry.v          # Transform type registry
├── sinks/                  # Data output (4 components)
│   ├── console.v           # stdout/stderr sink (json/text/logfmt)
│   ├── blackhole.v         # /dev/null sink (benchmarking)
│   ├── loki.v              # Grafana Loki push API
│   ├── opentelemetry.v     # OTLP HTTP logs export
│   ├── http_client.v       # Shared HTTP batching infrastructure
│   └── registry.v          # Sink type registry
├── topology/pipeline.v     # Pipeline runtime (wiring + event loop)
├── api/api.v               # REST API server (health/ready endpoints)
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
