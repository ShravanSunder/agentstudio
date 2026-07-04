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

metric_value_or_empty() {
  local query="$1"
  local response
  response="$(query_victoria_metrics "$query")"
  metric_max_value "$response"
}

metric_event_elapsed_selector() {
  local surface="$1"
  local phase="$2"
  local group_mode="$3"
  local trigger="$4"
  local event_name="performance.sidebar.projection"
  if [ "$phase" = "row_index" ]; then
    event_name="performance.sidebar.row_index"
  fi
  printf 'agent.proof.marker="%s",event="%s",surface="%s",phase="%s",group_mode="%s",trigger="%s"' \
    "$(metric_label_selector "$TRACE_NAME")" \
    "$(metric_label_selector "$event_name")" \
    "$(metric_label_selector "$surface")" \
    "$(metric_label_selector "$phase")" \
    "$(metric_label_selector "$group_mode")" \
    "$(metric_label_selector "$trigger")"
}

metric_event_elapsed_max_query() {
  local surface="$1"
  local phase="$2"
  local group_mode="$3"
  local trigger="$4"
  printf 'max(agentstudio_performance_event_elapsed_ms_max{%s})' \
    "$(metric_event_elapsed_selector "$surface" "$phase" "$group_mode" "$trigger")"
}

metric_event_elapsed_p95_query() {
  local surface="$1"
  local phase="$2"
  local group_mode="$3"
  local trigger="$4"
  printf 'histogram_quantile(0.95, sum by (le) (agentstudio_performance_event_elapsed_ms_bucket{%s}))' \
    "$(metric_event_elapsed_selector "$surface" "$phase" "$group_mode" "$trigger")"
}

metric_event_elapsed_count_query() {
  local surface="$1"
  local phase="$2"
  local group_mode="$3"
  local trigger="$4"
  printf 'sum(agentstudio_performance_event_elapsed_ms_bucket{%s,le="+Inf"})' \
    "$(metric_event_elapsed_selector "$surface" "$phase" "$group_mode" "$trigger")"
}

require_metric_value() {
  local key="$1"
  local query="$2"
  local value
  value="$(metric_value_or_empty "$query")"
  if [ -z "$value" ]; then
    echo "missing required sidebar metric series: $key" >&2
    echo "query: $query" >&2
    exit 1
  fi
  printf '%s\n' "$value"
}

wait_for_required_metric_count() {
  local key="$1"
  local query="$2"
  local minimum="$3"
  local attempt
  local value
  for attempt in $(seq 1 30); do
    value="$(metric_value_or_empty "$query")"
    if [ -n "$value" ]; then
      if /usr/bin/python3 - "$value" "$minimum" <<'PY'
import sys

value = float(sys.argv[1])
minimum = float(sys.argv[2])
raise SystemExit(0 if value >= minimum else 1)
PY
      then
        printf '%s\n' "$value"
        return 0
      fi
    fi
    /bin/sleep 2
  done
  echo "missing required sidebar metric sample count: $key >= $minimum" >&2
  echo "query: $query" >&2
  echo "value: ${value:-<missing>}" >&2
  exit 1
}

wait_for_required_metric_value() {
  local key="$1"
  local query="$2"
  local attempt
  local value
  for attempt in $(seq 1 30); do
    value="$(metric_value_or_empty "$query")"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
    /bin/sleep 2
  done
  require_metric_value "$key" "$query"
}

run_authenticated_sidebar_ipc_workload() {
  local metadata_path="${1:?missing metadata path}"
  local debug_token_path="${2:?missing debug token path}"
  /usr/bin/python3 - "$metadata_path" "$debug_token_path" <<'PY'
import json
import os
import socket
import sys
import time

metadata_path = sys.argv[1]
debug_token_path = sys.argv[2]
timeout = float(os.environ.get("AGENTSTUDIO_SIDEBAR_IPC_TIMEOUT_SECONDS", "15"))
step_delay = float(os.environ.get("AGENTSTUDIO_SIDEBAR_IPC_STEP_DELAY_SECONDS", "0.35"))
cycles = int(os.environ.get("AGENTSTUDIO_SIDEBAR_IPC_CYCLES", "5"))

with open(metadata_path, "r", encoding="utf-8") as metadata_file:
    metadata = json.load(metadata_file)
socket_path = metadata.get("socketPath")
if not socket_path:
    print(f"IPC metadata missing socketPath: {metadata_path}", file=sys.stderr)
    sys.exit(1)
with open(debug_token_path, "r", encoding="utf-8") as token_file:
    token = token_file.read().strip()
if not token:
    print(f"IPC debug token file is empty: {debug_token_path}", file=sys.stderr)
    sys.exit(1)


class Session:
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.settimeout(timeout)
        self.socket.connect(path)
        self.reader = self.socket.makefile("rb")

    def close(self):
        self.reader.close()
        self.socket.close()

    def request(self, request_id, method, params):
        payload = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
        self.socket.sendall((json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8"))
        while True:
            line = self.reader.readline()
            if not line:
                print(f"IPC socket closed before response for {method}", file=sys.stderr)
                sys.exit(1)
            response = json.loads(line.decode("utf-8"))
            if response.get("id") == request_id:
                return response


def require_success(response, label):
    if response.get("error") is not None:
        print(f"{label} failed: {response['error']}", file=sys.stderr)
        sys.exit(1)
    return response.get("result", {})


def require_error(response, label, expected_code, expected_message):
    error = response.get("error")
    if error is None:
        print(f"{label} unexpectedly succeeded: {response.get('result', {})}", file=sys.stderr)
        sys.exit(1)
    if error.get("code") != expected_code or error.get("message") != expected_message:
        print(f"{label} returned unexpected error: {error}", file=sys.stderr)
        sys.exit(1)


session = Session(socket_path)
try:
    require_success(session.request(1, "auth.login", {"token": token}), "auth.login")
    if os.path.exists(debug_token_path):
        print(f"IPC debug token was not consumed: {debug_token_path}", file=sys.stderr)
        sys.exit(1)
    replay = Session(socket_path)
    try:
        require_error(replay.request(900, "auth.login", {"token": token}), "auth.login replay", -32001, "unauthenticated")
    finally:
        replay.close()

    request_id = [2]

    def next_id():
        current = request_id[0]
        request_id[0] += 1
        return current

    def set_grouping(surface, mode):
        require_success(
            session.request(next_id(), "sidebar.grouping.set", {"surface": surface, "mode": mode}),
            f"sidebar.grouping.set {surface} {mode}",
        )
        result = require_success(
            session.request(next_id(), "sidebar.grouping.get", {"surface": surface}),
            f"sidebar.grouping.get {surface}",
        )
        if result.get("mode") != mode:
            print(f"sidebar grouping read-back mismatch for {surface}: {result}", file=sys.stderr)
            sys.exit(1)
        if step_delay > 0:
            time.sleep(step_delay)

    def set_surface(surface):
        require_success(
            session.request(next_id(), "sidebar.surface.set", {"surface": surface}),
            f"sidebar.surface.set {surface}",
        )
        result = require_success(
            session.request(next_id(), "sidebar.surface.get", {}),
            "sidebar.surface.get",
        )
        if result.get("surface") != surface:
            print(f"sidebar surface read-back mismatch for {surface}: {result}", file=sys.stderr)
            sys.exit(1)
        if step_delay > 0:
            time.sleep(step_delay)

    def set_repo_visibility(mode):
        result = require_success(
            session.request(
                next_id(),
                "command.execute",
                {
                    "commandId": "setRepoSidebarVisibilityMode",
                    "targetHandle": None,
                    "arguments": {"mode": mode},
                },
            ),
            f"command.execute setRepoSidebarVisibilityMode {mode}",
        )
        if result.get("applied") is not True:
            print(f"repo visibility command did not apply for {mode}: {result}", file=sys.stderr)
            sys.exit(1)
        if step_delay > 0:
            time.sleep(step_delay)

    def set_repo_sort_order(order):
        result = require_success(
            session.request(
                next_id(),
                "command.execute",
                {
                    "commandId": "setRepoSidebarSortOrder",
                    "targetHandle": None,
                    "arguments": {"order": order},
                },
            ),
            f"command.execute setRepoSidebarSortOrder {order}",
        )
        if result.get("applied") is not True:
            print(f"repo sort order command did not apply for {order}: {result}", file=sys.stderr)
            sys.exit(1)
        if step_delay > 0:
            time.sleep(step_delay)

    for _ in range(cycles):
        set_surface("repo")
        set_repo_sort_order("descending")
        set_repo_sort_order("ascending")
        set_repo_visibility("favoritesOnly")
        set_repo_visibility("all")
        set_grouping("repo", "repo")
        set_grouping("repo", "pane")
        set_grouping("repo", "tab")
        set_grouping("repo", "repo")
        set_surface("inbox")
        set_grouping("inbox", "tab")
        set_grouping("inbox", "repo")
        set_grouping("inbox", "pane")
        set_grouping("inbox", "none")
        set_grouping("inbox", "tab")
        set_surface("repo")
        set_surface("inbox")
        set_surface("repo")
finally:
    session.close()
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

sidebar_metric_query='agentstudio_performance_events_total{agent.proof.marker="'$(metric_label_selector "$TRACE_NAME")'",event="performance.sidebar.projection",surface=~"inbox|repo",phase=~"startup_diagnostic|request_build_mainactor|mainactor_apply|projection_worker|row_index"}'
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
  AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
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

state_data_dir="$(decode_env_file_value "$STATE_FILE" AGENTSTUDIO_OBSERVABILITY_DATA_DIR)"
ipc_metadata_path="${AGENTSTUDIO_OBSERVABILITY_IPC_METADATA:-$state_data_dir/ipc/runtime.json}"
ipc_debug_token_path="${AGENTSTUDIO_OBSERVABILITY_IPC_DEBUG_TOKEN:-$state_data_dir/ipc/debug-token}"
run_authenticated_sidebar_ipc_workload "$ipc_metadata_path" "$ipc_debug_token_path"

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

repo_pane_projection_worker_elapsed_ms_p95="$(
  wait_for_required_metric_value repo_pane_projection_worker_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo projection_worker pane grouping_switch)"
)"
repo_pane_projection_worker_elapsed_ms_max="$(
  wait_for_required_metric_value repo_pane_projection_worker_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo projection_worker pane grouping_switch)"
)"
repo_tab_mainactor_apply_elapsed_ms_p95="$(
  wait_for_required_metric_value repo_tab_mainactor_apply_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo mainactor_apply tab grouping_switch)"
)"
repo_tab_mainactor_apply_elapsed_ms_max="$(
  wait_for_required_metric_value repo_tab_mainactor_apply_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo mainactor_apply tab grouping_switch)"
)"
inbox_none_projection_worker_elapsed_ms_p95="$(
  wait_for_required_metric_value inbox_none_projection_worker_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query inbox projection_worker none grouping_switch)"
)"
inbox_none_projection_worker_elapsed_ms_max="$(
  wait_for_required_metric_value inbox_none_projection_worker_elapsed_ms_max \
    "$(metric_event_elapsed_max_query inbox projection_worker none grouping_switch)"
)"
inbox_pane_mainactor_apply_elapsed_ms_p95="$(
  wait_for_required_metric_value inbox_pane_mainactor_apply_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query inbox mainactor_apply pane grouping_switch)"
)"
inbox_pane_mainactor_apply_elapsed_ms_max="$(
  wait_for_required_metric_value inbox_pane_mainactor_apply_elapsed_ms_max \
    "$(metric_event_elapsed_max_query inbox mainactor_apply pane grouping_switch)"
)"
repo_pane_projection_worker_elapsed_ms_count="$(
  wait_for_required_metric_count repo_pane_projection_worker_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo projection_worker pane grouping_switch)" 3
)"
repo_visibility_projection_worker_elapsed_ms_p95="$(
  wait_for_required_metric_value repo_visibility_projection_worker_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo projection_worker repo visibility_mode)"
)"
repo_visibility_projection_worker_elapsed_ms_max="$(
  wait_for_required_metric_value repo_visibility_projection_worker_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo projection_worker repo visibility_mode)"
)"
repo_visibility_projection_worker_elapsed_ms_count="$(
  wait_for_required_metric_count repo_visibility_projection_worker_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo projection_worker repo visibility_mode)" 3
)"
repo_visibility_mainactor_apply_elapsed_ms_p95="$(
  wait_for_required_metric_value repo_visibility_mainactor_apply_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo mainactor_apply repo visibility_mode)"
)"
repo_visibility_mainactor_apply_elapsed_ms_max="$(
  wait_for_required_metric_value repo_visibility_mainactor_apply_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo mainactor_apply repo visibility_mode)"
)"
repo_visibility_mainactor_apply_elapsed_ms_count="$(
  wait_for_required_metric_count repo_visibility_mainactor_apply_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo mainactor_apply repo visibility_mode)" 3
)"
repo_sort_projection_worker_elapsed_ms_p95="$(
  wait_for_required_metric_value repo_sort_projection_worker_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo projection_worker repo sort_order)"
)"
repo_sort_projection_worker_elapsed_ms_max="$(
  wait_for_required_metric_value repo_sort_projection_worker_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo projection_worker repo sort_order)"
)"
repo_sort_projection_worker_elapsed_ms_count="$(
  wait_for_required_metric_count repo_sort_projection_worker_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo projection_worker repo sort_order)" 3
)"
repo_sort_mainactor_apply_elapsed_ms_p95="$(
  wait_for_required_metric_value repo_sort_mainactor_apply_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo mainactor_apply repo sort_order)"
)"
repo_sort_mainactor_apply_elapsed_ms_max="$(
  wait_for_required_metric_value repo_sort_mainactor_apply_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo mainactor_apply repo sort_order)"
)"
repo_sort_mainactor_apply_elapsed_ms_count="$(
  wait_for_required_metric_count repo_sort_mainactor_apply_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo mainactor_apply repo sort_order)" 3
)"
repo_sort_request_build_mainactor_elapsed_ms_p95="$(
  wait_for_required_metric_value repo_sort_request_build_mainactor_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo request_build_mainactor repo sort_order)"
)"
repo_sort_request_build_mainactor_elapsed_ms_max="$(
  wait_for_required_metric_value repo_sort_request_build_mainactor_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo request_build_mainactor repo sort_order)"
)"
repo_sort_request_build_mainactor_elapsed_ms_count="$(
  wait_for_required_metric_count repo_sort_request_build_mainactor_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo request_build_mainactor repo sort_order)" 3
)"
repo_sort_row_index_elapsed_ms_p95="$(
  wait_for_required_metric_value repo_sort_row_index_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo row_index repo sort_order)"
)"
repo_sort_row_index_elapsed_ms_max="$(
  wait_for_required_metric_value repo_sort_row_index_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo row_index repo sort_order)"
)"
repo_sort_row_index_elapsed_ms_count="$(
  wait_for_required_metric_count repo_sort_row_index_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo row_index repo sort_order)" 3
)"
repo_tab_mainactor_apply_elapsed_ms_count="$(
  wait_for_required_metric_count repo_tab_mainactor_apply_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo mainactor_apply tab grouping_switch)" 3
)"
inbox_none_projection_worker_elapsed_ms_count="$(
  wait_for_required_metric_count inbox_none_projection_worker_elapsed_ms_count \
    "$(metric_event_elapsed_count_query inbox projection_worker none grouping_switch)" 3
)"
inbox_pane_mainactor_apply_elapsed_ms_count="$(
  wait_for_required_metric_count inbox_pane_mainactor_apply_elapsed_ms_count \
    "$(metric_event_elapsed_count_query inbox mainactor_apply pane grouping_switch)" 3
)"
repo_pane_request_build_mainactor_elapsed_ms_p95="$(
  wait_for_required_metric_value repo_pane_request_build_mainactor_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo request_build_mainactor pane grouping_switch)"
)"
repo_pane_request_build_mainactor_elapsed_ms_max="$(
  wait_for_required_metric_value repo_pane_request_build_mainactor_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo request_build_mainactor pane grouping_switch)"
)"
repo_pane_request_build_mainactor_elapsed_ms_count="$(
  wait_for_required_metric_count repo_pane_request_build_mainactor_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo request_build_mainactor pane grouping_switch)" 3
)"
repo_pane_row_index_elapsed_ms_p95="$(
  wait_for_required_metric_value repo_pane_row_index_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo row_index pane grouping_switch)"
)"
repo_pane_row_index_elapsed_ms_max="$(
  wait_for_required_metric_value repo_pane_row_index_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo row_index pane grouping_switch)"
)"
repo_pane_row_index_elapsed_ms_count="$(
  wait_for_required_metric_count repo_pane_row_index_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo row_index pane grouping_switch)" 3
)"
inbox_none_request_build_mainactor_elapsed_ms_p95="$(
  wait_for_required_metric_value inbox_none_request_build_mainactor_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query inbox request_build_mainactor none grouping_switch)"
)"
inbox_none_request_build_mainactor_elapsed_ms_max="$(
  wait_for_required_metric_value inbox_none_request_build_mainactor_elapsed_ms_max \
    "$(metric_event_elapsed_max_query inbox request_build_mainactor none grouping_switch)"
)"
inbox_none_request_build_mainactor_elapsed_ms_count="$(
  wait_for_required_metric_count inbox_none_request_build_mainactor_elapsed_ms_count \
    "$(metric_event_elapsed_count_query inbox request_build_mainactor none grouping_switch)" 3
)"
surface_switch_repo_mainactor_apply_elapsed_ms_p95="$(
  wait_for_required_metric_value surface_switch_repo_mainactor_apply_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query repo mainactor_apply not_applicable surface_switch)"
)"
surface_switch_repo_mainactor_apply_elapsed_ms_max="$(
  wait_for_required_metric_value surface_switch_repo_mainactor_apply_elapsed_ms_max \
    "$(metric_event_elapsed_max_query repo mainactor_apply not_applicable surface_switch)"
)"
surface_switch_repo_mainactor_apply_elapsed_ms_count="$(
  wait_for_required_metric_count surface_switch_repo_mainactor_apply_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo mainactor_apply not_applicable surface_switch)" 3
)"
surface_switch_inbox_mainactor_apply_elapsed_ms_p95="$(
  wait_for_required_metric_value surface_switch_inbox_mainactor_apply_elapsed_ms_p95 \
    "$(metric_event_elapsed_p95_query inbox mainactor_apply not_applicable surface_switch)"
)"
surface_switch_inbox_mainactor_apply_elapsed_ms_max="$(
  wait_for_required_metric_value surface_switch_inbox_mainactor_apply_elapsed_ms_max \
    "$(metric_event_elapsed_max_query inbox mainactor_apply not_applicable surface_switch)"
)"
surface_switch_inbox_mainactor_apply_elapsed_ms_count="$(
  wait_for_required_metric_count surface_switch_inbox_mainactor_apply_elapsed_ms_count \
    "$(metric_event_elapsed_count_query inbox mainactor_apply not_applicable surface_switch)" 3
)"

if [ "$mode" = "baseline" ]; then
  {
    echo "trace_name=$TRACE_NAME"
    echo "inbox_projection_worker_elapsed_ms_max=$worker_elapsed_ms"
    echo "inbox_mainactor_apply_elapsed_ms_max=$apply_elapsed_ms"
    echo "repo_pane_projection_worker_elapsed_ms_p95=$repo_pane_projection_worker_elapsed_ms_p95"
    echo "repo_pane_projection_worker_elapsed_ms_max=$repo_pane_projection_worker_elapsed_ms_max"
    echo "repo_visibility_projection_worker_elapsed_ms_p95=$repo_visibility_projection_worker_elapsed_ms_p95"
    echo "repo_visibility_projection_worker_elapsed_ms_max=$repo_visibility_projection_worker_elapsed_ms_max"
    echo "repo_visibility_mainactor_apply_elapsed_ms_p95=$repo_visibility_mainactor_apply_elapsed_ms_p95"
    echo "repo_visibility_mainactor_apply_elapsed_ms_max=$repo_visibility_mainactor_apply_elapsed_ms_max"
    echo "repo_sort_projection_worker_elapsed_ms_p95=$repo_sort_projection_worker_elapsed_ms_p95"
    echo "repo_sort_projection_worker_elapsed_ms_max=$repo_sort_projection_worker_elapsed_ms_max"
    echo "repo_sort_mainactor_apply_elapsed_ms_p95=$repo_sort_mainactor_apply_elapsed_ms_p95"
    echo "repo_sort_mainactor_apply_elapsed_ms_max=$repo_sort_mainactor_apply_elapsed_ms_max"
    echo "repo_sort_request_build_mainactor_elapsed_ms_p95=$repo_sort_request_build_mainactor_elapsed_ms_p95"
    echo "repo_sort_request_build_mainactor_elapsed_ms_max=$repo_sort_request_build_mainactor_elapsed_ms_max"
    echo "repo_sort_row_index_elapsed_ms_p95=$repo_sort_row_index_elapsed_ms_p95"
    echo "repo_sort_row_index_elapsed_ms_max=$repo_sort_row_index_elapsed_ms_max"
    echo "repo_tab_mainactor_apply_elapsed_ms_p95=$repo_tab_mainactor_apply_elapsed_ms_p95"
    echo "repo_tab_mainactor_apply_elapsed_ms_max=$repo_tab_mainactor_apply_elapsed_ms_max"
    echo "inbox_none_projection_worker_elapsed_ms_p95=$inbox_none_projection_worker_elapsed_ms_p95"
    echo "inbox_none_projection_worker_elapsed_ms_max=$inbox_none_projection_worker_elapsed_ms_max"
    echo "inbox_pane_mainactor_apply_elapsed_ms_p95=$inbox_pane_mainactor_apply_elapsed_ms_p95"
    echo "inbox_pane_mainactor_apply_elapsed_ms_max=$inbox_pane_mainactor_apply_elapsed_ms_max"
    echo "repo_pane_request_build_mainactor_elapsed_ms_p95=$repo_pane_request_build_mainactor_elapsed_ms_p95"
    echo "repo_pane_request_build_mainactor_elapsed_ms_max=$repo_pane_request_build_mainactor_elapsed_ms_max"
    echo "repo_pane_row_index_elapsed_ms_p95=$repo_pane_row_index_elapsed_ms_p95"
    echo "repo_pane_row_index_elapsed_ms_max=$repo_pane_row_index_elapsed_ms_max"
    echo "inbox_none_request_build_mainactor_elapsed_ms_p95=$inbox_none_request_build_mainactor_elapsed_ms_p95"
    echo "inbox_none_request_build_mainactor_elapsed_ms_max=$inbox_none_request_build_mainactor_elapsed_ms_max"
    echo "surface_switch_repo_mainactor_apply_elapsed_ms_p95=$surface_switch_repo_mainactor_apply_elapsed_ms_p95"
    echo "surface_switch_repo_mainactor_apply_elapsed_ms_max=$surface_switch_repo_mainactor_apply_elapsed_ms_max"
    echo "surface_switch_inbox_mainactor_apply_elapsed_ms_p95=$surface_switch_inbox_mainactor_apply_elapsed_ms_p95"
    echo "surface_switch_inbox_mainactor_apply_elapsed_ms_max=$surface_switch_inbox_mainactor_apply_elapsed_ms_max"
  } >"$BASELINE_FILE"
fi

if [ "$mode" = "compare" ]; then
  if [ ! -f "$BASELINE_FILE" ]; then
    echo "missing sidebar baseline artifact: $BASELINE_FILE; run --baseline first" >&2
    exit 1
  fi
  compare_repo_pane_projection_worker_elapsed_ms_p95="$repo_pane_projection_worker_elapsed_ms_p95"
  compare_repo_pane_projection_worker_elapsed_ms_max="$repo_pane_projection_worker_elapsed_ms_max"
  compare_repo_visibility_projection_worker_elapsed_ms_p95="$repo_visibility_projection_worker_elapsed_ms_p95"
  compare_repo_visibility_projection_worker_elapsed_ms_max="$repo_visibility_projection_worker_elapsed_ms_max"
  compare_repo_visibility_mainactor_apply_elapsed_ms_p95="$repo_visibility_mainactor_apply_elapsed_ms_p95"
  compare_repo_visibility_mainactor_apply_elapsed_ms_max="$repo_visibility_mainactor_apply_elapsed_ms_max"
  compare_repo_sort_projection_worker_elapsed_ms_p95="$repo_sort_projection_worker_elapsed_ms_p95"
  compare_repo_sort_projection_worker_elapsed_ms_max="$repo_sort_projection_worker_elapsed_ms_max"
  compare_repo_sort_mainactor_apply_elapsed_ms_p95="$repo_sort_mainactor_apply_elapsed_ms_p95"
  compare_repo_sort_mainactor_apply_elapsed_ms_max="$repo_sort_mainactor_apply_elapsed_ms_max"
  compare_repo_sort_request_build_mainactor_elapsed_ms_p95="$repo_sort_request_build_mainactor_elapsed_ms_p95"
  compare_repo_sort_request_build_mainactor_elapsed_ms_max="$repo_sort_request_build_mainactor_elapsed_ms_max"
  compare_repo_sort_row_index_elapsed_ms_p95="$repo_sort_row_index_elapsed_ms_p95"
  compare_repo_sort_row_index_elapsed_ms_max="$repo_sort_row_index_elapsed_ms_max"
  compare_repo_tab_mainactor_apply_elapsed_ms_p95="$repo_tab_mainactor_apply_elapsed_ms_p95"
  compare_repo_tab_mainactor_apply_elapsed_ms_max="$repo_tab_mainactor_apply_elapsed_ms_max"
  compare_inbox_none_projection_worker_elapsed_ms_p95="$inbox_none_projection_worker_elapsed_ms_p95"
  compare_inbox_none_projection_worker_elapsed_ms_max="$inbox_none_projection_worker_elapsed_ms_max"
  compare_inbox_pane_mainactor_apply_elapsed_ms_p95="$inbox_pane_mainactor_apply_elapsed_ms_p95"
  compare_inbox_pane_mainactor_apply_elapsed_ms_max="$inbox_pane_mainactor_apply_elapsed_ms_max"
  compare_repo_pane_request_build_mainactor_elapsed_ms_p95="$repo_pane_request_build_mainactor_elapsed_ms_p95"
  compare_repo_pane_request_build_mainactor_elapsed_ms_max="$repo_pane_request_build_mainactor_elapsed_ms_max"
  compare_repo_pane_row_index_elapsed_ms_p95="$repo_pane_row_index_elapsed_ms_p95"
  compare_repo_pane_row_index_elapsed_ms_max="$repo_pane_row_index_elapsed_ms_max"
  compare_inbox_none_request_build_mainactor_elapsed_ms_p95="$inbox_none_request_build_mainactor_elapsed_ms_p95"
  compare_inbox_none_request_build_mainactor_elapsed_ms_max="$inbox_none_request_build_mainactor_elapsed_ms_max"
  compare_surface_switch_repo_mainactor_apply_elapsed_ms_p95="$surface_switch_repo_mainactor_apply_elapsed_ms_p95"
  compare_surface_switch_repo_mainactor_apply_elapsed_ms_max="$surface_switch_repo_mainactor_apply_elapsed_ms_max"
  compare_surface_switch_inbox_mainactor_apply_elapsed_ms_p95="$surface_switch_inbox_mainactor_apply_elapsed_ms_p95"
  compare_surface_switch_inbox_mainactor_apply_elapsed_ms_max="$surface_switch_inbox_mainactor_apply_elapsed_ms_max"
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
  performance_threshold_check repo_pane_projection_worker_elapsed_ms_p95 \
    "${repo_pane_projection_worker_elapsed_ms_p95:?missing baseline repo pane worker p95}" \
    "$compare_repo_pane_projection_worker_elapsed_ms_p95"
  performance_threshold_check repo_pane_projection_worker_elapsed_ms_max \
    "${repo_pane_projection_worker_elapsed_ms_max:?missing baseline repo pane worker max}" \
    "$compare_repo_pane_projection_worker_elapsed_ms_max"
  performance_threshold_check repo_visibility_projection_worker_elapsed_ms_p95 \
    "${repo_visibility_projection_worker_elapsed_ms_p95:?missing baseline repo visibility worker p95}" \
    "$compare_repo_visibility_projection_worker_elapsed_ms_p95"
  performance_threshold_check repo_visibility_projection_worker_elapsed_ms_max \
    "${repo_visibility_projection_worker_elapsed_ms_max:?missing baseline repo visibility worker max}" \
    "$compare_repo_visibility_projection_worker_elapsed_ms_max"
  performance_threshold_check repo_visibility_mainactor_apply_elapsed_ms_p95 \
    "${repo_visibility_mainactor_apply_elapsed_ms_p95:?missing baseline repo visibility apply p95}" \
    "$compare_repo_visibility_mainactor_apply_elapsed_ms_p95"
  performance_threshold_check repo_visibility_mainactor_apply_elapsed_ms_max \
    "${repo_visibility_mainactor_apply_elapsed_ms_max:?missing baseline repo visibility apply max}" \
    "$compare_repo_visibility_mainactor_apply_elapsed_ms_max"
  performance_threshold_check repo_sort_projection_worker_elapsed_ms_p95 \
    "${repo_sort_projection_worker_elapsed_ms_p95:?missing baseline repo sort worker p95}" \
    "$compare_repo_sort_projection_worker_elapsed_ms_p95"
  performance_threshold_check repo_sort_projection_worker_elapsed_ms_max \
    "${repo_sort_projection_worker_elapsed_ms_max:?missing baseline repo sort worker max}" \
    "$compare_repo_sort_projection_worker_elapsed_ms_max"
  performance_threshold_check repo_sort_mainactor_apply_elapsed_ms_p95 \
    "${repo_sort_mainactor_apply_elapsed_ms_p95:?missing baseline repo sort apply p95}" \
    "$compare_repo_sort_mainactor_apply_elapsed_ms_p95"
  performance_threshold_check repo_sort_mainactor_apply_elapsed_ms_max \
    "${repo_sort_mainactor_apply_elapsed_ms_max:?missing baseline repo sort apply max}" \
    "$compare_repo_sort_mainactor_apply_elapsed_ms_max"
  performance_threshold_check repo_sort_request_build_mainactor_elapsed_ms_p95 \
    "${repo_sort_request_build_mainactor_elapsed_ms_p95:?missing baseline repo sort request-build p95}" \
    "$compare_repo_sort_request_build_mainactor_elapsed_ms_p95"
  performance_threshold_check repo_sort_request_build_mainactor_elapsed_ms_max \
    "${repo_sort_request_build_mainactor_elapsed_ms_max:?missing baseline repo sort request-build max}" \
    "$compare_repo_sort_request_build_mainactor_elapsed_ms_max"
  performance_threshold_check repo_sort_row_index_elapsed_ms_p95 \
    "${repo_sort_row_index_elapsed_ms_p95:?missing baseline repo sort row-index p95}" \
    "$compare_repo_sort_row_index_elapsed_ms_p95"
  performance_threshold_check repo_sort_row_index_elapsed_ms_max \
    "${repo_sort_row_index_elapsed_ms_max:?missing baseline repo sort row-index max}" \
    "$compare_repo_sort_row_index_elapsed_ms_max"
  performance_threshold_check repo_tab_mainactor_apply_elapsed_ms_p95 \
    "${repo_tab_mainactor_apply_elapsed_ms_p95:?missing baseline repo tab apply p95}" \
    "$compare_repo_tab_mainactor_apply_elapsed_ms_p95"
  performance_threshold_check repo_tab_mainactor_apply_elapsed_ms_max \
    "${repo_tab_mainactor_apply_elapsed_ms_max:?missing baseline repo tab apply max}" \
    "$compare_repo_tab_mainactor_apply_elapsed_ms_max"
  performance_threshold_check inbox_none_projection_worker_elapsed_ms_p95 \
    "${inbox_none_projection_worker_elapsed_ms_p95:?missing baseline inbox none worker p95}" \
    "$compare_inbox_none_projection_worker_elapsed_ms_p95"
  performance_threshold_check inbox_none_projection_worker_elapsed_ms_max \
    "${inbox_none_projection_worker_elapsed_ms_max:?missing baseline inbox none worker max}" \
    "$compare_inbox_none_projection_worker_elapsed_ms_max"
  performance_threshold_check inbox_pane_mainactor_apply_elapsed_ms_p95 \
    "${inbox_pane_mainactor_apply_elapsed_ms_p95:?missing baseline inbox pane apply p95}" \
    "$compare_inbox_pane_mainactor_apply_elapsed_ms_p95"
  performance_threshold_check inbox_pane_mainactor_apply_elapsed_ms_max \
    "${inbox_pane_mainactor_apply_elapsed_ms_max:?missing baseline inbox pane apply max}" \
    "$compare_inbox_pane_mainactor_apply_elapsed_ms_max"
  performance_threshold_check repo_pane_request_build_mainactor_elapsed_ms_p95 \
    "${repo_pane_request_build_mainactor_elapsed_ms_p95:?missing baseline repo pane request-build p95}" \
    "$compare_repo_pane_request_build_mainactor_elapsed_ms_p95"
  performance_threshold_check repo_pane_request_build_mainactor_elapsed_ms_max \
    "${repo_pane_request_build_mainactor_elapsed_ms_max:?missing baseline repo pane request-build max}" \
    "$compare_repo_pane_request_build_mainactor_elapsed_ms_max"
  performance_threshold_check repo_pane_row_index_elapsed_ms_p95 \
    "${repo_pane_row_index_elapsed_ms_p95:?missing baseline repo pane row-index p95}" \
    "$compare_repo_pane_row_index_elapsed_ms_p95"
  performance_threshold_check repo_pane_row_index_elapsed_ms_max \
    "${repo_pane_row_index_elapsed_ms_max:?missing baseline repo pane row-index max}" \
    "$compare_repo_pane_row_index_elapsed_ms_max"
  performance_threshold_check inbox_none_request_build_mainactor_elapsed_ms_p95 \
    "${inbox_none_request_build_mainactor_elapsed_ms_p95:?missing baseline inbox none request-build p95}" \
    "$compare_inbox_none_request_build_mainactor_elapsed_ms_p95"
  performance_threshold_check inbox_none_request_build_mainactor_elapsed_ms_max \
    "${inbox_none_request_build_mainactor_elapsed_ms_max:?missing baseline inbox none request-build max}" \
    "$compare_inbox_none_request_build_mainactor_elapsed_ms_max"
  performance_threshold_check surface_switch_repo_mainactor_apply_elapsed_ms_p95 \
    "${surface_switch_repo_mainactor_apply_elapsed_ms_p95:?missing baseline repo surface-switch p95}" \
    "$compare_surface_switch_repo_mainactor_apply_elapsed_ms_p95"
  performance_threshold_check surface_switch_repo_mainactor_apply_elapsed_ms_max \
    "${surface_switch_repo_mainactor_apply_elapsed_ms_max:?missing baseline repo surface-switch max}" \
    "$compare_surface_switch_repo_mainactor_apply_elapsed_ms_max"
  performance_threshold_check surface_switch_inbox_mainactor_apply_elapsed_ms_p95 \
    "${surface_switch_inbox_mainactor_apply_elapsed_ms_p95:?missing baseline inbox surface-switch p95}" \
    "$compare_surface_switch_inbox_mainactor_apply_elapsed_ms_p95"
  performance_threshold_check surface_switch_inbox_mainactor_apply_elapsed_ms_max \
    "${surface_switch_inbox_mainactor_apply_elapsed_ms_max:?missing baseline inbox surface-switch max}" \
    "$compare_surface_switch_inbox_mainactor_apply_elapsed_ms_max"
  repo_pane_projection_worker_elapsed_ms_p95="$compare_repo_pane_projection_worker_elapsed_ms_p95"
  repo_pane_projection_worker_elapsed_ms_max="$compare_repo_pane_projection_worker_elapsed_ms_max"
  repo_visibility_projection_worker_elapsed_ms_p95="$compare_repo_visibility_projection_worker_elapsed_ms_p95"
  repo_visibility_projection_worker_elapsed_ms_max="$compare_repo_visibility_projection_worker_elapsed_ms_max"
  repo_visibility_mainactor_apply_elapsed_ms_p95="$compare_repo_visibility_mainactor_apply_elapsed_ms_p95"
  repo_visibility_mainactor_apply_elapsed_ms_max="$compare_repo_visibility_mainactor_apply_elapsed_ms_max"
  repo_sort_projection_worker_elapsed_ms_p95="$compare_repo_sort_projection_worker_elapsed_ms_p95"
  repo_sort_projection_worker_elapsed_ms_max="$compare_repo_sort_projection_worker_elapsed_ms_max"
  repo_sort_mainactor_apply_elapsed_ms_p95="$compare_repo_sort_mainactor_apply_elapsed_ms_p95"
  repo_sort_mainactor_apply_elapsed_ms_max="$compare_repo_sort_mainactor_apply_elapsed_ms_max"
  repo_sort_request_build_mainactor_elapsed_ms_p95="$compare_repo_sort_request_build_mainactor_elapsed_ms_p95"
  repo_sort_request_build_mainactor_elapsed_ms_max="$compare_repo_sort_request_build_mainactor_elapsed_ms_max"
  repo_sort_row_index_elapsed_ms_p95="$compare_repo_sort_row_index_elapsed_ms_p95"
  repo_sort_row_index_elapsed_ms_max="$compare_repo_sort_row_index_elapsed_ms_max"
  repo_tab_mainactor_apply_elapsed_ms_p95="$compare_repo_tab_mainactor_apply_elapsed_ms_p95"
  repo_tab_mainactor_apply_elapsed_ms_max="$compare_repo_tab_mainactor_apply_elapsed_ms_max"
  inbox_none_projection_worker_elapsed_ms_p95="$compare_inbox_none_projection_worker_elapsed_ms_p95"
  inbox_none_projection_worker_elapsed_ms_max="$compare_inbox_none_projection_worker_elapsed_ms_max"
  inbox_pane_mainactor_apply_elapsed_ms_p95="$compare_inbox_pane_mainactor_apply_elapsed_ms_p95"
  inbox_pane_mainactor_apply_elapsed_ms_max="$compare_inbox_pane_mainactor_apply_elapsed_ms_max"
  repo_pane_request_build_mainactor_elapsed_ms_p95="$compare_repo_pane_request_build_mainactor_elapsed_ms_p95"
  repo_pane_request_build_mainactor_elapsed_ms_max="$compare_repo_pane_request_build_mainactor_elapsed_ms_max"
  repo_pane_row_index_elapsed_ms_p95="$compare_repo_pane_row_index_elapsed_ms_p95"
  repo_pane_row_index_elapsed_ms_max="$compare_repo_pane_row_index_elapsed_ms_max"
  inbox_none_request_build_mainactor_elapsed_ms_p95="$compare_inbox_none_request_build_mainactor_elapsed_ms_p95"
  inbox_none_request_build_mainactor_elapsed_ms_max="$compare_inbox_none_request_build_mainactor_elapsed_ms_max"
  surface_switch_repo_mainactor_apply_elapsed_ms_p95="$compare_surface_switch_repo_mainactor_apply_elapsed_ms_p95"
  surface_switch_repo_mainactor_apply_elapsed_ms_max="$compare_surface_switch_repo_mainactor_apply_elapsed_ms_max"
  surface_switch_inbox_mainactor_apply_elapsed_ms_p95="$compare_surface_switch_inbox_mainactor_apply_elapsed_ms_p95"
  surface_switch_inbox_mainactor_apply_elapsed_ms_max="$compare_surface_switch_inbox_mainactor_apply_elapsed_ms_max"
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
  echo "repo_pane_projection_worker_elapsed_ms_p95=$repo_pane_projection_worker_elapsed_ms_p95"
  echo "repo_pane_projection_worker_elapsed_ms_max=$repo_pane_projection_worker_elapsed_ms_max"
  echo "repo_pane_projection_worker_elapsed_ms_count=$repo_pane_projection_worker_elapsed_ms_count"
  echo "repo_visibility_projection_worker_elapsed_ms_p95=$repo_visibility_projection_worker_elapsed_ms_p95"
  echo "repo_visibility_projection_worker_elapsed_ms_max=$repo_visibility_projection_worker_elapsed_ms_max"
  echo "repo_visibility_projection_worker_elapsed_ms_count=$repo_visibility_projection_worker_elapsed_ms_count"
  echo "repo_visibility_mainactor_apply_elapsed_ms_p95=$repo_visibility_mainactor_apply_elapsed_ms_p95"
  echo "repo_visibility_mainactor_apply_elapsed_ms_max=$repo_visibility_mainactor_apply_elapsed_ms_max"
  echo "repo_visibility_mainactor_apply_elapsed_ms_count=$repo_visibility_mainactor_apply_elapsed_ms_count"
  echo "repo_sort_projection_worker_elapsed_ms_p95=$repo_sort_projection_worker_elapsed_ms_p95"
  echo "repo_sort_projection_worker_elapsed_ms_max=$repo_sort_projection_worker_elapsed_ms_max"
  echo "repo_sort_projection_worker_elapsed_ms_count=$repo_sort_projection_worker_elapsed_ms_count"
  echo "repo_sort_mainactor_apply_elapsed_ms_p95=$repo_sort_mainactor_apply_elapsed_ms_p95"
  echo "repo_sort_mainactor_apply_elapsed_ms_max=$repo_sort_mainactor_apply_elapsed_ms_max"
  echo "repo_sort_mainactor_apply_elapsed_ms_count=$repo_sort_mainactor_apply_elapsed_ms_count"
  echo "repo_sort_request_build_mainactor_elapsed_ms_p95=$repo_sort_request_build_mainactor_elapsed_ms_p95"
  echo "repo_sort_request_build_mainactor_elapsed_ms_max=$repo_sort_request_build_mainactor_elapsed_ms_max"
  echo "repo_sort_request_build_mainactor_elapsed_ms_count=$repo_sort_request_build_mainactor_elapsed_ms_count"
  echo "repo_sort_row_index_elapsed_ms_p95=$repo_sort_row_index_elapsed_ms_p95"
  echo "repo_sort_row_index_elapsed_ms_max=$repo_sort_row_index_elapsed_ms_max"
  echo "repo_sort_row_index_elapsed_ms_count=$repo_sort_row_index_elapsed_ms_count"
  echo "repo_tab_mainactor_apply_elapsed_ms_p95=$repo_tab_mainactor_apply_elapsed_ms_p95"
  echo "repo_tab_mainactor_apply_elapsed_ms_max=$repo_tab_mainactor_apply_elapsed_ms_max"
  echo "repo_tab_mainactor_apply_elapsed_ms_count=$repo_tab_mainactor_apply_elapsed_ms_count"
  echo "inbox_none_projection_worker_elapsed_ms_p95=$inbox_none_projection_worker_elapsed_ms_p95"
  echo "inbox_none_projection_worker_elapsed_ms_max=$inbox_none_projection_worker_elapsed_ms_max"
  echo "inbox_none_projection_worker_elapsed_ms_count=$inbox_none_projection_worker_elapsed_ms_count"
  echo "inbox_pane_mainactor_apply_elapsed_ms_p95=$inbox_pane_mainactor_apply_elapsed_ms_p95"
  echo "inbox_pane_mainactor_apply_elapsed_ms_max=$inbox_pane_mainactor_apply_elapsed_ms_max"
  echo "inbox_pane_mainactor_apply_elapsed_ms_count=$inbox_pane_mainactor_apply_elapsed_ms_count"
  echo "repo_pane_request_build_mainactor_elapsed_ms_p95=$repo_pane_request_build_mainactor_elapsed_ms_p95"
  echo "repo_pane_request_build_mainactor_elapsed_ms_max=$repo_pane_request_build_mainactor_elapsed_ms_max"
  echo "repo_pane_request_build_mainactor_elapsed_ms_count=$repo_pane_request_build_mainactor_elapsed_ms_count"
  echo "repo_pane_row_index_elapsed_ms_p95=$repo_pane_row_index_elapsed_ms_p95"
  echo "repo_pane_row_index_elapsed_ms_max=$repo_pane_row_index_elapsed_ms_max"
  echo "repo_pane_row_index_elapsed_ms_count=$repo_pane_row_index_elapsed_ms_count"
  echo "inbox_none_request_build_mainactor_elapsed_ms_p95=$inbox_none_request_build_mainactor_elapsed_ms_p95"
  echo "inbox_none_request_build_mainactor_elapsed_ms_max=$inbox_none_request_build_mainactor_elapsed_ms_max"
  echo "inbox_none_request_build_mainactor_elapsed_ms_count=$inbox_none_request_build_mainactor_elapsed_ms_count"
  echo "surface_switch_repo_mainactor_apply_elapsed_ms_p95=$surface_switch_repo_mainactor_apply_elapsed_ms_p95"
  echo "surface_switch_repo_mainactor_apply_elapsed_ms_max=$surface_switch_repo_mainactor_apply_elapsed_ms_max"
  echo "surface_switch_repo_mainactor_apply_elapsed_ms_count=$surface_switch_repo_mainactor_apply_elapsed_ms_count"
  echo "surface_switch_inbox_mainactor_apply_elapsed_ms_p95=$surface_switch_inbox_mainactor_apply_elapsed_ms_p95"
  echo "surface_switch_inbox_mainactor_apply_elapsed_ms_max=$surface_switch_inbox_mainactor_apply_elapsed_ms_max"
  echo "surface_switch_inbox_mainactor_apply_elapsed_ms_count=$surface_switch_inbox_mainactor_apply_elapsed_ms_count"
  echo "sidebar_surface_switch.ipc_sequence=repo,inbox,repo,inbox,repo"
  echo "repo_sort.ipc_sequence=descending,ascending"
  echo "repo_visibility.ipc_sequence=favoritesOnly,all"
  if [ "$mode" = "baseline" ] || [ "$mode" = "compare" ]; then
    echo "baseline_file=$BASELINE_FILE"
  fi
} >"$SUMMARY_FILE"
echo "sidebar performance workload ok: $SUMMARY_FILE"
