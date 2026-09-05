#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

REPETITIONS=5
TIMEOUT_SECONDS=900
COOLDOWN_SECONDS=5
WORKLOADS=(tele cnot bitflip3 ghz3 ghz4 ghz5 ghz6 ghz7)
METHODS=(full single proposed)
OUTPUT_DIR=""
FORCE=0

usage() {
  cat <<'EOF'
Usage:
  ./run_rq3_experiment.sh [options]

Options:
  --repetitions N       Number of runs per workload/method (default: 5)
  --timeout SECONDS     Timeout per Maude process (default: 900)
  --cooldown SECONDS    Pause between processes (default: 5)
  --workloads "LIST"    Space-separated workloads
                        (default: "tele cnot bitflip3 ghz3 ghz4 ghz5 ghz6 ghz7")
  --methods "LIST"      Space-separated methods
                        (default: "full single proposed")
  --output-dir PATH     Experiment directory. Existing JSON records are skipped.
  --force               Re-run and overwrite existing records.
  -h, --help            Show this help.

Examples:
  # One-run pilot through GHZ5
  ./run_rq3_experiment.sh \
    --repetitions 1 \
    --workloads "tele cnot bitflip3 ghz3 ghz4 ghz5" \
    --output-dir results/rq3_pilot

  # Resume the same pilot with GHZ6
  ./run_rq3_experiment.sh \
    --repetitions 1 \
    --workloads "ghz6" \
    --output-dir results/rq3_pilot

  # Example five-run experiment using the generic driver defaults
  ./run_rq3_experiment.sh \
    --repetitions 5 \
    --timeout 900 \
    --output-dir results/rq3_final
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repetitions)
      REPETITIONS="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --cooldown)
      COOLDOWN_SECONDS="$2"
      shift 2
      ;;
    --workloads)
      read -r -a WORKLOADS <<< "$2"
      shift 2
      ;;
    --methods)
      read -r -a METHODS <<< "$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for value_name in REPETITIONS TIMEOUT_SECONDS; do
  value="${!value_name}"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "$value_name must be a positive integer: $value" >&2
    exit 2
  fi
done

if ! [[ "$COOLDOWN_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "COOLDOWN_SECONDS must be a nonnegative integer: $COOLDOWN_SECONDS" >&2
  exit 2
fi

if [[ ! -x ./run_rq3_once.sh ]]; then
  echo "Missing executable ./run_rq3_once.sh" >&2
  exit 2
fi

if [[ ! -f evaluation/tools/aggregate_rq3_results.py ]]; then
  echo "Missing evaluation/tools/aggregate_rq3_results.py" >&2
  exit 2
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  SHA_SHORT="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  OUTPUT_DIR="results/rq3_main/$(date +%Y%m%d_%H%M%S)_${SHA_SHORT}"
fi

mkdir -p "$OUTPUT_DIR"

MANIFEST="${OUTPUT_DIR}/manifest.txt"
if [[ -f "$MANIFEST" ]]; then
  MANIFEST="${OUTPUT_DIR}/resume_$(date +%Y%m%d_%H%M%S).txt"
fi

{
  echo "RQ3 experiment manifest"
  echo "======================="
  echo "created_at=$(date --iso-8601=seconds)"
  echo "working_directory=$(pwd)"
  echo "repetitions=${REPETITIONS}"
  echo "timeout_seconds=${TIMEOUT_SECONDS}"
  echo "cooldown_seconds=${COOLDOWN_SECONDS}"
  echo "workloads=${WORKLOADS[*]}"
  echo "methods=${METHODS[*]}"
  echo "force=${FORCE}"
  echo
  echo "[git]"
  git rev-parse HEAD 2>&1 || true
  git status --short 2>&1 || true
  echo
  echo "[sha256]"
  sha256sum \
    run_rq3_once.sh \
    run_rq3_experiment.sh \
    evaluation/tools/parse_rq3_run.py \
    evaluation/tools/aggregate_rq3_results.py \
    evaluation/common/rq3_core.maude 2>&1 || true
  echo
  echo "[uname]"
  uname -a 2>&1 || true
  echo
  echo "[lscpu]"
  lscpu 2>&1 || true
  echo
  echo "[memory]"
  free -h 2>&1 || true
  echo
  echo "[maude]"
  printf 'quit\n' | maude 2>&1 || true
  echo
  echo "[time]"
  /usr/bin/time --version 2>&1 | head -n 2 || true
  echo
  echo "[timeout]"
  timeout --version 2>&1 | head -n 2 || true
} > "$MANIFEST"

export RQ3_FORCE="$FORCE"

METHOD_COUNT="${#METHODS[@]}"

for workload in "${WORKLOADS[@]}"; do
  for ((rep = 1; rep <= REPETITIONS; rep++)); do
    shift_by=$(( (rep - 1) % METHOD_COUNT ))
    ordered_methods=()
    for ((offset = 0; offset < METHOD_COUNT; offset++)); do
      index=$(( (shift_by + offset) % METHOD_COUNT ))
      ordered_methods+=("${METHODS[$index]}")
    done

    for method in "${ordered_methods[@]}"; do
      echo "============================================================"
      echo "workload=${workload} method=${method} repetition=${rep}"
      echo "output=${OUTPUT_DIR}"
      echo "============================================================"

      set +e
      ./run_rq3_once.sh \
        "$workload" \
        "$method" \
        "$rep" \
        "$TIMEOUT_SECONDS" \
        "$OUTPUT_DIR"
      status=$?
      set -e

      echo "process_exit_status=${status}"
      if [[ "$COOLDOWN_SECONDS" -gt 0 ]]; then
        sleep "$COOLDOWN_SECONDS"
      fi
    done
  done
done

python3 evaluation/tools/aggregate_rq3_results.py "$OUTPUT_DIR"

echo
echo "Experiment finished."
echo "Output directory: $OUTPUT_DIR"
