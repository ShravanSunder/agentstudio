#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
METRICS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL:-http://127.0.0.1:8428/api/v1/query}"
TRACES_QUERY_URL="${AI_TOOLS_OBSERVABILITY_TRACES_QUERY_URL:-http://127.0.0.1:10428/select/logsql/query}"
CURL_BIN="${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}"
DEFAULT_BRIDGE_OBSERVABILITY_SCENARIO="package_apply_content_fetch_v1"
VERIFY_ATTEMPTS="${AGENTSTUDIO_OBSERVABILITY_VERIFY_ATTEMPTS:-30}"
VERIFY_RETRY_DELAY_SECONDS="${AGENTSTUDIO_OBSERVABILITY_VERIFY_RETRY_DELAY_SECONDS:-2}"

state_marker=""
state_query_start=""
state_startup_diagnostic_action=""
state_bridge_observability_scenario=""
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
      AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION)
        state_startup_diagnostic_action="$decoded_value"
        ;;
      AGENTSTUDIO_BRIDGE_OBSERVABILITY_SCENARIO)
        state_bridge_observability_scenario="$decoded_value"
        ;;
    esac
  done <"$STATE_FILE"
fi

MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-$state_marker}"
BRIDGE_OBSERVABILITY_SCENARIO="$(
  printf '%s' "${AGENTSTUDIO_BRIDGE_OBSERVABILITY_SCENARIO:-${state_bridge_observability_scenario:-$DEFAULT_BRIDGE_OBSERVABILITY_SCENARIO}}"
)"
QUERY_START="${AGENTSTUDIO_OBSERVABILITY_QUERY_START:-${state_query_start:-$(date -u -v-4H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '4 hours ago' +"%Y-%m-%dT%H:%M:%SZ")}}"
QUERY_END="${AGENTSTUDIO_OBSERVABILITY_QUERY_END:-$(date -u -v+5M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '5 minutes' +"%Y-%m-%dT%H:%M:%SZ")}"
STARTUP_DIAGNOSTIC_ACTION="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$state_startup_diagnostic_action}"

if [ -z "$MARKER" ]; then
  echo "missing AgentStudio debug observability marker; run the Bridge smoke debug app first" >&2
  exit 1
fi

if [ "$STARTUP_DIAGNOSTIC_ACTION" != "bridge-review-observability-smoke" ]; then
  echo "Bridge observability proof requires startup action bridge-review-observability-smoke" >&2
  echo "actual: ${STARTUP_DIAGNOSTIC_ACTION:-<missing>}" >&2
  echo "state file: $STATE_FILE" >&2
  exit 1
fi

"$PROJECT_ROOT/scripts/verify-debug-observability.sh" >/dev/null
"$PROJECT_ROOT/scripts/verify-bridge-web-no-direct-otlp.sh" >/dev/null

logsql_exact_value_filter() {
  local field="${1:?missing LogSQL field}"
  local value="${2:-}"
  local escaped_value="${value//\\/\\\\}"
  escaped_value="${escaped_value//\"/\\\"}"
  printf '%s:="%s"' "$field" "$escaped_value"
}

logsql_quoted_exact_value_filter() {
  local field="${1:?missing LogSQL field}"
  local value="${2:-}"
  local escaped_value="${value//\\/\\\\}"
  escaped_value="${escaped_value//\"/\\\"}"
  printf '"%s":"%s"' "$field" "$escaped_value"
}

query_logs() {
  local logsql="$1"
  "$CURL_BIN" --fail --silent --show-error --max-time 5 --get \
    --data-urlencode "query=$logsql" \
    --data-urlencode "start=$QUERY_START" \
    --data-urlencode "end=$QUERY_END" \
    "$LOGS_QUERY_URL"
}

query_metrics() {
  local promql="$1"
  "$CURL_BIN" --fail --silent --show-error --max-time 5 --get \
    --data-urlencode "query=$promql" \
    "$METRICS_QUERY_URL"
}

query_traces() {
  local logsql="$1"
  "$CURL_BIN" --fail --silent --show-error --max-time 5 --get \
    --data-urlencode "query=$logsql" \
    --data-urlencode "start=$QUERY_START" \
    --data-urlencode "end=$QUERY_END" \
    "$TRACES_QUERY_URL"
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
      sleep "$VERIFY_RETRY_DELAY_SECONDS"
    fi
    attempt=$((attempt + 1))
  done
  echo "$description" >&2
  return 1
}

wait_for_trace_query() {
  local description="${1:?missing description}"
  local logsql="${2:?missing trace LogSQL query}"
  local response=""
  local attempt=1
  while [ "$attempt" -le "$VERIFY_ATTEMPTS" ]; do
    response="$(query_traces "$logsql")"
    if [ -n "$response" ]; then
      printf '%s' "$response"
      return 0
    fi
    if [ "$attempt" -lt "$VERIFY_ATTEMPTS" ]; then
      sleep "$VERIFY_RETRY_DELAY_SECONDS"
    fi
    attempt=$((attempt + 1))
  done
  echo "$description" >&2
  return 1
}

metric_value() {
  local promql="$1"
  local response
  response="$(query_metrics "$promql" 2>/dev/null || true)"
  if [ -z "$response" ]; then
    printf '0\n'
    return 0
  fi
  /usr/bin/python3 - "$response" <<'PY'
import json
import sys

total = 0.0
try:
    payload = json.loads(sys.argv[1])
    for item in payload["data"]["result"]:
        total += float(item["value"][1])
except Exception:
    pass

print(int(total) if total.is_integer() else total)
PY
}

wait_for_metric_count() {
  local description="${1:?missing description}"
  local promql="${2:?missing PromQL query}"
  local count="0"
  local attempt=1
  while [ "$attempt" -le "$VERIFY_ATTEMPTS" ]; do
    count="$(metric_value "$promql")"
    if [ "$count" != "0" ] && [ "$count" != "0.0" ]; then
      printf '%s' "$count"
      return 0
    fi
    if [ "$attempt" -lt "$VERIFY_ATTEMPTS" ]; then
      sleep "$VERIFY_RETRY_DELAY_SECONDS"
    fi
    attempt=$((attempt + 1))
  done
  echo "$description" >&2
  return 1
}

marker_filter="$(logsql_exact_value_filter agent.proof.marker "$MARKER")"
scenario_filter="$(logsql_exact_value_filter agentstudio.bridge.test.scenario "$BRIDGE_OBSERVABILITY_SCENARIO")"
trace_marker_filter="$(logsql_quoted_exact_value_filter span_attr:agent.proof.marker "$MARKER")"
trace_scenario_filter="$(
  logsql_quoted_exact_value_filter span_attr:agentstudio.bridge.test.scenario "$BRIDGE_OBSERVABILITY_SCENARIO"
)"
base_log_query="service.name:AgentStudio dev.runtime.flavor:debug $marker_filter $scenario_filter"

required_log_event_contracts=(
  "performance.bridge.swift.package_build|package_build|data|cold|diff_package_metadata|swift"
  "performance.bridge.swift.delta_build|delta_build|data|warm|diff_package_delta|swift"
  "performance.bridge.swift.content_register|content_register|data|cold|diff_package_metadata|swift"
  "performance.bridge.swift.content_load|success|data|hot|content_fetch|content"
  "performance.bridge.swift.telemetry_ingest|accepted|observability|best_effort|telemetry_ingest|swift"
  "performance.bridge.webkit.package_push|transport|data|cold|diff_package_metadata|push"
  "performance.bridge.webkit.package_push|transport|data|warm|diff_package_delta|push"
  "performance.bridge.webkit.package_push|transport|data|hot|diff_status|push"
  "performance.bridge.webkit.rpc_dispatch|dispatch|control|warm|review_rpc|rpc"
  "performance.bridge.webkit.rpc_response|success|control|warm|review_rpc|rpc"
  "performance.bridge.webkit.telemetry_batch|accepted|observability|best_effort|telemetry_batch|rpc"
  "performance.bridge.web.package_apply|apply|data|cold|diff_package_metadata|push"
  "performance.bridge.web.package_apply|apply|data|warm|diff_package_delta|push"
  "performance.bridge.web.package_apply|apply|data|hot|diff_status|push"
  "performance.bridge.web.rpc_send|send|control|warm|review_rpc|rpc"
  "performance.bridge.web.content_fetch|fetch|data|hot|content_fetch|content"
  "performance.bridge.web.first_render|render|data|hot|diff_package_metadata|push"
)

historical_bridge_lane_field="agentstudio.bridge.${BRIDGE_HISTORICAL_LANE_SUFFIX:-lane}"

for contract in "${required_log_event_contracts[@]}"; do
  IFS='|' read -r event_name phase plane priority slice transport <<<"$contract"
  response="$(wait_for_log_query \
    "missing Bridge log event for marker $MARKER: $event_name $plane/$priority/$slice/$transport" \
    "$base_log_query _msg:$event_name $(logsql_exact_value_filter agentstudio.bridge.phase "$phase") $(logsql_exact_value_filter agentstudio.bridge.plane "$plane") $(logsql_exact_value_filter agentstudio.bridge.priority "$priority") $(logsql_exact_value_filter agentstudio.bridge.slice "$slice") $(logsql_exact_value_filter agentstudio.bridge.transport "$transport") | fields _msg,agentstudio.bridge.phase,agentstudio.bridge.plane,agentstudio.bridge.priority,agentstudio.bridge.slice,agentstudio.bridge.transport,trace_id,span_id | limit 20")"
done

required_metric_event_contracts=(
  "performance.bridge.swift.package_build|package_build|data|cold|diff_package_metadata"
  "performance.bridge.swift.content_load|success|data|hot|content_fetch"
  "performance.bridge.webkit.package_push|transport|data|cold|diff_package_metadata"
  "performance.bridge.webkit.package_push|transport|data|warm|diff_package_delta"
  "performance.bridge.webkit.package_push|transport|data|hot|diff_status"
  "performance.bridge.webkit.rpc_dispatch|dispatch|control|warm|review_rpc"
  "performance.bridge.webkit.telemetry_batch|accepted|observability|best_effort|telemetry_batch"
  "performance.bridge.web.package_apply|apply|data|cold|diff_package_metadata"
  "performance.bridge.web.package_apply|apply|data|warm|diff_package_delta"
  "performance.bridge.web.package_apply|apply|data|hot|diff_status"
  "performance.bridge.web.content_fetch|fetch|data|hot|content_fetch"
  "performance.bridge.web.first_render|render|data|hot|diff_package_metadata"
)

for contract in "${required_metric_event_contracts[@]}"; do
  IFS='|' read -r event_name phase plane priority slice <<<"$contract"
  promql='agentstudio_performance_events_total{service.name="AgentStudio",dev.runtime.flavor="debug",agent.proof.marker="'"$MARKER"'",event="'"$event_name"'",phase="'"$phase"'",plane="'"$plane"'",priority="'"$priority"'",slice="'"$slice"'"}'
  count="$(wait_for_metric_count "missing Bridge metric counter for marker $MARKER: $event_name $phase/$plane/$priority/$slice" "$promql")"
done

package_push_slice_promql='agentstudio_performance_events_total{service.name="AgentStudio",dev.runtime.flavor="debug",agent.proof.marker="'"$MARKER"'",event="performance.bridge.webkit.package_push",phase="transport",plane="data",priority="cold",slice="diff_package_metadata"}'
package_push_slice_count="$(
  wait_for_metric_count \
    "missing Bridge package_push metric counter grouped by plane/priority/slice for marker $MARKER" \
    "$package_push_slice_promql"
)"

broad_package_push_promql='agentstudio_performance_events_total{service.name="AgentStudio",dev.runtime.flavor="debug",agent.proof.marker="'"$MARKER"'",event="performance.bridge.webkit.package_push"} unless agentstudio_performance_events_total{service.name="AgentStudio",dev.runtime.flavor="debug",agent.proof.marker="'"$MARKER"'",event="performance.bridge.webkit.package_push",phase=~".+",plane=~".+",priority=~".+",slice=~".+"}'
broad_package_push_count="$(metric_value "$broad_package_push_promql")"
if [ "$broad_package_push_count" != "0" ] && [ "$broad_package_push_count" != "0.0" ]; then
  echo "missing Bridge broad package_push metric fallback guard: unlabeled fallback series survived" >&2
  echo "count=$broad_package_push_count" >&2
  exit 1
fi

unknown_package_push_promql='agentstudio_performance_events_total{service.name="AgentStudio",dev.runtime.flavor="debug",agent.proof.marker="'"$MARKER"'",event="performance.bridge.webkit.package_push",slice="unknown"}'
unknown_package_push_count="$(metric_value "$unknown_package_push_promql")"
if [ "$unknown_package_push_count" != "0" ] && [ "$unknown_package_push_count" != "0.0" ]; then
  echo "Bridge package_push metric used unknown producer slice" >&2
  echo "count=$unknown_package_push_count" >&2
  exit 1
fi

trace_response="$(
  wait_for_trace_query \
    "missing Bridge Swift package_build span in VictoriaTraces for marker $MARKER" \
    "$trace_marker_filter $trace_scenario_filter \"span_attr:agentstudio.bridge.phase\":\"package_build\" \"span_attr:agentstudio.bridge.transport\":\"swift\" | fields trace_id,span_id,span_name,span_attr:agent.proof.marker,span_attr:agentstudio.bridge.test.scenario,span_attr:agentstudio.bridge.phase | limit 20"
)"

content_trace_response="$(
  wait_for_trace_query \
    "missing Bridge content fetch span in VictoriaTraces for marker $MARKER" \
    "$trace_marker_filter $trace_scenario_filter \"span_attr:agentstudio.bridge.phase\":\"fetch\" \"span_attr:agentstudio.bridge.transport\":\"content\" | fields trace_id,span_id,span_name,span_attr:agent.proof.marker,span_attr:agentstudio.bridge.test.scenario,span_attr:agentstudio.bridge.phase | limit 20"
)"

rpc_trace_response="$(
  wait_for_trace_query \
    "missing Bridge review RPC span in VictoriaTraces for marker $MARKER" \
    "$trace_marker_filter $trace_scenario_filter \"span_attr:agentstudio.bridge.phase\":\"dispatch\" \"span_attr:agentstudio.bridge.transport\":\"rpc\" \"span_attr:agentstudio.bridge.rpc.method_class\":\"review\" | fields trace_id,span_id,span_name,span_attr:agent.proof.marker,span_attr:agentstudio.bridge.test.scenario,span_attr:agentstudio.bridge.phase,span_attr:agentstudio.bridge.rpc.method_class | limit 20"
)"

for unsafe_field in \
  agentstudio.bridge.item_id \
  "$historical_bridge_lane_field" \
  agentstudio.bridge.tab_id \
  agentstudio.bridge.session_id \
  agentstudio.bridge.operation_id \
  agentstudio.bridge.request_id \
  agentstudio.bridge.content_hash \
  agentstudio.bridge.checkpoint_id \
  agentstudio.bridge.dynamic_key \
  agentstudio.bridge.path \
  agentstudio.bridge.prompt \
  agentstudio.bridge.raw_error \
  agentstudio.bridge.payload \
  agentstudio.bridge.text \
  agentstudio.bridge.output \
  agentstudio.bridge.token \
  agentstudio.bridge.secret
do
  unsafe_field_response="$(query_logs "$base_log_query $unsafe_field:* | limit 1")"
  if [ -n "$unsafe_field_response" ]; then
    echo "unsafe Bridge field survived OTLP logs: $unsafe_field" >&2
    echo "$unsafe_field_response" >&2
    exit 1
  fi
done

unknown_package_push_log_response="$(
  query_logs "$base_log_query _msg:performance.bridge.webkit.package_push $(logsql_exact_value_filter agentstudio.bridge.slice unknown) | limit 1"
)"
if [ -n "$unknown_package_push_log_response" ]; then
  echo "Bridge package_push log used unknown producer slice" >&2
  echo "$unknown_package_push_log_response" >&2
  exit 1
fi

telemetry_self_rpc_log_response="$(
  query_logs "$base_log_query agentstudio.bridge.rpc.method_class:telemetry | limit 1"
)"
if [ -n "$telemetry_self_rpc_log_response" ]; then
  echo "Bridge telemetry self-RPC survived OTLP logs" >&2
  echo "$telemetry_self_rpc_log_response" >&2
  exit 1
fi

telemetry_self_rpc_trace_response="$(
  query_traces "$trace_marker_filter $trace_scenario_filter \"span_attr:agentstudio.bridge.rpc.method_class\":\"telemetry\" | limit 1"
)"
if [ -n "$telemetry_self_rpc_trace_response" ]; then
  echo "Bridge telemetry self-RPC survived VictoriaTraces" >&2
  echo "$telemetry_self_rpc_trace_response" >&2
  exit 1
fi

echo "bridge observability ok:"
echo "marker=$MARKER"
echo "scenario=$BRIDGE_OBSERVABILITY_SCENARIO"
echo "logs=${#required_log_event_contracts[@]} metrics=${#required_metric_event_contracts[@]} traces=3"
echo "telemetry_self_rpc=absent"
