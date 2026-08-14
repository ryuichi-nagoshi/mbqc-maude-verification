"""Aggregate RQ3 per-run JSON records into concise CSV files.

Outputs:
  runs.csv       One concise row per run.
  summary.csv    Median results by workload and method.
  comparison.csv Main full-branch versus proposed-workflow comparison.

The detailed diagnostic information remains in records/**/*.json and is not
duplicated in the concise CSV files.
"""

from __future__ import annotations

import argparse
import csv
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


def median(values: Iterable[float | int | None]) -> float | None:
    usable = [float(value) for value in values if value is not None]
    return statistics.median(usable) if usable else None


def safe_ratio(numerator: float | None, denominator: float | None) -> float | None:
    if numerator is None or denominator in (None, 0):
        return None
    return numerator / denominator


def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("experiment_dir")
    args = parser.parse_args()

    root = Path(args.experiment_dir)
    record_paths = sorted((root / "records").glob("*/*.json"))
    if not record_paths:
        raise SystemExit(f"No JSON records found under {root / 'records'}")

    records = [
        json.loads(path.read_text(encoding="utf-8"))
        for path in record_paths
    ]
    records.sort(
        key=lambda row: (
            row["workload"],
            row["method"],
            row["repetition"],
        )
    )

    # Concise per-run data. Detailed diagnostics remain in each JSON record.
    run_fields = [
        "workload",
        "method",
        "repetition",
        "run_status",
        "semantic_ok",
        "result_value",
        "rewrites",
        "maude_cpu_ms",
        "maude_real_ms",
        "max_rss_kb",
        "logical_outputs",
        "pattern_qubits",
        "measurements",
        "expected_branches",
        "git_sha",
        "maude_version",
    ]
    write_csv(root / "runs.csv", records, run_fields)

    grouped: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        grouped[(record["workload"], record["method"])].append(record)

    summary_rows: list[dict[str, Any]] = []
    summary_index: dict[tuple[str, str], dict[str, Any]] = {}

    for (workload, method), rows in sorted(grouped.items()):
        statuses = Counter(row["run_status"] for row in rows)
        valid = [
            row
            for row in rows
            if row.get("run_status") == "completed"
            and row.get("semantic_ok") is True
        ]
        rewrite_values = sorted({
            int(row["rewrites"])
            for row in valid
            if row.get("rewrites") is not None
        })
        metadata = rows[0]

        summary = {
            "workload": workload,
            "method": method,
            "attempts": len(rows),
            "completed": statuses.get("completed", 0),
            "timeouts": statuses.get("timeout", 0),
            "other_failures": len(rows) - statuses.get("completed", 0)
                              - statuses.get("timeout", 0),
            "rewrite_consistent": (len(valid) >= 2 and len(rewrite_values) == 1),
            "median_rewrites": median(row.get("rewrites") for row in valid),
            "median_cpu_ms": median(row.get("maude_cpu_ms") for row in valid),
            "median_real_ms": median(row.get("maude_real_ms") for row in valid),
            "median_max_rss_kb": median(row.get("max_rss_kb") for row in valid),
            "logical_outputs": metadata.get("logical_outputs"),
            "pattern_qubits": metadata.get("pattern_qubits"),
            "measurements": metadata.get("measurements"),
            "expected_branches": metadata.get("expected_branches"),
        }
        summary_rows.append(summary)
        summary_index[(workload, method)] = summary

    summary_fields = [
        "workload",
        "method",
        "attempts",
        "completed",
        "timeouts",
        "other_failures",
        "rewrite_consistent",
        "median_rewrites",
        "median_cpu_ms",
        "median_real_ms",
        "median_max_rss_kb",
        "logical_outputs",
        "pattern_qubits",
        "measurements",
        "expected_branches",
    ]
    write_csv(root / "summary.csv", summary_rows, summary_fields)

    # Main paper-facing comparison: exhaustive full branches versus proposal.
    workloads = sorted({record["workload"] for record in records})
    comparison_rows: list[dict[str, Any]] = []

    for workload in workloads:
        full = summary_index.get((workload, "full"))
        proposed = summary_index.get((workload, "proposed"))
        if full is None or proposed is None:
            continue

        full_rewrites = full.get("median_rewrites")
        proposed_rewrites = proposed.get("median_rewrites")
        full_real = full.get("median_real_ms")
        proposed_real = proposed.get("median_real_ms")

        comparison_rows.append({
            "workload": workload,
            "logical_outputs": full.get("logical_outputs"),
            "pattern_qubits": full.get("pattern_qubits"),
            "measurements": full.get("measurements"),
            "expected_branches": full.get("expected_branches"),
            "full_completed": full.get("completed"),
            "proposed_completed": proposed.get("completed"),
            "full_rewrites": full_rewrites,
            "proposed_rewrites": proposed_rewrites,
            "rewrite_ratio_full_over_proposed": safe_ratio(
                full_rewrites, proposed_rewrites
            ),
            "full_real_ms": full_real,
            "proposed_real_ms": proposed_real,
            "time_ratio_full_over_proposed": safe_ratio(
                full_real, proposed_real
            ),
            "full_max_rss_kb": full.get("median_max_rss_kb"),
            "proposed_max_rss_kb": proposed.get("median_max_rss_kb"),
        })

    comparison_fields = [
        "workload",
        "logical_outputs",
        "pattern_qubits",
        "measurements",
        "expected_branches",
        "full_completed",
        "proposed_completed",
        "full_rewrites",
        "proposed_rewrites",
        "rewrite_ratio_full_over_proposed",
        "full_real_ms",
        "proposed_real_ms",
        "time_ratio_full_over_proposed",
        "full_max_rss_kb",
        "proposed_max_rss_kb",
    ]
    write_csv(root / "comparison.csv", comparison_rows, comparison_fields)

    print(f"Records: {len(records)}")
    print(f"Created: {root / 'runs.csv'}")
    print(f"Created: {root / 'summary.csv'}")
    print(f"Created: {root / 'comparison.csv'}")


if __name__ == "__main__":
    main()