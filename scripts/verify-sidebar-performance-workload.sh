#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_STACK_HELPER="$HOME/dev/ai-tools/observability/observability-stack"
STACK_HELPER="${AI_TOOLS_OBSERVABILITY_STACK_HELPER:-$DEFAULT_STACK_HELPER}"
COLLECTOR_HEALTH_URL="${AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL:-http://127.0.0.1:13133/}"
METRICS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL:-http://127.0.0.1:8428/api/v1/query}"
DEFAULT_PROOF_ROOT="/tmp/agentstudio-sidebar-performance"
WORKLOAD_TRACE_TAGS="${AGENTSTUDIO_TRACE_TAGS:-performance,app.startup,terminal.startup}"

usage() {
  cat <<'USAGE'
Usage: verify-sidebar-performance-workload.sh --prepare-only
       verify-sidebar-performance-workload.sh --baseline
       verify-sidebar-performance-workload.sh --compare
       verify-sidebar-performance-workload.sh --sidebar-proof

Runs a marker-scoped sidebar semantic/performance proof through the standard
per-worktree debug observability runner. Proof modes reject unsafe no-auth IPC
and foreground activation. The script never exports sidebar query text,
notification text, labels, repo/worktree names, pane/tab labels, paths, or raw ids.

Environment overrides:
  AGENTSTUDIO_SIDEBAR_PROOF_ROOT          Parent directory for artifacts.
  AGENTSTUDIO_TRACE_NAME                  Safe marker name.
  AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES
                                          Only with --prepare-only; injects canned
                                          metrics responses for script tests.
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE    State file passed to debug runner.
USAGE
}

mode=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prepare-only|--baseline|--compare|--sidebar-proof)
      if [ -n "$mode" ]; then
        usage >&2
        exit 2
      fi
      mode="${1#--}"
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

if [ -z "$mode" ]; then
  usage >&2
  exit 2
fi

if [ "$mode" != "prepare-only" ] && [ -n "${AGENTSTUDIO_IPC_UNSAFE_NO_AUTH:-}" ]; then
  echo "sidebar proof refuses AGENTSTUDIO_IPC_UNSAFE_NO_AUTH" >&2
  exit 2
fi

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

validate_controls() {
  validate_loopback_url AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL "$COLLECTOR_HEALTH_URL"
  validate_loopback_url AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL "$METRICS_QUERY_URL"
  if [ "${AGENTSTUDIO_OBSERVABILITY_ALLOW_TEST_OVERRIDES:-0}" = "1" ]; then
    return
  fi
  if [ "$(canonical_path "$STACK_HELPER")" != "$(canonical_path "$DEFAULT_STACK_HELPER")" ]; then
    echo "AI_TOOLS_OBSERVABILITY_STACK_HELPER must point to the trusted ai-tools helper: $DEFAULT_STACK_HELPER" >&2
    exit 2
  fi
}

validate_trace_name() {
  local trace_name="${1:?missing trace name}"
  case "$trace_name" in
    ""|"."|".."|*"/"*|*"\\"*|*".."*|*"*"*|*"?"*|*"["*|*"]"*|*"{"*|*"}"*|*[!A-Za-z0-9_.-]*)
      echo "AGENTSTUDIO_TRACE_NAME must be a safe path component: $trace_name" >&2
      exit 2
      ;;
  esac
  printf '%s\n' "$trace_name"
}

decode_env_file_value() {
  local state_file="${1:?missing state file}"
  local key="${2:?missing key}"
  local raw_value
  raw_value="$(sed -n "s/^$key=//p" "$state_file" | tail -1)"
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

metric_label_selector() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

query_victoria_metrics() {
  local query="$1"
  if [ "${AGENTSTUDIO_SIDEBAR_ALLOW_TEST_RESPONSES:-0}" = "1" ]; then
    if [ "$mode" != "prepare-only" ]; then
      echo "canned sidebar metrics responses are allowed only with --prepare-only" >&2
      exit 2
    fi
    printf '%s\n' "${AGENTSTUDIO_SIDEBAR_TEST_METRICS_RESPONSE:-}"
    return 0
  fi
  /usr/bin/curl --fail --silent --show-error --max-time 10 --get \
    --data-urlencode "query=$query" \
    "$METRICS_QUERY_URL"
}

metric_result_count() {
  local response="$1"
  /usr/bin/python3 - "$response" <<'PY'
import json
import sys

payload = sys.argv[1]
try:
    data = json.loads(payload)
except json.JSONDecodeError:
    print(0)
    raise SystemExit
print(len(data.get("data", {}).get("result", [])))
PY
}

metric_max_value() {
  local response="$1"
  /usr/bin/python3 - "$response" <<'PY'
import json
import sys

payload = sys.argv[1]
try:
    data = json.loads(payload)
except json.JSONDecodeError:
    raise SystemExit
values = []
for result in data.get("data", {}).get("result", []):
    try:
        values.append(float(result.get("value", [None, ""])[1]))
    except (TypeError, ValueError, IndexError):
        pass
if values:
    print(max(values))
PY
}

performance_threshold_check() {
  local label="${1:?missing label}"
  local baseline_value="${2:?missing baseline value}"
  local compare_value="${3:?missing compare value}"
  /usr/bin/python3 - "$label" "$baseline_value" "$compare_value" <<'PY'
import sys

label, baseline_raw, compare_raw = sys.argv[1], sys.argv[2], sys.argv[3]
baseline = float(baseline_raw)
compare = float(compare_raw)
threshold = max(baseline * 2.0, baseline + 25.0)
if compare > threshold:
    print(f"{label} regressed: baseline={baseline:.3f}ms compare={compare:.3f}ms threshold={threshold:.3f}ms", file=sys.stderr)
    sys.exit(1)
PY
}

wait_for_debug_observability() {
  local attempt
  for attempt in $(seq 1 45); do
    if AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
      "$PROJECT_ROOT/scripts/verify-debug-observability.sh" >/dev/null; then
      return 0
    fi
    /bin/sleep 2
  done
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
    "$PROJECT_ROOT/scripts/verify-debug-observability.sh"
}

wait_for_sidebar_metric_count() {
  local attempt
  local metrics_response
  local metrics_count
  for attempt in $(seq 1 45); do
    metrics_response="$(query_victoria_metrics "$sidebar_metric_query")"
    metrics_count="$(metric_result_count "$metrics_response")"
    if [ "$metrics_count" != "0" ]; then
      printf '%s\n%s\n' "$metrics_count" "$metrics_response"
      return 0
    fi
    /bin/sleep 2
  done
  metrics_response="$(query_victoria_metrics "$sidebar_metric_query")"
  metrics_count="$(metric_result_count "$metrics_response")"
  printf '%s\n%s\n' "$metrics_count" "$metrics_response"
}

wait_for_sidebar_metric_value() {
  local query="$1"
  local attempt
  local metrics_response
  local metrics_count
  local metrics_value
  for attempt in $(seq 1 45); do
    metrics_response="$(query_victoria_metrics "$query")"
    metrics_count="$(metric_result_count "$metrics_response")"
    if [ "$metrics_count" != "0" ]; then
      metrics_value="$(metric_max_value "$metrics_response")"
      printf '%s\n%s\n%s\n' "$metrics_count" "$metrics_value" "$metrics_response"
      return 0
    fi
    /bin/sleep 2
  done
  metrics_response="$(query_victoria_metrics "$query")"
  metrics_count="$(metric_result_count "$metrics_response")"
  metrics_value="$(metric_max_value "$metrics_response")"
  printf '%s\n%s\n%s\n' "$metrics_count" "$metrics_value" "$metrics_response"
}

validate_controls

PROOF_ROOT="${AGENTSTUDIO_SIDEBAR_PROOF_ROOT:-$DEFAULT_PROOF_ROOT}"
TRACE_NAME="$(validate_trace_name "${AGENTSTUDIO_TRACE_NAME:-sidebar-performance-$(date +%Y%m%d%H%M%S)-$$}")"
ARTIFACT="$PROOF_ROOT/$TRACE_NAME"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$ARTIFACT/debug-observability.env}"
SUMMARY_FILE="$ARTIFACT/summary.txt"
BASELINE_FILE="$PROOF_ROOT/sidebar-performance-baseline.env"
mkdir -p "$ARTIFACT" "$(dirname "$STATE_FILE")"

sidebar_metric_query='agentstudio_performance_events_total{agent.proof.marker="'$(metric_label_selector "$TRACE_NAME")'",event="performance.sidebar.projection",surface=~"inbox|repo",phase=~"startup_diagnostic|mainactor_apply|projection_worker"}'
inbox_worker_event_query='agentstudio_performance_events_total{agent.proof.marker="'$(metric_label_selector "$TRACE_NAME")'",event="performance.sidebar.projection",surface="inbox",phase="projection_worker"}'
inbox_apply_event_query='agentstudio_performance_events_total{agent.proof.marker="'$(metric_label_selector "$TRACE_NAME")'",event="performance.sidebar.projection",surface="inbox",phase="mainactor_apply"}'
inbox_worker_elapsed_query='agentstudio_performance_event_elapsed_ms_max{agent.proof.marker="'$(metric_label_selector "$TRACE_NAME")'",event="performance.sidebar.projection",surface="inbox",phase="projection_worker"}'
inbox_apply_elapsed_query='agentstudio_performance_event_elapsed_ms_max{agent.proof.marker="'$(metric_label_selector "$TRACE_NAME")'",event="performance.sidebar.projection",surface="inbox",phase="mainactor_apply"}'

if [ "$mode" = "prepare-only" ]; then
  metrics_response="$(query_victoria_metrics "$sidebar_metric_query")"
  metrics_count="$(metric_result_count "$metrics_response")"
  {
    echo "mode=$mode"
    echo "trace_name=$TRACE_NAME"
    echo "state_file=$STATE_FILE"
    echo "startup_diagnostic=sidebar-performance-proof"
    echo "requires_unsafe_no_auth=false"
    echo "requires_non_foreground_activation=true"
    echo "sidebar_projection.metric_result_count=$metrics_count"
  } >"$SUMMARY_FILE"
  echo "sidebar performance workload prepare-only ok: $SUMMARY_FILE"
  exit 0
fi

env \
  AGENTSTUDIO_TRACE_TAGS="$WORKLOAD_TRACE_TAGS" \
  AGENTSTUDIO_TRACE_NAME="$TRACE_NAME" \
  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=sidebar-performance-proof \
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
  "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach

AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
  wait_for_debug_observability

activation_mode="$(decode_env_file_value "$STATE_FILE" AGENTSTUDIO_OBSERVABILITY_ACTIVATION_MODE)"
ipc_auth_mode="$(decode_env_file_value "$STATE_FILE" AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE)"
if [ "$ipc_auth_mode" != "authenticated" ]; then
  echo "sidebar proof requires authenticated IPC auth mode: ${ipc_auth_mode:-<missing>}" >&2
  exit 1
fi
if [ "$activation_mode" != "background" ]; then
  echo "sidebar proof requires background LaunchServices activation mode: ${activation_mode:-<missing>}" >&2
  exit 1
fi

metrics_result="$(wait_for_sidebar_metric_count)"
metrics_count="$(printf '%s\n' "$metrics_result" | sed -n '1p')"
metrics_response="$(printf '%s\n' "$metrics_result" | sed '1d')"
if [ "$metrics_count" = "0" ]; then
  echo "missing sidebar projection Victoria metric for marker $TRACE_NAME" >&2
  echo "$metrics_response" >&2
  exit 1
fi

worker_event_result="$(wait_for_sidebar_metric_value "$inbox_worker_event_query")"
worker_event_count="$(printf '%s\n' "$worker_event_result" | sed -n '1p')"
worker_event_response="$(printf '%s\n' "$worker_event_result" | sed '1,2d')"
if [ "$worker_event_count" = "0" ]; then
  echo "missing inbox projection_worker event metric for marker $TRACE_NAME" >&2
  echo "$worker_event_response" >&2
  exit 1
fi

apply_event_result="$(wait_for_sidebar_metric_value "$inbox_apply_event_query")"
apply_event_count="$(printf '%s\n' "$apply_event_result" | sed -n '1p')"
apply_event_response="$(printf '%s\n' "$apply_event_result" | sed '1,2d')"
if [ "$apply_event_count" = "0" ]; then
  echo "missing inbox mainactor_apply event metric for marker $TRACE_NAME" >&2
  echo "$apply_event_response" >&2
  exit 1
fi

worker_elapsed_result="$(wait_for_sidebar_metric_value "$inbox_worker_elapsed_query")"
worker_elapsed_count="$(printf '%s\n' "$worker_elapsed_result" | sed -n '1p')"
worker_elapsed_ms="$(printf '%s\n' "$worker_elapsed_result" | sed -n '2p')"
worker_elapsed_response="$(printf '%s\n' "$worker_elapsed_result" | sed '1,2d')"
if [ "$worker_elapsed_count" = "0" ] || [ -z "$worker_elapsed_ms" ]; then
  echo "missing inbox projection_worker elapsed metric for marker $TRACE_NAME" >&2
  echo "$worker_elapsed_response" >&2
  exit 1
fi

apply_elapsed_result="$(wait_for_sidebar_metric_value "$inbox_apply_elapsed_query")"
apply_elapsed_count="$(printf '%s\n' "$apply_elapsed_result" | sed -n '1p')"
apply_elapsed_ms="$(printf '%s\n' "$apply_elapsed_result" | sed -n '2p')"
apply_elapsed_response="$(printf '%s\n' "$apply_elapsed_result" | sed '1,2d')"
if [ "$apply_elapsed_count" = "0" ] || [ -z "$apply_elapsed_ms" ]; then
  echo "missing inbox mainactor_apply elapsed metric for marker $TRACE_NAME" >&2
  echo "$apply_elapsed_response" >&2
  exit 1
fi

if [ "$mode" = "baseline" ]; then
  {
    echo "trace_name=$TRACE_NAME"
    echo "inbox_projection_worker_elapsed_ms_max=$worker_elapsed_ms"
    echo "inbox_mainactor_apply_elapsed_ms_max=$apply_elapsed_ms"
  } >"$BASELINE_FILE"
fi

if [ "$mode" = "compare" ]; then
  if [ ! -f "$BASELINE_FILE" ]; then
    echo "missing sidebar baseline artifact: $BASELINE_FILE; run --baseline first" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  . "$BASELINE_FILE"
  performance_threshold_check \
    inbox_projection_worker_elapsed_ms_max \
    "${inbox_projection_worker_elapsed_ms_max:?missing baseline worker elapsed}" \
    "$worker_elapsed_ms"
  performance_threshold_check \
    inbox_mainactor_apply_elapsed_ms_max \
    "${inbox_mainactor_apply_elapsed_ms_max:?missing baseline apply elapsed}" \
    "$apply_elapsed_ms"
fi

{
  echo "mode=$mode"
  echo "trace_name=$TRACE_NAME"
  echo "state_file=$STATE_FILE"
  echo "activation_mode=$activation_mode"
  echo "ipc_auth_mode=$ipc_auth_mode"
  echo "sidebar_projection.metric_result_count=$metrics_count"
  echo "inbox_projection_worker.metric_result_count=$worker_event_count"
  echo "inbox_mainactor_apply.metric_result_count=$apply_event_count"
  echo "inbox_projection_worker_elapsed_ms_max=$worker_elapsed_ms"
  echo "inbox_mainactor_apply_elapsed_ms_max=$apply_elapsed_ms"
  if [ "$mode" = "baseline" ] || [ "$mode" = "compare" ]; then
    echo "baseline_file=$BASELINE_FILE"
  fi
} >"$SUMMARY_FILE"
echo "sidebar performance workload ok: $SUMMARY_FILE"
