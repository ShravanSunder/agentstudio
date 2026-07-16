#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
CURL_BIN="${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}"
DEBUG_OBSERVABILITY_VERIFIER="$PROJECT_ROOT/scripts/verify-debug-observability.sh"
VERIFY_ATTEMPTS="${AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS:-30}"
VERIFY_RETRY_DELAY_SECONDS="${AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS:-2}"
EXPECTED_STARTUP_ACTION="bridge-product-paint-correlation"

dry_run=false

usage() {
  cat <<'USAGE'
Usage: verify-bridge-product-paint-correlation.sh [--dry-run]

Verifies the marker-scoped real-current-worktree Bridge Review and File paint
correlation result. Launch the current debug app first:

  AGENTSTUDIO_STARTUP_WATCH_FOLDER=<current-worktree> \
  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-product-paint-correlation \
    mise run run-debug-observability -- --detach
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

case "$VERIFY_ATTEMPTS" in
  ''|*[!0-9]*|0)
    echo "AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS must be a positive integer" >&2
    exit 2
    ;;
esac

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
state_proof_token=""
state_query_start=""
state_startup_diagnostic_action=""
if [ -f "$STATE_FILE" ]; then
  while IFS='=' read -r key value; do
    decoded_value="$(decode_state_value "$value")"
    case "$key" in
      AGENTSTUDIO_OBSERVABILITY_MARKER)
        state_marker="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN)
        state_proof_token="$decoded_value"
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
  MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-${state_marker:-dry-run-product-paint-marker}}"
  STARTUP_DIAGNOSTIC_ACTION="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$EXPECTED_STARTUP_ACTION}"
else
  MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-$state_marker}"
  STARTUP_DIAGNOSTIC_ACTION="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$state_startup_diagnostic_action}"
fi
PROOF_TOKEN="${AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN:-$state_proof_token}"
QUERY_START="${AGENTSTUDIO_OBSERVABILITY_QUERY_START:-${state_query_start:-$(portable_utc_time -4H '4 hours ago')}}"
QUERY_END="${AGENTSTUDIO_OBSERVABILITY_QUERY_END:-$(portable_utc_time +5M '5 minutes')}"

if [ -z "$MARKER" ]; then
  echo "missing AgentStudio debug observability marker; launch the paint correlation diagnostic first" >&2
  exit 1
fi
if [ -z "$PROOF_TOKEN" ]; then
  echo "missing AgentStudio debug observability proof token; launch the paint correlation diagnostic first" >&2
  exit 1
fi
if [ "$STARTUP_DIAGNOSTIC_ACTION" != "$EXPECTED_STARTUP_ACTION" ]; then
  echo "product paint correlation proof requires startup action $EXPECTED_STARTUP_ACTION" >&2
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

query_logs() {
  local logsql="$1"
  "$CURL_BIN" --fail --silent --show-error --max-time 5 --get \
    --data-urlencode "query=$logsql" \
    --data-urlencode "start=$QUERY_START" \
    --data-urlencode "end=$QUERY_END" \
    "$LOGS_QUERY_URL"
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

prefix="agentstudio.startup_diagnostic.bridge.product_paint"
render_proof_field="agentstudio.startup_diagnostic.render_proof.succeeded"
proof_fields="$prefix.document_visible,$prefix.frame_live,$prefix.review_selected_identity_matched"
proof_fields="$proof_fields,$prefix.review_source_matched,$prefix.review_source_match.count"
proof_fields="$proof_fields,$prefix.file_mode_activated,$prefix.file_selected_identity_matched"
proof_fields="$proof_fields,$prefix.file_source_matched,$prefix.file_source_match.count,$render_proof_field"

marker_filter="$(logsql_exact_filter agent.proof.marker "$MARKER")"
proof_token_filter="$(logsql_exact_filter agent.proof.launch "$PROOF_TOKEN")"
action_filter="$(logsql_exact_filter agentstudio.startup_diagnostic.action "$STARTUP_DIAGNOSTIC_ACTION")"
base_query="service.name:AgentStudio dev.runtime.flavor:debug $marker_filter $proof_token_filter $action_filter"
completed_query="$base_query _msg:app.startup_diagnostic_action.completed"
blocked_query="$base_query _msg:app.startup_diagnostic_action.blocked"

if [ "$dry_run" = true ]; then
  redacted_proof_token_filter='agent.proof.launch:="<redacted>"'
  redacted_base_query="service.name:AgentStudio dev.runtime.flavor:debug $marker_filter $redacted_proof_token_filter $action_filter"
  redacted_completed_query="$redacted_base_query _msg:app.startup_diagnostic_action.completed"
  echo "dry-run ok: requires exactly one launch-bound completed event"
  echo "dry-run ok: rejects any launch-bound blocked event"
  echo "dry-run ok: requires all paint-correlation booleans true: document_visible, frame_live, review_selected_identity_matched, review_source_matched, file_mode_activated, file_selected_identity_matched, file_source_matched, render_proof.succeeded"
  echo "dry-run ok: requires review and file source match counts greater than zero"
  echo "marker=$MARKER"
  echo "startup_action=$STARTUP_DIAGNOSTIC_ACTION"
  echo "query=$redacted_completed_query | fields _msg,$proof_fields | limit 20"
  exit 0
fi

"$DEBUG_OBSERVABILITY_VERIFIER" >/dev/null

proof_response=""
for ((attempt = 1; attempt <= VERIFY_ATTEMPTS; attempt += 1)); do
  blocked_response="$(query_logs "$blocked_query | fields _msg | limit 20")"
  if [ "$(json_record_count "$blocked_response")" -gt 0 ]; then
    echo "FAILED: real-current-worktree Bridge product paint correlation diagnostic blocked" >&2
    exit 1
  fi

  proof_response="$(query_logs "$completed_query | fields _msg,$proof_fields | limit 20")"
  if [ "$(json_record_count "$proof_response")" -gt 0 ]; then
    break
  fi
  if [ "$attempt" -lt "$VERIFY_ATTEMPTS" ]; then
    sleep "$VERIFY_RETRY_DELAY_SECONDS"
  fi
done

proof_record_count="$(json_record_count "$proof_response")"
if [ "$proof_record_count" -eq 0 ]; then
  echo "FAILED: no completed Bridge product paint correlation event for marker $MARKER" >&2
  exit 1
fi
if [ "$proof_record_count" -ne 1 ]; then
  echo "FAILED: expected exactly one launch-bound Bridge product paint correlation event; observed $proof_record_count" >&2
  exit 1
fi

/usr/bin/python3 - "$proof_response" "$prefix" "$render_proof_field" <<'PY'
import json
import sys

payload, prefix, render_proof_field = sys.argv[1], sys.argv[2], sys.argv[3]

def normalized_bool(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, str) and value.lower() in {"true", "false"}:
        return value.lower() == "true"
    return None

def normalized_int(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str):
        try:
            parsed = float(value)
        except ValueError:
            return None
        return int(parsed) if parsed.is_integer() else None
    return None

records = []
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        records.append(json.loads(line))
    except json.JSONDecodeError:
        continue

if len(records) != 1:
    print("FAILED: expected exactly one decoded paint correlation event", file=sys.stderr)
    sys.exit(1)

record = records[0]
required_boolean_fields = [
    f"{prefix}.document_visible",
    f"{prefix}.frame_live",
    f"{prefix}.review_selected_identity_matched",
    f"{prefix}.review_source_matched",
    f"{prefix}.file_mode_activated",
    f"{prefix}.file_selected_identity_matched",
    f"{prefix}.file_source_matched",
    render_proof_field,
]
required_positive_count_fields = [
    f"{prefix}.review_source_match.count",
    f"{prefix}.file_source_match.count",
]

booleans_match = all(normalized_bool(record.get(field)) is True for field in required_boolean_fields)
counts_match = all(
    (normalized_int(record.get(field)) or 0) > 0
    for field in required_positive_count_fields
)
if booleans_match and counts_match:
    sys.exit(0)

print("FAILED: completed paint correlation event did not satisfy the source-to-DOM/disposition contract", file=sys.stderr)
sys.exit(1)
PY

echo "real-current-worktree Bridge product paint correlation proof PASS"
echo "marker=$MARKER"
echo "query_window=$QUERY_START..$QUERY_END"
echo "review_source_match_count=positive"
echo "file_source_match_count=positive"
