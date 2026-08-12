#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLE_COUNT="${AGENTSTUDIO_STARTUP_PERFORMANCE_SAMPLE_COUNT:-10}"
COMPLETION_ATTEMPTS="${AGENTSTUDIO_STARTUP_PERFORMANCE_COMPLETION_ATTEMPTS:-45}"
ARTIFACT_ROOT="${AGENTSTUDIO_STARTUP_PERFORMANCE_ARTIFACT_ROOT:-$PROJECT_ROOT/tmp/startup-performance}"
STATE_FILE="$ARTIFACT_ROOT/latest-observability.env"
MARKERS_FILE="$ARTIFACT_ROOT/completed-markers.txt"
dry_run=false

if [ "${1:-}" = "--dry-run" ]; then
  dry_run=true
  shift
fi
if [ "$#" -ne 0 ]; then
  echo "usage: verify-startup-performance-workload.sh [--dry-run]" >&2
  exit 2
fi
if ! [[ "$SAMPLE_COUNT" =~ ^[0-9]+$ ]] || [ "$SAMPLE_COUNT" -lt 10 ]; then
  echo "AGENTSTUDIO_STARTUP_PERFORMANCE_SAMPLE_COUNT must be an integer >= 10" >&2
  exit 2
fi
if ! [[ "$COMPLETION_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$COMPLETION_ATTEMPTS" -lt 1 ]; then
  echo "AGENTSTUDIO_STARTUP_PERFORMANCE_COMPLETION_ATTEMPTS must be an integer >= 1" >&2
  exit 2
fi

echo "sample_count=$SAMPLE_COUNT"
echo "trace_tags=performance,app.startup"
echo "trace_flush=immediate"
echo "startup_diagnostic=command-bar-repo-filter"
echo "completion=app.startup_diagnostic_action.completed"
echo "usable_lane=performance.startup.usable"
echo "renderer_probe=program_instrument_gap"
[ "$dry_run" = false ] || exit 0

decode_assignment() {
  local source="$1"
  local key="$2"
  local raw_value
  raw_value="$(printf '%s\n' "$source" | sed -n "s/^$key=//p" | tail -1)"
  /usr/bin/python3 - "$raw_value" <<'PY'
import shlex
import sys

parts = shlex.split(sys.argv[1]) if sys.argv[1] else []
print(parts[0] if parts else "")
PY
}

state_value() {
  decode_assignment "$(<"$STATE_FILE")" "$1"
}

reset_isolated_debug_root() {
  local identity debug_code data_dir bundle_identifier expected_bundle_identifier
  identity="$("$PROJECT_ROOT/scripts/run-debug-observability.sh" --print-identity)"
  debug_code="$(decode_assignment "$identity" AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE)"
  data_dir="$(decode_assignment "$identity" AGENTSTUDIO_OBSERVABILITY_DATA_DIR)"
  bundle_identifier="$(decode_assignment "$identity" AGENTSTUDIO_OBSERVABILITY_BUNDLE_IDENTIFIER)"
  case "$data_dir" in
    "$HOME/.agentstudio-db/"*) ;;
    *) echo "refusing reset outside isolated debug roots: $data_dir" >&2; exit 1 ;;
  esac
  case "$debug_code" in
    ''|*[!a-z0-9]*) echo "refusing reset with unsafe debug code: $debug_code" >&2; exit 1 ;;
  esac
  expected_bundle_identifier="com.agentstudio.app.debug.d$debug_code"
  if [ "$bundle_identifier" != "$expected_bundle_identifier" ]; then
    echo "refusing reset for mismatched debug bundle identifier: $bundle_identifier" >&2
    exit 1
  fi
  "$PROJECT_ROOT/scripts/run-debug-observability.sh" --preflight-idle
  /bin/rm -rf -- "$data_dir"
}

stop_owned_app() {
  local app_pid="${1:-}"
  case "$app_pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  if kill -0 "$app_pid" >/dev/null 2>&1; then
    kill "$app_pid"
    wait "$app_pid" >/dev/null 2>&1 || true
  fi
}

mkdir -p "$ARTIFACT_ROOT"
: >"$MARKERS_FILE"

for sample_index in $(seq 1 "$SAMPLE_COUNT"); do
  reset_isolated_debug_root
  trace_name="startup-usable-$(/usr/bin/uuidgen | tr '[:upper:]' '[:lower:]')"
  env \
    AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
    AGENTSTUDIO_TRACE_NAME="$trace_name" \
    AGENTSTUDIO_TRACE_TAGS=performance,app.startup \
    AGENTSTUDIO_TRACE_FLUSH=immediate \
    AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=command-bar-repo-filter \
    "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach

  app_pid="$(state_value AGENTSTUDIO_OBSERVABILITY_PID)"
  marker="$(state_value AGENTSTUDIO_OBSERVABILITY_MARKER)"
  completed=false
  for _ in $(seq 1 "$COMPLETION_ATTEMPTS"); do
    if env AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
      "$PROJECT_ROOT/scripts/verify-debug-observability.sh" >/dev/null 2>&1
    then
      completed=true
      break
    fi
    /bin/sleep 1
  done
  if [ "$completed" != true ]; then
    stop_owned_app "$app_pid"
    echo "bounded completion wait expired for sample $sample_index" >&2
    exit 1
  fi
  printf '%s\n' "$marker" >>"$MARKERS_FILE"
  echo "completed_sample=$sample_index marker=$marker"
  stop_owned_app "$app_pid"
done

echo "completed_markers=$MARKERS_FILE"
echo "perf_report_example=mise run perf:report -- --channel debug --baseline <marker> --candidate <marker> --lane performance.startup.usable"
