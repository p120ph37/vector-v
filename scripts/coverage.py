#!/usr/bin/env python3
"""
V language function-level code coverage analyzer for Vector-V.

Since V does not have built-in code coverage tooling, this script performs
static analysis to measure function-level test coverage:

1. Scans all .v source files (excluding _test.v) to extract public and
   private function/method signatures.
2. Scans all _test.v files to determine which functions are exercised
   by looking for direct calls, method calls, and constructor usage.
3. For VRL stdlib functions (fn_*), checks if the corresponding VRL
   function name appears in test file string literals (since VRL stdlib
   functions are called indirectly through the runtime evaluator).
4. Traces transitive coverage: if function A is covered and calls B,
   then B is also considered covered.
5. Reports per-module and overall coverage percentages.

Usage:
    python3 scripts/coverage.py [--verbose] [--json] [--threshold N]

Exit code 0 if coverage >= threshold (default 95), else exit code 1.
"""

import argparse
import json as json_mod
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class FuncInfo:
    name: str
    file: str
    line: int
    is_method: bool = False
    receiver_type: str = ""
    is_public: bool = False
    is_test: bool = False
    body_calls: set = field(default_factory=set)  # functions called in body


@dataclass
class ModuleCoverage:
    module: str
    total_funcs: int = 0
    covered_funcs: int = 0
    uncovered: list = field(default_factory=list)
    covered: list = field(default_factory=list)

    @property
    def pct(self) -> float:
        if self.total_funcs == 0:
            return 100.0
        return (self.covered_funcs / self.total_funcs) * 100.0


# Regex for V function definitions
RE_FUNC = re.compile(
    r"^(?:pub\s+)?fn\s+"
    r"(?:\(\s*(?:mut\s+)?\w+\s+&?(\w+)\)\s+)?"  # optional receiver
    r"(\w+)\s*\(",
    re.MULTILINE,
)


def extract_functions_with_bodies(filepath: str) -> list[FuncInfo]:
    """Extract all function definitions and their body calls from a V source file."""
    funcs = []
    try:
        with open(filepath, "r") as f:
            lines = f.readlines()
    except Exception:
        return funcs

    call_re = re.compile(r"(\w+)\s*[!(]\s*")

    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        m = RE_FUNC.match(stripped)
        if m:
            receiver_type = m.group(1) or ""
            func_name = m.group(2)
            is_public = stripped.startswith("pub ")
            is_method = bool(receiver_type)
            is_test = func_name.startswith("test_")

            # Collect body calls by scanning until the function ends
            body_calls = set()
            brace_depth = 0
            j = i
            started = False
            while j < len(lines):
                line = lines[j]
                for ch in line:
                    if ch == "{":
                        brace_depth += 1
                        started = True
                    elif ch == "}":
                        brace_depth -= 1
                if started and brace_depth <= 0:
                    break
                if started:
                    for cm in call_re.finditer(line):
                        body_calls.add(cm.group(1))
                j += 1

            funcs.append(
                FuncInfo(
                    name=func_name,
                    file=filepath,
                    line=i + 1,
                    is_method=is_method,
                    receiver_type=receiver_type,
                    is_public=is_public,
                    is_test=is_test,
                    body_calls=body_calls,
                )
            )
        i += 1
    return funcs


def extract_test_calls(test_files: list[str]) -> set[str]:
    """Extract all function/method names called in test files."""
    calls = set()
    call_pattern = re.compile(r"(?:^|[^.\w])(\w+)\s*[!(]\s*", re.MULTILINE)
    method_pattern = re.compile(r"\.(\w+)\s*[!(]\s*", re.MULTILINE)
    constructor_pattern = re.compile(r"(\w+)\s*\{", re.MULTILINE)

    for filepath in test_files:
        try:
            with open(filepath, "r") as f:
                content = f.read()
        except Exception:
            continue

        for m in call_pattern.finditer(content):
            calls.add(m.group(1))
        for m in method_pattern.finditer(content):
            calls.add(m.group(1))
        for m in constructor_pattern.finditer(content):
            calls.add(m.group(1))

    return calls


def extract_vrl_function_calls_from_tests(test_files: list[str]) -> set[str]:
    """Extract VRL function names referenced in test string literals."""
    vrl_calls = set()
    func_call_pattern = re.compile(r"(\w+)\s*[!(]\s*")

    for filepath in test_files:
        try:
            with open(filepath, "r") as f:
                content = f.read()
        except Exception:
            continue

        for m in re.finditer(r"'([^']*(?:\\.[^']*)*)'", content):
            for fm in func_call_pattern.finditer(m.group(1)):
                vrl_calls.add(fm.group(1))
        for m in re.finditer(r'"([^"]*(?:\\.[^"]*)*)"', content):
            for fm in func_call_pattern.finditer(m.group(1)):
                vrl_calls.add(fm.group(1))

    return vrl_calls


# Functions that are inherently untestable in unit tests (require network,
# stdin, blocking event loops, OS-level resources, etc.)
UNTESTABLE_FUNCS = {
    # Blocking network servers / event loops
    "run_server",
    "run",  # ApiServer.run, Pipeline.run, DemoLogsSource.run, etc.
    "handle_api_request",
    "handle_fluent_conn",
    # Requires TCP connection
    "send_response",
    # HTTP calls to external services
    "fetch_imds_token",
    "fetch_metadata_path",
    "fetch_all_metadata",
    # Functions that call HTTP endpoints
    "send_payload",
    "simple_healthcheck",
    # Dispatchers that call run() on sources (blocking)
    "run_source",
}


def get_vrl_name_for_stdlib_fn(fn_name: str) -> str:
    """Convert fn_downcase to 'downcase'."""
    if fn_name.startswith("fn_"):
        return fn_name[3:]
    return ""


def compute_transitive_coverage(
    funcs: list[FuncInfo], directly_covered: set[str]
) -> set[str]:
    """Compute transitive coverage: if A is covered and A calls B, B is covered."""
    covered = set(directly_covered)
    func_map = {f.name: f for f in funcs}
    changed = True
    while changed:
        changed = False
        for name in list(covered):
            f = func_map.get(name)
            if f:
                for called in f.body_calls:
                    if called in func_map and called not in covered:
                        covered.add(called)
                        changed = True
    return covered


def analyze_module(
    src_dir: str,
    module_path: str,
    all_test_calls: set[str],
    vrl_test_calls: set[str],
    verbose: bool = False,
) -> Optional[ModuleCoverage]:
    """Analyze coverage for a single module directory."""
    module_name = os.path.relpath(module_path, src_dir)
    source_files = []
    test_files = []

    for f in sorted(os.listdir(module_path)):
        if not f.endswith(".v"):
            continue
        full = os.path.join(module_path, f)
        if f.endswith("_test.v"):
            test_files.append(full)
        elif f == "test_helpers.v":
            continue
        elif f.endswith("_data.v"):
            continue
        elif f.endswith(".c.v"):
            continue
        else:
            source_files.append(full)

    if not source_files:
        return None

    all_funcs = []
    for sf in source_files:
        all_funcs.extend(extract_functions_with_bodies(sf))

    target_funcs = [
        f
        for f in all_funcs
        if not f.is_test and f.name not in UNTESTABLE_FUNCS
    ]

    if not target_funcs:
        return None

    local_calls = extract_test_calls(test_files)
    is_vrl = module_name == "vrl"

    # Determine directly covered functions
    directly_covered = set()
    for func in target_funcs:
        covered = func.name in local_calls or func.name in all_test_calls
        if not covered and is_vrl and func.name.startswith("fn_"):
            vrl_name = get_vrl_name_for_stdlib_fn(func.name)
            if vrl_name and vrl_name in vrl_test_calls:
                covered = True
        if covered:
            directly_covered.add(func.name)

    # Compute transitive coverage
    all_covered = compute_transitive_coverage(target_funcs, directly_covered)

    cov = ModuleCoverage(module=module_name)
    cov.total_funcs = len(target_funcs)

    for func in target_funcs:
        if func.name in all_covered:
            cov.covered_funcs += 1
            cov.covered.append(func)
        else:
            cov.uncovered.append(func)

    return cov


def find_modules(src_dir: str) -> list[str]:
    """Find all V module directories under src/."""
    modules = []
    for entry in sorted(os.listdir(src_dir)):
        full = os.path.join(src_dir, entry)
        if os.path.isdir(full):
            has_v = any(f.endswith(".v") for f in os.listdir(full))
            if has_v:
                modules.append(full)
    return modules


def main():
    parser = argparse.ArgumentParser(
        description="V function-level code coverage analyzer"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Show uncovered functions"
    )
    parser.add_argument(
        "--json", action="store_true", help="Output as JSON"
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=95.0,
        help="Coverage threshold percentage (default: 95)",
    )
    parser.add_argument(
        "--src", default="src", help="Source directory (default: src)"
    )
    args = parser.parse_args()

    src_dir = os.path.abspath(args.src)
    if not os.path.isdir(src_dir):
        print(f"Error: source directory not found: {src_dir}", file=sys.stderr)
        sys.exit(1)

    all_test_files = []
    for root, dirs, files in os.walk(src_dir):
        for f in files:
            if f.endswith("_test.v"):
                all_test_files.append(os.path.join(root, f))

    all_test_calls = extract_test_calls(all_test_files)
    vrl_test_calls = extract_vrl_function_calls_from_tests(all_test_files)

    modules = find_modules(src_dir)
    results = []
    total_funcs = 0
    total_covered = 0

    for mod_path in modules:
        cov = analyze_module(
            src_dir, mod_path, all_test_calls, vrl_test_calls, args.verbose
        )
        if cov:
            results.append(cov)
            total_funcs += cov.total_funcs
            total_covered += cov.covered_funcs

    overall_pct = (total_covered / total_funcs * 100.0) if total_funcs > 0 else 0.0

    if args.json:
        output = {
            "overall": {
                "total_functions": total_funcs,
                "covered_functions": total_covered,
                "coverage_pct": round(overall_pct, 1),
            },
            "modules": [],
        }
        for r in results:
            mod_data = {
                "module": r.module,
                "total_functions": r.total_funcs,
                "covered_functions": r.covered_funcs,
                "coverage_pct": round(r.pct, 1),
                "uncovered": [
                    {
                        "name": f.name,
                        "file": os.path.relpath(f.file, src_dir),
                        "line": f.line,
                    }
                    for f in r.uncovered
                ],
            }
            output["modules"].append(mod_data)
        print(json_mod.dumps(output, indent=2))
    else:
        print("=" * 70)
        print("Vector-V Function-Level Code Coverage Report")
        print("=" * 70)
        print()
        print(
            f"{'Module':<25} {'Functions':>10} {'Covered':>10} {'Coverage':>10}"
        )
        print("-" * 55)
        for r in results:
            marker = " *" if r.pct < args.threshold else ""
            print(
                f"{r.module:<25} {r.total_funcs:>10} {r.covered_funcs:>10}"
                f" {r.pct:>9.1f}%{marker}"
            )
        print("-" * 55)
        print(
            f"{'TOTAL':<25} {total_funcs:>10} {total_covered:>10}"
            f" {overall_pct:>9.1f}%"
        )
        print()

        if args.verbose:
            for r in results:
                if r.uncovered:
                    print(f"\nUncovered functions in {r.module}:")
                    for f in r.uncovered:
                        rel_file = os.path.relpath(f.file, src_dir)
                        kind = "method" if f.is_method else "fn"
                        pub = "pub " if f.is_public else ""
                        recv = (
                            f" on {f.receiver_type}" if f.receiver_type else ""
                        )
                        print(
                            f"  {rel_file}:{f.line}  {pub}{kind}"
                            f" {f.name}{recv}"
                        )

        if overall_pct >= args.threshold:
            print(
                f"PASS: Coverage {overall_pct:.1f}% >="
                f" {args.threshold}% threshold"
            )
        else:
            print(
                f"FAIL: Coverage {overall_pct:.1f}% <"
                f" {args.threshold}% threshold"
            )
            deficit = (
                int(total_funcs * args.threshold / 100) - total_covered
            )
            print(f"  Need to cover {deficit} more functions")

    sys.exit(0 if overall_pct >= args.threshold else 1)


if __name__ == "__main__":
    main()
