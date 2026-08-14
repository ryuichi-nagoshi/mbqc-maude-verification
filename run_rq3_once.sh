#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

usage() {
  cat <<'EOF'
Usage:
  ./run_rq3_once.sh WORKLOAD METHOD REPETITION TIMEOUT_SECONDS OUTPUT_DIR

WORKLOAD:
  tele | cnot | bitflip3 | ghzK  (for example ghz3, ghz5, ghz7)

METHOD:
  full | single | proposed | precheck

This script must be run from the repository root.
EOF
}

if [[ $# -ne 5 ]]; then
  usage >&2
  exit 2
fi

WORKLOAD_RAW="$1"
METHOD="$2"
REPETITION="$3"
LIMIT="$4"
OUT_DIR="$5"

for cmd in maude timeout /usr/bin/time python3 git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 127
  fi
done

if [[ ! -f evaluation/common/rq3_core.maude ]]; then
  echo "Run this script from the repository root." >&2
  exit 2
fi

if ! [[ "$REPETITION" =~ ^[1-9][0-9]*$ ]]; then
  echo "REPETITION must be a positive integer: $REPETITION" >&2
  exit 2
fi

if ! [[ "$LIMIT" =~ ^[1-9][0-9]*$ ]]; then
  echo "TIMEOUT_SECONDS must be a positive integer: $LIMIT" >&2
  exit 2
fi

case "$WORKLOAD_RAW" in
  tele|teleportation)
    WORKLOAD="tele"
    P_EXPR="RQ3TeleP"
    SPEC_EXPR="RQ3TeleSpec"
    LOGICAL_OUTPUTS=1
    PATTERN_QUBITS=3
    MEASUREMENTS=2
    EXPECTED_BRANCHES=4
    ;;
  cnot)
    WORKLOAD="cnot"
    P_EXPR="RQ3CNOTP"
    SPEC_EXPR="RQ3CNOTSpec"
    LOGICAL_OUTPUTS=2
    PATTERN_QUBITS=4
    MEASUREMENTS=2
    EXPECTED_BRANCHES=4
    ;;
  bitflip3|bitflip)
    WORKLOAD="bitflip3"
    P_EXPR="RQ3BitFlip3P"
    SPEC_EXPR="RQ3BitFlip3Spec"
    LOGICAL_OUTPUTS=3
    PATTERN_QUBITS=7
    MEASUREMENTS=4
    EXPECTED_BRANCHES=16
    ;;
  ghz[0-9]*)
    K="${WORKLOAD_RAW#ghz}"
    if ! [[ "$K" =~ ^[2-9][0-9]*$ ]]; then
      echo "GHZ width must be an integer >= 2: $WORKLOAD_RAW" >&2
      exit 2
    fi
    WORKLOAD="ghz${K}"
    P_EXPR="GHZP(${K})"
    SPEC_EXPR="GHZSpec(${K})"
    LOGICAL_OUTPUTS="$K"
    PATTERN_QUBITS=$((2 * K - 1))
    MEASUREMENTS=$((K - 1))
    EXPECTED_BRANCHES=$((2 ** MEASUREMENTS))
    ;;
  *)
    echo "Unknown workload: $WORKLOAD_RAW" >&2
    usage >&2
    exit 2
    ;;
esac

case "$METHOD" in
  full)
    MEASURE_EXPR="fullCost(${P_EXPR}, ${SPEC_EXPR})"
    EXPECTED_RESULT="true"
    NEED_SPEC=1
    ;;
  single)
    MEASURE_EXPR="singleCost(${P_EXPR}, ${SPEC_EXPR})"
    EXPECTED_RESULT="true"
    NEED_SPEC=1
    ;;
  proposed)
    MEASURE_EXPR="proposedCost(${P_EXPR}, ${SPEC_EXPR})"
    EXPECTED_RESULT="pass"
    NEED_SPEC=1
    ;;
  precheck)
    MEASURE_EXPR="precheckP(${P_EXPR})"
    EXPECTED_RESULT="true"
    NEED_SPEC=0
    ;;
  *)
    echo "Unknown method: $METHOD" >&2
    usage >&2
    exit 2
    ;;
esac

REP_PADDED="$(printf '%02d' "$REPETITION")"
RUN_ID="${WORKLOAD}_${METHOD}_r${REP_PADDED}"

RAW_DIR="${OUT_DIR}/raw/${WORKLOAD}"
TIME_DIR="${OUT_DIR}/time/${WORKLOAD}"
RECORD_DIR="${OUT_DIR}/records/${WORKLOAD}"
mkdir -p "$RAW_DIR" "$TIME_DIR" "$RECORD_DIR"

RAW_FILE="${RAW_DIR}/${RUN_ID}.txt"
TIME_FILE="${TIME_DIR}/${RUN_ID}.time.txt"
RECORD_FILE="${RECORD_DIR}/${RUN_ID}.json"

if [[ -f "$RECORD_FILE" && "${RQ3_FORCE:-0}" != "1" ]]; then
  echo "SKIP existing record: $RECORD_FILE"
  exit 0
fi

TMP="$(mktemp -p . rq3_main_XXXXXX.maude)"
trap 'rm -f "$TMP"' EXIT

{
  echo 'load evaluation/common/rq3_core.maude'
  echo
  echo 'set clear memo off .'
  echo 'set show stats on .'
  echo 'set show timing on .'
  echo
  echo "--- Warm transformed pattern outside the measured reduction."
  echo "red in RQ3-CORE : forcePattern(${P_EXPR}) ."
  if [[ "$NEED_SPEC" -eq 1 ]]; then
    echo "--- Warm specification outside the measured reduction."
    echo "red in RQ3-CORE : forceVect(${SPEC_EXPR}) ."
  fi
  echo
  echo "--- The final reduction is the measured expression."
  echo "red in RQ3-CORE : ${MEASURE_EXPR} ."
  echo
  echo 'quit'
} > "$TMP"

GIT_SHA="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
START_ISO="$(date --iso-8601=seconds)"

set +e
/usr/bin/time -v -o "$TIME_FILE" \
  timeout --signal=TERM --kill-after=10s "${LIMIT}s" \
  maude "$TMP" > "$RAW_FILE" 2>&1
EXIT_CODE=$?
set -e

END_ISO="$(date --iso-8601=seconds)"

if [[ "$EXIT_CODE" -eq 124 ]]; then
  echo "RQ3_STATUS: TIMEOUT after ${LIMIT}s" >> "$RAW_FILE"
elif [[ "$EXIT_CODE" -ne 0 ]]; then
  echo "RQ3_STATUS: ERROR exit_code=${EXIT_CODE}" >> "$RAW_FILE"
fi

python3 evaluation/tools/parse_rq3_run.py \
  --raw "$RAW_FILE" \
  --time "$TIME_FILE" \
  --record "$RECORD_FILE" \
  --workload "$WORKLOAD" \
  --method "$METHOD" \
  --repetition "$REPETITION" \
  --timeout "$LIMIT" \
  --exit-code "$EXIT_CODE" \
  --expected-result "$EXPECTED_RESULT" \
  --logical-outputs "$LOGICAL_OUTPUTS" \
  --pattern-qubits "$PATTERN_QUBITS" \
  --measurements "$MEASUREMENTS" \
  --expected-branches "$EXPECTED_BRANCHES" \
  --git-sha "$GIT_SHA" \
  --start-iso "$START_ISO" \
  --end-iso "$END_ISO"

echo "Record: $RECORD_FILE"
exit "$EXIT_CODE"
