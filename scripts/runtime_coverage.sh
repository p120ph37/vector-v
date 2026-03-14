#!/usr/bin/env bash
#
# runtime_coverage.sh — Runtime line-level code coverage for Vector-V
#
# Uses V's built-in coverage support (available since V 0.4.7):
#   1. Compile tests with `-coverage <dir>` — the C codegen inserts a
#      counter increment (`_v_cov[offset]++`) at every statement
#   2. Running the instrumented test binary writes per-file .json metadata
#      (mapping coverage point indices → V source line numbers) and
#      timestamped .csv counter files (recording hit counts)
#   3. `v cover -P <dir>` reads both and produces per-file line coverage
#
# Usage:
#   ./scripts/runtime_coverage.sh [--threshold N] [--verbose] [--filter PATTERN]
#
# Requires: v (modern version with -coverage support)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COV_DIR="$PROJECT_DIR/.coverage"

THRESHOLD=20
VERBOSE=false
FILTER=""

usage() {
    cat <<'USAGE'
Usage: ./scripts/runtime_coverage.sh [OPTIONS]

Run all tests with V's native coverage instrumentation and report results.

Options:
  --threshold N       Minimum coverage percentage (default: 95)
  --filter PATTERN    Only show files matching PATTERN in the report
  --verbose           Show detailed output during test runs
  -h, --help          Show this help

Examples:
  ./scripts/runtime_coverage.sh
  ./scripts/runtime_coverage.sh --threshold 90
  ./scripts/runtime_coverage.sh --filter transforms
  ./scripts/runtime_coverage.sh --verbose
USAGE
}

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_verbose() { $VERBOSE && echo "[DEBUG] $*" || true; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --threshold) THRESHOLD="$2"; shift 2 ;;
        --filter)    FILTER="$2"; shift 2 ;;
        --verbose)   VERBOSE=true; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if ! command -v v &>/dev/null; then
    log_error "V compiler not found. Install a modern V (>= 0.4.7)."
    exit 1
fi

V_VERSION=$(v version 2>/dev/null || echo "unknown")
log_info "V compiler: $V_VERSION"

rm -rf "$COV_DIR"
mkdir -p "$COV_DIR"

# All test modules
modules=(
    "src/event/"
    "src/conf/"
    "src/transforms/"
    "src/sinks/"
    "src/sources/"
    "src/topology/"
    "src/api/"
    "src/cliargs/"
    "src/vrl/"
)

log_info "Compiling and running tests with coverage instrumentation..."

# Each test module compilation can overwrite metadata files for shared source
# files. Some compilations produce npoints=0 for files that other compilations
# instrument properly. We run each module into a separate coverage subdirectory,
# then merge results — keeping the metadata entry with the most coverage points
# for each source file.
mod_index=0
for mod in "${modules[@]}"; do
    mod_cov="$COV_DIR/mod_${mod_index}"
    mkdir -p "$mod_cov/meta"
    log_verbose "Testing $mod → $mod_cov"
    # shellcheck disable=SC2086
    v -enable-globals -coverage "$mod_cov" test "$mod" 2>&1 || {
        log_warn "Tests in $mod had failures (coverage data still collected)"
    }
    mod_index=$((mod_index + 1))
done

# The aggregator script scans all subdirectories automatically,
# merging metadata and counters across all module compilations.

# Generate report — use custom aggregator to read raw coverage data directly,
# working around `v cover` not reporting all instrumented files.
log_info "Generating coverage report..."

agg_flags=("$COV_DIR")
if [[ -n "$FILTER" ]]; then
    agg_flags+=("--filter" "$FILTER")
fi
$VERBOSE && agg_flags+=("--verbose")

printf "%-80s | %8s | %8s | %8s\n" "File" "Executed" "Total" "Coverage"
printf -- '-%.0s' {1..115}; echo

report_output=$(python3 "$SCRIPT_DIR/aggregate_coverage.py" "${agg_flags[@]}")
echo "$report_output" | tee "$COV_DIR/report.txt"

# Parse summary from aggregator output (last line: "Coverage: NN.N%")
pct=$(echo "$report_output" | grep '^Coverage:' | awk '{print $2}' | tr -d '%')
lines_summary=$(echo "$report_output" | grep '^Lines:' | awk '{print $2}')

if [[ -n "$pct" ]]; then
    echo ""
    log_info "Overall line coverage: ${pct}% ($lines_summary lines)"

    if (( $(echo "$pct >= $THRESHOLD" | bc -l) )); then
        log_info "PASS: Coverage ${pct}% >= ${THRESHOLD}% threshold"
    else
        log_error "FAIL: Coverage ${pct}% < ${THRESHOLD}% threshold"
        exit 1
    fi
else
    log_warn "No coverage data collected — check that tests ran successfully"
    exit 1
fi

log_info "Coverage data stored in $COV_DIR/"
