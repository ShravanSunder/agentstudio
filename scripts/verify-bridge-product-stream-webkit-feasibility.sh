#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
CURL_BIN="${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}"
DEBUG_OBSERVABILITY_VERIFIER="$PROJECT_ROOT/scripts/verify-debug-observability.sh"
VERIFY_ATTEMPTS="${AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS:-30}"
VERIFY_RETRY_DELAY_SECONDS="${AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS:-2}"
EXPECTED_STARTUP_ACTION="bridge-product-stream-webkit-feasibility"

dry_run=false

usage() {
  cat <<'USAGE'
Usage: verify-bridge-product-stream-webkit-feasibility.sh [--dry-run]

Verifies the marker-scoped packaged WKWebView result for the Bridge product
stream worker-fetch feasibility probe. Launch the current debug app first:

  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-product-stream-webkit-feasibility \
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
  MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-${state_marker:-dry-run-product-stream-marker}}"
  STARTUP_DIAGNOSTIC_ACTION="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$EXPECTED_STARTUP_ACTION}"
else
  MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-$state_marker}"
  STARTUP_DIAGNOSTIC_ACTION="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$state_startup_diagnostic_action}"
fi
PROOF_TOKEN="${AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN:-$state_proof_token}"
QUERY_START="${AGENTSTUDIO_OBSERVABILITY_QUERY_START:-${state_query_start:-$(portable_utc_time -4H '4 hours ago')}}"
QUERY_END="${AGENTSTUDIO_OBSERVABILITY_QUERY_END:-$(portable_utc_time +5M '5 minutes')}"

if [ -z "$MARKER" ]; then
  echo "missing AgentStudio debug observability marker; launch the feasibility diagnostic first" >&2
  exit 1
fi
if [ -z "$PROOF_TOKEN" ]; then
  echo "missing AgentStudio debug observability proof token; launch the feasibility diagnostic first" >&2
  exit 1
fi
if [ "$STARTUP_DIAGNOSTIC_ACTION" != "$EXPECTED_STARTUP_ACTION" ]; then
  echo "product stream feasibility proof requires startup action $EXPECTED_STARTUP_ACTION" >&2
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

first_json_field() {
  local field_name="$1"
  local payload="$2"
  /usr/bin/python3 - "$field_name" "$payload" <<'PY'
import json
import sys

field = sys.argv[1]
for line in sys.argv[2].splitlines():
    if not line.strip():
        continue
    try:
        value = json.loads(line).get(field)
    except json.JSONDecodeError:
        continue
    if value is not None:
        print(str(value).lower() if isinstance(value, bool) else value)
        sys.exit(0)
print("")
PY
}

prefix="agentstudio.startup_diagnostic.bridge.product_stream_webkit"
proof_fields="$prefix.carrier.succeeded,$prefix.authentication_before_body.succeeded,$prefix.body_cap_before_decode.succeeded"
proof_fields="$proof_fields,$prefix.strict_route_decode.succeeded,$prefix.missing_content_length.accepted,$prefix.exact_request_body_bytes.succeeded"
proof_fields="$proof_fields,$prefix.total_body_read.count,$prefix.total_body_read_byte.count,$prefix.total_decode_call.count,$prefix.total_provider_call.count"
proof_fields="$proof_fields,$prefix.unauthorized_body_read.count,$prefix.valid_body_byte.count,$prefix.first_frame_byte.count"
proof_fields="$proof_fields,$prefix.valid_stream_ended,$prefix.worker_start_post.observed,$prefix.worker_observed_exact_frames"
proof_fields="$proof_fields,$prefix.worker_observed_incremental_frames,$prefix.framed_stream.succeeded,$prefix.frame_receipt.count"
proof_fields="$proof_fields,$prefix.worker_observed_cancellation,$prefix.abort_causal_cancellation.succeeded,$prefix.cancellation_event.count"
proof_fields="$proof_fields,$prefix.active_producer.count,$prefix.active_producer_task.count,$prefix.queued_frame.count"
proof_fields="$proof_fields,$prefix.maximum_queued_frame.count,$prefix.producer_overflow.count,$prefix.post_terminal_frame.count,$prefix.failure.reason"

marker_filter="$(logsql_exact_filter agent.proof.marker "$MARKER")"
proof_token_filter="$(logsql_exact_filter agent.proof.launch "$PROOF_TOKEN")"
action_filter="$(logsql_exact_filter agentstudio.startup_diagnostic.action "$STARTUP_DIAGNOSTIC_ACTION")"
base_query="service.name:AgentStudio dev.runtime.flavor:debug $marker_filter $proof_token_filter $action_filter"
completed_query="$base_query _msg:app.startup_diagnostic_action.completed $prefix.carrier.succeeded:*"
blocked_query="$base_query _msg:app.startup_diagnostic_action.blocked $prefix.failure.reason:*"

if [ "$dry_run" = true ]; then
  redacted_proof_token_filter='agent.proof.launch:="<redacted>"'
  redacted_base_query="service.name:AgentStudio dev.runtime.flavor:debug $marker_filter $redacted_proof_token_filter $action_filter"
  redacted_completed_query="$redacted_base_query _msg:app.startup_diagnostic_action.completed $prefix.carrier.succeeded:*"
  echo "dry-run ok: requires authenticated actual-body admission without Content-Length"
  echo "dry-run ok: requires receipt-gated incremental frames"
  echo "dry-run ok: requires abort-causal zero producer residue"
  echo "dry-run ok: requires exactly one launch-bound completed record"
  echo "marker=$MARKER"
  echo "startup_action=$STARTUP_DIAGNOSTIC_ACTION"
  echo "query=$redacted_completed_query | fields _msg,$proof_fields | limit 20"
  exit 0
fi

"$DEBUG_OBSERVABILITY_VERIFIER" >/dev/null

proof_response=""
for ((attempt = 1; attempt <= VERIFY_ATTEMPTS; attempt += 1)); do
  blocked_response="$(query_logs "$blocked_query | fields _msg,$proof_fields | limit 20")"
  if [ "$(json_record_count "$blocked_response")" -gt 0 ]; then
    failure_reason="$(first_json_field "$prefix.failure.reason" "$blocked_response")"
    echo "FAILED: packaged WKWebView product stream feasibility diagnostic blocked" >&2
    echo "failure.reason=${failure_reason:-<missing>}" >&2
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
  echo "FAILED: no completed packaged WKWebView feasibility record for marker $MARKER" >&2
  exit 1
fi
if [ "$proof_record_count" -ne 1 ]; then
  echo "FAILED: expected exactly one launch-bound packaged WKWebView feasibility record; observed $proof_record_count" >&2
  exit 1
fi

/usr/bin/python3 - "$proof_response" "$prefix" <<'PY'
import json
import sys

payload, prefix = sys.argv[1], sys.argv[2]

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

expected_bools = {
    "carrier.succeeded": True,
    "authentication_before_body.succeeded": True,
    "body_cap_before_decode.succeeded": True,
    "strict_route_decode.succeeded": True,
    "missing_content_length.accepted": True,
    "exact_request_body_bytes.succeeded": True,
    "valid_stream_ended": True,
    "worker_start_post.observed": True,
    "worker_observed_exact_frames": True,
    "worker_observed_incremental_frames": True,
    "framed_stream.succeeded": True,
    "worker_observed_cancellation": True,
    "abort_causal_cancellation.succeeded": True,
}
expected_ints = {
    "total_body_read.count": 11,
    "total_decode_call.count": 10,
    "total_provider_call.count": 8,
    "unauthorized_body_read.count": 0,
    "frame_receipt.count": 4,
    "cancellation_event.count": 3,
    "active_producer.count": 0,
    "active_producer_task.count": 0,
    "queued_frame.count": 0,
    "maximum_queued_frame.count": 1,
    "producer_overflow.count": 0,
    "post_terminal_frame.count": 0,
}

records = []
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        records.append(json.loads(line))
    except json.JSONDecodeError:
        continue

if len(records) != 1:
    print("FAILED: expected exactly one decoded feasibility record", file=sys.stderr)
    sys.exit(1)

record = records[0]
booleans_match = all(
    normalized_bool(record.get(f"{prefix}.{key}")) is expected
    for key, expected in expected_bools.items()
)
integers_match = all(
    normalized_int(record.get(f"{prefix}.{key}")) == expected
    for key, expected in expected_ints.items()
)
positive_byte_counts = all(
    (normalized_int(record.get(f"{prefix}.{key}")) or 0) > 0
    for key in ["total_body_read_byte.count", "valid_body_byte.count", "first_frame_byte.count"]
)
failure_matches = record.get(f"{prefix}.failure.reason") == "none"
if booleans_match and integers_match and positive_byte_counts and failure_matches:
    sys.exit(0)

print("FAILED: completed feasibility record did not satisfy the positive carrier contract", file=sys.stderr)
sys.exit(1)
PY

echo "packaged WKWebView product stream feasibility proof PASS"
echo "marker=$MARKER"
echo "query_window=$QUERY_START..$QUERY_END"
echo "carrier=bounded_post_stream_abort"
echo "frame_receipts=4"
echo "producer_residue=0"
