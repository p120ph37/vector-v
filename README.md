# vector-v

A V-lang re-implementation of [Vector](https://github.com/vectordotdev/vector) — the high-performance observability data pipeline by Datadog.

## Status

**Early development / MVP** — this project incrementally re-implements Vector's functionality in V-lang, starting with the core pipeline and simple components.

### What works today

- **Core event model**: `LogEvent`, `Metric`, `TraceEvent` (mirroring Vector's event types)
- **Config system**: TOML configuration parsing with topology validation
- **Pipeline runtime**: Multi-threaded source → transform → sink pipeline with channel-based communication
- **Sources**: `stdin`, `demo_logs`
- **Transforms**: `remap` (basic VRL-like field manipulation), `filter`, `reduce`
- **Sinks**: `console` (stdout/stderr, json/text/logfmt encoding), `blackhole`
- **CLI**: `--config`, `--validate`, `--verbose`, `--version`, `--help`

### Planned (MVP targets)

- [ ] Full VRL (Vector Remap Language) support
- [ ] `fluent` source (Fluentd forward protocol)
- [ ] `remap` transform with complete VRL parser
- [ ] `reduce` transform with full merge strategies
- [ ] `otlp` sink (OpenTelemetry Protocol)
- [ ] `api` module (GraphQL management API)

## Quick start

### Prerequisites

- [V compiler](https://vlang.io) (v0.4+ recommended)

### Build

```bash
v -o vector-v src/
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
v test src/event/
v test src/conf/
v test src/transforms/
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
├── cli/args.v              # Command-line argument parsing
├── conf/config.v           # TOML config parser and topology validation
├── event/                  # Core event model
│   ├── event.v             # Event sum type (Log | Metric | Trace)
│   ├── log.v               # LogEvent, Value type, metadata
│   ├── metric.v            # Metric types (counter, gauge, histogram, etc.)
│   └── trace.v             # TraceEvent
├── sources/                # Data ingestion
│   ├── stdin.v             # stdin source
│   ├── demo_logs.v         # Demo log generator
│   └── registry.v          # Source type registry
├── transforms/             # Data processing
│   ├── remap.v             # VRL-like field manipulation
│   ├── filter.v            # Event filtering
│   ├── reduce.v            # Event aggregation/merging
│   ├── passthrough.v       # Identity transform
│   └── registry.v          # Transform type registry
├── sinks/                  # Data output
│   ├── console.v           # stdout/stderr sink
│   ├── blackhole.v         # /dev/null sink (benchmarking)
│   └── registry.v          # Sink type registry
├── topology/pipeline.v     # Pipeline runtime (wiring + event loop)
└── api/                    # (planned) GraphQL management API
```

## Upstream references

The `upstream/` directory contains git submodules of the original projects for reference and test vectors:

- `upstream/vector` — [vectordotdev/vector](https://github.com/vectordotdev/vector)
- `upstream/vrl` — [vectordotdev/vrl](https://github.com/vectordotdev/vrl)

These are included for reference and to borrow test suites. To initialize them:

```bash
git submodule update --init --recursive
```

## License

MPL-2.0 (same as upstream Vector)
