#!/usr/bin/env python3
"""
Aggregate V coverage data from metadata JSON and counter CSV files.

Works around `v cover` not reporting all instrumented files by reading
the raw coverage data directly.

Usage:
    python3 scripts/aggregate_coverage.py [--filter PATTERN] [--verbose] .coverage/
"""
import csv
import glob
import json
import os
import sys


def load_metadata(meta_dir):
    """Load all metadata JSON files, mapping file hash -> {file, npoints, points}."""
    meta = {}
    for path in glob.glob(os.path.join(meta_dir, "*.json")):
        with open(path) as f:
            content = f.read()
        try:
            decoder = json.JSONDecoder()
            data, _ = decoder.raw_decode(content)
        except json.JSONDecodeError:
            continue
        fhash = data.get("fhash", "")
        if fhash:
            meta[fhash] = {
                "file": data.get("file", ""),
                "npoints": data.get("npoints", 0),
                "points": data.get("points", []),
            }
    return meta


def load_counters(cov_dir):
    """Load all counter CSV files, aggregating hits per (file_hash, point)."""
    hits = {}  # (fhash, point_index) -> total_hits
    for path in glob.glob(os.path.join(cov_dir, "vcounters_*.csv")):
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line == "meta,point,hits":
                    continue
                parts = line.split(",")
                if len(parts) != 3:
                    continue
                fhash, point_str, hits_str = parts
                try:
                    point = int(point_str)
                    hit_count = int(hits_str)
                except ValueError:
                    continue
                key = (fhash, point)
                hits[key] = hits.get(key, 0) + hit_count
    return hits


def compute_coverage(meta, hits, project_root, filter_pattern=None):
    """Compute per-file coverage from metadata and hit counters."""
    results = []
    for fhash, info in meta.items():
        filepath = info["file"]
        # Make path relative to project root
        if filepath.startswith(project_root):
            rel_path = filepath[len(project_root) :].lstrip("/")
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

        npoints = info["npoints"]
        if npoints == 0:
            continue

        executed = 0
        for i in range(npoints):
            key = (fhash, i)
            if hits.get(key, 0) > 0:
                executed += 1

        results.append({
            "file": rel_path,
            "executed": executed,
            "total": npoints,
            "pct": (executed / npoints * 100) if npoints > 0 else 0.0,
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
    meta_dir = os.path.join(cov_dir, "meta")
    project_root = os.path.dirname(cov_dir)  # .coverage is inside project root

    if not os.path.isdir(meta_dir):
        print(f"Error: metadata directory not found: {meta_dir}", file=sys.stderr)
        sys.exit(1)

    meta = load_metadata(meta_dir)
    if args.verbose:
        print(f"[DEBUG] Loaded {len(meta)} metadata entries", file=sys.stderr)

    hits = load_counters(cov_dir)
    if args.verbose:
        print(f"[DEBUG] Loaded {len(hits)} counter entries", file=sys.stderr)

    results = compute_coverage(meta, hits, project_root, args.filter)

    # Print report
    total_executed = 0
    total_points = 0

    for r in results:
        total_executed += r["executed"]
        total_points += r["total"]
        print(f"{r['file']:<80s} | {r['executed']:>8d} | {r['total']:>8d} | {r['pct']:>7.2f}%")

    if total_points > 0:
        overall = total_executed / total_points * 100
        # Print summary in a parseable format
        print()
        print(f"Files: {len(results)}")
        print(f"Lines: {total_executed}/{total_points}")
        print(f"Coverage: {overall:.1f}%")
    else:
        print("No coverage data found.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
