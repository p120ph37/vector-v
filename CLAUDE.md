# Vector-V Development Guide

Vector-V is a V-language reimplementation of [Vector](https://vector.dev), a high-performance observability data pipeline originally written in Rust. The upstream Rust source is kept in `upstream/` for reference.

## Project Structure

- `src/` — V source code
  - `vrl/` — VRL (Vector Remap Language) interpreter and runtime
  - `sources/` — Data ingestion components (stdin, demo_logs, fluent)
  - `transforms/` — Data processing (remap, filter, reduce, aws_ec2_metadata)
  - `sinks/` — Data output destinations (console, blackhole, loki, opentelemetry)
  - `event/` — Event types (log, metric, trace)
  - `topology/` — Component graph management with input-based routing
  - `conf/` — TOML configuration parsing
  - `api/` — REST API server (health/ready endpoints)
  - `cliargs/` — Command-line argument parsing
  - `main.v` — Entry point
- `upstream/` — Upstream Rust source for Vector and VRL (read-only reference)

## Build & Test

```bash
v .                    # Build
v test src/            # Run all tests
v test src/vrl/        # Run VRL tests only
v test src/sinks/      # Run sink tests only
```

## Implemented Components

### Sources
- **stdin** — Reads lines from stdin
- **demo_logs** — Generates sample log events
- **fluent** — Fluent Forward Protocol v1 over TCP (msgpack)

### Transforms
- **remap** — VRL program execution
- **filter** — Condition-based event filtering
- **reduce** — Event accumulation with merge strategies (discard, retain, sum, min, max, array, concat, concat_newline, concat_raw, flat_unique, shortest_array, longest_array)
- **aws_ec2_metadata** — EC2 instance metadata enrichment via IMDSv2

### Sinks
- **console** — Write to stdout/stderr (json, text, logfmt)
- **blackhole** — Discard events (benchmarking)
- **loki** — Grafana Loki push API (JSON, label-based batching)
- **opentelemetry** — OTLP HTTP logs export

### API
- `GET /health` — Liveness check
- `GET /ready` — Readiness check

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

### Fluent Source: Simplified msgpack decoder

We implement a minimal msgpack decoder directly in V rather than depending on an external library. Only the subset of msgpack needed for the Fluent Forward Protocol is supported (fixstr, str8-32, fixint, uint8-64, fixmap, fixarray, bin, ext type 0 for EventTime).

### EC2 Metadata: Synchronous refresh (diverges from upstream)

Upstream uses `ArcSwap` for lock-free atomic metadata updates via a background task. Our implementation refreshes metadata lazily during `transform()` when the cache expires, avoiding the complexity of V's shared memory primitives. This is simpler but means the first event after a refresh interval may see slightly higher latency.
