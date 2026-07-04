#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
CURL_BIN="${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}"
EXPECTED_STARTUP_ACTION="bridge-worker-fetch-scheme-smoke"

dry_run=false

usage() {
  cat <<'USAGE'
Usage: verify-bridge-worker-fetch-scheme-smoke.sh [--dry-run]

Verifies marker-scoped VictoriaLogs for the Bridge worker fetch scheme smoke.
This script does not launch AgentStudio. F1 should launch the debug app first:

  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke \
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

state_marker=""
state_query_start=""
state_startup_diagnostic_action=""
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
    esac
  done <"$STATE_FILE"
fi

if [ "$dry_run" = true ]; then
  MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-${state_marker:-dry-run-worker-fetch-marker}}"
  STARTUP_DIAGNOSTIC_ACTION="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$EXPECTED_STARTUP_ACTION}"
else
  MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-$state_marker}"
  STARTUP_DIAGNOSTIC_ACTION="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$state_startup_diagnostic_action}"
fi

QUERY_START="${AGENTSTUDIO_OBSERVABILITY_QUERY_START:-${state_query_start:-$(portable_utc_time -4H '4 hours ago')}}"
QUERY_END="${AGENTSTUDIO_OBSERVABILITY_QUERY_END:-$(portable_utc_time +5M '5 minutes')}"

if [ -z "$MARKER" ]; then
  echo "missing AgentStudio debug observability marker; run the worker fetch smoke debug app first" >&2
  exit 1
fi

if [ "$STARTUP_DIAGNOSTIC_ACTION" != "$EXPECTED_STARTUP_ACTION" ]; then
  echo "Bridge worker fetch scheme smoke requires startup action $EXPECTED_STARTUP_ACTION" >&2
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

json_record_count() {
  /usr/bin/python3 - "$1" <<'PY'
import json
import sys

count = 0
for line in sys.argv[1].splitlines():
    if not line.strip():
        continue
    try:
        json.loads(line)
    except json.JSONDecodeError:
        continue
    count += 1
print(count)
PY
}

max_numeric_field() {
  local field_name="$1"
  local payload="$2"
  /usr/bin/python3 - "$field_name" "$payload" <<'PY'
import json
import sys

field = sys.argv[1]
maximum = 0
for line in sys.argv[2].splitlines():
    if not line.strip():
        continue
    try:
        value = json.loads(line).get(field)
    except json.JSONDecodeError:
        continue
    if isinstance(value, (int, float)):
        maximum = max(maximum, int(value))
print(maximum)
PY
}

has_boolean_field() {
  local field_name="$1"
  local expected_value="$2"
  local payload="$3"
  /usr/bin/python3 - "$field_name" "$expected_value" "$payload" <<'PY'
import json
import sys

field, expected = sys.argv[1], sys.argv[2].lower() == "true"
for line in sys.argv[3].splitlines():
    if not line.strip():
        continue
    try:
        value = json.loads(line).get(field)
    except json.JSONDecodeError:
        continue
    if value is expected:
        sys.exit(0)
sys.exit(1)
PY
}

has_string_field() {
  local field_name="$1"
  local expected_value="$2"
  local payload="$3"
  /usr/bin/python3 - "$field_name" "$expected_value" "$payload" <<'PY'
import json
import sys

field, expected = sys.argv[1], sys.argv[2]
for line in sys.argv[3].splitlines():
    if not line.strip():
        continue
    try:
        value = json.loads(line).get(field)
    except json.JSONDecodeError:
        continue
    if value == expected:
        sys.exit(0)
sys.exit(1)
PY
}

assert_gte() {
  local name="$1"
  local observed="$2"
  local floor="$3"
  if [ "$observed" -ge "$floor" ]; then
    echo "ok: $name observed=$observed floor=$floor"
  else
    echo "FAILED: $name observed=$observed floor=$floor" >&2
    exit 1
  fi
}

assert_true_field() {
  local name="$1"
  local field_name="$2"
  local payload="$3"
  if has_boolean_field "$field_name" true "$payload"; then
    echo "ok: $name"
  else
    echo "FAILED: $name" >&2
    exit 1
  fi
}

assert_string_field() {
  local name="$1"
  local field_name="$2"
  local expected="$3"
  local payload="$4"
  if has_string_field "$field_name" "$expected" "$payload"; then
    echo "ok: $name"
  else
    echo "FAILED: $name expected=$expected" >&2
    exit 1
  fi
}

marker_filter="$(logsql_exact_filter agent.proof.marker "$MARKER")"
action_filter="$(logsql_exact_filter agentstudio.startup_diagnostic.action "$STARTUP_DIAGNOSTIC_ACTION")"
base_query="service.name:AgentStudio dev.runtime.flavor:debug $marker_filter"
diagnostic_completed_query="$base_query $action_filter _msg:app.startup_diagnostic_action.completed"
worker_fetch_fields="agentstudio.startup_diagnostic.bridge.worker_fetch.marker.count,agentstudio.startup_diagnostic.bridge.worker_fetch.content_url.scheme,agentstudio.startup_diagnostic.bridge.worker_fetch.content_resource.kind,agentstudio.startup_diagnostic.bridge.worker_fetch.fetch.succeeded,agentstudio.startup_diagnostic.bridge.worker_fetch.stream.succeeded,agentstudio.startup_diagnostic.bridge.worker_fetch.worker_observed_byte.count,agentstudio.startup_diagnostic.bridge.worker_fetch.stream_first_chunk_byte.count,agentstudio.startup_diagnostic.bridge.worker_fetch.stream_held_open"
worker_fetch_query="$diagnostic_completed_query agentstudio.startup_diagnostic.bridge.worker_fetch.marker.count:* agentstudio.startup_diagnostic.bridge.worker_fetch.worker_observed_byte.count:* agentstudio.startup_diagnostic.bridge.worker_fetch.stream_first_chunk_byte.count:*"

if [ "$dry_run" = true ]; then
  echo "dry-run ok: requires worker fetch marker and byte observation"
  echo "marker=$MARKER"
  echo "startup_action=$STARTUP_DIAGNOSTIC_ACTION"
  echo "query=$worker_fetch_query | fields _msg,$worker_fetch_fields | limit 20"
  exit 0
fi

AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT=1 \
  "$PROJECT_ROOT/scripts/verify-debug-observability.sh" >/dev/null

worker_fetch_response="$(query_logs "$worker_fetch_query | fields _msg,$worker_fetch_fields | limit 20")"
worker_fetch_record_count="$(json_record_count "$worker_fetch_response")"
worker_marker_count="$(max_numeric_field "agentstudio.startup_diagnostic.bridge.worker_fetch.marker.count" "$worker_fetch_response")"
worker_observed_byte_count="$(max_numeric_field "agentstudio.startup_diagnostic.bridge.worker_fetch.worker_observed_byte.count" "$worker_fetch_response")"
stream_first_chunk_byte_count="$(
  max_numeric_field \
    "agentstudio.startup_diagnostic.bridge.worker_fetch.stream_first_chunk_byte.count" \
    "$worker_fetch_response"
)"

assert_gte "worker fetch marker exists" "$worker_fetch_record_count" 1
assert_gte "worker fetch marker count recorded" "$worker_marker_count" 1
assert_string_field \
  "worker-originated request uses content scheme" \
  "agentstudio.startup_diagnostic.bridge.worker_fetch.content_url.scheme" \
  "agentstudio" \
  "$worker_fetch_response"
assert_string_field \
  "worker-originated request uses content resource kind" \
  "agentstudio.startup_diagnostic.bridge.worker_fetch.content_resource.kind" \
  "content" \
  "$worker_fetch_response"
assert_true_field \
  "worker fetch completed successfully" \
  "agentstudio.startup_diagnostic.bridge.worker_fetch.fetch.succeeded" \
  "$worker_fetch_response"
assert_true_field \
  "worker streamed response read completed successfully" \
  "agentstudio.startup_diagnostic.bridge.worker_fetch.stream.succeeded" \
  "$worker_fetch_response"
assert_gte "worker observed returned byte count" "$worker_observed_byte_count" 1
assert_gte "worker observed streamed first chunk byte count" "$stream_first_chunk_byte_count" 1
assert_true_field \
  "worker held streamed response reader open" \
  "agentstudio.startup_diagnostic.bridge.worker_fetch.stream_held_open" \
  "$worker_fetch_response"

echo "bridge worker fetch scheme smoke summary:"
echo "marker=$MARKER"
echo "query_window=$QUERY_START..$QUERY_END"
echo "worker_observed_byte_count=$worker_observed_byte_count"
echo "stream_first_chunk_byte_count=$stream_first_chunk_byte_count"
