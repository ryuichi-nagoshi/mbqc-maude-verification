#!/usr/bin/env python3
"""Parse one RQ3 Maude run into a machine-readable JSON record."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


REWRITE_RE = re.compile(
    r"rewrites:\s+([0-9]+)\s+in\s+"
    r"([0-9]+(?:\.[0-9]+)?)([A-Za-zµ]+)\s+cpu\s+"
    r"\(([0-9]+(?:\.[0-9]+)?)([A-Za-zµ]+)\s+real\)"
)
RESULT_RE = re.compile(r"^result\s+([^:]+):\s*(.*?)\s*$", re.MULTILINE)


def duration_to_ms(value: str, unit: str) -> float:
    factors = {
        "ns": 1e-6,
        "us": 1e-3,
        "µs": 1e-3,
        "ms": 1.0,
        "s": 1000.0,
        "sec": 1000.0,
        "m": 60_000.0,
        "min": 60_000.0,
        "h": 3_600_000.0,
    }
    if unit not in factors:
        raise ValueError(f"Unsupported Maude time unit: {unit}")
    return float(value) * factors[unit]


def parse_elapsed_seconds(value: str) -> float | None:
    value = value.strip()
    if not value:
        return None
    try:
        parts = [float(part) for part in value.split(":")]
    except ValueError:
        return None
    if len(parts) == 2:
        minutes, seconds = parts
        return minutes * 60 + seconds
    if len(parts) == 3:
        hours, minutes, seconds = parts
        return hours * 3600 + minutes * 60 + seconds
    return None


def parse_time_file(text: str) -> dict[str, Any]:
    fields: dict[str, Any] = {}
    mapping = {
        "User time (seconds)": ("process_user_seconds", float),
        "System time (seconds)": ("process_system_seconds", float),
        "Percent of CPU this job got": ("process_cpu_percent_raw", str),
        "Elapsed (wall clock) time (h:mm:ss or m:ss)": (
            "process_elapsed_raw",
            str,
        ),
        "Maximum resident set size (kbytes)": ("max_rss_kb", int),
        "Minor (reclaiming a frame) page faults": ("minor_page_faults", int),
        "Major (requiring I/O) page faults": ("major_page_faults", int),
        "Voluntary context switches": ("voluntary_context_switches", int),
        "Involuntary context switches": ("involuntary_context_switches", int),
        "Exit status": ("time_exit_status", int),
    }
    for raw_line in text.splitlines():
        line = raw_line.strip()
        for prefix, (key, converter) in mapping.items():
            marker = prefix + ":"
            if line.startswith(marker):
                raw_value = line[len(marker) :].strip()
                try:
                    fields[key] = converter(raw_value)
                except ValueError:
                    fields[key] = None
    elapsed_raw = fields.get("process_elapsed_raw")
    fields["process_elapsed_seconds"] = (
        parse_elapsed_seconds(elapsed_raw) if isinstance(elapsed_raw, str) else None
    )
    return fields


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", required=True)
    parser.add_argument("--time", required=True)
    parser.add_argument("--record", required=True)
    parser.add_argument("--workload", required=True)
    parser.add_argument("--method", required=True)
    parser.add_argument("--repetition", required=True, type=int)
    parser.add_argument("--timeout", required=True, type=int)
    parser.add_argument("--exit-code", required=True, type=int)
    parser.add_argument("--expected-result", required=True)
    parser.add_argument("--logical-outputs", required=True, type=int)
    parser.add_argument("--pattern-qubits", required=True, type=int)
    parser.add_argument("--measurements", required=True, type=int)
    parser.add_argument("--expected-branches", required=True, type=int)
    parser.add_argument("--git-sha", required=True)
    parser.add_argument("--start-iso", required=True)
    parser.add_argument("--end-iso", required=True)
    args = parser.parse_args()

    raw_path = Path(args.raw)
    time_path = Path(args.time)
    raw_text = raw_path.read_text(encoding="utf-8", errors="replace")
    time_text = (
        time_path.read_text(encoding="utf-8", errors="replace")
        if time_path.exists()
        else ""
    )

    rewrite_matches = list(REWRITE_RE.finditer(raw_text))
    result_matches = list(RESULT_RE.finditer(raw_text))

    rewrites = None
    maude_cpu_ms = None
    maude_real_ms = None
    maude_stats_line = None
    if rewrite_matches:
        match = rewrite_matches[-1]
        rewrites = int(match.group(1))
        maude_cpu_ms = duration_to_ms(match.group(2), match.group(3))
        maude_real_ms = duration_to_ms(match.group(4), match.group(5))
        maude_stats_line = match.group(0)

    result_sort = None
    result_value = None
    if result_matches:
        result_sort = result_matches[-1].group(1).strip()
        result_value = result_matches[-1].group(2).strip()

    warning_lines = [
        line.strip()
        for line in raw_text.splitlines()
        if line.lstrip().startswith(("Warning:", "Advisory:"))
    ]

    if args.exit_code == 124:
        run_status = "timeout"
    elif args.exit_code == 137:
        run_status = "killed"
    elif args.exit_code != 0:
        run_status = "error"
    elif warning_lines:
        run_status = "warning"
    elif rewrites is None or result_value is None:
        run_status = "incomplete-output"
    elif result_value != args.expected_result:
        run_status = "completed-invalid-result"
    else:
        run_status = "completed"

    semantic_ok = (
        args.exit_code == 0
        and not warning_lines
        and result_value == args.expected_result
    )

    # If the final measured reduction did not complete, the last
    # completed result belongs to a warm-up reduction.
    if args.exit_code != 0:
        result_sort = None
        result_value = None
        rewrites = None
        maude_cpu_ms = None
        maude_real_ms = None
        maude_stats_line = None


    maude_version_match = re.search(r"\bMaude\s+([0-9]+(?:\.[0-9]+)+)", raw_text)
    maude_version = maude_version_match.group(1) if maude_version_match else None

    record: dict[str, Any] = {
        "workload": args.workload,
        "method": args.method,
        "repetition": args.repetition,
        "run_status": run_status,
        "semantic_ok": semantic_ok,
        "exit_code": args.exit_code,
        "timeout_seconds": args.timeout,
        "result_sort": result_sort,
        "result_value": result_value,
        "expected_result": args.expected_result,
        "rewrites": rewrites,
        "maude_cpu_ms": maude_cpu_ms,
        "maude_real_ms": maude_real_ms,
        "maude_stats_line": maude_stats_line,
        "warning_count": len(warning_lines),
        "warnings": warning_lines,
        "logical_outputs": args.logical_outputs,
        "pattern_qubits": args.pattern_qubits,
        "measurements": args.measurements,
        "expected_branches": args.expected_branches,
        "git_sha": args.git_sha,
        "maude_version": maude_version,
        "start_iso": args.start_iso,
        "end_iso": args.end_iso,
        "raw_file": str(raw_path),
        "time_file": str(time_path),
    }
    record.update(parse_time_file(time_text))

    record_path = Path(args.record)
    record_path.parent.mkdir(parents=True, exist_ok=True)
    record_path.write_text(
        json.dumps(record, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
