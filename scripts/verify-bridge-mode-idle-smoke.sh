#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
CURL_BIN="${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}"
IDLE_MINUTES="${AGENTSTUDIO_BRIDGE_IDLE_MINUTES:-3}"
IDLE_POLL_SECONDS="${AGENTSTUDIO_BRIDGE_IDLE_POLL_SECONDS:-5}"
IDLE_CONTENT_LOAD_CEILING="${AGENTSTUDIO_BRIDGE_IDLE_CONTENT_LOAD_CEILING:-0}"
EXPECTED_STARTUP_ACTION="bridge-review-to-file-view-observability-smoke"

dry_run=false

usage() {
  cat <<'USAGE'
Usage: verify-bridge-mode-idle-smoke.sh [--dry-run]

Verifies Bridge review/file mode-switch stability and idle gating from a
launcher-driven debug app. This script does not launch AgentStudio. Start with:

  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-to-file-view-observability-smoke \
    mise run run-debug-observability -- --detach

Then run this verifier.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

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

validate_loopback_url AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL "$LOGS_QUERY_URL"

decode_state_value() {
  local raw_value="${1:-}"
  /usr/bin/python3 - "$raw_value" <<'PY'
import shlex
import sys

try:
    parsed = shlex.split(sys.argv[1])
except ValueError:
    parsed = []
print(parsed[0] if parsed else "")
PY
}

portable_utc_time() {
  local macos_offset="$1"
  local gnu_offset="$2"
  date -u -v"${macos_offset}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null ||
    date -u -d "$gnu_offset" +"%Y-%m-%dT%H:%M:%SZ"
}

unix_now() {
  date -u +"%s"
}

utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

state_marker=""
state_query_start=""
state_startup_diagnostic_action=""
state_status=""
state_pid=""
if [ -f "$STATE_FILE" ]; then
  while IFS='=' read -r key value; do
    decoded_value="$(decode_state_value "$value")"
    case "$key" in
      AGENTSTUDIO_OBSERVABILITY_MARKER)
        state_marker="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_QUERY_START)
        state_query_start="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION)
        state_startup_diagnostic_action="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_STATUS)
        state_status="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_PID)
        state_pid="$decoded_value"
        ;;
    esac
  done <"$STATE_FILE"
fi

MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-$state_marker}"
STARTUP_DIAGNOSTIC_ACTION="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$state_startup_diagnostic_action}"
QUERY_START="${AGENTSTUDIO_OBSERVABILITY_QUERY_START:-${state_query_start:-$(portable_utc_time -4H '4 hours ago')}}"
QUERY_END="${AGENTSTUDIO_OBSERVABILITY_QUERY_END:-$(portable_utc_time +5M '5 minutes')}"

if [ -z "$MARKER" ]; then
  if [ "$dry_run" = true ]; then
    MARKER="dry-run-mode-idle-marker"
  else
    echo "missing AgentStudio debug observability marker; run the Bridge mode-idle debug app first" >&2
    exit 1
  fi
fi

if [ -z "$STARTUP_DIAGNOSTIC_ACTION" ] && [ "$dry_run" = true ]; then
  STARTUP_DIAGNOSTIC_ACTION="$EXPECTED_STARTUP_ACTION"
fi

if [ "$STARTUP_DIAGNOSTIC_ACTION" != "$EXPECTED_STARTUP_ACTION" ]; then
  echo "Bridge mode idle smoke requires startup action $EXPECTED_STARTUP_ACTION" >&2
  echo "actual: ${STARTUP_DIAGNOSTIC_ACTION:-<missing>}" >&2
  echo "state file: $STATE_FILE" >&2
  exit 1
fi

logsql_escape_exact_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf '%s' "$value"
}

logsql_exact_filter() {
  local field_name="$1"
  local field_value="$2"
  printf '%s:="%s"' "$field_name" "$(logsql_escape_exact_value "$field_value")"
}

query_logs_between() {
  local logsql="$1"
  local start_time="$2"
  local end_time="$3"
  "$CURL_BIN" --fail --silent --show-error --max-time 5 --get \
    --data-urlencode "query=$logsql" \
    --data-urlencode "start=$start_time" \
    --data-urlencode "end=$end_time" \
    "$LOGS_QUERY_URL"
}

query_logs() {
  query_logs_between "$1" "$QUERY_START" "$QUERY_END"
}

count_log_records_between() {
  local logsql="$1"
  local start_time="$2"
  local end_time="$3"
  local response
  response="$(query_logs_between "$logsql" "$start_time" "$end_time")"
  /usr/bin/python3 - "$response" <<'PY'
import sys

payload = sys.argv[1]
print(sum(1 for line in payload.splitlines() if line.strip()))
PY
}

count_log_records() {
  count_log_records_between "$1" "$QUERY_START" "$QUERY_END"
}

json_truthy_field() {
  local field_name="$1"
  local payload="$2"
  /usr/bin/python3 - "$field_name" "$payload" <<'PY'
import json
import sys

field_name, payload = sys.argv[1], sys.argv[2]
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        continue
    if record.get(field_name) is True or record.get(field_name) == "true":
        sys.exit(0)
sys.exit(1)
PY
}

json_field_at_least() {
  local field_name="$1"
  local minimum="$2"
  local payload="$3"
  /usr/bin/python3 - "$field_name" "$minimum" "$payload" <<'PY'
import json
import sys

field_name, minimum, payload = sys.argv[1], int(sys.argv[2]), sys.argv[3]
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        record = json.loads(line)
        value = int(record.get(field_name, 0))
    except (json.JSONDecodeError, TypeError, ValueError):
        continue
    if value >= minimum:
        sys.exit(0)
sys.exit(1)
PY
}

count_reopen_unsignaled_intake_rejects() {
  local payload="$1"
  /usr/bin/python3 - "$payload" <<'PY'
import json
import sys

payload = sys.argv[1]
count = 0
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        continue
    value = record.get("agentstudio.bridge.reopen_signaled")
    if value is False or value == "false":
        count += 1
print(count)
PY
}

count_invalid_active_viewer_rejections() {
  local payload="$1"
  /usr/bin/python3 - "$payload" <<'PY'
import json
import sys

allowed = {"stale_generation", "stale_sequence", "session_reset"}
payload = sys.argv[1]
invalid = 0
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        continue
    reason = record.get("agentstudio.bridge.active_viewer.signal_rejection_reason")
    if reason not in allowed:
        invalid += 1
print(invalid)
PY
}

assertion_failures=0

pass_assertion() {
  local name="$1"
  local detail="$2"
  printf 'PASS %s: %s\n' "$name" "$detail"
}

fail_assertion() {
  local name="$1"
  local detail="$2"
  printf 'FAIL %s: %s\n' "$name" "$detail" >&2
  assertion_failures=$((assertion_failures + 1))
}

assert_zero() {
  local name="$1"
  local observed="$2"
  if [ "$observed" = "0" ] || [ "$observed" = "0.0" ]; then
    pass_assertion "$name" "observed=$observed"
  else
    fail_assertion "$name" "observed=$observed expected=0"
  fi
}

assert_lte() {
  local name="$1"
  local observed="$2"
  local ceiling="$3"
  if /usr/bin/python3 - "$observed" "$ceiling" <<'PY'
import sys

observed = float(sys.argv[1])
ceiling = float(sys.argv[2])
sys.exit(0 if observed <= ceiling else 1)
PY
  then
    pass_assertion "$name" "observed=$observed ceiling=$ceiling"
  else
    fail_assertion "$name" "observed=$observed ceiling=$ceiling"
  fi
}

require_process_alive() {
  local label="$1"
  case "$state_pid" in
    ''|*[!0-9]*)
      echo "AgentStudio debug observability state missing numeric PID for $label" >&2
      echo "state file: $STATE_FILE" >&2
      exit 1
      ;;
  esac
  if ! kill -0 "$state_pid" >/dev/null 2>&1; then
    echo "AgentStudio debug process is not alive for $label: PID $state_pid" >&2
    echo "state file: $STATE_FILE" >&2
    exit 1
  fi
}

wait_for_idle_wall_coverage() {
  local idle_seconds="$1"
  local started_epoch="$2"
  local marker_probe_query="$3"
  local elapsed=0
  while [ "$elapsed" -lt "$idle_seconds" ]; do
    require_process_alive "idle coverage poll"
    query_logs "$marker_probe_query | fields _msg | limit 1" >/dev/null
    read -r -t "$IDLE_POLL_SECONDS" _ </dev/null || true
    elapsed=$(( $(unix_now) - started_epoch ))
  done
}

marker_filter="$(logsql_exact_filter agent.proof.marker "$MARKER")"
action_filter="$(logsql_exact_filter agentstudio.startup_diagnostic.action "$STARTUP_DIAGNOSTIC_ACTION")"
base_query="service.name:AgentStudio dev.runtime.flavor:debug $marker_filter"
diagnostic_completed_query="$base_query $action_filter _msg:app.startup_diagnostic_action.completed"
content_load_query="$base_query _msg:performance.bridge.swift.content_load"
intake_reject_query="$base_query _msg:performance.bridge.web.worktree_file_intake_reject"
active_viewer_rejected_query="$base_query _msg:performance.bridge.swift.active_viewer_mode_signal_rejected"

dry_run_queries=(
  "$diagnostic_completed_query | limit 0"
  "$content_load_query | limit 0"
  "$intake_reject_query | limit 0"
  "$active_viewer_rejected_query | limit 0"
  "$base_query | limit 0"
)

if [ "$dry_run" = true ]; then
  for dry_run_query in "${dry_run_queries[@]}"; do
    query_logs "$dry_run_query" >/dev/null
  done
  echo "dry-run ok: mode-idle LogSQL probes validated"
  echo "marker=$MARKER"
  echo "startup_action=$STARTUP_DIAGNOSTIC_ACTION"
  echo "queries=${#dry_run_queries[@]}"
  exit 0
fi

if [ "$state_status" != "running" ]; then
  echo "AgentStudio debug observability state is not running: ${state_status:-<missing>}" >&2
  echo "state file: $STATE_FILE" >&2
  exit 1
fi

require_process_alive "process alive at start"
"$PROJECT_ROOT/scripts/verify-debug-observability.sh" >/dev/null

idle_start_epoch="$(unix_now)"
idle_query_start="$(utc_now)"
idle_seconds="$(/usr/bin/python3 - "$IDLE_MINUTES" <<'PY'
import math
import sys

minutes = float(sys.argv[1])
seconds = max(0, int(math.ceil(minutes * 60)))
print(seconds)
PY
)"

wait_for_idle_wall_coverage "$idle_seconds" "$idle_start_epoch" "$base_query"
idle_query_end="$(utc_now)"
require_process_alive "process alive at end"
pass_assertion "process alive at end" "pid=$state_pid idle_seconds=$idle_seconds"

diagnostic_completed_response="$(
  query_logs "$diagnostic_completed_query | fields _msg,agentstudio.startup_diagnostic.bridge.file_view.mode_switch.count,agentstudio.startup_diagnostic.bridge.file_view.mode_switch.final_file_selected,agentstudio.startup_diagnostic.render_proof.succeeded | limit 20"
)"
if json_field_at_least \
  "agentstudio.startup_diagnostic.bridge.file_view.mode_switch.count" \
  4 \
  "$diagnostic_completed_response" &&
  json_truthy_field \
    "agentstudio.startup_diagnostic.bridge.file_view.mode_switch.final_file_selected" \
    "$diagnostic_completed_response"; then
  pass_assertion "active_viewer_mode signals accepted" "mode_switch_count>=4 final_file_selected=true"
else
  fail_assertion "active_viewer_mode signals accepted" "mode switch diagnostic fields missing or incomplete"
fi

idle_content_load_count="$(
  count_log_records_between \
    "$content_load_query | fields _msg,agentstudio.bridge.transport,agentstudio.bridge.content.role | limit 200" \
    "$idle_query_start" \
    "$idle_query_end"
)"
idle_content_load_rate="$(
  /usr/bin/python3 - "$idle_content_load_count" "$idle_seconds" <<'PY'
import sys

count = float(sys.argv[1])
seconds = max(float(sys.argv[2]), 1.0)
print(f"{count / (seconds / 60.0):.3f}")
PY
)"
assert_lte "content_load rate is zero during idle" "$idle_content_load_count" "$IDLE_CONTENT_LOAD_CEILING"

intake_reject_response="$(
  query_logs "$intake_reject_query | fields _msg,agentstudio.bridge.result_reason,agentstudio.bridge.reopen_signaled,agentstudio.bridge.stream_id_matches | limit 200"
)"
intake_reject_count="$(/usr/bin/python3 - "$intake_reject_response" <<'PY'
import sys

print(sum(1 for line in sys.argv[1].splitlines() if line.strip()))
PY
)"
unhealed_intake_reject_count="$(count_reopen_unsignaled_intake_rejects "$intake_reject_response")"
assert_zero "zero unhealed intake rejects" "$unhealed_intake_reject_count"

active_viewer_rejection_response="$(
  query_logs "$active_viewer_rejected_query | fields _msg,agentstudio.bridge.active_viewer.signal_rejection_reason,agentstudio.bridge.active_viewer.mode,agentstudio.bridge.active_source.protocol | limit 200"
)"
active_viewer_rejection_count="$(/usr/bin/python3 - "$active_viewer_rejection_response" <<'PY'
import sys

print(sum(1 for line in sys.argv[1].splitlines() if line.strip()))
PY
)"
invalid_active_viewer_rejection_count="$(
  count_invalid_active_viewer_rejections "$active_viewer_rejection_response"
)"
assert_zero "active_viewer_mode rejections only with valid reasons" "$invalid_active_viewer_rejection_count"

final_marker_record_count="$(count_log_records "$base_query | fields _msg | limit 1")"
if [ "$final_marker_record_count" -gt 0 ]; then
  pass_assertion "OTLP exporter alive" "marker logs queryable at end count=$final_marker_record_count"
else
  fail_assertion "OTLP exporter alive" "no marker-scoped log lines queryable at end"
fi

echo "bridge mode idle smoke summary:"
echo "marker=$MARKER"
echo "query_window=$QUERY_START..$QUERY_END"
echo "idle_window=$idle_query_start..$idle_query_end"
echo "idle_minutes=$IDLE_MINUTES idle_seconds=$idle_seconds"
echo "content_load_idle_count=$idle_content_load_count content_load_idle_rate_per_minute=$idle_content_load_rate ceiling=$IDLE_CONTENT_LOAD_CEILING"
echo "worktree_file_intake_rejects=$intake_reject_count unhealed=$unhealed_intake_reject_count"
echo "active_viewer_mode_rejections=$active_viewer_rejection_count invalid_reasons=$invalid_active_viewer_rejection_count"
echo "otlp_exporter_marker_records_at_end=$final_marker_record_count"

if [ "$assertion_failures" -ne 0 ]; then
  echo "bridge mode idle smoke failed assertions=$assertion_failures" >&2
  exit 1
fi
