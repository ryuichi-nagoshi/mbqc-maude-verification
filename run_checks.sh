#!/usr/bin/env bash

set -u
set -o pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

for cmd in maude timeout; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 127
  fi
done

OUTDIR="artifacts/checks"
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

# This runner checks clean execution only; semantic expectations are
# documented in the corresponding .maude files.
overall_status=0

run_one() {
  local file="$1"
  local limit="$2"

  local name="${file//\//__}"
  name="${name%.maude}"
  local out="$OUTDIR/${name}.txt"

  echo
  echo "============================================================"
  echo "Running: $file"
  echo "Output : $out"
  echo "Limit  : ${limit}s"
  echo "============================================================"

  timeout "${limit}s" maude "$file" > "$out" 2>&1
  local rc=$?

  local bad=0
  if grep -Eiq \
    'Warning:|bad token|no parse for|Error:' \
    "$out"
  then
    bad=1
  fi

  if [ "$rc" -eq 0 ] && [ "$bad" -eq 0 ]; then
    echo "PASS: $file"
  else
    echo "FAIL: $file"
    echo "  exit_status=$rc"
    echo "  warning_or_parse_error=$bad"
    echo "  log=$out"
    overall_status=1
  fi
}

# Core arithmetic and execution
run_one tests/test_cpx_regression.maude           180
run_one tests/test_exec_angles.maude              180
run_one tests/test_output_order.maude             180

# Structural checks and public workflow
run_one tests/test_gflow_extraction.maude         180
run_one tests/test_public_input_checker.maude     180
run_one tests/test_workflow_public_verdicts.maude 180
run_one tests/test_workflow_wf_integration.maude  180

# Paper evaluation: RQ1 and RQ2
run_one evaluation/eval_rq1_integrated.maude      300
run_one evaluation/eval_rq2_integrated.maude      300

# RQ3 machinery smoke test
run_one evaluation/eval_rq3_smoke.maude           300

echo
echo "============================================================"

if [ "$overall_status" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
else
  echo "ONE OR MORE CHECKS FAILED"
  echo "Inspect logs under: $OUTDIR"
fi

echo "============================================================"

exit "$overall_status"
