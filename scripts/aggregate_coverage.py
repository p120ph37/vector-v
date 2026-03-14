#!/usr/bin/env python3
"""
Aggregate V coverage data from metadata JSON and counter CSV files.

Works around `v cover` not reporting all instrumented files by reading
the raw coverage data directly. Merges coverage across multiple test
module compilations — each compilation may instrument the same source
file differently, so we union line-level hits across all compilations.

Usage:
    python3 scripts/aggregate_coverage.py [--filter PATTERN] [--verbose] .coverage/
"""
import glob
import json
import os
import sys


def load_all_data(cov_dir):
    """Load metadata and counters, returning per-file line hit sets.

    Returns: {filepath: {"lines": set_of_total_lines, "hit_lines": set_of_hit_lines}}
    """
    # Phase 1: Load all metadata entries (fhash -> {file, points[]})
    meta = {}  # fhash -> {file, points}
    meta_dirs = glob.glob(os.path.join(cov_dir, "*/meta")) + [os.path.join(cov_dir, "meta")]
    for meta_dir in meta_dirs:
        if not os.path.isdir(meta_dir):
            continue
        for path in glob.glob(os.path.join(meta_dir, "*.json")):
            with open(path) as f:
                content = f.read()
            try:
                decoder = json.JSONDecoder()
                data, _ = decoder.raw_decode(content)
            except (json.JSONDecodeError, ValueError):
                continue
            fhash = data.get("fhash", "")
            points = data.get("points", [])
            npoints = data.get("npoints", 0)
            filepath = data.get("file", "")
            if fhash and filepath and npoints > 0:
                # Keep the entry with more points if we've seen this hash before
                if fhash not in meta or len(points) > len(meta[fhash].get("points", [])):
                    meta[fhash] = {"file": filepath, "points": points, "npoints": npoints}

    # Phase 2: Load all counter CSVs
    hits = {}  # (fhash, point_index) -> total_hits
    for path in glob.glob(os.path.join(cov_dir, "vcounters_*.csv")):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or line.startswith("meta,"):
                    continue
                parts = line.split(",")
                if len(parts) != 3:
                    continue
                try:
                    fhash, point, hit_count = parts[0], int(parts[1]), int(parts[2])
                except ValueError:
                    continue
                key = (fhash, point)
                hits[key] = hits.get(key, 0) + hit_count

    # Also check subdirectories for counter CSVs
    for sub_csv in glob.glob(os.path.join(cov_dir, "*/vcounters_*.csv")):
        with open(sub_csv) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or line.startswith("meta,"):
                    continue
                parts = line.split(",")
                if len(parts) != 3:
                    continue
                try:
                    fhash, point, hit_count = parts[0], int(parts[1]), int(parts[2])
                except ValueError:
                    continue
                key = (fhash, point)
                hits[key] = hits.get(key, 0) + hit_count

    # Phase 3: Merge into per-file line coverage
    # A source file may appear under multiple fhashes (different compilations).
    # Each compilation maps point indices to source line numbers.
    # We union the line sets across all compilations.
    file_coverage = {}  # filepath -> {"lines": set, "hit_lines": set}

    for fhash, info in meta.items():
        filepath = info["file"]
        points = info["points"]  # list of source line numbers

        if filepath not in file_coverage:
            file_coverage[filepath] = {"lines": set(), "hit_lines": set()}

        for i, line_no in enumerate(points):
            file_coverage[filepath]["lines"].add(line_no)
            if hits.get((fhash, i), 0) > 0:
                file_coverage[filepath]["hit_lines"].add(line_no)

    return file_coverage


def format_results(file_coverage, project_root, filter_pattern=None):
    """Format coverage results, filtering to project source files."""
    results = []
    for filepath, cov in file_coverage.items():
        # Make path relative to project root
        if filepath.startswith(project_root):
            rel_path = filepath[len(project_root):].lstrip("/")
        else:
            rel_path = filepath

        # Only include project source files (src/), exclude test files
        if not rel_path.startswith("src/"):
            continue
        if rel_path.endswith("_test.v"):
            continue
        # Skip data-only files
        if rel_path.endswith("psl_data.v") or rel_path.endswith("grok_patterns_data.v"):
            continue

        if filter_pattern and filter_pattern not in rel_path:
            continue

        total = len(cov["lines"])
        if total == 0:
            continue
        executed = len(cov["hit_lines"])

        results.append({
            "file": rel_path,
            "executed": executed,
            "total": total,
            "pct": (executed / total * 100) if total > 0 else 0.0,
        })

    results.sort(key=lambda r: r["file"])
    return results


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Aggregate V coverage data")
    parser.add_argument("cov_dir", help="Coverage data directory")
    parser.add_argument("--filter", default=None, help="Only show files matching pattern")
    parser.add_argument("--verbose", action="store_true", help="Show detailed output")
    args = parser.parse_args()

    cov_dir = os.path.abspath(args.cov_dir)
    project_root = os.path.dirname(cov_dir)  # .coverage is inside project root

    file_coverage = load_all_data(cov_dir)
    if args.verbose:
        print(f"[DEBUG] Found coverage data for {len(file_coverage)} files", file=sys.stderr)

    results = format_results(file_coverage, project_root, args.filter)

    # Print report
    total_executed = 0
    total_points = 0

    for r in results:
        total_executed += r["executed"]
        total_points += r["total"]
        print(f"{r['file']:<80s} | {r['executed']:>8d} | {r['total']:>8d} | {r['pct']:>7.2f}%")

    if total_points > 0:
        overall = total_executed / total_points * 100
        print()
        print(f"Files: {len(results)}")
        print(f"Lines: {total_executed}/{total_points}")
        print(f"Coverage: {overall:.1f}%")
    else:
        print("No coverage data found.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
