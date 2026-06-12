#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_HELPER="${SHRAVAN_OBSERVABILITY_STACK_HELPER:-$HOME/dev/devfiles/shared/observability/observability-stack}"
COLLECTOR_HEALTH_URL="${SHRAVAN_OBSERVABILITY_COLLECTOR_HEALTH_URL:-http://127.0.0.1:13133/}"

usage() {
  cat <<'USAGE'
Usage: run-beta-observability.sh [--app <AgentStudio Beta.app>] [--detach]

Launches a beta bundle with full AgentStudio trace tags exported to the
already-running shared Victoria/OTel stack. This helper does not start
observability services; run `mise run observability:up` first. By default the
helper stays attached so task runners do not clean up the launched process
before verification.
USAGE
}

latest_local_beta_bundle() {
  local beta_root="$PROJECT_ROOT/tmp/beta-observability"
  [ -d "$beta_root" ] || return 0

  find "$beta_root" -name 'AgentStudio Beta.app' -type d -prune -print0 2>/dev/null |
    while IFS= read -r -d '' bundle_path; do
      printf '%s\t%s\n' "$(stat -f '%m' "$bundle_path")" "$bundle_path"
    done |
    sort -nr |
    sed -n $'1s/^[^\t]*\t//p'
}

bundle_service_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist" 2>/dev/null || true
}

app_path="${AGENTSTUDIO_BETA_APP:-}"
detach=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      app_path="${2:?missing value for --app}"
      shift 2
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

if [ -z "$app_path" ]; then
  newest_local_bundle="$(latest_local_beta_bundle || true)"
  if [ -n "$newest_local_bundle" ]; then
    app_path="$newest_local_bundle"
  elif [ -d "$PROJECT_ROOT/AgentStudio Beta.app" ]; then
    app_path="$PROJECT_ROOT/AgentStudio Beta.app"
  else
    app_path="/Applications/AgentStudio Beta.app"
  fi
fi

binary_path="$app_path/Contents/MacOS/AgentStudio"
if [ ! -x "$binary_path" ]; then
  echo "AgentStudio beta executable not found: $binary_path" >&2
  exit 1
fi

export AGENTSTUDIO_TRACE_TAGS="${AGENTSTUDIO_TRACE_TAGS:-*}"
export AGENTSTUDIO_TRACE_FLUSH="${AGENTSTUDIO_TRACE_FLUSH:-immediate}"
export AGENTSTUDIO_TRACE_NAME="${AGENTSTUDIO_TRACE_NAME:-beta-observability-$(date +%s)-$$}"
export AGENTSTUDIO_TRACE_DIR="${AGENTSTUDIO_TRACE_DIR:-$PROJECT_ROOT/tmp/beta-observability/traces}"

if [ ! -x "$STACK_HELPER" ]; then
  echo "observability stack helper not executable: $STACK_HELPER" >&2
  exit 1
fi
if ! curl --fail --silent --show-error --max-time 2 "$COLLECTOR_HEALTH_URL" >/dev/null; then
  echo "OTLP collector is not healthy at $COLLECTOR_HEALTH_URL" >&2
  echo "Run: mise run observability:up" >&2
  exit 1
fi

export AGENTSTUDIO_TRACE_BACKEND=otlp
export OTEL_EXPORTER_OTLP_ENDPOINT="$("$STACK_HELPER" collector-url)"
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
echo "launching beta with OTLP collector: $OTEL_EXPORTER_OTLP_ENDPOINT"

echo "app: $app_path"
launch_log="${AGENTSTUDIO_OBSERVABILITY_LAUNCH_LOG:-$PROJECT_ROOT/tmp/beta-observability/$AGENTSTUDIO_TRACE_NAME.log}"
mkdir -p "$(dirname "$launch_log")"
: >"$launch_log"
state_file="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/beta-observability/latest-observability.env}"
mkdir -p "$(dirname "$state_file")"
service_version="$(bundle_service_version)"
{
  printf 'AGENTSTUDIO_OBSERVABILITY_MARKER=%s\n' "$AGENTSTUDIO_TRACE_NAME"
  if [ -n "$service_version" ]; then
    printf 'AGENTSTUDIO_OBSERVABILITY_SERVICE_VERSION=%s\n' "$service_version"
  fi
  printf 'AGENTSTUDIO_OBSERVABILITY_QUERY_START=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} >"$state_file"

if [ "$detach" = true ]; then
  nohup "$binary_path" >>"$launch_log" 2>&1 &
  pid=$!
  echo "pid: $pid"
else
  "$binary_path" >>"$launch_log" 2>&1 &
  pid=$!
  echo "pid: $pid"
fi
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
