# Vector-V Development Guide

Vector-V is a V-language reimplementation of [Vector](https://vector.dev), a high-performance observability data pipeline originally written in Rust. The upstream Rust source is kept in `upstream/` for reference.

## Project Structure

- `src/` — V source code
  - `vrl/` — VRL (Vector Remap Language) interpreter and runtime
  - `sources/` — Data ingestion components
  - `transforms/` — Data processing (e.g., remap)
  - `sinks/` — Data output destinations
  - `event/` — Event types (log, metric, trace)
  - `topology/` — Component graph management
  - `conf/` — Configuration parsing
  - `api/` — Management API
  - `cli/` — Command-line interface
  - `main.v` — Entry point
- `upstream/` — Upstream Rust source for Vector and VRL (read-only reference)

## Build & Test

```bash
v .                    # Build
v test src/            # Run all tests
v test src/vrl/        # Run VRL tests only
```

## Key Design Decisions

### ObjectMap: Unsorted adaptive map (diverges from upstream)

Upstream Rust VRL uses `BTreeMap<KeyString, Value>` for `ObjectMap`, which iterates keys in sorted (lexicographic) order. Our V implementation (`src/vrl/objectmap.v`) uses an adaptive flat-array/hashmap that does **not** maintain sorted order:

- **Small maps (≤32 keys):** Flat parallel arrays, approximate insertion order. Swap-remove on delete can reorder entries.
- **Large maps (>32 keys):** V built-in `map[string]VrlValue`, arbitrary iteration order.

This is acceptable because JSON serialization (`vrl_to_json`) sorts keys explicitly at the output boundary. No VRL program can observe internal iteration order in a way that affects correctness of event processing. If sorted iteration is needed at a call site, sort there rather than adding overhead to every map operation.

### VRL Interpretation Strategy

VRL programs are interpreted rather than compiled to native code. The runtime walks an AST representation of VRL expressions. This trades some execution speed for implementation simplicity compared to the upstream Rust approach of compiling VRL to native Rust.
