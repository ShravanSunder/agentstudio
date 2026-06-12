#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_HELPER="${SHRAVAN_OBSERVABILITY_STACK_HELPER:-$HOME/dev/devfiles/shared/observability/observability-stack}"
COLLECTOR_HEALTH_URL="${SHRAVAN_OBSERVABILITY_COLLECTOR_HEALTH_URL:-http://127.0.0.1:13133/}"

usage() {
  cat <<'USAGE'
Usage: run-debug-observability.sh [--build-path <dir>] [--skip-build] [--detach]

Builds the debug AgentStudio binary and launches AgentStudio with full trace
tags exported to the already-running shared Victoria/OTel stack. This helper
does not start observability services; run `mise run observability:up` first.
USAGE
}

build_path="${AGENTSTUDIO_DEBUG_BUILD_PATH:-.build-agent-review}"
skip_build=false
detach=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --build-path)
      build_path="${2:?missing value for --build-path}"
      shift 2
      ;;
    --skip-build)
      skip_build=true
      shift
      ;;
    --detach)
      detach=true
      shift
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

cd "$PROJECT_ROOT"

if [ ! -x "$STACK_HELPER" ]; then
  echo "observability stack helper not executable: $STACK_HELPER" >&2
  exit 1
fi

if ! curl --fail --silent --show-error --max-time 2 "$COLLECTOR_HEALTH_URL" >/dev/null; then
  echo "OTLP collector is not healthy at $COLLECTOR_HEALTH_URL" >&2
  echo "Run: mise run observability:up" >&2
  exit 1
fi

if [ "$skip_build" = false ]; then
  swift build --build-path "$build_path"
fi

binary_path="$build_path/debug/AgentStudio"
if [ ! -x "$binary_path" ]; then
  echo "debug AgentStudio executable not found: $binary_path" >&2
  exit 1
fi

export AGENTSTUDIO_TRACE_TAGS="${AGENTSTUDIO_TRACE_TAGS:-*}"
export AGENTSTUDIO_TRACE_FLUSH="${AGENTSTUDIO_TRACE_FLUSH:-immediate}"
export AGENTSTUDIO_TRACE_BACKEND=otlp
export AGENTSTUDIO_TRACE_NAME="${AGENTSTUDIO_TRACE_NAME:-debug-observability-$(date +%s)-$$}"
export AGENTSTUDIO_TRACE_DIR="${AGENTSTUDIO_TRACE_DIR:-$PROJECT_ROOT/tmp/debug-observability/traces}"
export OTEL_EXPORTER_OTLP_ENDPOINT="$("$STACK_HELPER" collector-url)"
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf

launch_log="${AGENTSTUDIO_OBSERVABILITY_LAUNCH_LOG:-$PROJECT_ROOT/tmp/debug-observability/$AGENTSTUDIO_TRACE_NAME.log}"
state_file="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
mkdir -p "$(dirname "$launch_log")" "$(dirname "$state_file")" "$AGENTSTUDIO_TRACE_DIR"
: >"$launch_log"
query_start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "launching debug with OTLP collector: $OTEL_EXPORTER_OTLP_ENDPOINT"
echo "binary: $binary_path"
echo "marker: $AGENTSTUDIO_TRACE_NAME"

if [ "$detach" = true ]; then
  nohup "$binary_path" >>"$launch_log" 2>&1 &
  pid=$!
else
  "$binary_path" >>"$launch_log" 2>&1 &
  pid=$!
fi

{
  printf 'AGENTSTUDIO_OBSERVABILITY_MARKER=%s\n' "$AGENTSTUDIO_TRACE_NAME"
  printf 'AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR=debug\n'
  printf 'AGENTSTUDIO_OBSERVABILITY_QUERY_START=%s\n' "$query_start"
  printf 'AGENTSTUDIO_OBSERVABILITY_PID=%s\n' "$pid"
  printf 'AGENTSTUDIO_OBSERVABILITY_LOG=%s\n' "$launch_log"
  printf 'AGENTSTUDIO_OBSERVABILITY_BUILD_PATH=%s\n' "$build_path"
} >"$state_file"

echo "pid: $pid"
echo "log: $launch_log"
echo "observability state: $state_file"

if [ "$detach" = false ]; then
  terminate_child() {
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
    exit 0
  }
  trap terminate_child INT TERM
  set +e
  wait "$pid"
  child_status=$?
  set -e
  case "$child_status" in
    0|130|143)
      exit 0
      ;;
    *)
      exit "$child_status"
      ;;
  esac
fi
