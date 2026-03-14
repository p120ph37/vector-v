# Vector-V Development Guide

Vector-V is a V-language reimplementation of [Vector](https://vector.dev), a high-performance observability data pipeline originally written in Rust. The upstream Rust source is kept in `upstream/` for reference.

## Project Structure

- `src/` — V source code
  - `vrl/` — VRL (Vector Remap Language) interpreter and runtime
  - `sources/` — Data ingestion components (stdin, demo_logs, fluent)
  - `transforms/` — Data processing (remap, filter, reduce, aws_ec2_metadata, dedupe, sample, throttle, exclusive_route, passthrough)
  - `sinks/` — Data output destinations (console, blackhole, loki, opentelemetry)
  - `event/` — Event types (log, metric, trace)
  - `topology/` — Component graph management with input-based routing
  - `conf/` — TOML configuration parsing
  - `api/` — REST API server (health/ready endpoints)
  - `cliargs/` — Command-line argument parsing
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

### Sources (3 / 27 upstream)
- **stdin** — Reads lines from stdin
- **demo_logs** — Generates sample log events
- **fluent** — Fluent Forward Protocol v1 over TCP (msgpack)

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

### Sinks (4 / 43 upstream)
- **console** — Write to stdout/stderr (json, text, logfmt)
- **blackhole** — Discard events (benchmarking)
- **loki** — Grafana Loki push API (JSON, label-based batching)
- **opentelemetry** — OTLP HTTP logs export

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

### EC2 Metadata: Synchronous refresh (diverges from upstream)

Upstream uses `ArcSwap` for lock-free atomic metadata updates via a background task. Our implementation refreshes metadata lazily during `transform()` when the cache expires, avoiding the complexity of V's shared memory primitives. This is simpler but means the first event after a refresh interval may see slightly higher latency.

All IMDS HTTP requests use a 1-second timeout (the metadata service is on the local link). On fetch failure, the transform keeps its cached values (possibly empty) and defers the next retry until the refresh interval expires again, avoiding frequent retries while still allowing recovery from transient failures.
