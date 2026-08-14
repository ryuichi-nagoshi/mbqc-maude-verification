#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

OUTDIR="${1:-artifacts/rq3_reproduction_$(date +%Y%m%d_%H%M%S)}"

echo "============================================================"
echo "RQ3 paper reproduction"
echo "============================================================"
echo "Output directory : $OUTDIR"
echo "Repetitions      : 5"
echo "Timeout per run  : 3600 seconds"
echo "Cooldown         : 5 seconds"
echo "Workloads        : tele cnot bitflip3 ghz3 ghz4 ghz5 ghz6"
echo "Methods          : full proposed"
echo
echo "WARNING:"
echo "  This experiment includes GHZ6."
echo "  A complete run can require substantial execution time"
echo "  and memory."
echo "============================================================"
echo

./run_rq3_experiment.sh \
  --repetitions 5 \
  --timeout 3600 \
  --cooldown 5 \
  --workloads "tele cnot bitflip3 ghz3 ghz4 ghz5 ghz6" \
  --methods "full proposed" \
  --output-dir "$OUTDIR"
