#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: compare-atomlib-v2-performance.sh \
  --baseline-workload <summary.txt> \
  --after-workload <summary.txt> \
  --baseline-interaction <summary.txt> \
  --after-interaction <summary.txt> \
  --output <comparison.txt>

Enforces the AtomLib v2 T9 performance contract:
  - command-bar interaction improves performance.commandbar.items count or p95 by >=50%;
  - at least one repo-cache fanout surface improves count or p95 by >=50%;
  - no targeted surface regresses by more than 10%.
USAGE
}

baseline_workload=""
after_workload=""
baseline_interaction=""
after_interaction=""
output_file=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --baseline-workload)
      baseline_workload="${2:-}"
      shift 2
      ;;
    --after-workload)
      after_workload="${2:-}"
      shift 2
      ;;
    --baseline-interaction)
      baseline_interaction="${2:-}"
      shift 2
      ;;
    --after-interaction)
      after_interaction="${2:-}"
      shift 2
      ;;
    --output)
      output_file="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

for required_path in "$baseline_workload" "$after_workload" "$baseline_interaction" "$after_interaction"; do
  if [ -z "$required_path" ] || [ ! -f "$required_path" ]; then
    echo "missing comparison input summary: ${required_path:-<empty>}" >&2
    exit 2
  fi
done
if [ -z "$output_file" ]; then
  echo "missing --output <comparison.txt>" >&2
  exit 2
fi

mkdir -p "$(dirname "$output_file")"

comparison_status=0
/usr/bin/python3 "$PROJECT_ROOT/scripts/compare-atomlib-v2-performance.py" \
  "$baseline_workload" \
  "$after_workload" \
  "$baseline_interaction" \
  "$after_interaction" \
  "$output_file" || comparison_status=$?

if [ -f "$output_file" ]; then
  cat "$output_file"
fi
exit "$comparison_status"
