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
BETA_ARTIFACT_ROOT="${AGENTSTUDIO_BETA_ARTIFACT_ROOT:-$HOME/.agentstudio-db/beta-observability}"
LEGACY_BETA_ARTIFACT_ROOT="${AGENTSTUDIO_LEGACY_BETA_ARTIFACT_ROOT:-$PROJECT_ROOT/tmp/beta-observability}"

fail_on_legacy_observability_env() {
  local legacy_prefix="SHRAVAN_""OBSERVABILITY_"
  local env_name
  while IFS='=' read -r env_name _; do
    case "$env_name" in
      "$legacy_prefix"*)
        echo "Legacy observability env prefix is no longer supported; use AI_TOOLS_OBSERVABILITY_* instead of $env_name" >&2
        exit 2
        ;;
    esac
  done < <(env)
}

fail_on_legacy_observability_env

canonical_path() {
  /usr/bin/python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

validate_loopback_url() {
  local url_name="${1:?missing url name}"
  local url_value="${2:?missing url value}"
  /usr/bin/python3 - "$url_name" "$url_value" <<'PY'
import sys
from urllib.parse import urlparse

name, value = sys.argv[1], sys.argv[2]
parsed = urlparse(value)
if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
    print(f"{name} must be a loopback http URL: {value}", file=sys.stderr)
    sys.exit(2)
PY
}

validate_observability_controls() {
  validate_loopback_url AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL "$COLLECTOR_HEALTH_URL"
  if [ "${AGENTSTUDIO_OBSERVABILITY_ALLOW_TEST_OVERRIDES:-0}" = "1" ]; then
    return
  fi
  if [ "$(canonical_path "$STACK_HELPER")" != "$(canonical_path "$DEFAULT_STACK_HELPER")" ]; then
    echo "AI_TOOLS_OBSERVABILITY_STACK_HELPER must point to the trusted ai-tools helper: $DEFAULT_STACK_HELPER" >&2
    exit 2
  fi
}

validate_observability_controls

usage() {
  cat <<'USAGE'
Usage: run-beta-observability.sh --app <AgentStudio Beta.app> [--detach]
       run-beta-observability.sh --latest-local [--detach]

Launches a beta bundle with full AgentStudio trace tags exported to the
already-running shared Victoria/OTel stack. This helper does not start
observability services; run `mise run observability:up` first. By default the
helper stays attached to LaunchServices with `open -W` so task runners do not
clean up the launched process before verification.

Release-promotion proof must pass the exact downloaded/notarized beta app with
`--app`. `--latest-local` is only for local diagnostic bundles.
USAGE
}

latest_local_beta_bundle() {
  local primary_bundle
  primary_bundle="$(newest_beta_bundle_in "$BETA_ARTIFACT_ROOT")"
  if [ -n "$primary_bundle" ]; then
    printf '%s\n' "$primary_bundle"
    return 0
  fi

  newest_beta_bundle_in "$LEGACY_BETA_ARTIFACT_ROOT"
}

newest_beta_bundle_in() {
  local beta_root="${1:?missing beta root}"
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

running_beta_channel_pids() {
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
      if [ "$(bundle_release_channel_for_executable "$txt_path")" = "beta" ]; then
        printf '%s\n' "$pid"
      fi
    done
}

running_beta_app_pids() {
  local expected_app_path="${1:?missing beta app path}"
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
        [ "$(bundle_release_channel_for_executable "$txt_path")" = "beta" ]; then
        printf '%s\n' "$pid"
      fi
    done
}

wait_for_beta_app_pid() {
  local expected_app_path="${1:?missing beta app path}"
  local attempts="${2:-${AGENTSTUDIO_PID_WAIT_ATTEMPTS:-200}}"
  local pid=""

  for _ in $(seq 1 "$attempts"); do
    pid="$(running_beta_app_pids "$expected_app_path" | tail -1 || true)"
    if [ -n "$pid" ]; then
      printf '%s\n' "$pid"
      return 0
    fi
    sleep 0.1
  done

  return 1
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

write_launch_failed_state() {
  local reason="${1:?missing launch failure reason}"
  {
    write_state_value AGENTSTUDIO_OBSERVABILITY_STATUS launch_failed
    write_state_value AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR beta
    write_state_value AGENTSTUDIO_OBSERVABILITY_MARKER "${trace_name:-}"
    if [ -n "${service_version:-}" ]; then
      write_state_value AGENTSTUDIO_OBSERVABILITY_SERVICE_VERSION "$service_version"
    fi
    write_state_value AGENTSTUDIO_OBSERVABILITY_QUERY_START "${query_start:-}"
    write_state_value AGENTSTUDIO_OBSERVABILITY_REASON "$reason"
    write_state_value AGENTSTUDIO_OBSERVABILITY_APP "${app_path:-}"
    write_state_value AGENTSTUDIO_OBSERVABILITY_DATA_DIR "${launch_data_root:-}"
    write_state_value AGENTSTUDIO_OBSERVABILITY_LOG "${launch_log:-}"
    if [ -n "${preferences_mode:-}" ]; then
      write_state_value AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE "$preferences_mode"
    fi
  } >"$state_file"
}

app_path="${AGENTSTUDIO_BETA_APP:-}"
detach=false
use_latest_local=false
state_file="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/beta-observability/latest-observability.env}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      app_path="${2:?missing value for --app}"
      shift 2
      ;;
    --latest-local)
      use_latest_local=true
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
preferences_mode="${AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE:-}"
if [ -n "$preferences_mode" ] && [ "$preferences_mode" != "honor_preferences" ]; then
  mkdir -p "$(dirname "$state_file")"
  write_launch_failed_state invalid_preferences_mode
  echo "invalid AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE: $preferences_mode" >&2
  echo "observability state: $state_file" >&2
  exit 2
fi

if [ -z "$app_path" ]; then
  if [ "$use_latest_local" = true ]; then
    newest_local_bundle="$(latest_local_beta_bundle || true)"
    if [ -n "$newest_local_bundle" ]; then
      app_path="$newest_local_bundle"
    else
      mkdir -p "$(dirname "$state_file")"
      write_launch_failed_state beta_app_not_found
      echo "No local AgentStudio Beta.app artifact found under $BETA_ARTIFACT_ROOT or $LEGACY_BETA_ARTIFACT_ROOT" >&2
      echo "Run: mise run create-beta-app-bundle" >&2
      echo "observability state: $state_file" >&2
      exit 1
    fi
  else
    usage >&2
    echo "missing required --app <AgentStudio Beta.app> (or --latest-local for local diagnostics)" >&2
    exit 2
  fi
elif [ "$use_latest_local" = true ]; then
  usage >&2
  echo "use either --app or --latest-local, not both" >&2
  exit 2
fi

binary_path="$app_path/Contents/MacOS/AgentStudio"
if [ ! -x "$binary_path" ]; then
  mkdir -p "$(dirname "$state_file")"
  write_launch_failed_state beta_executable_not_found
  echo "AgentStudio beta executable not found: $binary_path" >&2
  echo "observability state: $state_file" >&2
  exit 1
fi
if ! existing_pids="$(running_beta_channel_pids | paste -sd ' ' -)"; then
  mkdir -p "$(dirname "$state_file")"
  {
    write_state_value AGENTSTUDIO_OBSERVABILITY_STATUS launch_failed
    write_state_value AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR beta
    write_state_value AGENTSTUDIO_OBSERVABILITY_REASON duplicate_attribution_failed
    write_state_value AGENTSTUDIO_OBSERVABILITY_APP "$app_path"
    if [ -n "${preferences_mode:-}" ]; then
      write_state_value AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE "$preferences_mode"
    fi
  } >"$state_file"
  echo "Unable to verify whether AgentStudio beta is already running." >&2
  echo "Refusing to launch because duplicate beta apps would share data and zmx roots." >&2
  echo "observability state: $state_file" >&2
  exit 1
fi
if [ -n "$existing_pids" ]; then
  mkdir -p "$(dirname "$state_file")"
  {
    write_state_value AGENTSTUDIO_OBSERVABILITY_STATUS already_running
    write_state_value AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR beta
    write_state_value AGENTSTUDIO_OBSERVABILITY_PID "$existing_pids"
    write_state_value AGENTSTUDIO_OBSERVABILITY_APP "$app_path"
    if [ -n "${preferences_mode:-}" ]; then
      write_state_value AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE "$preferences_mode"
    fi
  } >"$state_file"
  echo "AgentStudio beta is already running: PID(s) $existing_pids" >&2
  echo "Quit that beta app before launching another observability run." >&2
  echo "observability state: $state_file" >&2
  exit 1
fi

trace_tags="${AGENTSTUDIO_TRACE_TAGS:-*}"
trace_flush="${AGENTSTUDIO_TRACE_FLUSH:-immediate}"
trace_name="${AGENTSTUDIO_TRACE_NAME:-beta-observability-$(date +%s)-$$}"
trace_proof_token="$(uuidgen | tr '[:upper:]' '[:lower:]')"
trace_dir="${AGENTSTUDIO_TRACE_DIR:-$BETA_ARTIFACT_ROOT/traces}"
if [ "$preferences_mode" = "honor_preferences" ]; then
  launch_data_root="${AGENTSTUDIO_BETA_DATA_DIR:-}"
  if [ -z "$launch_data_root" ]; then
    mkdir -p "$(dirname "$state_file")"
    write_launch_failed_state missing_beta_preferences_data_dir
    echo "AGENTSTUDIO_BETA_DATA_DIR is required for preference-honoring beta proof" >&2
    echo "observability state: $state_file" >&2
    exit 2
  fi
fi

if [ ! -x "$STACK_HELPER" ]; then
  mkdir -p "$(dirname "$state_file")"
  write_launch_failed_state observability_stack_helper_not_executable
  echo "observability stack helper not executable: $STACK_HELPER" >&2
  echo "observability state: $state_file" >&2
  exit 1
fi
if ! "$CURL_BIN" --fail --silent --show-error --max-time 2 "$COLLECTOR_HEALTH_URL" >/dev/null; then
  mkdir -p "$(dirname "$state_file")"
  write_launch_failed_state otlp_collector_unhealthy
  echo "OTLP collector is not healthy at $COLLECTOR_HEALTH_URL" >&2
  echo "Run: mise run observability:up" >&2
  echo "observability state: $state_file" >&2
  exit 1
fi

trace_backend=otlp
otlp_endpoint="$(/usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$STACK_HELPER" collector-url)"
otlp_protocol=http/protobuf
echo "launching beta with OTLP collector: $otlp_endpoint"
if [ "$preferences_mode" = "honor_preferences" ]; then
  echo "preferences mode: honor_preferences"
fi

echo "app: $app_path"
launch_log="${AGENTSTUDIO_OBSERVABILITY_LAUNCH_LOG:-$BETA_ARTIFACT_ROOT/logs/$trace_name.log}"
mkdir -p "$(dirname "$launch_log")"
: >"$launch_log"
mkdir -p "$(dirname "$state_file")"
service_version="$(bundle_service_version)"
query_start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
{
  write_state_value AGENTSTUDIO_OBSERVABILITY_MARKER "$trace_name"
  write_state_value AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN "$trace_proof_token"
  if [ -n "$service_version" ]; then
    write_state_value AGENTSTUDIO_OBSERVABILITY_SERVICE_VERSION "$service_version"
  fi
  write_state_value AGENTSTUDIO_OBSERVABILITY_QUERY_START "$query_start"
  write_state_value AGENTSTUDIO_OBSERVABILITY_APP "$app_path"
  write_state_value AGENTSTUDIO_OBSERVABILITY_DATA_DIR "${launch_data_root:-}"
  if [ -n "$preferences_mode" ]; then
    write_state_value AGENTSTUDIO_OBSERVABILITY_PREFERENCES_MODE "$preferences_mode"
  fi
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
    --env "AGENTSTUDIO_TRACE_NAME=$trace_name" \
    --env "AGENTSTUDIO_TRACE_PROOF_TOKEN=$trace_proof_token" \
    --env "AGENTSTUDIO_TRACE_DIR=$trace_dir"
)
if [ "$preferences_mode" = "honor_preferences" ]; then
  open_env_args+=(--env "AGENTSTUDIO_DATA_DIR=$launch_data_root")
else
  open_env_args+=(
    --env "AGENTSTUDIO_TRACE_TAGS=$trace_tags" \
    --env "AGENTSTUDIO_TRACE_FLUSH=$trace_flush" \
    --env "AGENTSTUDIO_TRACE_BACKEND=$trace_backend" \
    --env "OTEL_EXPORTER_OTLP_ENDPOINT=$otlp_endpoint" \
    --env "OTEL_EXPORTER_OTLP_PROTOCOL=$otlp_protocol"
  )
fi

if [ "$detach" = true ]; then
  if ! open_app "$app_path" "$launch_log" "" "${open_env_args[@]}"; then
    write_launch_failed_state launchservices_open_failed
    echo "LaunchServices open failed for beta app; GUI observability proof was not started." >&2
    echo "Use an accepted/notarized beta bundle, such as /Applications/AgentStudio Beta.app." >&2
    echo "observability state: $state_file" >&2
    exit 1
  fi
  if ! pid="$(wait_for_beta_app_pid "$app_path")"; then
    write_launch_failed_state launchservices_pid_not_found
    echo "LaunchServices started but AgentStudio beta PID was not found." >&2
    echo "observability state: $state_file" >&2
    exit 1
  fi
  echo "pid: $pid"
else
  open_app "$app_path" "$launch_log" "-W" "${open_env_args[@]}" &
  open_pid=$!
  if ! pid="$(wait_for_beta_app_pid "$app_path")"; then
    if kill -0 "$open_pid" >/dev/null 2>&1; then
      failure_reason=launchservices_pid_not_found
      kill "$open_pid" >/dev/null 2>&1 || true
      wait "$open_pid" >/dev/null 2>&1 || true
    elif wait "$open_pid" >/dev/null 2>&1; then
      failure_reason=launchservices_pid_not_found
    else
      failure_reason=launchservices_open_failed
    fi
    write_launch_failed_state "$failure_reason"
    echo "LaunchServices started but AgentStudio beta PID was not found." >&2
    echo "observability state: $state_file" >&2
    exit 1
  fi
  echo "pid: $pid"
fi
	{
	  write_state_value AGENTSTUDIO_OBSERVABILITY_STATUS running
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
