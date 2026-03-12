module vrl

// Build-time compatibility flags for matching Rust VRL behavior.
//
// rust_vrl_compat: When true, emulate Rust VRL's quirks:
//   - uuid_v7: Reproduce the chrono timestamp_nanos_opt() -> u32 truncation
//     that shifts the 48-bit millisecond timestamp in the UUID.
//   - Timestamp formatting: Use nanosecond-precision RFC3339 (AutoSi style)
//     matching chrono's to_rfc3339_opts(SecondsFormat::AutoSi, true).
//
// Set to true for maximum conformance with upstream Rust VRL test vectors.
const rust_vrl_compat = true
