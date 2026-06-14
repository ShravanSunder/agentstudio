#!/bin/bash
set -euo pipefail

LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
CURL_BIN="${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}"
LSOF_BIN="${AGENTSTUDIO_LSOF_BIN:-/usr/sbin/lsof}"

state_marker=""
state_query_start=""
state_status=""
state_reason=""
state_pid=""
state_debug_code=""
state_launch_method=""
state_app=""
state_executable=""
state_startup_diagnostic_action=""
if [ -f "$STATE_FILE" ]; then
  while IFS='=' read -r key value; do
    decoded_value="$(
      /usr/bin/python3 - "$value" <<'PY'
import shlex
import sys

try:
    parsed = shlex.split(sys.argv[1])
except ValueError:
    parsed = []
print(parsed[0] if parsed else "")
PY
    )"
    case "$key" in
      AGENTSTUDIO_OBSERVABILITY_MARKER)
        state_marker="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_QUERY_START)
        state_query_start="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_STATUS)
        state_status="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_PID)
        state_pid="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE)
        state_debug_code="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD)
        state_launch_method="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_APP)
        state_app="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_EXECUTABLE)
        state_executable="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_REASON)
        state_reason="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION)
        state_startup_diagnostic_action="$decoded_value"
        ;;
    esac
  done <"$STATE_FILE"
fi

if [ "$state_status" = "launch_failed" ] || [ "$state_status" = "already_running" ]; then
  if [ -n "$state_reason" ]; then
    echo "AgentStudio debug observability did not start: $state_status ($state_reason)" >&2
  else
    echo "AgentStudio debug observability did not start: $state_status" >&2
  fi
  echo "state file: $STATE_FILE" >&2
  exit 1
fi

MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-$state_marker}"
if [ -z "$MARKER" ]; then
  echo "missing AgentStudio debug observability marker; run mise run run-debug-observability first" >&2
  exit 1
fi

bundle_path_for_executable() {
  local executable_path="${1:?missing executable path}"
  case "$executable_path" in
    *.app/Contents/MacOS/AgentStudio)
      printf '%s\n' "${executable_path%/Contents/MacOS/AgentStudio}"
      ;;
  esac
}

bundle_identifier_for_executable() {
  local executable_path="${1:?missing executable path}"
  local bundle_path
  bundle_path="$(bundle_path_for_executable "$executable_path")"
  [ -n "$bundle_path" ] || return 0
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_path/Contents/Info.plist" 2>/dev/null || true
}

process_executable_path() {
  local pid="${1:?missing pid}"
  local txt_output
  if ! txt_output="$("$LSOF_BIN" -a -p "$pid" -d txt -Fn 2>/dev/null)"; then
    echo "unable to inspect AgentStudio debug PID $pid with $LSOF_BIN" >&2
    return 1
  fi
  awk '/^n/ { print substr($0, 2); exit }' <<<"$txt_output"
}

realpath_or_empty() {
  /usr/bin/python3 - "$1" <<'PY'
import os
import sys

print(os.path.realpath(sys.argv[1]) if sys.argv[1] else "")
PY
}

require_live_debug_process() {
  if [ "$state_status" != "running" ]; then
    echo "AgentStudio debug observability state is not running: ${state_status:-<missing>}" >&2
    echo "state file: $STATE_FILE" >&2
    exit 1
  fi
  case "$state_pid" in
    ''|*[!0-9]*)
      echo "AgentStudio debug observability state missing numeric PID" >&2
      echo "state file: $STATE_FILE" >&2
      exit 1
      ;;
  esac
  if ! kill -0 "$state_pid" >/dev/null 2>&1; then
    echo "AgentStudio debug observability PID is not running: $state_pid" >&2
    echo "state file: $STATE_FILE" >&2
    exit 1
  fi

  local executable_path
  executable_path="$(process_executable_path "$state_pid")"
  if [ -z "$executable_path" ]; then
    echo "unable to resolve executable for AgentStudio debug PID $state_pid" >&2
    echo "state file: $STATE_FILE" >&2
    exit 1
  fi

  if [ "$state_launch_method" = "direct_executable" ]; then
    local expected_executable actual_executable
    expected_executable="$(realpath_or_empty "$state_executable")"
    actual_executable="$(realpath_or_empty "$executable_path")"
    if [ -z "$expected_executable" ] || [ "$actual_executable" != "$expected_executable" ]; then
      echo "AgentStudio debug observability executable mismatch" >&2
      echo "expected: ${expected_executable:-<missing>}" >&2
      echo "actual: ${actual_executable:-<missing>}" >&2
      echo "state file: $STATE_FILE" >&2
      exit 1
    fi
    return 0
  fi

  if [ -z "$state_debug_code" ]; then
    echo "AgentStudio debug observability state missing debug code" >&2
    echo "state file: $STATE_FILE" >&2
    exit 1
  fi
  local expected_bundle_identifier actual_bundle_identifier
  expected_bundle_identifier="com.agentstudio.app.debug.d$state_debug_code"
  actual_bundle_identifier="$(bundle_identifier_for_executable "$executable_path")"
  if [ "$actual_bundle_identifier" != "$expected_bundle_identifier" ]; then
    echo "AgentStudio debug observability bundle identity mismatch" >&2
    echo "expected: $expected_bundle_identifier" >&2
    echo "actual: ${actual_bundle_identifier:-<missing>}" >&2
    echo "state file: $STATE_FILE" >&2
    exit 1
  fi
}

require_live_debug_process

portable_utc_time() {
  local macos_offset="$1"
  local gnu_offset="$2"
  date -u -v"${macos_offset}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null ||
    date -u -d "$gnu_offset" +"%Y-%m-%dT%H:%M:%SZ"
}

logsql_exact_value_filter() {
  local field="${1:?missing LogSQL field}"
  local value="${2:-}"
  local escaped_value="${value//\\/\\\\}"
  escaped_value="${escaped_value//\"/\\\"}"
  printf '%s:="%s"' "$field" "$escaped_value"
}

QUERY_START="${AGENTSTUDIO_OBSERVABILITY_QUERY_START:-${state_query_start:-$(portable_utc_time -4H '4 hours ago')}}"
QUERY_END="${AGENTSTUDIO_OBSERVABILITY_QUERY_END:-$(portable_utc_time +5M '5 minutes')}"

marker_filter="$(logsql_exact_value_filter agentstudio.trace.name "$MARKER")"
query="service.name:AgentStudio dev.runtime.flavor:debug $marker_filter"

query_logs() {
  local logsql="$1"
  "$CURL_BIN" --fail --silent --show-error --max-time 5 --get \
    --data-urlencode "query=$logsql" \
    --data-urlencode "start=$QUERY_START" \
    --data-urlencode "end=$QUERY_END" \
    "$LOGS_QUERY_URL"
}

positive_response="$(query_logs "$query | fields service.name,service.version,dev.runtime.flavor,_msg | limit 20")"
if [ -z "$positive_response" ]; then
  echo "no AgentStudio debug records found in VictoriaLogs for query window $QUERY_START..$QUERY_END" >&2
  exit 1
fi

startup_response="$(
  query_logs \
    "$query _msg:app.zmx_startup_reconciliation.completed | fields _msg,agentstudio.zmx.startup.inventory_outcome,agentstudio.zmx.startup.live_session_count,agentstudio.zmx.startup.hydrated_anchor_count,agentstudio.zmx.startup.protected_session_count,agentstudio.zmx.startup.unresolved_candidate_count,agentstudio.zmx.startup.unmatched_live_session_count | limit 5"
)"
if [ -z "$startup_response" ]; then
  echo "no startup zmx reconciliation record found in VictoriaLogs for marker $MARKER" >&2
  exit 1
fi

required_startup_fields=(
  agentstudio.zmx.startup.inventory_outcome
  agentstudio.zmx.startup.live_session_count
  agentstudio.zmx.startup.hydrated_anchor_count
  agentstudio.zmx.startup.protected_session_count
  agentstudio.zmx.startup.unresolved_candidate_count
  agentstudio.zmx.startup.unmatched_live_session_count
)

for field in "${required_startup_fields[@]}"; do
  if ! grep -q "\"$field\":" <<<"$startup_response"; then
    echo "startup zmx reconciliation record missing field: $field" >&2
    echo "$startup_response" >&2
    exit 1
  fi
done

if [ "${AGENTSTUDIO_OBSERVABILITY_ALLOW_UNAVAILABLE_ZMX_STARTUP:-0}" != "1" ] &&
  grep -q '"agentstudio.zmx.startup.inventory_outcome":"unavailable"' <<<"$startup_response"; then
  echo "startup zmx reconciliation inventory was unavailable" >&2
  echo "$startup_response" >&2
  exit 1
fi

startup_diagnostic_action="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$state_startup_diagnostic_action}"
if [ -n "$startup_diagnostic_action" ]; then
  startup_diagnostic_action_filter="$(
    logsql_exact_value_filter agentstudio.startup_diagnostic.action "$startup_diagnostic_action"
  )"
  diagnostic_query="$query $startup_diagnostic_action_filter"
  diagnostic_command_response="$(
    query_logs \
      "$diagnostic_query _msg:app.startup_diagnostic_action.command_exercised | fields _msg,agentstudio.startup_diagnostic.action,agentstudio.startup_diagnostic.expected_visible_pane.count,agentstudio.startup_diagnostic.fixture.terminal_view.count,agentstudio.startup_diagnostic.fixture.surface_reference.count,agentstudio.startup_diagnostic.fixture.surface.count,agentstudio.startup_diagnostic.fixture.valid_geometry.count,agentstudio.startup_diagnostic.render_proof.succeeded | limit 5"
  )"
  if [ -z "$diagnostic_command_response" ]; then
    echo "startup diagnostic command_exercised record missing for action $startup_diagnostic_action" >&2
    exit 1
  fi

  diagnostic_completed_response="$(
    query_logs \
      "$diagnostic_query _msg:app.startup_diagnostic_action.completed | fields _msg,agentstudio.startup_diagnostic.action,agentstudio.startup_diagnostic.expected_visible_pane.count,agentstudio.startup_diagnostic.fixture.terminal_view.count,agentstudio.startup_diagnostic.fixture.surface_reference.count,agentstudio.startup_diagnostic.fixture.surface.count,agentstudio.startup_diagnostic.fixture.valid_geometry.count,agentstudio.startup_diagnostic.render_proof.succeeded | limit 5"
  )"
  if [ -z "$diagnostic_completed_response" ]; then
    diagnostic_blocked_response="$(
      query_logs \
        "$diagnostic_query _msg:app.startup_diagnostic_action.blocked | fields _msg,agentstudio.startup_diagnostic.action,agentstudio.startup_diagnostic.skip_reason,agentstudio.startup_diagnostic.expected_visible_pane.count,agentstudio.startup_diagnostic.fixture.terminal_view.count,agentstudio.startup_diagnostic.fixture.surface_reference.count,agentstudio.startup_diagnostic.fixture.surface.count,agentstudio.startup_diagnostic.fixture.valid_geometry.count,agentstudio.startup_diagnostic.render_proof.succeeded | limit 5"
    )"
    diagnostic_skipped_response="$(
      query_logs \
        "$diagnostic_query _msg:app.startup_diagnostic_action.skipped | fields _msg,agentstudio.startup_diagnostic.action,agentstudio.startup_diagnostic.skip_reason | limit 5"
    )"
    echo "startup diagnostic did not complete successfully for action $startup_diagnostic_action" >&2
    if [ -n "$diagnostic_blocked_response" ]; then
      echo "$diagnostic_blocked_response" >&2
    fi
    if [ -n "$diagnostic_skipped_response" ]; then
      echo "$diagnostic_skipped_response" >&2
    fi
    exit 1
  fi
  if ! grep -q '"agentstudio.startup_diagnostic.render_proof.succeeded":true' <<<"$diagnostic_completed_response"; then
    echo "startup diagnostic completed without successful render proof for action $startup_diagnostic_action" >&2
    echo "$diagnostic_completed_response" >&2
    exit 1
  fi
fi

sensitive_fields=(
  agentstudio.session.id
  agentstudio.pane.id
  agentstudio.repo.id
  agentstudio.sqlite.database_path
  agentstudio.surface.id
  agentstudio.trace.name.raw
  agentstudio.worktree.id
  agentstudio.workspace.id
  agentstudio.zmx.session_id
  db.statement
  dev.repo.name
  error
  error.message
  exception.message
  payload
  process.pid
  secret
  token
)

for field in "${sensitive_fields[@]}"; do
  sensitive_response="$(query_logs "$query ${field}:* | limit 1")"
  if [ -n "$sensitive_response" ]; then
    echo "sensitive field survived AgentStudio debug OTLP export: $field" >&2
    echo "$sensitive_response" >&2
    exit 1
  fi
done

echo "debug observability ok:"
sed -n '1,5p' <<<"$startup_response"
