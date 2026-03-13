#!/usr/bin/env bash
#
# runtime_coverage.sh — Runtime code coverage for Vector-V using V's native
# -coverage flag and vcover tool, with gcov/lcov fallback.
#
# V (>= 0.4.7) has built-in coverage support:
#   1. Compile tests with `-coverage <dir>` to instrument every statement
#   2. Running the test binary writes .json metadata + .csv counter files
#   3. `v cover <dir>` produces per-file line coverage reports
#
# When V's native coverage is unavailable or for C-level line coverage,
# this script falls back to compiling with gcc --coverage and using
# gcov + lcov to produce HTML reports.
#
# Usage:
#   ./scripts/runtime_coverage.sh [--method native|gcov] [--html] [--threshold N]
#
# Requires:
#   Native: v (>= 0.4.7)
#   Gcov:   v, gcc, gcov, lcov (optional for HTML), genhtml (optional)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COV_DIR="$PROJECT_DIR/.coverage"
HTML_DIR="$PROJECT_DIR/.coverage/html"

METHOD=""
THRESHOLD=95
GENERATE_HTML=false
VERBOSE=false

usage() {
    cat <<'USAGE'
Usage: ./scripts/runtime_coverage.sh [OPTIONS]

Options:
  --method native|gcov  Coverage method (default: auto-detect)
  --html                Generate HTML report (lcov/genhtml for gcov)
  --threshold N         Minimum coverage percentage (default: 95)
  --verbose             Show detailed output
  -h, --help            Show this help

Methods:
  native   Use V's built-in -coverage flag and vcover tool (V >= 0.4.7)
  gcov     Compile V-generated C with gcc --coverage, then gcov/lcov

Examples:
  ./scripts/runtime_coverage.sh                    # Auto-detect best method
  ./scripts/runtime_coverage.sh --method native    # Force V native coverage
  ./scripts/runtime_coverage.sh --method gcov --html  # gcov + HTML report
USAGE
}

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_verbose() { $VERBOSE && echo "[DEBUG] $*" || true; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --method)   METHOD="$2"; shift 2 ;;
        --html)     GENERATE_HTML=true; shift ;;
        --threshold) THRESHOLD="$2"; shift 2 ;;
        --verbose)  VERBOSE=true; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# Check V compiler availability
check_v() {
    if command -v v &>/dev/null; then
        V_VERSION=$(v version 2>/dev/null || echo "unknown")
        log_verbose "V compiler found: $V_VERSION"
        return 0
    fi
    return 1
}

# Check if V supports -coverage (>= 0.4.7)
check_v_coverage() {
    if ! check_v; then return 1; fi
    # Try to get help on coverage; if the flag exists, V supports it
    if v help 2>&1 | grep -q "coverage"; then
        log_verbose "V native coverage support detected"
        return 0
    fi
    # Also check by version number
    local ver
    ver=$(v version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    local major minor patch
    IFS='.' read -r major minor patch <<< "$ver"
    if [[ "$major" -gt 0 ]] || [[ "$major" -eq 0 && "$minor" -ge 5 ]] || \
       [[ "$major" -eq 0 && "$minor" -eq 4 && "$patch" -ge 7 ]]; then
        log_verbose "V version $ver supports coverage"
        return 0
    fi
    log_verbose "V version $ver may not support -coverage"
    return 1
}

# Check gcov toolchain
check_gcov() {
    local missing=()
    command -v gcc &>/dev/null || missing+=(gcc)
    command -v gcov &>/dev/null || missing+=(gcov)
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_verbose "Missing for gcov method: ${missing[*]}"
        return 1
    fi
    log_verbose "gcov toolchain available"
    return 0
}

# Auto-detect method
if [[ -z "$METHOD" ]]; then
    if check_v_coverage; then
        METHOD="native"
    elif check_gcov && check_v; then
        METHOD="gcov"
    else
        log_error "No coverage method available."
        log_error "Install V (>= 0.4.7) for native coverage, or gcc+gcov for C-level coverage."
        exit 1
    fi
    log_info "Auto-detected method: $METHOD"
fi

# ============================================================================
# Method: V Native Coverage (-coverage flag + vcover)
# ============================================================================
run_native_coverage() {
    log_info "Running V native coverage..."
    rm -rf "$COV_DIR/native"
    mkdir -p "$COV_DIR/native"

    local cov_flag="-coverage $COV_DIR/native"

    # Test modules that can be tested independently
    local modules=(
        "src/event/"
        "src/conf/"
        "src/transforms/"
        "src/sinks/"
        "src/sources/"
        "src/topology/"
        "src/api/"
        "src/cliargs/"
    )

    log_info "Compiling and running tests with coverage instrumentation..."
    for mod in "${modules[@]}"; do
        log_verbose "Testing $mod"
        # shellcheck disable=SC2086
        v -enable-globals $cov_flag test "$mod" 2>&1 || {
            log_warn "Tests in $mod had failures (coverage data still collected)"
        }
    done

    # VRL module (separate due to size)
    log_info "Running VRL tests with coverage..."
    # shellcheck disable=SC2086
    v -enable-globals $cov_flag test src/vrl/ 2>&1 || {
        log_warn "VRL tests had failures (coverage data still collected)"
    }

    # Generate report using vcover
    log_info "Generating coverage report..."
    if command -v v &>/dev/null; then
        v cover -P "$COV_DIR/native/" | tee "$COV_DIR/native/report.txt"

        # Parse overall coverage from the report
        local total_executed=0
        local total_points=0
        while IFS='|' read -r file executed points pct; do
            executed=$(echo "$executed" | tr -d ' ')
            points=$(echo "$points" | tr -d ' ')
            if [[ "$executed" =~ ^[0-9]+$ ]] && [[ "$points" =~ ^[0-9]+$ ]]; then
                total_executed=$((total_executed + executed))
                total_points=$((total_points + points))
            fi
        done < "$COV_DIR/native/report.txt"

        if [[ $total_points -gt 0 ]]; then
            local pct
            pct=$(echo "scale=1; $total_executed * 100 / $total_points" | bc)
            log_info "Overall line coverage: ${pct}% ($total_executed/$total_points lines)"

            if (( $(echo "$pct >= $THRESHOLD" | bc -l) )); then
                log_info "PASS: Coverage ${pct}% >= ${THRESHOLD}% threshold"
            else
                log_error "FAIL: Coverage ${pct}% < ${THRESHOLD}% threshold"
                return 1
            fi
        fi
    fi

    log_info "Coverage data stored in $COV_DIR/native/"
}

# ============================================================================
# Method: gcov (compile V→C with gcc --coverage, then gcov/lcov)
#
# This approach is based on the discussion at:
# https://github.com/vlang/v/discussions/11742
#
# How it works:
# 1. V transpiles .v source to .c files (v -o file.c -keepc ...)
# 2. We compile the generated .c with gcc --coverage -O0
# 3. Running the binary produces .gcda/.gcno profiling files
# 4. gcov/lcov processes these into coverage reports
# 5. We map C coverage data back to V source lines using V's -cg flag
#    (which preserves C-to-V line number mappings)
#
# Limitations:
# - Coverage is on generated C code, not V source directly
# - V runtime/stdlib lines are included (can be filtered)
# - Requires -keepc and -cg flags for source mapping
# ============================================================================
run_gcov_coverage() {
    log_info "Running gcov-based coverage..."
    rm -rf "$COV_DIR/gcov"
    mkdir -p "$COV_DIR/gcov"

    local modules=(
        "src/event/"
        "src/conf/"
        "src/transforms/"
        "src/sinks/"
        "src/sources/"
        "src/topology/"
        "src/api/"
        "src/cliargs/"
    )

    log_info "Compiling tests with gcc --coverage..."
    for mod in "${modules[@]}"; do
        local mod_name
        mod_name=$(basename "$mod")
        log_verbose "Compiling $mod with coverage flags"

        # Compile V test to C, then compile C with coverage
        v -enable-globals -cc gcc -cg -keepc \
          -cflags "--coverage" -cflags "-O0" \
          test "$mod" 2>&1 || {
            log_warn "Tests in $mod failed (coverage data may still be partial)"
        }
    done

    # Collect .gcda files
    log_info "Collecting gcov data..."
    local gcda_files
    gcda_files=$(find "$PROJECT_DIR" -name "*.gcda" 2>/dev/null | head -100)

    if [[ -z "$gcda_files" ]]; then
        log_warn "No .gcda files found. Tests may not have produced coverage data."
        log_info "This can happen if:"
        log_info "  - V doesn't use gcc as backend (try: v -cc gcc ...)"
        log_info "  - The -cflags aren't being passed through correctly"
        log_info "  - Consider using 'native' method instead"
        return 1
    fi

    # Run gcov on each .gcda file
    for gcda in $gcda_files; do
        gcov -o "$(dirname "$gcda")" "$gcda" 2>/dev/null || true
    done

    # If lcov is available, generate combined report
    if command -v lcov &>/dev/null; then
        log_info "Generating lcov report..."
        lcov --capture --directory "$PROJECT_DIR" \
             --output-file "$COV_DIR/gcov/coverage.info" \
             --no-external 2>/dev/null || true

        # Filter out V standard library if possible
        if [[ -f "$COV_DIR/gcov/coverage.info" ]]; then
            lcov --remove "$COV_DIR/gcov/coverage.info" \
                 '*/v/vlib/*' '*/v/thirdparty/*' '/usr/*' \
                 --output-file "$COV_DIR/gcov/coverage_filtered.info" 2>/dev/null || true

            # Generate summary
            lcov --summary "$COV_DIR/gcov/coverage_filtered.info" 2>&1 | \
                tee "$COV_DIR/gcov/summary.txt"

            # Generate HTML if requested
            if $GENERATE_HTML && command -v genhtml &>/dev/null; then
                log_info "Generating HTML report..."
                genhtml "$COV_DIR/gcov/coverage_filtered.info" \
                        --output-directory "$HTML_DIR" \
                        --title "Vector-V Coverage" 2>/dev/null
                log_info "HTML report: $HTML_DIR/index.html"
            fi
        fi
    else
        log_info "Install lcov for combined reports: apt-get install lcov"
    fi

    # Cleanup .gcda and .gcno files from source tree
    find "$PROJECT_DIR/src" -name "*.gcda" -o -name "*.gcno" -o -name "*.gcov" \
        -exec rm -f {} + 2>/dev/null || true

    log_info "Coverage data stored in $COV_DIR/gcov/"
}

# ============================================================================
# Main
# ============================================================================
case "$METHOD" in
    native)
        if ! check_v; then
            log_error "V compiler not found. Install V >= 0.4.7."
            exit 1
        fi
        run_native_coverage
        ;;
    gcov)
        if ! check_v; then
            log_error "V compiler not found."
            exit 1
        fi
        if ! check_gcov; then
            log_error "gcc and gcov required for gcov method."
            exit 1
        fi
        run_gcov_coverage
        ;;
    *)
        log_error "Unknown method: $METHOD (use 'native' or 'gcov')"
        exit 1
        ;;
esac
