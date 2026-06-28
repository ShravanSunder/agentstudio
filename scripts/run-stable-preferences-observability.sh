#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_STACK_HELPER="$HOME/dev/ai-tools/observability/observability-stack"
STACK_HELPER="${AI_TOOLS_OBSERVABILITY_STACK_HELPER:-$DEFAULT_STACK_HELPER}"
COLLECTOR_HEALTH_URL="${AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL:-http://127.0.0.1:13133/}"
OPEN_BIN="${AGENTSTUDIO_OPEN_BIN:-/usr/bin/open}"
PGREP_BIN="${AGENTSTUDIO_PGREP_BIN:-/usr/bin/pgrep}"
LSOF_BIN="${AGENTSTUDIO_LSOF_BIN:-/usr/sbin/lsof}"
CURL_BIN="${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}"
STABLE_ARTIFACT_ROOT="${AGENTSTUDIO_STABLE_ARTIFACT_ROOT:-$HOME/.agentstudio-db/stable-preferences-observability}"
state_file="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/stable-preferences-observability/latest-observability.env}"
export AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE=honor_preferences
# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/observability-control-guards.sh"

fail_on_legacy_observability_env
validate_observability_controls "$DEFAULT_STACK_HELPER" "$STACK_HELPER" "$COLLECTOR_HEALTH_URL"

usage() {
  cat <<'USAGE'
Usage: run-stable-preferences-observability.sh --app <AgentStudio.app> [--detach]

Launches a local stable AgentStudio bundle with observability configured only by
preferences.global.json under an isolated proof data root.
USAGE
}

write_state_value() {
  local key="${1:?missing state key}"
  local value="${2:-}"
  printf '%s=%q\n' "$key" "$value"
}

bundle_path_for_executable() {
  local executable_path="${1:?missing executable path}"
  case "$executable_path" in
    *.app/Contents/MacOS/AgentStudio)
      printf '%s\n' "${executable_path%/Contents/MacOS/AgentStudio}"
      ;;
  esac
}

bundle_release_channel_for_executable() {
  local executable_path="${1:?missing executable path}"
  local bundle_path
  bundle_path="$(bundle_path_for_executable "$executable_path")"
  [ -n "$bundle_path" ] || return 0
  /usr/libexec/PlistBuddy -c 'Print :AgentStudioReleaseChannel' "$bundle_path/Contents/Info.plist" 2>/dev/null || true
}

realpath_or_empty() {
  /usr/bin/python3 - "$1" <<'PY'
import os
import sys

print(os.path.realpath(sys.argv[1]) if sys.argv[1] else "")
PY
}

running_stable_channel_pids() {
  local pids
  pids="$("$PGREP_BIN" -x AgentStudio 2>/dev/null || true)"
  [ -n "$pids" ] || return 0

  printf '%s\n' "$pids" |
    while IFS= read -r pid; do
      local txt_output
      if ! txt_output="$("$LSOF_BIN" -a -p "$pid" -d txt -Fn 2>/dev/null)"; then
        echo "unable to inspect running AgentStudio PID $pid with $LSOF_BIN" >&2
        return 2
      fi
      txt_path="$(awk '/^n/ { print substr($0, 2); exit }' <<<"$txt_output")"
      if [ -z "$txt_path" ]; then
        echo "unable to resolve executable for running AgentStudio PID $pid" >&2
        return 2
      fi
      if [ "$(bundle_release_channel_for_executable "$txt_path")" = "stable" ]; then
        printf '%s\n' "$pid"
      fi
    done
}

running_stable_app_pids() {
  local expected_app_path="${1:?missing stable app path}"
  local expected_binary_path="$expected_app_path/Contents/MacOS/AgentStudio"
  local expected_binary_realpath
  local pids
  expected_binary_realpath="$(realpath_or_empty "$expected_binary_path")"
  pids="$("$PGREP_BIN" -x AgentStudio 2>/dev/null || true)"
  [ -n "$pids" ] || return 0

  printf '%s\n' "$pids" |
    while IFS= read -r pid; do
      local txt_output
      if ! txt_output="$("$LSOF_BIN" -a -p "$pid" -d txt -Fn 2>/dev/null)"; then
        echo "unable to inspect running AgentStudio PID $pid with $LSOF_BIN" >&2
        return 2
      fi
      txt_path="$(awk '/^n/ { print substr($0, 2); exit }' <<<"$txt_output")"
      if [ -z "$txt_path" ]; then
        echo "unable to resolve executable for running AgentStudio PID $pid" >&2
        return 2
      fi
      if [ "$(realpath_or_empty "$txt_path")" = "$expected_binary_realpath" ] &&
        [ "$(bundle_release_channel_for_executable "$txt_path")" = "stable" ]; then
        printf '%s\n' "$pid"
      fi
    done
}

wait_for_stable_app_pid() {
  local expected_app_path="${1:?missing stable app path}"
  local attempts="${AGENTSTUDIO_PID_WAIT_ATTEMPTS:-200}"
  local pid=""

  for _ in $(seq 1 "$attempts"); do
    pid="$(running_stable_app_pids "$expected_app_path" | tail -1 || true)"
    if [ -n "$pid" ]; then
      printf '%s\n' "$pid"
      return 0
    fi
    sleep 0.1
  done

  return 1
}

write_launch_failed_state() {
  local reason="${1:?missing launch failure reason}"
  {
    write_state_value AGENTSTUDIO_OBSERVABILITY_STATUS launch_failed
    write_state_value AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR stable
    write_state_value AGENTSTUDIO_OBSERVABILITY_MARKER "${trace_name:-}"
    write_state_value AGENTSTUDIO_OBSERVABILITY_QUERY_START "${query_start:-}"
    write_state_value AGENTSTUDIO_OBSERVABILITY_REASON "$reason"
    write_state_value AGENTSTUDIO_OBSERVABILITY_APP "${app_path:-}"
    write_state_value AGENTSTUDIO_OBSERVABILITY_DATA_DIR "${launch_data_root:-}"
    write_state_value AGENTSTUDIO_OBSERVABILITY_LOG "${launch_log:-}"
    write_state_value AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE honor_preferences
  } >"$state_file"
}

open_app() {
  local app_path="${1:?missing app path}"
  local launch_log="${2:?missing launch log}"
  local wait_flag="${3:-}"
  shift 3
  local open_args=("$@")

  for attempt in 1 2 3 4 5; do
    if "${clean_open_env[@]}" "$OPEN_BIN" ${wait_flag:+"$wait_flag"} -n "$app_path" \
      --stdout "$launch_log" \
      --stderr "$launch_log" \
      "${open_args[@]}"
    then
      return 0
    fi
    sleep "$attempt"
  done

  return 1
}

app_path=""
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
  usage >&2
  echo "missing required --app <AgentStudio.app>" >&2
  exit 2
fi

binary_path="$app_path/Contents/MacOS/AgentStudio"
mkdir -p "$(dirname "$state_file")"
if [ ! -x "$binary_path" ]; then
  write_launch_failed_state stable_executable_not_found
  echo "AgentStudio stable executable not found: $binary_path" >&2
  echo "observability state: $state_file" >&2
  exit 1
fi
if ! existing_pids="$(running_stable_channel_pids | paste -sd ' ' -)"; then
  write_launch_failed_state duplicate_attribution_failed
  echo "Unable to verify whether AgentStudio stable is already running." >&2
  echo "observability state: $state_file" >&2
  exit 1
fi
if [ -n "$existing_pids" ]; then
  {
    write_state_value AGENTSTUDIO_OBSERVABILITY_STATUS already_running
    write_state_value AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR stable
    write_state_value AGENTSTUDIO_OBSERVABILITY_PID "$existing_pids"
    write_state_value AGENTSTUDIO_OBSERVABILITY_APP "$app_path"
    write_state_value AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE honor_preferences
  } >"$state_file"
  echo "AgentStudio stable is already running: PID(s) $existing_pids" >&2
  echo "observability state: $state_file" >&2
  exit 1
fi
if [ ! -x "$STACK_HELPER" ]; then
  write_launch_failed_state observability_stack_helper_not_executable
  echo "observability stack helper not executable: $STACK_HELPER" >&2
  echo "observability state: $state_file" >&2
  exit 1
fi
if ! "$CURL_BIN" --fail --silent --show-error --max-time 2 "$COLLECTOR_HEALTH_URL" >/dev/null; then
  write_launch_failed_state otlp_collector_unhealthy
  echo "OTLP collector is not healthy at $COLLECTOR_HEALTH_URL" >&2
  echo "observability state: $state_file" >&2
  exit 1
fi

trace_name="${AGENTSTUDIO_TRACE_NAME:-stable-preferences-observability-$(date +%s)-$$}"
if ! validate_safe_trace_name "$trace_name" "AGENTSTUDIO_TRACE_NAME for stable preferences proof"; then
  write_launch_failed_state invalid_trace_name
  echo "observability state: $state_file" >&2
  exit 2
fi
trace_proof_token="$(uuidgen | tr '[:upper:]' '[:lower:]')"
trace_dir="${AGENTSTUDIO_TRACE_DIR:-$STABLE_ARTIFACT_ROOT/traces}"
default_launch_parent="$STABLE_ARTIFACT_ROOT/runs"
default_launch_data_root="$default_launch_parent/$trace_name"
if [ -n "${AGENTSTUDIO_STABLE_DATA_DIR:-}" ]; then
  if [ "${AGENTSTUDIO_OBSERVABILITY_ALLOW_DATA_ROOT_ESCAPE:-0}" != "1" ] &&
    ! assert_child_path_under_parent "$default_launch_parent" "$AGENTSTUDIO_STABLE_DATA_DIR" AGENTSTUDIO_STABLE_DATA_DIR; then
    write_launch_failed_state invalid_data_root
    echo "observability state: $state_file" >&2
    exit 2
  fi
  launch_data_root="$AGENTSTUDIO_STABLE_DATA_DIR"
else
  if ! assert_child_path_under_parent "$default_launch_parent" "$default_launch_data_root" AGENTSTUDIO_STABLE_DATA_DIR; then
    write_launch_failed_state invalid_trace_name
    echo "observability state: $state_file" >&2
    exit 2
  fi
  launch_data_root="$default_launch_data_root"
fi
preferences_file="$launch_data_root/preferences.global.json"
otlp_endpoint="$(/usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$STACK_HELPER" collector-url)"
if ! validate_loopback_url OTEL_EXPORTER_OTLP_ENDPOINT "$otlp_endpoint"; then
  write_launch_failed_state non_loopback_otlp_endpoint
  echo "observability state: $state_file" >&2
  exit 2
fi
launch_log="${AGENTSTUDIO_OBSERVABILITY_LAUNCH_LOG:-$STABLE_ARTIFACT_ROOT/logs/$trace_name.log}"

mkdir -p "$launch_data_root" "$trace_dir" "$(dirname "$launch_log")"
cat >"$preferences_file" <<JSON
{
  "schemaVersion": 1,
  "observability": {
    "enabled": true,
    "traceTags": "*",
    "traceBackend": "otlp",
    "traceFlush": "buffered",
    "otlpEndpoint": "$otlp_endpoint"
  }
}
JSON
chmod 600 "$preferences_file"
: >"$launch_log"
query_start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  write_state_value AGENTSTUDIO_OBSERVABILITY_MARKER "$trace_name"
  write_state_value AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN "$trace_proof_token"
  write_state_value AGENTSTUDIO_OBSERVABILITY_QUERY_START "$query_start"
  write_state_value AGENTSTUDIO_OBSERVABILITY_APP "$app_path"
  write_state_value AGENTSTUDIO_OBSERVABILITY_DATA_DIR "$launch_data_root"
  write_state_value AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE honor_preferences
} >"$state_file"

clean_open_env=(
  /usr/bin/env
  -i
  "HOME=$HOME"
  "USER=${USER:-$(id -un)}"
  "LOGNAME=${LOGNAME:-${USER:-$(id -un)}}"
  "SHELL=${SHELL:-/bin/zsh}"
  "TMPDIR=${TMPDIR:-/tmp}"
  "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
)

open_env_args=(
  --env "AGENTSTUDIO_DATA_DIR=$launch_data_root"
  --env "AGENTSTUDIO_TRACE_NAME=$trace_name"
  --env "AGENTSTUDIO_TRACE_PROOF_TOKEN=$trace_proof_token"
  --env "AGENTSTUDIO_TRACE_DIR=$trace_dir"
)

echo "launching stable preferences proof with OTLP collector: $otlp_endpoint"
echo "app: $app_path"
echo "data root: $launch_data_root"
echo "marker: $trace_name"

if [ "$detach" = true ]; then
  if ! open_app "$app_path" "$launch_log" "" "${open_env_args[@]}"; then
    write_launch_failed_state launchservices_open_failed
    echo "LaunchServices open failed for stable app." >&2
    echo "observability state: $state_file" >&2
    exit 1
  fi
  if ! pid="$(wait_for_stable_app_pid "$app_path")"; then
    write_launch_failed_state launchservices_pid_not_found
    echo "LaunchServices started but AgentStudio stable PID was not found." >&2
    echo "observability state: $state_file" >&2
    exit 1
  fi
  echo "pid: $pid"
else
  open_app "$app_path" "$launch_log" "-W" "${open_env_args[@]}" &
  open_pid=$!
  if ! pid="$(wait_for_stable_app_pid "$app_path")"; then
    kill "$open_pid" >/dev/null 2>&1 || true
    wait "$open_pid" >/dev/null 2>&1 || true
    write_launch_failed_state launchservices_pid_not_found
    echo "LaunchServices started but AgentStudio stable PID was not found." >&2
    echo "observability state: $state_file" >&2
    exit 1
  fi
  echo "pid: $pid"
fi

{
  write_state_value AGENTSTUDIO_OBSERVABILITY_STATUS running
  write_state_value AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR stable
  write_state_value AGENTSTUDIO_OBSERVABILITY_PID "$pid"
} >>"$state_file"
echo "log: $launch_log"
echo "observability state: $state_file"

if [ "$detach" = false ]; then
  terminate_child() {
    kill "$pid" >/dev/null 2>&1 || true
    wait "$open_pid" >/dev/null 2>&1 || true
    exit 0
  }
  trap terminate_child INT TERM
  set +e
  wait "$open_pid"
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
