#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
CURL_BIN="${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}"
EXPECTED_SELECTIONS="${AGENTSTUDIO_BRIDGE_REVIEW_JOURNEY_EXPECTED_SELECTIONS:-4}"
# The diagnostic commits four selections, but selected_content_painted is anchored to foreground
# click demand. Only the explicit modified-row click and review-tree click have that anchor.
CLICK_SELECTIONS="${AGENTSTUDIO_BRIDGE_REVIEW_JOURNEY_CLICK_SELECTIONS:-2}"
# The initial auto-selection materializes before its selection_commit event, and the unchanged
# re-selection does not produce a new selected materialization. Observed selected materializations
# are therefore exactly selection commits minus that initial pre-commit materialization.
EXPECTED_SELECTED_MATERIALIZATIONS="$((EXPECTED_SELECTIONS - 1))"
QUIESCENCE_SECONDS="${AGENTSTUDIO_BRIDGE_REVIEW_JOURNEY_QUIESCENCE_SECONDS:-8}"
NON_STALE_TELEMETRY_DROP_STORM_THRESHOLD="${AGENTSTUDIO_BRIDGE_NON_STALE_TELEMETRY_DROP_STORM_THRESHOLD:-0}"
VERIFY_ATTEMPTS="${AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS:-12}"
VERIFY_RETRY_DELAY_SECONDS="${AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS:-2}"
EXPECTED_STARTUP_ACTION="bridge-review-observability-smoke"

dry_run=false

usage() {
  cat <<'USAGE'
Usage: verify-bridge-review-journey-smoke.sh [--dry-run]

Verifies a launcher-driven Bridge review journey smoke from marker-scoped
VictoriaLogs. This script does not launch AgentStudio. Start the debug app with:

  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-review-observability-smoke \
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

query_sleep() {
  local seconds="$1"
  read -r -t "$seconds" _ </dev/null || true
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

MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-$state_marker}"
STARTUP_DIAGNOSTIC_ACTION="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$state_startup_diagnostic_action}"
QUERY_START="${AGENTSTUDIO_OBSERVABILITY_QUERY_START:-${state_query_start:-$(portable_utc_time -4H '4 hours ago')}}"
QUERY_END="${AGENTSTUDIO_OBSERVABILITY_QUERY_END:-$(portable_utc_time +5M '5 minutes')}"

if [ -z "$MARKER" ]; then
  if [ "$dry_run" = true ]; then
    MARKER="dry-run-review-journey-marker"
  else
    echo "missing AgentStudio debug observability marker; run the Bridge review smoke debug app first" >&2
    exit 1
  fi
fi

if [ -z "$STARTUP_DIAGNOSTIC_ACTION" ] && [ "$dry_run" = true ]; then
  STARTUP_DIAGNOSTIC_ACTION="$EXPECTED_STARTUP_ACTION"
fi

if [ "$STARTUP_DIAGNOSTIC_ACTION" != "$EXPECTED_STARTUP_ACTION" ]; then
  echo "Bridge review journey smoke requires startup action $EXPECTED_STARTUP_ACTION" >&2
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

wait_for_log_query() {
  local description="${1:?missing description}"
  local logsql="${2:?missing LogSQL query}"
  local response=""
  local attempt=1
  while [ "$attempt" -le "$VERIFY_ATTEMPTS" ]; do
    response="$(query_logs "$logsql")"
    if [ -n "$response" ]; then
      printf '%s' "$response"
      return 0
    fi
    if [ "$attempt" -lt "$VERIFY_ATTEMPTS" ]; then
      query_sleep "$VERIFY_RETRY_DELAY_SECONDS"
    fi
    attempt=$((attempt + 1))
  done
  echo "$description" >&2
  return 1
}

wait_for_optional_log_query() {
  local logsql="${1:?missing LogSQL query}"
  local response=""
  local attempt=1
  while [ "$attempt" -le "$VERIFY_ATTEMPTS" ]; do
    response="$(query_logs "$logsql")"
    if [ -n "$response" ]; then
      printf '%s' "$response"
      return 0
    fi
    if [ "$attempt" -lt "$VERIFY_ATTEMPTS" ]; then
      query_sleep "$VERIFY_RETRY_DELAY_SECONDS"
    fi
    attempt=$((attempt + 1))
  done
  return 0
}

count_payload_records() {
  local payload="$1"
  /usr/bin/python3 - "$payload" <<'PY'
import sys

payload = sys.argv[1]
print(sum(1 for line in payload.splitlines() if line.strip()))
PY
}

count_log_records_between() {
  local logsql="$1"
  local start_time="$2"
  local end_time="$3"
  local response
  response="$(query_logs_between "$logsql" "$start_time" "$end_time")"
  count_payload_records "$response"
}

count_log_records() {
  count_log_records_between "$1" "$QUERY_START" "$QUERY_END"
}

sum_numeric_field() {
  local logsql="$1"
  local field_name="$2"
  local response
  response="$(query_logs "$logsql")"
  /usr/bin/python3 - "$field_name" "$response" <<'PY'
import json
import math
import sys

field_name, payload = sys.argv[1], sys.argv[2]
total = 0.0
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        continue
    value = record.get(field_name, 0)
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        continue
    if math.isfinite(numeric):
        total += numeric
print(int(total) if total.is_integer() else total)
PY
}

max_numeric_field() {
  local field_name="$1"
  local payload="$2"
  /usr/bin/python3 - "$field_name" "$payload" <<'PY'
import json
import math
import sys

field_name, payload = sys.argv[1], sys.argv[2]
maximum = None
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        continue
    value = record.get(field_name)
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        continue
    if math.isfinite(numeric):
        maximum = numeric if maximum is None else max(maximum, numeric)
if maximum is None:
    print(0)
else:
    print(int(maximum) if maximum.is_integer() else maximum)
PY
}

first_json_string_field() {
  local field_name="$1"
  local payload="$2"
  local fallback="${3:-unknown}"
  /usr/bin/python3 - "$field_name" "$payload" "$fallback" <<'PY'
import json
import sys

field_name, payload, fallback = sys.argv[1], sys.argv[2], sys.argv[3]
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        continue
    value = record.get(field_name)
    if isinstance(value, str) and value:
        print(value)
        sys.exit(0)
print(fallback)
PY
}

first_json_numeric_field() {
  local field_name="$1"
  local payload="$2"
  local fallback="${3:--1}"
  /usr/bin/python3 - "$field_name" "$payload" "$fallback" <<'PY'
import json
import math
import sys

field_name, payload, fallback = sys.argv[1], sys.argv[2], sys.argv[3]
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        continue
    value = record.get(field_name)
    if isinstance(value, bool):
        continue
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        continue
    if math.isfinite(numeric):
        print(int(numeric) if numeric.is_integer() else numeric)
        sys.exit(0)
print(fallback)
PY
}

first_json_boolean_field() {
  local field_name="$1"
  local payload="$2"
  local fallback="${3:-unknown}"
  /usr/bin/python3 - "$field_name" "$payload" "$fallback" <<'PY'
import json
import sys

field_name, payload, fallback = sys.argv[1], sys.argv[2], sys.argv[3]
for line in payload.splitlines():
    if not line.strip():
        continue
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        continue
    value = record.get(field_name)
    if isinstance(value, bool):
        print("true" if value else "false")
        sys.exit(0)
    if isinstance(value, str) and value in {"true", "false"}:
        print(value)
        sys.exit(0)
print(fallback)
PY
}

json_exact_string_field() {
  local field_name="$1"
  local expected="$2"
  local payload="$3"
  grep -q "\"$field_name\":\"$expected\"" <<<"$payload"
}

json_falseish_field() {
  local field_name="$1"
  local payload="$2"
  grep -Eq "\"$field_name\":(\"false\"|false)([,}[:space:]]|$)" <<<"$payload"
}

is_frame_not_live_skip() {
  local payload="$1"
  json_exact_string_field agentstudio.startup_diagnostic.skip_reason frame_not_live "$payload" &&
    json_falseish_field agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive "$payload" &&
    json_falseish_field agentstudio.startup_diagnostic.render_proof.succeeded "$payload"
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

skip_assertion() {
  local name="$1"
  local detail="$2"
  printf 'SKIP %s: %s\n' "$name" "$detail"
}

assert_equals() {
  local name="$1"
  local observed="$2"
  local expected="$3"
  if [ "$observed" = "$expected" ]; then
    pass_assertion "$name" "observed=$observed expected=$expected"
  else
    fail_assertion "$name" "observed=$observed expected=$expected"
  fi
}

assert_zero() {
  local name="$1"
  local observed="$2"
  assert_equals "$name" "$observed" "0"
}

assert_not_equals() {
  local name="$1"
  local observed="$2"
  local rejected="$3"
  if [ "$observed" != "$rejected" ]; then
    pass_assertion "$name" "observed=$observed rejected=$rejected"
  else
    fail_assertion "$name" "observed=$observed rejected=$rejected"
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

assert_gte() {
  local name="$1"
  local observed="$2"
  local floor="$3"
  if /usr/bin/python3 - "$observed" "$floor" <<'PY'
import sys

observed = float(sys.argv[1])
floor = float(sys.argv[2])
sys.exit(0 if observed >= floor else 1)
PY
  then
    pass_assertion "$name" "observed=$observed floor=$floor"
  else
    fail_assertion "$name" "observed=$observed floor=$floor"
  fi
}

marker_filter="$(logsql_exact_filter agent.proof.marker "$MARKER")"
action_filter="$(logsql_exact_filter agentstudio.startup_diagnostic.action "$STARTUP_DIAGNOSTIC_ACTION")"
base_query="service.name:AgentStudio dev.runtime.flavor:debug $marker_filter"
diagnostic_completed_query="$base_query $action_filter _msg:app.startup_diagnostic_action.completed"
diagnostic_skipped_query="$base_query $action_filter _msg:app.startup_diagnostic_action.skipped"
selection_commit_query="$base_query _msg:performance.bridge.web.selection_commit $(logsql_exact_filter agentstudio.bridge.phase selection_commit)"
materialized_query="$base_query _msg:performance.bridge.web.code_view_item_materialize $(logsql_exact_filter agentstudio.bridge.phase code_view_item_materialize) $(logsql_exact_filter agentstudio.bridge.selected true)"
painted_query="$base_query _msg:performance.bridge.web.selected_content_painted $(logsql_exact_filter agentstudio.bridge.phase selected_content_painted)"
painted_materialize_ms_query="$painted_query agentstudio.bridge.selected_content.materialize_ms:*"
revision_churn_drop_query="$base_query _msg:performance.bridge.web.selected_content_dropped $(logsql_exact_filter agentstudio.bridge.drop_reason revision_churn)"
content_load_query="$base_query _msg:performance.bridge.swift.content_load"
telemetry_drop_query="$base_query _msg:performance.bridge.web.telemetry_drop"
stale_telemetry_drop_query="$telemetry_drop_query $(logsql_exact_filter agentstudio.bridge.telemetry.drop_reason stale_push)"
non_stale_telemetry_drop_query="$telemetry_drop_query agentstudio.bridge.telemetry.drop_reason:!=\"stale_push\""
telemetry_sidecar_drain_query="$base_query _msg:performance.bridge.swift.telemetry_sidecar_drain"
telemetry_sidecar_nonterminal_query="$telemetry_sidecar_drain_query $(logsql_exact_filter agentstudio.bridge.phase nonterminal_reopened)"
telemetry_sidecar_terminal_query="$telemetry_sidecar_drain_query $(logsql_exact_filter agentstudio.bridge.phase terminal_closed)"

dry_run_queries=(
  "$diagnostic_completed_query | limit 0"
  "$diagnostic_skipped_query | limit 0"
  "$selection_commit_query | limit 0"
  "$materialized_query | limit 0"
  "$painted_query | limit 0"
  "$painted_materialize_ms_query | limit 0"
  "$revision_churn_drop_query | limit 0"
  "$content_load_query | limit 0"
  "$telemetry_drop_query | limit 0"
  "$non_stale_telemetry_drop_query | limit 0"
  "$telemetry_sidecar_nonterminal_query | limit 0"
  "$telemetry_sidecar_terminal_query | limit 0"
)

if [ "$dry_run" = true ]; then
  for dry_run_query in "${dry_run_queries[@]}"; do
    query_logs "$dry_run_query" >/dev/null
  done
  echo "dry-run ok: review-journey LogSQL probes validated"
  echo "marker=$MARKER"
  echo "startup_action=$STARTUP_DIAGNOSTIC_ACTION"
  echo "queries=${#dry_run_queries[@]}"
  exit 0
fi

AGENTSTUDIO_OBSERVABILITY_ALLOW_COMPLETED_EXIT=1 \
  "$PROJECT_ROOT/scripts/verify-debug-observability.sh" >/dev/null

diagnostic_completed_response="$(
  wait_for_optional_log_query \
    "$diagnostic_completed_query | fields _msg,agentstudio.startup_diagnostic.bridge.review_expected_item.count,agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive,agentstudio.startup_diagnostic.bridge.frame_liveness.raf_fired_latency.bucket | limit 20"
)"
if [ -z "$diagnostic_completed_response" ]; then
  diagnostic_skipped_response="$(
    wait_for_optional_log_query \
      "$diagnostic_skipped_query | fields _msg,agentstudio.startup_diagnostic.action,agentstudio.startup_diagnostic.skip_reason,agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive,agentstudio.startup_diagnostic.render_proof.succeeded | limit 20"
  )"
  if is_frame_not_live_skip "$diagnostic_skipped_response"; then
    skip_assertion \
      "review journey smoke skipped because startup frame is not live" \
      "skip_reason=frame_not_live"
    echo "bridge review journey smoke summary:"
    echo "marker=$MARKER"
    echo "query_window=$QUERY_START..$QUERY_END"
    echo "startup_diagnostic_skip_reason=frame_not_live"
    exit 0
  fi
  echo "startup diagnostic completed/skipped record missing for review journey marker $MARKER" >&2
  echo "$diagnostic_skipped_response" >&2
  exit 1
fi
diagnostic_completed_count="$(count_payload_records "$diagnostic_completed_response")"
frame_liveness_raf_alive="$(
  first_json_string_field \
    "agentstudio.startup_diagnostic.bridge.frame_liveness.raf_alive" \
    "$diagnostic_completed_response"
)"
frame_liveness_raf_fired_latency_bucket="$(
  first_json_string_field \
    "agentstudio.startup_diagnostic.bridge.frame_liveness.raf_fired_latency.bucket" \
    "$diagnostic_completed_response"
)"
review_expected_item_count="$(
  max_numeric_field \
    "agentstudio.startup_diagnostic.bridge.review_expected_item.count" \
    "$diagnostic_completed_response"
)"
content_load_expected_role_ceiling=$((review_expected_item_count * 2))
selection_commit_count="$(count_log_records "$selection_commit_query | fields _msg,agentstudio.bridge.viewer | limit 100")"
materialized_count="$(count_log_records "$materialized_query | fields _msg,agentstudio.bridge.viewer,agentstudio.bridge.selected,agentstudio.bridge.result | limit 100")"
painted_count="$(count_log_records "$painted_query | fields _msg,agentstudio.bridge.viewer,agentstudio.bridge.selected_content.materialize_ms | limit 100")"
painted_materialize_ms_count="$(count_log_records "$painted_materialize_ms_query | fields _msg,agentstudio.bridge.selected_content.materialize_ms | limit 100")"
revision_churn_drop_count="$(count_log_records "$revision_churn_drop_query | fields _msg,agentstudio.bridge.drop_reason | limit 100")"
content_load_before_quiescence_count="$(count_log_records "$content_load_query | fields _msg,agentstudio.bridge.transport,agentstudio.bridge.content.role | limit 20000")"
query_sleep "$QUIESCENCE_SECONDS"
content_load_count="$(count_log_records "$content_load_query | fields _msg,agentstudio.bridge.transport,agentstudio.bridge.content.role | limit 20000")"
telemetry_drop_sample_count="$(count_log_records "$telemetry_drop_query | fields _msg,agentstudio.bridge.telemetry.dropped_count | limit 100")"
telemetry_dropped_total="$(sum_numeric_field "$telemetry_drop_query | fields _msg,agentstudio.bridge.telemetry.dropped_count | limit 100" "agentstudio.bridge.telemetry.dropped_count")"
stale_telemetry_drop_sample_count="$(count_log_records "$stale_telemetry_drop_query | fields _msg,agentstudio.bridge.telemetry.drop_reason,agentstudio.bridge.telemetry.dropped_count | limit 100")"
stale_telemetry_dropped_total="$(sum_numeric_field "$stale_telemetry_drop_query | fields _msg,agentstudio.bridge.telemetry.drop_reason,agentstudio.bridge.telemetry.dropped_count | limit 100" "agentstudio.bridge.telemetry.dropped_count")"
non_stale_telemetry_drop_sample_count="$(count_log_records "$non_stale_telemetry_drop_query | fields _msg,agentstudio.bridge.telemetry.drop_reason,agentstudio.bridge.telemetry.dropped_count | limit 100")"
non_stale_telemetry_dropped_total="$(sum_numeric_field "$non_stale_telemetry_drop_query | fields _msg,agentstudio.bridge.telemetry.drop_reason,agentstudio.bridge.telemetry.dropped_count | limit 100" "agentstudio.bridge.telemetry.dropped_count")"
telemetry_sidecar_proof_fields="_msg,agentstudio.bridge.phase,agentstudio.bridge.telemetry.session.digest,agentstudio.bridge.telemetry.accepted_batch.sequence,agentstudio.bridge.telemetry.main_producer.high_watermark,agentstudio.bridge.telemetry.comm_producer.high_watermark,agentstudio.bridge.telemetry.required_loss.count,agentstudio.bridge.telemetry.optional_loss.count,agentstudio.bridge.telemetry.worker_sequence_gap.count,agentstudio.bridge.telemetry.native_batch_sequence_gap.count,agentstudio.bridge.telemetry.proof_eligible,agentstudio.bridge.telemetry.lossy,agentstudio.bridge.telemetry.settlement_acknowledged"
telemetry_sidecar_nonterminal_response="$(
  wait_for_log_query \
    "nonterminal telemetry sidecar drain receipt missing for marker $MARKER" \
    "$telemetry_sidecar_nonterminal_query | fields $telemetry_sidecar_proof_fields | limit 10"
)"
telemetry_sidecar_terminal_response="$(
  wait_for_log_query \
    "terminal telemetry sidecar drain receipt missing for marker $MARKER" \
    "$telemetry_sidecar_terminal_query | fields $telemetry_sidecar_proof_fields | limit 10"
)"
telemetry_sidecar_nonterminal_count="$(count_payload_records "$telemetry_sidecar_nonterminal_response")"
telemetry_sidecar_terminal_count="$(count_payload_records "$telemetry_sidecar_terminal_response")"
telemetry_sidecar_nonterminal_digest="$(first_json_string_field "agentstudio.bridge.telemetry.session.digest" "$telemetry_sidecar_nonterminal_response" missing)"
telemetry_sidecar_terminal_digest="$(first_json_string_field "agentstudio.bridge.telemetry.session.digest" "$telemetry_sidecar_terminal_response" missing)"
telemetry_sidecar_nonterminal_accepted_batch_sequence="$(first_json_numeric_field "agentstudio.bridge.telemetry.accepted_batch.sequence" "$telemetry_sidecar_nonterminal_response")"
telemetry_sidecar_terminal_accepted_batch_sequence="$(first_json_numeric_field "agentstudio.bridge.telemetry.accepted_batch.sequence" "$telemetry_sidecar_terminal_response")"
telemetry_sidecar_nonterminal_main_high_watermark="$(first_json_numeric_field "agentstudio.bridge.telemetry.main_producer.high_watermark" "$telemetry_sidecar_nonterminal_response")"
telemetry_sidecar_nonterminal_comm_high_watermark="$(first_json_numeric_field "agentstudio.bridge.telemetry.comm_producer.high_watermark" "$telemetry_sidecar_nonterminal_response")"
telemetry_sidecar_terminal_main_high_watermark="$(first_json_numeric_field "agentstudio.bridge.telemetry.main_producer.high_watermark" "$telemetry_sidecar_terminal_response")"
telemetry_sidecar_terminal_comm_high_watermark="$(first_json_numeric_field "agentstudio.bridge.telemetry.comm_producer.high_watermark" "$telemetry_sidecar_terminal_response")"

assert_gte "startup diagnostic completed at least once" "$diagnostic_completed_count" 1
assert_gte "diagnostic review_expected_item count present" "$review_expected_item_count" 1
if [ "$frame_liveness_raf_alive" = "false" ]; then
  skip_assertion \
    "selected_content_painted skipped because requestAnimationFrame is not live" \
    "raf_alive=false observed=$painted_count expected=$CLICK_SELECTIONS"
  skip_assertion \
    "selected_content_painted materialize_ms skipped because requestAnimationFrame is not live" \
    "raf_alive=false observed=$painted_materialize_ms_count expected=$CLICK_SELECTIONS"
else
  assert_equals "selected_content_painted fires exactly once per click-anchored selection" "$painted_count" "$CLICK_SELECTIONS"
  assert_equals "selected_content_painted materialize_ms present exactly once per click-anchored selection" "$painted_materialize_ms_count" "$CLICK_SELECTIONS"
fi
assert_equals "selection_commit fires exactly once per selection" "$selection_commit_count" "$EXPECTED_SELECTIONS"
assert_equals "code_view_item_materialize selected items materialize for selection-changing renders" "$materialized_count" "$EXPECTED_SELECTED_MATERIALIZATIONS"
assert_zero "selected_content_dropped revision_churn count" "$revision_churn_drop_count"
assert_gte "content_load count is at least explicit selections" "$content_load_count" "$EXPECTED_SELECTIONS"
# Native content_load fires per content role. The review journey diagnostic
# expects base/head content, so the ceiling is two role loads per expected item.
assert_lte "content_load count bounded by diagnostic review_expected_item base/head role count" "$content_load_count" "$content_load_expected_role_ceiling"
assert_equals "content_load count quiesced" "$content_load_count" "$content_load_before_quiescence_count"
assert_lte "zero non-stale telemetry_drop storms (sample count)" "$non_stale_telemetry_drop_sample_count" "$NON_STALE_TELEMETRY_DROP_STORM_THRESHOLD"
assert_lte "zero non-stale telemetry_drop storms (dropped total)" "$non_stale_telemetry_dropped_total" "$NON_STALE_TELEMETRY_DROP_STORM_THRESHOLD"
assert_equals "one nonterminal telemetry sidecar drain receipt" "$telemetry_sidecar_nonterminal_count" 1
assert_equals "one terminal telemetry sidecar drain receipt" "$telemetry_sidecar_terminal_count" 1
assert_not_equals "nonterminal telemetry sidecar session digest present" "$telemetry_sidecar_nonterminal_digest" missing
assert_equals "telemetry sidecar drain receipts share one session digest" "$telemetry_sidecar_terminal_digest" "$telemetry_sidecar_nonterminal_digest"
assert_gte "nonterminal main producer high-watermark present" "$telemetry_sidecar_nonterminal_main_high_watermark" 0
assert_gte "nonterminal comm producer high-watermark present" "$telemetry_sidecar_nonterminal_comm_high_watermark" 0
assert_gte "terminal main producer high-watermark present" "$telemetry_sidecar_terminal_main_high_watermark" 0
assert_gte "terminal comm producer high-watermark present" "$telemetry_sidecar_terminal_comm_high_watermark" 0
assert_gte "nonterminal accepted batch sequence present" "$telemetry_sidecar_nonterminal_accepted_batch_sequence" 0
assert_gte "terminal accepted batch sequence present" "$telemetry_sidecar_terminal_accepted_batch_sequence" 0
assert_gte "terminal accepted batch sequence covers nonterminal drain" "$telemetry_sidecar_terminal_accepted_batch_sequence" "$telemetry_sidecar_nonterminal_accepted_batch_sequence"
for telemetry_sidecar_phase in nonterminal terminal; do
  telemetry_sidecar_response_variable="telemetry_sidecar_${telemetry_sidecar_phase}_response"
  telemetry_sidecar_response="${!telemetry_sidecar_response_variable}"
  assert_zero "$telemetry_sidecar_phase required telemetry loss" "$(first_json_numeric_field "agentstudio.bridge.telemetry.required_loss.count" "$telemetry_sidecar_response")"
  assert_zero "$telemetry_sidecar_phase optional telemetry loss" "$(first_json_numeric_field "agentstudio.bridge.telemetry.optional_loss.count" "$telemetry_sidecar_response")"
  assert_zero "$telemetry_sidecar_phase worker sequence gaps" "$(first_json_numeric_field "agentstudio.bridge.telemetry.worker_sequence_gap.count" "$telemetry_sidecar_response")"
  assert_zero "$telemetry_sidecar_phase native batch sequence gaps" "$(first_json_numeric_field "agentstudio.bridge.telemetry.native_batch_sequence_gap.count" "$telemetry_sidecar_response")"
  assert_equals "$telemetry_sidecar_phase telemetry proof eligible" "$(first_json_boolean_field "agentstudio.bridge.telemetry.proof_eligible" "$telemetry_sidecar_response")" true
  assert_equals "$telemetry_sidecar_phase telemetry lossless" "$(first_json_boolean_field "agentstudio.bridge.telemetry.lossy" "$telemetry_sidecar_response")" false
  assert_equals "$telemetry_sidecar_phase producer settlement acknowledged" "$(first_json_boolean_field "agentstudio.bridge.telemetry.settlement_acknowledged" "$telemetry_sidecar_response")" true
done

echo "bridge review journey smoke summary:"
echo "marker=$MARKER"
echo "query_window=$QUERY_START..$QUERY_END"
echo "expected_selections=$EXPECTED_SELECTIONS click_selections=$CLICK_SELECTIONS expected_selected_materializations=$EXPECTED_SELECTED_MATERIALIZATIONS"
echo "review_expected_item_count=$review_expected_item_count"
echo "frame_liveness_raf_alive=$frame_liveness_raf_alive frame_liveness_raf_fired_latency_bucket=$frame_liveness_raf_fired_latency_bucket"
echo "selected_content_painted=$painted_count selected_content_painted_materialize_ms=$painted_materialize_ms_count"
echo "selection_commit=$selection_commit_count"
echo "code_view_item_materialize_selected=$materialized_count"
echo "selected_content_dropped_revision_churn=$revision_churn_drop_count"
echo "content_load_before_quiescence=$content_load_before_quiescence_count content_load=$content_load_count quiescence_seconds=$QUIESCENCE_SECONDS review_expected_item_count=$review_expected_item_count"
echo "telemetry_drop_samples=$telemetry_drop_sample_count dropped_total=$telemetry_dropped_total stale_samples=$stale_telemetry_drop_sample_count stale_dropped_total=$stale_telemetry_dropped_total non_stale_samples=$non_stale_telemetry_drop_sample_count non_stale_dropped_total=$non_stale_telemetry_dropped_total threshold=$NON_STALE_TELEMETRY_DROP_STORM_THRESHOLD"
echo "telemetry_sidecar_session_digest=$telemetry_sidecar_nonterminal_digest nonterminal_accepted_batch_sequence=$telemetry_sidecar_nonterminal_accepted_batch_sequence terminal_accepted_batch_sequence=$telemetry_sidecar_terminal_accepted_batch_sequence"

if [ "$assertion_failures" -ne 0 ]; then
  echo "bridge review journey smoke failed assertions=$assertion_failures" >&2
  exit 1
fi
