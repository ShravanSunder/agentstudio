#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_STACK_HELPER="$HOME/dev/ai-tools/observability/observability-stack"
STACK_HELPER="${AI_TOOLS_OBSERVABILITY_STACK_HELPER:-$DEFAULT_STACK_HELPER}"
COLLECTOR_HEALTH_URL="${AI_TOOLS_OBSERVABILITY_COLLECTOR_HEALTH_URL:-http://127.0.0.1:13133/}"
METRICS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL:-http://127.0.0.1:8428/api/v1/query}"
LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
DEFAULT_PROOF_ROOT="/tmp/agentstudio-sidebar-performance"
WORKLOAD_TRACE_TAGS="performance,app.startup,terminal.startup"
KEY_MUTATION_TRACE_TAGS="performance,app.startup"
WORKLOAD_CYCLES="${AGENTSTUDIO_SIDEBAR_IPC_CYCLES:-100}"
REQUIRED_SAMPLE_COUNT=100
REQUIRED_MATERIALIZED_SAMPLE_COUNT=90
REQUIRED_METRIC_READBACK_ATTEMPTS=45
WORKLOAD_FIXTURE_VERSION=sidebar-workload-v5-repo-only
REQUIRED_REPOSITORY_COUNT=150
REQUIRED_WORKTREE_COUNT=180
REQUIRED_TAB_COUNT=12
REQUIRED_PANE_COUNT=36
REQUIRED_ACTIVE_PTY_COUNT=1
STRICT_SIDEBAR_IDLE_POPULATIONS="zero_pty_idle quiescent_pty_idle"
STRICT_SIDEBAR_ACTION_POPULATIONS="search_clear grouping hide_show tab_switch"
STRICT_SIDEBAR_READBACK_FIELDS="semantic_generation acknowledged_revision visible_generation focus_disposition accessibility_disposition"
STRICT_SIDEBAR_FALSE_GREEN_OUTCOMES="population_invalidated sampler_gap"
STRICT_SIDEBAR_PERTURBATION_FIELDS="diagnostic_cpu_p95_delta_percentage_points diagnostic_interaction_p95_growth_percent"

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

decode_identity_value() {
  local identity="$1"
  local key="$2"
  local raw_value
  raw_value="$(printf '%s\n' "$identity" | sed -n "s/^$key=//p" | tail -1)"
  /usr/bin/python3 - "$raw_value" <<'PY'
import shlex
import sys

parts = shlex.split(sys.argv[1]) if sys.argv[1] else []
print(parts[0] if parts else "")
PY
}

stop_pid() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  fi
}

sample_process_cpu() {
  local pid="${1:?missing process pid}"
  local sample_file="${2:?missing CPU sample file}"
  exec /usr/bin/top -l 0 -s 1 -pid "$pid" -stats pid,cpu >"$sample_file"
}

summarize_process_cpu() {
  local sample_file="${1:?missing CPU sample file}"
  local pid="${2:?missing process pid}"
  /usr/bin/python3 - "$sample_file" "$pid" <<'PY'
import math
import pathlib
import sys

values = []
pid = sys.argv[2]
discarded_first_process_sample = False
for raw_line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    fields = raw_line.split()
    if len(fields) != 2 or fields[0] != pid:
        continue
    try:
        value = float(fields[1])
    except ValueError:
        continue
    if not discarded_first_process_sample:
        discarded_first_process_sample = True
        continue
    if math.isfinite(value):
        values.append(value)
if not values:
    raise SystemExit("process CPU sampling produced no values")
values.sort()
def percentile(fraction):
    return values[min(len(values) - 1, max(0, math.ceil(len(values) * fraction) - 1))]
print(percentile(0.50))
print(percentile(0.95))
print(values[-1])
print(len(values))
PY
}

owned_zmx_pids() {
  /bin/ps -axo pid=,command= | /usr/bin/python3 -c '
import os, shlex, sys
data_dir = sys.argv[1]
for line in sys.stdin:
    process_fields = line.strip().split(maxsplit=1)
    if len(process_fields) != 2 or not process_fields[0].isdigit():
        continue
    command = process_fields[1]
    try:
        command_parts = shlex.split(command)
    except ValueError:
        continue
    if not command_parts or os.path.basename(command_parts[0]) != "zmx":
        continue
    if data_dir in command:
        print(process_fields[0])
' "$RESET_DATA_DIR"
}

reset_disposable_debug_root() {
  local expected_bundle_identifier zmx_pid zmx_pids
  RESET_IDENTITY="$("$PROJECT_ROOT/scripts/run-debug-observability.sh" --print-identity)"
  RESET_DEBUG_CODE="$(decode_identity_value "$RESET_IDENTITY" AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE)"
  RESET_DATA_DIR="$(decode_identity_value "$RESET_IDENTITY" AGENTSTUDIO_OBSERVABILITY_DATA_DIR)"
  RESET_BUNDLE_IDENTIFIER="$(decode_identity_value "$RESET_IDENTITY" AGENTSTUDIO_OBSERVABILITY_BUNDLE_IDENTIFIER)"

  case "$RESET_DATA_DIR" in
    "$HOME/.agentstudio-db/"*) ;;
    *) echo "refusing to reset debug data root outside $HOME/.agentstudio-db/: $RESET_DATA_DIR" >&2; return 1 ;;
  esac
  [ "$RESET_DATA_DIR" != "$HOME/.agentstudio-db" ] || {
    echo "refusing to reset debug data root container" >&2
    return 1
  }
  case "$RESET_DEBUG_CODE" in
    ''|*[!a-z0-9]*) echo "refusing reset with unsafe debug code: $RESET_DEBUG_CODE" >&2; return 1 ;;
  esac
  expected_bundle_identifier="com.agentstudio.app.debug.d$RESET_DEBUG_CODE"
  if [ "$RESET_BUNDLE_IDENTIFIER" != "$expected_bundle_identifier" ]; then
    echo "refusing reset for mismatched debug bundle identifier: $RESET_BUNDLE_IDENTIFIER" >&2
    return 1
  fi

  "$PROJECT_ROOT/scripts/run-debug-observability.sh" --preflight-idle
  zmx_pids="$(owned_zmx_pids)"
  for zmx_pid in $zmx_pids; do
    kill "$zmx_pid"
  done
  for _ in $(seq 1 40); do
    local live_zmx_pid=""
    for zmx_pid in $zmx_pids; do
      if kill -0 "$zmx_pid" >/dev/null 2>&1; then
        live_zmx_pid="$zmx_pid"
        break
      fi
    done
    [ -z "$live_zmx_pid" ] && break
    /bin/sleep 0.25
  done
  for zmx_pid in $zmx_pids; do
    if kill -0 "$zmx_pid" >/dev/null 2>&1; then
      kill -KILL "$zmx_pid"
    fi
  done
  for _ in $(seq 1 20); do
    local live_zmx_pid=""
    for zmx_pid in $zmx_pids; do
      if kill -0 "$zmx_pid" >/dev/null 2>&1; then
        live_zmx_pid="$zmx_pid"
        break
      fi
    done
    [ -z "$live_zmx_pid" ] && break
    /bin/sleep 0.25
  done
  for zmx_pid in $zmx_pids; do
    if kill -0 "$zmx_pid" >/dev/null 2>&1; then
      echo "refusing to remove debug data root while zmx remains live: pid=$zmx_pid data_dir=$RESET_DATA_DIR" >&2
      return 1
    fi
  done

  echo "sidebar reset: bundle_id=$RESET_BUNDLE_IDENTIFIER data_dir=$RESET_DATA_DIR zmx_pids=${zmx_pids:-none}"
  /bin/rm -rf -- "$RESET_DATA_DIR"
}

cleanup() {
  stop_pid "${CPU_SAMPLER_PID:-}"
  local cleanup_pid="$APP_PID"
  if [ -z "$cleanup_pid" ] && [ -f "$STATE_FILE" ] \
    && [ "$(decode_env_file_value "$STATE_FILE" AGENTSTUDIO_OBSERVABILITY_MARKER)" = "$TRACE_MARKER" ]
  then
    cleanup_pid="$(decode_env_file_value "$STATE_FILE" AGENTSTUDIO_OBSERVABILITY_PID)"
  fi
  case "$cleanup_pid" in
    ''|*[!0-9]*) ;;
    *) stop_pid "$cleanup_pid" ;;
  esac

  if [ -n "$RESET_DATA_DIR" ]; then
    reset_disposable_debug_root || true
  fi
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

opaque_trace_marker() {
  local trace_name="${1:?missing trace name}"
  local trace_nonce="${2:?missing trace nonce}"
  printf '%s:%s' "$trace_name" "$trace_nonce" | /usr/bin/shasum -a 256 | awk '{ print "sidebar-" substr($1, 1, 24) }'
}

hashed_identity() {
  local value="${1:?missing identity value}"
  printf '%s' "$value" | /usr/bin/shasum -a 256 | awk '{ print substr($1, 1, 24) }'
}

validate_workload_cycles() {
  /usr/bin/python3 - "$WORKLOAD_CYCLES" "$REQUIRED_SAMPLE_COUNT" <<'PY'
import sys

try:
    cycles = int(sys.argv[1])
    minimum = int(sys.argv[2])
except ValueError:
    print("AGENTSTUDIO_SIDEBAR_IPC_CYCLES must be an integer", file=sys.stderr)
    raise SystemExit(2)
if cycles < minimum:
    print(f"AGENTSTUDIO_SIDEBAR_IPC_CYCLES must be >= {minimum}: {cycles}", file=sys.stderr)
    raise SystemExit(2)
PY
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

strict_sidebar_policy_query() {
  printf '%s' '{service.name="AgentStudio",dev.runtime.flavor="debug"} _msg:app.startup_diagnostic_action.command_exercised agent.proof.marker:"'"$TRACE_MARKER"'" | fields agentstudio.startup_diagnostic.sidebar_proof.policy_id,agentstudio.startup_diagnostic.sidebar_proof.policy_version,agentstudio.startup_diagnostic.sidebar_proof.standard_trace_tags,agentstudio.startup_diagnostic.sidebar_proof.diagnostic_trace_tags,agentstudio.startup_diagnostic.sidebar_proof.idle_populations,agentstudio.startup_diagnostic.sidebar_proof.action_populations,agentstudio.startup_diagnostic.sidebar_proof.idle_p99_max_percent,agentstudio.startup_diagnostic.sidebar_proof.action_p95_max_percent,agentstudio.startup_diagnostic.sidebar_proof.sample_interval_ms,agentstudio.startup_diagnostic.sidebar_proof.idle_sample_floor,agentstudio.startup_diagnostic.sidebar_proof.action_count_floor,agentstudio.startup_diagnostic.sidebar_proof.action_sample_floor,agentstudio.startup_diagnostic.sidebar_proof.search_character_count,agentstudio.startup_diagnostic.sidebar_proof.search_character_interval_ms,agentstudio.startup_diagnostic.sidebar_proof.quiescence_interval_ms,agentstudio.startup_diagnostic.sidebar_proof.readback_timeout_ms,agentstudio.startup_diagnostic.sidebar_proof.sampler_gap_max_ms,agentstudio.startup_diagnostic.sidebar_proof.unrelated_host_cpu_max_percent,agentstudio.startup_diagnostic.sidebar_proof.diagnostic_cpu_delta_max_points,agentstudio.startup_diagnostic.sidebar_proof.diagnostic_interaction_growth_max_percent | limit 1'
}

load_strict_sidebar_policy() {
  local policy_file="${1:?missing policy output file}"
  local query response
  query="$(strict_sidebar_policy_query)"
  for _ in $(seq 1 30); do
    response="$(curl --silent --show-error --max-time 5 "$LOGS_QUERY_URL" --data-urlencode "query=$query")"
    if [ -n "$response" ]; then
      printf '%s\n' "$response" >"$policy_file"
      return 0
    fi
    /bin/sleep 1
  done
  echo "strict sidebar policy did not become queryable for marker $TRACE_MARKER" >&2
  return 1
}

# S12 establishes the descriptor-driven driver/readback protocol. S13 owns
# execution and final acceptance for these six independent populations.
positive_quiescence() {
  local unchanged_seconds="${1:?missing unchanged-second count}"
  [ "$unchanged_seconds" -ge 5 ]
}

parse_strict_sidebar_policy() {
  local policy_file="${1:?missing policy file}"
  local environment_file="${2:?missing policy environment file}"
  /usr/bin/python3 - "$policy_file" "$environment_file" <<'PY'
import json, pathlib, shlex, sys
records = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if line.strip()]
if len(records) != 1:
    raise SystemExit(f"strict policy requires exactly one record, got {len(records)}")
record = records[0]
prefix = "agentstudio.startup_diagnostic.sidebar_proof."
mapping = {
    "STRICT_POLICY_ID": "policy_id",
    "STRICT_POLICY_VERSION": "policy_version",
    "STRICT_POLICY_IDLE_P99": "idle_p99_max_percent",
    "STRICT_POLICY_ACTION_P95": "action_p95_max_percent",
    "STRICT_POLICY_SAMPLE_INTERVAL_MS": "sample_interval_ms",
    "STRICT_POLICY_IDLE_SAMPLE_FLOOR": "idle_sample_floor",
    "STRICT_POLICY_ACTION_COUNT_FLOOR": "action_count_floor",
    "STRICT_POLICY_ACTION_SAMPLE_FLOOR": "action_sample_floor",
    "STRICT_POLICY_QUIESCENCE_MS": "quiescence_interval_ms",
    "STRICT_POLICY_READBACK_TIMEOUT_MS": "readback_timeout_ms",
    "STRICT_POLICY_MAXIMUM_SAMPLER_GAP_MS": "sampler_gap_max_ms",
    "STRICT_POLICY_HOST_CPU_MAX": "unrelated_host_cpu_max_percent",
    "STRICT_POLICY_DIAGNOSTIC_CPU_DELTA_MAX": "diagnostic_cpu_delta_max_points",
    "STRICT_POLICY_DIAGNOSTIC_INTERACTION_GROWTH_MAX": "diagnostic_interaction_growth_max_percent",
    "STRICT_POLICY_STANDARD_TRACE_TAGS": "standard_trace_tags",
    "STRICT_POLICY_DIAGNOSTIC_TRACE_TAGS": "diagnostic_trace_tags",
    "STRICT_POLICY_IDLE_POPULATIONS": "idle_populations",
    "STRICT_POLICY_ACTION_POPULATIONS": "action_populations",
}
values = {}
for variable, suffix in mapping.items():
    value = record.get(prefix + suffix)
    if value is None:
        raise SystemExit(f"strict policy missing {suffix}")
    values[variable] = str(value)
values["STRICT_POLICY_IDLE_POPULATIONS"] = values["STRICT_POLICY_IDLE_POPULATIONS"].replace(",", " ")
values["STRICT_POLICY_ACTION_POPULATIONS"] = values["STRICT_POLICY_ACTION_POPULATIONS"].replace(",", " ")
pathlib.Path(sys.argv[2]).write_text("".join(f"{key}={shlex.quote(value)}\n" for key, value in values.items()))
PY
}

nearest_rank_percentile() {
  local samples_file="${1:?missing samples file}"
  local percentile="${2:?missing percentile}"
  /usr/bin/python3 - "$samples_file" "$percentile" <<'PY'
import math, pathlib, sys
values = sorted(float(line.split()[-1]) for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if line.strip())
if not values: raise SystemExit("population has no usable samples")
rank = max(1, math.ceil(len(values) * float(sys.argv[2])))
print(values[rank - 1])
PY
}

validate_strict_host_envelope() {
  local artifact="${1:?missing population artifact}"
  {
    /usr/bin/pmset -g batt
    /usr/bin/pmset -g custom
    /usr/bin/pmset -g therm
    /usr/bin/memory_pressure -Q
    /usr/sbin/sysctl kern.memorystatus_vm_pressure_level vm.swapusage vm.compressor_mode
  } >"$artifact/host-envelope.txt"
  /bin/ps -axo pid=,ppid=,%cpu=,command= >"$artifact/processes.txt"
  grep -q "AC Power" "$artifact/host-envelope.txt" || return 1
  ! grep -Eq 'Low Power Mode[^0-9]*1' "$artifact/host-envelope.txt" || return 1
  grep -q 'No thermal warning level has been recorded' "$artifact/host-envelope.txt" || return 1
  grep -Eq 'kern.memorystatus_vm_pressure_level:[[:space:]]*1$' "$artifact/host-envelope.txt" || return 1
  /usr/bin/python3 - "$artifact/processes.txt" "$APP_PID" "$STRICT_POLICY_HOST_CPU_MAX" \
    "$artifact/unrelated-host-cpu.txt" "$artifact/forbidden-processes.txt" <<'PY'
import pathlib, re, sys

process_path, app_pid, maximum_cpu, cpu_path, forbidden_path = sys.argv[1:]
maximum_cpu = float(maximum_cpu)
forbidden_pattern = re.compile(
    r"(?:^|[ /])(codex|claude|gemini)(?:[ /]|$)|swift-frontend|swiftc|xcodebuild|"
    r"Instruments|spindump|(?:^|[ /])sample(?:[ /]|$)|mise run (?:test|build)",
    re.IGNORECASE,
)
unrelated_cpu = 0.0
forbidden = []
for line in pathlib.Path(process_path).read_text().splitlines():
    fields = line.strip().split(maxsplit=3)
    if len(fields) != 4 or not fields[0].isdigit():
        continue
    pid, _, raw_cpu, command = fields
    if pid == app_pid:
        continue
    try:
        unrelated_cpu += float(raw_cpu)
    except ValueError:
        raise SystemExit(f"invalid host CPU value for pid {pid}: {raw_cpu}")
    if forbidden_pattern.search(command):
        forbidden.append(f"{pid} {command}")
pathlib.Path(cpu_path).write_text(f"{unrelated_cpu}\n")
pathlib.Path(forbidden_path).write_text("\n".join(forbidden) + ("\n" if forbidden else ""))
if unrelated_cpu > maximum_cpu:
    raise SystemExit(f"unrelated host CPU {unrelated_cpu} exceeds {maximum_cpu}")
if forbidden:
    raise SystemExit(f"forbidden concurrent processes: {len(forbidden)}")
PY
}

record_strict_cpu_sample() {
  local samples="${1:?missing samples file}"
  local sample_interval_seconds cpu_value started_ns ended_ns
  sample_interval_seconds="$(/usr/bin/python3 -c 'import sys; print(float(sys.argv[1])/1000)' \
    "$STRICT_POLICY_SAMPLE_INTERVAL_MS")"
  started_ns="$(/usr/bin/python3 -c 'import time; print(time.monotonic_ns())')"
  cpu_value="$(/usr/bin/top -l 2 -s "$sample_interval_seconds" -pid "$APP_PID" -stats pid,cpu \
    | awk -v pid="$APP_PID" '$1 == pid { value=$2 } END { if (value != "") print value }')"
  [ -n "$cpu_value" ] || return 1
  ended_ns="$(/usr/bin/python3 -c 'import time; print(time.monotonic_ns())')"
  printf '%s %s %s\n' "$started_ns" "$ended_ns" "$cpu_value" >>"$samples"
}

validate_strict_sampler_gaps() {
  local samples="${1:?missing samples file}"
  /usr/bin/python3 - "$samples" "$STRICT_POLICY_MAXIMUM_SAMPLER_GAP_MS" <<'PY'
import pathlib, sys

timestamps = [int(line.split()[0]) for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if line.strip()]
maximum_gap_ns = float(sys.argv[2]) * 1_000_000
for prior, current in zip(timestamps, timestamps[1:]):
    if current <= prior or current - prior > maximum_gap_ns:
        raise SystemExit(f"sampler_gap={current - prior}")
PY
}

start_strict_action_sampler() {
  local population="${1:?missing population}"
  local population_artifact="$ARTIFACT/populations/$population"
  local raw_samples="$population_artifact/cpu.raw.samples"
  local stop_file="$population_artifact/stop-sampler"
  : >"$raw_samples"
  /bin/rm -f -- "$stop_file"
  (
    while [ ! -f "$stop_file" ]; do
      record_strict_cpu_sample "$raw_samples"
    done
  ) &
  CPU_SAMPLER_PID=$!
}

validate_strict_zero_loss() {
  local summary="${1:?missing population summary}"
  grep -q '^trace_queue_dropped_record_count=0$' "$summary"
  grep -q '^runtime_delivery_dropped_count=0$' "$summary"
  grep -q '^collector_loss_count=0$' "$summary"
}

capture_strict_population_loss() {
  local summary="${1:?missing population summary}"
  local population="${2:?missing population}"
  local marker_selector
  marker_selector="$(metric_label_selector "$TRACE_MARKER")"
  local trace_loss runtime_loss required_record_loss
  trace_loss="$(metric_value_or_empty "max(agentstudio_performance_trace_queue_dropped_record_count{agent.proof.marker=\"$marker_selector\"})")"
  runtime_loss="$(metric_value_or_empty "max(agentstudio_performance_runtime_delivery_runtime_channel_outbound_dropped_count{agent.proof.marker=\"$marker_selector\"}) + max(agentstudio_performance_runtime_delivery_eventbus_live_dropped_count{agent.proof.marker=\"$marker_selector\"}) + max(agentstudio_performance_runtime_delivery_eventbus_replay_dropped_count{agent.proof.marker=\"$marker_selector\"})")"
  [ -n "$trace_loss" ] || return 1
  runtime_loss="${runtime_loss:-0}"
  required_record_loss="$(strict_required_record_loss "$population")"
  {
    echo "trace_queue_dropped_record_count=$trace_loss"
    echo "runtime_delivery_dropped_count=$runtime_loss"
    echo "collector_loss_count=$required_record_loss"
  } >"$summary"
}

wait_for_positive_quiescence() {
  local marker="${1:?missing marker}"
  local required_unchanged=$((STRICT_POLICY_QUIESCENCE_MS / STRICT_POLICY_SAMPLE_INTERVAL_MS))
  local prior="" unchanged=0 signature
  while [ "$unchanged" -lt "$required_unchanged" ]; do
    signature="$(query_victoria_metrics "sum(agentstudio_performance_events_total{agent.proof.marker=\"$(metric_label_selector "$marker")\",event=~\"performance.repo_explorer.keyed_wake|performance.sidebar.projection\"})")"
    if [ "$signature" = "$prior" ]; then unchanged=$((unchanged + 1)); else unchanged=0; prior="$signature"; fi
    /bin/sleep "$(/usr/bin/python3 -c 'import sys; print(float(sys.argv[1])/1000)' "$STRICT_POLICY_SAMPLE_INTERVAL_MS")"
  done
}

begin_strict_population() {
  local population="${1:?missing population}"
  local selector="${2:?missing diagnostic selector}"
  local trace_tags="${3:-$STRICT_POLICY_STANDARD_TRACE_TAGS}"
  local population_artifact="$ARTIFACT/populations/$population"
  mkdir -p "$population_artifact"
  reset_disposable_debug_root
  TRACE_MARKER="$(opaque_trace_marker "${TRACE_NAME}-${population}" "$(/usr/bin/uuidgen)")"
  STATE_FILE="$population_artifact/debug-observability.env"
  env AGENTSTUDIO_TRACE_FLUSH=immediate \
    AGENTSTUDIO_TRACE_TAGS="$trace_tags" \
    AGENTSTUDIO_TRACE_NAME="$TRACE_MARKER" \
    AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION="$selector" \
    AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
    "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach
  for _ in $(seq 1 60); do [ -s "$STATE_FILE" ] && break; /bin/sleep 1; done
  [ -s "$STATE_FILE" ] || return 1
  APP_PID="$(decode_env_file_value "$STATE_FILE" AGENTSTUDIO_OBSERVABILITY_PID)"
  load_strict_sidebar_policy "$population_artifact/projected-policy.jsonl"
  echo "$TRACE_MARKER" >"$population_artifact/marker.txt"
  echo "$APP_PID" >"$population_artifact/pid.txt"
  validate_strict_host_envelope "$population_artifact" || {
    echo "population_invalidated=host_envelope" >"$population_artifact/invalid.env"
    return 1
  }
  if printf '%s\n' "$STRICT_POLICY_ACTION_POPULATIONS" | grep -qw "$population" \
    || [ "$population" = "grouping_diagnostic" ]
  then
    start_strict_action_sampler "$population"
  fi
  wait_for_positive_quiescence "$TRACE_MARKER"
}

sample_strict_idle_population() {
  local population="${1:?missing population}"
  local samples="$ARTIFACT/populations/$population/cpu.samples"
  : >"$samples"
  while [ "$(wc -l <"$samples")" -lt "$STRICT_POLICY_IDLE_SAMPLE_FLOOR" ]; do
    record_strict_cpu_sample "$samples"
  done
  validate_strict_sampler_gaps "$samples"
}

drive_strict_action_population() {
  local population="${1:?missing population}"
  local marker="$TRACE_MARKER"
  local population_artifact="$ARTIFACT/populations/$population"
  local raw_samples="$population_artifact/cpu.raw.samples"
  local samples="$population_artifact/cpu.samples"
  local records="$population_artifact/action-records.jsonl"
  local terminal_query='{service.name="AgentStudio",dev.runtime.flavor="debug"} agent.proof.marker:"'"$marker"'" _msg:performance.sidebar.proof_population.completed | fields _msg,agentstudio.performance.sidebar.proof.action.sequence | limit 1'
  local response=""
  while [ -z "$response" ]; do
    kill -0 "$APP_PID" || return 1
    response="$(curl --silent --show-error --max-time 5 "$LOGS_QUERY_URL" --data-urlencode "query=$terminal_query")"
    [ -n "$response" ] || /bin/sleep 1
  done
  printf '%s\n' "$response" >"$population_artifact/action-terminal.jsonl"
  : >"$population_artifact/stop-sampler"
  wait "$CPU_SAMPLER_PID"
  CPU_SAMPLER_PID=""
  query_strict_action_records "$marker" "$records"
  classify_strict_action_samples "$raw_samples" "$records" "$samples"
  validate_strict_sampler_gaps "$raw_samples"
}

query_strict_action_records() {
  local marker="${1:?missing marker}"
  local output="${2:?missing output file}"
  local query='{service.name="AgentStudio",dev.runtime.flavor="debug"} agent.proof.marker:"'"$marker"'" (_msg:performance.sidebar.proof_action.started OR _msg:performance.sidebar.proof_action.settled OR _msg:performance.sidebar.proof_action.failed OR _msg:performance.sidebar.proof_population.completed) | fields _msg,agentstudio.performance.sidebar.proof.action.sequence,agentstudio.performance.sidebar.proof.monotonic_ns | limit 1000'
  curl --fail --silent --show-error --max-time 10 "$LOGS_QUERY_URL" \
    --data-urlencode "query=$query" >"$output"
  /usr/bin/python3 - "$output" "$STRICT_POLICY_ACTION_COUNT_FLOOR" \
    "$STRICT_POLICY_ACTION_SAMPLE_FLOOR" <<'PY'
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
required = max(int(float(sys.argv[2])), int(float(sys.argv[3])))
records = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
by_sequence = {}
completed = []
for record in records:
    message = record.get("_msg")
    sequence = int(float(record.get("agentstudio.performance.sidebar.proof.action.sequence", 0)))
    if message == "performance.sidebar.proof_population.completed":
        completed.append(sequence)
        continue
    if message == "performance.sidebar.proof_action.failed":
        raise SystemExit(f"action population contains failed sequence {sequence}")
    if message not in {
        "performance.sidebar.proof_action.started",
        "performance.sidebar.proof_action.settled",
    }:
        continue
    timestamp = int(float(record.get("agentstudio.performance.sidebar.proof.monotonic_ns", 0)))
    events = by_sequence.setdefault(sequence, {})
    if message in events:
        raise SystemExit(f"duplicate action record {sequence} {message}")
    events[message] = timestamp
if completed != [required]:
    raise SystemExit(f"action population terminal did not satisfy both floors: {completed}")
if sorted(by_sequence) != list(range(1, required + 1)):
    raise SystemExit("action sequence is incomplete or out of order")
prior_settlement = 0
for sequence in range(1, required + 1):
    events = by_sequence[sequence]
    if set(events) != {
        "performance.sidebar.proof_action.started",
        "performance.sidebar.proof_action.settled",
    }:
        raise SystemExit(f"action sequence {sequence} lacks a complete pair")
    started = events["performance.sidebar.proof_action.started"]
    settled = events["performance.sidebar.proof_action.settled"]
    if started <= prior_settlement or settled <= started:
        raise SystemExit(f"action sequence {sequence} overlaps or is non-monotonic")
    prior_settlement = settled
PY
}

classify_strict_action_samples() {
  local raw_samples="${1:?missing raw samples}"
  local records="${2:?missing action records}"
  local samples="${3:?missing classified samples}"
  /usr/bin/python3 - "$raw_samples" "$records" "$samples" \
    "$STRICT_POLICY_ACTION_SAMPLE_FLOOR" <<'PY'
import json, pathlib, sys

raw_path, records_path, output_path, minimum = sys.argv[1:]
minimum = int(float(minimum))
actions = {}
for line in pathlib.Path(records_path).read_text().splitlines():
    if not line.strip():
        continue
    record = json.loads(line)
    message = record.get("_msg")
    if message not in {
        "performance.sidebar.proof_action.started",
        "performance.sidebar.proof_action.settled",
    }:
        continue
    sequence = int(float(record["agentstudio.performance.sidebar.proof.action.sequence"]))
    actions.setdefault(sequence, {})[message] = int(
        float(record["agentstudio.performance.sidebar.proof.monotonic_ns"])
    )
intervals = [
    (events["performance.sidebar.proof_action.started"], events["performance.sidebar.proof_action.settled"])
    for _, events in sorted(actions.items())
]
retained = []
covered_actions = set()
for line in pathlib.Path(raw_path).read_text().splitlines():
    if not line.strip():
        continue
    fields = line.split()
    if len(fields) != 3:
        raise SystemExit(f"malformed CPU sample: {line}")
    sample_start, sample_end = map(int, fields[:2])
    if sample_end <= sample_start:
        raise SystemExit(f"partial CPU sample: {line}")
    overlaps = {
        index for index, (action_start, action_end) in enumerate(intervals)
        if sample_start < action_end and sample_end > action_start
    }
    if overlaps:
        retained.append(line)
        covered_actions.update(overlaps)
if len(covered_actions) != len(intervals):
    raise SystemExit("one or more actions had no action-bearing CPU interval")
if len(retained) < minimum:
    raise SystemExit("action population terminal did not satisfy both floors")
pathlib.Path(output_path).write_text("\n".join(retained) + "\n")
PY
}

strict_required_record_loss() {
  local population="${1:?missing population}"
  local marker="${TRACE_MARKER:?missing marker}"
  if printf '%s\n' "$STRICT_POLICY_ACTION_POPULATIONS" | grep -qw "$population" \
    || [ "$population" = "grouping_diagnostic" ]
  then
    local records="$ARTIFACT/populations/$population/action-records.jsonl"
    [ -s "$records" ] || return 1
    # Exact started/settled/terminal validation proves the required records
    # traversed the app exporter and collector into VictoriaLogs.
    printf '0\n'
    return
  fi
  local ready_query='{service.name="AgentStudio",dev.runtime.flavor="debug"} agent.proof.marker:"'"$marker"'" _msg:performance.sidebar.proof_population.ready | fields _msg | limit 2'
  local ready_count
  ready_count="$(curl --fail --silent --show-error --max-time 10 "$LOGS_QUERY_URL" \
    --data-urlencode "query=$ready_query" | /usr/bin/python3 -c 'import sys; print(sum(1 for line in sys.stdin if line.strip()))')"
  [ "$ready_count" = "1" ] || return 1
  printf '0\n'
}

validate_strict_population() {
  local population="${1:?missing population}"
  local samples="$ARTIFACT/populations/$population/cpu.samples"
  local percentile limit
  if printf '%s\n' "$STRICT_POLICY_IDLE_POPULATIONS" | grep -qw "$population"; then
    percentile="$(nearest_rank_percentile "$samples" 0.99)"; limit="$STRICT_POLICY_IDLE_P99"
  else
    percentile="$(nearest_rank_percentile "$samples" 0.95)"; limit="$STRICT_POLICY_ACTION_P95"
  fi
  /usr/bin/python3 - "$percentile" "$limit" <<'PY'
import sys
value, limit = map(float, sys.argv[1:])
if value >= limit: raise SystemExit(f"population CPU percentile {value} must be below {limit}")
PY
  validate_strict_sampler_gaps "$samples"
  # no sample replacement or trimming: every retained sample belongs to this marker and PID.
}

validate_strict_perturbation_pair() {
  local standard_cpu="${1:?missing standard cpu p95}" diagnostic_cpu="${2:?missing diagnostic cpu p95}"
  local standard_interaction="${3:?missing standard interaction p95}" diagnostic_interaction="${4:?missing diagnostic interaction p95}"
  /usr/bin/python3 - "$standard_cpu" "$diagnostic_cpu" "$standard_interaction" "$diagnostic_interaction" \
    "$STRICT_POLICY_DIAGNOSTIC_CPU_DELTA_MAX" "$STRICT_POLICY_DIAGNOSTIC_INTERACTION_GROWTH_MAX" <<'PY'
import sys
s_cpu, d_cpu, s_time, d_time, cpu_limit, time_limit = map(float, sys.argv[1:])
if d_cpu - s_cpu > cpu_limit: raise SystemExit("diagnostic CPU perturbation exceeded")
if s_time <= 0 or ((d_time - s_time) / s_time * 100) > time_limit: raise SystemExit("diagnostic interaction perturbation exceeded")
PY
}

strict_interaction_p95_ms() {
  local marker="${1:?missing marker}"
  local output="${2:?missing interaction output}"
  local query='{service.name="AgentStudio",dev.runtime.flavor="debug"} agent.proof.marker:"'"$marker"'" (_msg:performance.sidebar.proof_action.started OR _msg:performance.sidebar.proof_action.settled) | fields _msg,agentstudio.performance.sidebar.proof.action.sequence,agentstudio.performance.sidebar.proof.monotonic_ns | limit 1000'
  curl --silent --show-error --max-time 10 "$LOGS_QUERY_URL" --data-urlencode "query=$query" >"$output"
  /usr/bin/python3 - "$output" <<'PY'
import json, math, pathlib, sys
times = {}
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if not line.strip(): continue
    record = json.loads(line); sequence = record.get("agentstudio.performance.sidebar.proof.action.sequence")
    timestamp = record.get("agentstudio.performance.sidebar.proof.monotonic_ns")
    if sequence is None or timestamp is None: continue
    times.setdefault(int(sequence), {})[record.get("_msg")] = int(timestamp)
durations = sorted((pair["performance.sidebar.proof_action.settled"] - pair["performance.sidebar.proof_action.started"]) / 1_000_000 for pair in times.values() if len(pair) == 2)
if not durations: raise SystemExit("missing complete interaction pairs")
print(durations[math.ceil(len(durations) * .95) - 1])
PY
}

run_strict_sidebar_cpu_populations() {
  local policy_environment="$ARTIFACT/strict-sidebar-policy.env"
  parse_strict_sidebar_policy "$STRICT_SIDEBAR_POLICY_FILE" "$policy_environment"
  # shellcheck disable=SC1090
  source "$policy_environment"
  local specifications=(
    "zero_pty_idle:sidebar-cpu-zero-pty-idle" "quiescent_pty_idle:sidebar-cpu-quiescent-pty-idle"
    "search_clear:sidebar-cpu-search-clear" "grouping:sidebar-cpu-grouping"
    "hide_show:sidebar-cpu-hide-show" "tab_switch:sidebar-cpu-tab-switch"
  )
  local specification population selector
  for specification in "${specifications[@]}"; do
    population="${specification%%:*}"; selector="${specification#*:}"
    begin_strict_population "$population" "$selector"
    if printf '%s\n' "$STRICT_POLICY_IDLE_POPULATIONS" | grep -qw "$population"; then
      sample_strict_idle_population "$population"
    else
      drive_strict_action_population "$population"
    fi
    validate_strict_population "$population"
    capture_strict_population_loss "$ARTIFACT/populations/$population/loss.env" "$population"
    validate_strict_zero_loss "$ARTIFACT/populations/$population/loss.env"
    stop_pid "$APP_PID"; APP_PID=""
  done
  local standard_cpu standard_interaction diagnostic_cpu diagnostic_interaction
  standard_cpu="$(nearest_rank_percentile "$ARTIFACT/populations/grouping/cpu.samples" 0.95)"
  standard_interaction="$(strict_interaction_p95_ms \
    "$(cat "$ARTIFACT/populations/grouping/marker.txt")" \
    "$ARTIFACT/populations/grouping/interaction-records.jsonl")"
  begin_strict_population "grouping_diagnostic" "sidebar-cpu-grouping" \
    "$STRICT_POLICY_DIAGNOSTIC_TRACE_TAGS"
  drive_strict_action_population "grouping_diagnostic"
  diagnostic_cpu="$(nearest_rank_percentile "$ARTIFACT/populations/grouping_diagnostic/cpu.samples" 0.95)"
  diagnostic_interaction="$(strict_interaction_p95_ms "$TRACE_MARKER" \
    "$ARTIFACT/populations/grouping_diagnostic/interaction-records.jsonl")"
  validate_strict_perturbation_pair "$standard_cpu" "$diagnostic_cpu" \
    "$standard_interaction" "$diagnostic_interaction"
  capture_strict_population_loss "$ARTIFACT/populations/grouping_diagnostic/loss.env" \
    "grouping_diagnostic"
  validate_strict_zero_loss "$ARTIFACT/populations/grouping_diagnostic/loss.env"
  stop_pid "$APP_PID"; APP_PID=""
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
    "$(metric_label_selector "$TRACE_MARKER")" \
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
  for attempt in $(seq 1 "$REQUIRED_METRIC_READBACK_ATTEMPTS"); do
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
  for attempt in $(seq 1 "$REQUIRED_METRIC_READBACK_ATTEMPTS"); do
    value="$(metric_value_or_empty "$query")"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
    /bin/sleep 2
  done
  require_metric_value "$key" "$query"
}

record_required_metric_value() {
  local key="$1"
  local query="$2"
  local value
  value="$(wait_for_required_metric_value "$key" "$query")"
  printf '%s\n' "$key" >>"$REQUIRED_METRIC_KEYS_FILE"
  printf '%s=%s\n' "$key" "$value" >>"$METRIC_VALUES_FILE"
  eval "$key=\"\$value\""
}

record_required_metric_count() {
  local key="$1"
  local query="$2"
  local minimum="$3"
  local value
  value="$(wait_for_required_metric_count "$key" "$query" "$minimum")"
  printf '%s\n' "$key" >>"$REQUIRED_METRIC_KEYS_FILE"
  printf '%s=%s\n' "$key" "$value" >>"$METRIC_VALUES_FILE"
  eval "$key=\"\$value\""
}

record_required_metric_series() {
  local surface="$1"
  local phase="$2"
  local group_mode="$3"
  local trigger="$4"
  local key_prefix="$5"
  local minimum_count="$6"

  record_required_metric_value "${key_prefix}_elapsed_ms_p95" \
    "$(metric_event_elapsed_p95_query "$surface" "$phase" "$group_mode" "$trigger")"
  record_required_metric_value "${key_prefix}_elapsed_ms_max" \
    "$(metric_event_elapsed_max_query "$surface" "$phase" "$group_mode" "$trigger")"
  record_required_metric_count "${key_prefix}_elapsed_ms_count" \
    "$(metric_event_elapsed_count_query "$surface" "$phase" "$group_mode" "$trigger")" \
    "$minimum_count"
}

record_required_sidebar_metric_matrix() {
  local mode_name
  local phase
  local minimum_count

  : >"$REQUIRED_METRIC_KEYS_FILE"
  : >"$METRIC_VALUES_FILE"

  for mode_name in repo pane tab; do
    for phase in request_build_mainactor projection_worker row_index mainactor_apply; do
      minimum_count="$REQUIRED_MATERIALIZED_SAMPLE_COUNT"
      if [ "$phase" = "request_build_mainactor" ]; then
        minimum_count="$REQUIRED_SAMPLE_COUNT"
      fi
      record_required_metric_series repo "$phase" "$mode_name" grouping_switch \
        "repo_${mode_name}_${phase}" "$minimum_count"
    done
  done

}

metric_env_value() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '$1 == key { value = substr($0, length($1) + 2) } END { if (value != "") print value }' "$file"
}

metric_value_is_nonnegative_finite() {
  local value="$1"
  /usr/bin/python3 - "$value" <<'PY'
import math
import sys

try:
    value = float(sys.argv[1])
except (IndexError, ValueError):
    raise SystemExit(1)
raise SystemExit(0 if math.isfinite(value) and value >= 0 else 1)
PY
}

required_metric_keys_line() {
  tr '\n' ' ' <"$REQUIRED_METRIC_KEYS_FILE" | sed 's/[[:space:]]*$//'
}

append_required_metric_values() {
  local output_file="$1"
  cat "$METRIC_VALUES_FILE" >>"$output_file"
  printf "required_metric_keys='%s'\n" "$(required_metric_keys_line)" >>"$output_file"
}

compare_required_metric_matrix() {
  local baseline_values_file="$1"
  local compare_values_file="$2"
  local key
  local baseline_value
  local compare_value

  for key in $required_metric_keys; do
    baseline_value="$(metric_env_value "$baseline_values_file" "$key")"
    compare_value="$(metric_env_value "$compare_values_file" "$key")"
    if [ -z "$baseline_value" ]; then
      echo "missing baseline required sidebar metric: $key" >&2
      exit 1
    fi
    if [ -z "$compare_value" ]; then
      echo "missing compare required sidebar metric: $key" >&2
      exit 1
    fi
    if ! metric_value_is_nonnegative_finite "$baseline_value"; then
      echo "invalid baseline required sidebar metric: $key" >&2
      exit 1
    fi
    if ! metric_value_is_nonnegative_finite "$compare_value"; then
      echo "invalid compare required sidebar metric: $key" >&2
      exit 1
    fi
    case "$key" in
      *_elapsed_ms_p95 | *_elapsed_ms_max)
        performance_threshold_check "$key" "$baseline_value" "$compare_value"
        ;;
    esac
  done
}

load_baseline_metric_value() {
  local baseline_values_file="$1"
  local key="$2"
  local value
  value="$(metric_env_value "$baseline_values_file" "$key")"
  if ! metric_value_is_nonnegative_finite "$value"; then
    echo "invalid or missing baseline sidebar metric: $key" >&2
    exit 1
  fi
  printf -v "$key" '%s' "$value"
}

validate_compare_baseline_fixture() {
  if [ "$mode" != "compare" ]; then
    return
  fi
  if [ ! -f "$BASELINE_FILE" ]; then
    echo "missing sidebar baseline artifact: $BASELINE_FILE; run --baseline first" >&2
    exit 1
  fi

  local baseline_workload_fixture_key
  local baseline_worktree_fixture_key
  baseline_workload_fixture_key="$(metric_env_value "$BASELINE_FILE" workload_fixture_key)"
  baseline_worktree_fixture_key="$(metric_env_value "$BASELINE_FILE" worktree_fixture_key)"
  if [ "$baseline_workload_fixture_key" != "$WORKLOAD_FIXTURE_KEY" ]; then
    echo "sidebar baseline workload fixture mismatch" >&2
    exit 1
  fi
  if [ "$baseline_worktree_fixture_key" != "$WORKTREE_FIXTURE_KEY" ]; then
    echo "sidebar baseline worktree fixture mismatch" >&2
    exit 1
  fi
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
readback_poll_delay = float(os.environ.get("AGENTSTUDIO_SIDEBAR_IPC_READBACK_POLL_SECONDS", "0.01"))
cycles = int(os.environ["AGENTSTUDIO_SIDEBAR_IPC_CYCLES"])

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

    def execute_sidebar_command(command_id, arguments, label):
        result = require_success(
            session.request(
                next_id(),
                "command.execute",
                {
                    "commandId": command_id,
                    "targetHandle": None,
                    "arguments": arguments,
                },
            ),
            label,
        )
        if result.get("applied") is not True:
            print(f"{label} did not apply: {result}", file=sys.stderr)
            sys.exit(1)

    def wait_for_readback(method, params, label, matches):
        deadline = time.monotonic() + timeout
        last_result = None
        while time.monotonic() < deadline:
            last_result = require_success(session.request(next_id(), method, params), label)
            if matches(last_result):
                return last_result
            if readback_poll_delay > 0:
                time.sleep(readback_poll_delay)
        print(f"{label} readiness timed out: {last_result}", file=sys.stderr)
        sys.exit(1)

    def pace_projection_application():
        if step_delay > 0:
            time.sleep(step_delay)

    def set_grouping(surface, mode):
        command_by_grouping = {
            ("repo", "repo"): "setRepoSidebarGroupingRepo",
            ("repo", "pane"): "setRepoSidebarGroupingPane",
            ("repo", "tab"): "setRepoSidebarGroupingTab",
        }
        command_id = command_by_grouping.get((surface, mode))
        if command_id is None:
            print(f"unsupported sidebar grouping command: surface={surface} mode={mode}", file=sys.stderr)
            sys.exit(1)
        execute_sidebar_command(command_id, {}, f"command.execute {command_id}")
        wait_for_readback(
            "sidebar.grouping.get",
            {"surface": surface},
            f"sidebar.grouping.get {surface}",
            lambda result: result.get("mode") == mode,
        )
        pace_projection_application()

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
        set_grouping("repo", "repo")
        set_repo_sort_order("descending")
        set_repo_sort_order("ascending")
        set_grouping("repo", "pane")
        set_grouping("repo", "tab")
        set_grouping("repo", "repo")
        set_grouping("repo", "pane")
        set_grouping("repo", "tab")
        set_grouping("repo", "repo")
        set_repo_sort_order("descending")
        set_repo_sort_order("ascending")
        set_grouping("repo", "pane")
        set_grouping("repo", "tab")
        set_grouping("repo", "repo")
        set_grouping("repo", "pane")
        set_grouping("repo", "repo")
        set_repo_sort_order("descending")
        set_repo_sort_order("ascending")
finally:
    session.close()
PY
}

run_repo_explorer_key_mutation_phase() {
  local first_phase_pid="${APP_PID:?missing first phase app pid}"
  stop_pid "$first_phase_pid"
  APP_PID=""
  reset_disposable_debug_root

  TRACE_MARKER="$TRACE_MARKER_K"
  env \
    AGENTSTUDIO_TRACE_FLUSH=immediate \
    AGENTSTUDIO_TRACE_TAGS="$KEY_MUTATION_TRACE_TAGS" \
    AGENTSTUDIO_TRACE_NAME="$TRACE_MARKER" \
    AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=repo-explorer-key-mutation-proof \
    AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
    "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach

  AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
    wait_for_debug_observability
  APP_PID="$(decode_env_file_value "$STATE_FILE" AGENTSTUDIO_OBSERVABILITY_PID)"
  TRACE_MARKER="$TRACE_MARKER_W"
}

run_repo_explorer_interaction_phase() {
  wait_for_required_metric_count keyed_wake_key_mutation_completion \
    "sum(agentstudio_performance_events_total{agent.proof.marker=\"$(metric_label_selector "$TRACE_MARKER_K")\",event=\"performance.repo_explorer.keyed_wake\",key_class=\"missing_declared_key\",stage=\"membership_path\"})" \
    "$WORKLOAD_CYCLES" >/dev/null
  local key_phase_pid="${APP_PID:?missing key phase app pid}"
  stop_pid "$key_phase_pid"
  APP_PID=""
  reset_disposable_debug_root
  TRACE_MARKER="$TRACE_MARKER_I"
  env \
    AGENTSTUDIO_TRACE_FLUSH=immediate \
    AGENTSTUDIO_TRACE_TAGS="$WORKLOAD_TRACE_TAGS" \
    AGENTSTUDIO_TRACE_NAME="$TRACE_MARKER" \
    AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=repo-explorer-interaction-proof \
    AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
    "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" wait_for_debug_observability
  APP_PID="$(decode_env_file_value "$STATE_FILE" AGENTSTUDIO_OBSERVABILITY_PID)"
  TRACE_MARKER="$TRACE_MARKER_W"
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

ratio_value() {
  local numerator="${1:?missing numerator}"
  local denominator="${2:?missing denominator}"
  /usr/bin/python3 - "$numerator" "$denominator" <<'PY'
import sys
numerator, denominator = map(float, sys.argv[1:])
print(0 if denominator == 0 else numerator / denominator)
PY
}

require_exact_fixture_count() {
  local label="${1:?missing fixture label}"
  local actual="${2:?missing fixture actual}"
  local expected="${3:?missing fixture expected}"
  if [ "$actual" != "$expected" ] && [ "$actual" != "${expected}.0" ]; then
    echo "$label expected $expected, got ${actual:-<missing>}" >&2
    exit 1
  fi
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

keyed_wake_count() {
  local key_class="${1:?missing key class}"
  local stage="${2:?missing stage}"
  local selector='agent.proof.marker="'"$(metric_label_selector "$TRACE_MARKER_K")"'",event="performance.repo_explorer.keyed_wake",key_class="'"$key_class"'",stage="'"$stage"'"'
  local response
  local value
  response="$(query_victoria_metrics "sum(agentstudio_performance_events_total{$selector})")"
  value="$(metric_max_value "$response")"
  printf '%s\n' "${value:-0}"
}

keyed_wake_outcome_count() {
  local stage="${1:?missing stage}"
  local outcome="${2:?missing outcome}"
  local selector='agent.proof.marker="'"$(metric_label_selector "$TRACE_MARKER_K")"'",event="performance.repo_explorer.keyed_wake",stage="'"$stage"'",outcome="'"$outcome"'"'
  local response
  local value
  response="$(query_victoria_metrics "sum(agentstudio_performance_events_total{$selector})")"
  value="$(metric_max_value "$response")"
  printf '%s\n' "${value:-0}"
}

keyed_wake_stage_count() {
  local stage="${1:?missing stage}"
  local selector='agent.proof.marker="'"$(metric_label_selector "$TRACE_MARKER_K")"'",event="performance.repo_explorer.keyed_wake",stage="'"$stage"'"'
  local response
  local value
  response="$(query_victoria_metrics "sum(agentstudio_performance_events_total{$selector})")"
  value="$(metric_max_value "$response")"
  printf '%s\n' "${value:-0}"
}

assert_keyed_wake_contract() {
  local key_class="${1:?missing key class}"
  local stage="${2:?missing stage}"
  local expected="${3:?missing expected count}"
  local actual
  actual="$(keyed_wake_count "$key_class" "$stage")"
  if [ "$expected" = "bounded" ]; then
    /usr/bin/python3 - "$key_class" "$stage" "$actual" "$WORKLOAD_CYCLES" <<'PY'
import sys
key_class, stage, actual, limit = sys.argv[1], sys.argv[2], float(sys.argv[3]), int(sys.argv[4])
if actual < 1 or actual > limit:
    raise SystemExit(f"{key_class} {stage} expected 1..{limit}, got {actual:g}")
PY
    return
  fi
  if [ "$actual" != "$expected" ] && [ "$actual" != "${expected}.0" ]; then
    echo "$key_class $stage expected $expected, got $actual" >&2
    exit 1
  fi
}

validate_controls
validate_workload_cycles

PROOF_ROOT="${AGENTSTUDIO_SIDEBAR_PROOF_ROOT:-$DEFAULT_PROOF_ROOT}"
TRACE_NAME="$(validate_trace_name "${AGENTSTUDIO_TRACE_NAME:-sidebar-performance-$(date +%Y%m%d%H%M%S)-$$}")"
TRACE_NONCE="$(/usr/bin/uuidgen)"
TRACE_MARKER_W="$(opaque_trace_marker "${TRACE_NAME}-w" "$TRACE_NONCE")"
TRACE_MARKER_K="$(opaque_trace_marker "${TRACE_NAME}-k" "$(/usr/bin/uuidgen)")"
TRACE_MARKER_I="$(opaque_trace_marker "${TRACE_NAME}-i" "$(/usr/bin/uuidgen)")"
TRACE_MARKER="$TRACE_MARKER_W"
ARTIFACT="$PROOF_ROOT/$TRACE_NAME"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$ARTIFACT/debug-observability.env}"
SUMMARY_FILE="$ARTIFACT/summary.txt"
REQUIRED_METRIC_KEYS_FILE="$ARTIFACT/required-metric-keys.txt"
METRIC_VALUES_FILE="$ARTIFACT/metric-values.env"
KEYED_WAKE_VALUES_FILE="$ARTIFACT/keyed-wake-values.env"
BASELINE_FILE="$PROOF_ROOT/sidebar-performance-baseline.env"
WORKTREE_FIXTURE_KEY="$(hashed_identity "repos=$REQUIRED_REPOSITORY_COUNT:worktrees=$REQUIRED_WORKTREE_COUNT:tabs=$REQUIRED_TAB_COUNT:panes=$REQUIRED_PANE_COUNT:active_ptys=$REQUIRED_ACTIVE_PTY_COUNT")"
WORKLOAD_FIXTURE_KEY="$(hashed_identity "$WORKLOAD_FIXTURE_VERSION:cycles=$WORKLOAD_CYCLES:tags=$WORKLOAD_TRACE_TAGS:backend=otlp")"
mkdir -p "$ARTIFACT" "$(dirname "$STATE_FILE")"
validate_compare_baseline_fixture

sidebar_metric_query='agentstudio_performance_events_total{agent.proof.marker="'$(metric_label_selector "$TRACE_MARKER")'",event="performance.sidebar.projection",surface="repo",phase=~"startup_diagnostic|request_build_mainactor|mainactor_apply|projection_worker|row_index"}'

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
    echo "workload_fixture_key=$WORKLOAD_FIXTURE_KEY"
    echo "worktree_fixture_key=$WORKTREE_FIXTURE_KEY"
    echo "workload_cycles=$WORKLOAD_CYCLES"
    echo "sidebar_projection.metric_result_count=$metrics_count"
  } >"$SUMMARY_FILE"
  echo "sidebar performance workload prepare-only ok: $SUMMARY_FILE"
  exit 0
fi

APP_PID=""
CPU_SAMPLER_PID=""
RESET_IDENTITY=""
RESET_DEBUG_CODE=""
RESET_DATA_DIR=""
RESET_BUNDLE_IDENTIFIER=""
trap cleanup EXIT INT TERM
reset_disposable_debug_root

env \
  AGENTSTUDIO_TRACE_FLUSH=immediate \
  AGENTSTUDIO_TRACE_TAGS="$WORKLOAD_TRACE_TAGS" \
  AGENTSTUDIO_TRACE_NAME="$TRACE_MARKER" \
  AGENTSTUDIO_SIDEBAR_IPC_CYCLES="$WORKLOAD_CYCLES" \
  AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=sidebar-performance-proof \
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
  "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach

AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
  wait_for_debug_observability
STRICT_SIDEBAR_POLICY_FILE="$ARTIFACT/strict-sidebar-policy.jsonl"
load_strict_sidebar_policy "$STRICT_SIDEBAR_POLICY_FILE"
APP_PID="$(decode_env_file_value "$STATE_FILE" AGENTSTUDIO_OBSERVABILITY_PID)"
if [ "$mode" = "sidebar-proof" ]; then
  stop_pid "$APP_PID"
  APP_PID=""
  run_strict_sidebar_cpu_populations
  echo "strict sidebar CPU populations passed: $ARTIFACT"
  exit 0
fi
CPU_SAMPLES_FILE="$ARTIFACT/process-cpu-percent.txt"
: >"$CPU_SAMPLES_FILE"
sample_process_cpu "$APP_PID" "$CPU_SAMPLES_FILE" &
CPU_SAMPLER_PID=$!

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
AGENTSTUDIO_SIDEBAR_IPC_CYCLES="$WORKLOAD_CYCLES" \
  run_authenticated_sidebar_ipc_workload "$ipc_metadata_path" "$ipc_debug_token_path"
stop_pid "$CPU_SAMPLER_PID"
CPU_SAMPLER_PID=""
process_cpu_summary="$(summarize_process_cpu "$CPU_SAMPLES_FILE" "$APP_PID")"
process_cpu_percent_p50="$(printf '%s\n' "$process_cpu_summary" | sed -n '1p')"
process_cpu_percent_p95="$(printf '%s\n' "$process_cpu_summary" | sed -n '2p')"
process_cpu_percent_max="$(printf '%s\n' "$process_cpu_summary" | sed -n '3p')"
process_cpu_sample_count="$(printf '%s\n' "$process_cpu_summary" | sed -n '4p')"
record_required_sidebar_metric_matrix

metrics_result="$(wait_for_sidebar_metric_count)"
metrics_count="$(printf '%s\n' "$metrics_result" | sed -n '1p')"
metrics_response="$(printf '%s\n' "$metrics_result" | sed '1d')"
if [ "$metrics_count" = "0" ]; then
  echo "missing sidebar projection Victoria metric for marker $TRACE_NAME" >&2
  echo "$metrics_response" >&2
  exit 1
fi

fixture_repo_count="$(wait_for_required_metric_value fixture_repo_count \
  "max(agentstudio_startup_diagnostic_fixture_repo_count{agent.proof.marker=\"$(metric_label_selector "$TRACE_MARKER_W")\"})")"
fixture_worktree_count="$(wait_for_required_metric_value fixture_worktree_count \
  "max(agentstudio_startup_diagnostic_fixture_worktree_count{agent.proof.marker=\"$(metric_label_selector "$TRACE_MARKER_W")\"})")"
fixture_tab_count="$(wait_for_required_metric_value fixture_tab_count \
  "max(agentstudio_startup_diagnostic_fixture_tab_count{agent.proof.marker=\"$(metric_label_selector "$TRACE_MARKER_W")\"})")"
fixture_pane_count="$(wait_for_required_metric_value fixture_pane_count \
  "max(agentstudio_startup_diagnostic_fixture_pane_count{agent.proof.marker=\"$(metric_label_selector "$TRACE_MARKER_W")\"})")"
fixture_active_pty_count="$(wait_for_required_metric_value fixture_active_pty_count \
  "max(agentstudio_startup_diagnostic_fixture_active_pty_count{agent.proof.marker=\"$(metric_label_selector "$TRACE_MARKER_W")\"})")"
require_exact_fixture_count fixture_repo_count "$fixture_repo_count" "$REQUIRED_REPOSITORY_COUNT"
require_exact_fixture_count fixture_worktree_count "$fixture_worktree_count" "$REQUIRED_WORKTREE_COUNT"
require_exact_fixture_count fixture_tab_count "$fixture_tab_count" "$REQUIRED_TAB_COUNT"
require_exact_fixture_count fixture_pane_count "$fixture_pane_count" "$REQUIRED_PANE_COUNT"
require_exact_fixture_count fixture_active_pty_count "$fixture_active_pty_count" "$REQUIRED_ACTIVE_PTY_COUNT"

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
repo_pane_projection_worker_elapsed_ms_count="$(
  wait_for_required_metric_count repo_pane_projection_worker_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo projection_worker pane grouping_switch)" \
    "$REQUIRED_MATERIALIZED_SAMPLE_COUNT"
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
    "$(metric_event_elapsed_count_query repo projection_worker repo sort_order)" \
    "$REQUIRED_MATERIALIZED_SAMPLE_COUNT"
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
    "$(metric_event_elapsed_count_query repo mainactor_apply repo sort_order)" \
    "$REQUIRED_MATERIALIZED_SAMPLE_COUNT"
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
    "$(metric_event_elapsed_count_query repo request_build_mainactor repo sort_order)" "$REQUIRED_SAMPLE_COUNT"
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
    "$(metric_event_elapsed_count_query repo row_index repo sort_order)" \
    "$REQUIRED_MATERIALIZED_SAMPLE_COUNT"
)"
repo_tab_mainactor_apply_elapsed_ms_count="$(
  wait_for_required_metric_count repo_tab_mainactor_apply_elapsed_ms_count \
    "$(metric_event_elapsed_count_query repo mainactor_apply tab grouping_switch)" \
    "$REQUIRED_MATERIALIZED_SAMPLE_COUNT"
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
    "$(metric_event_elapsed_count_query repo request_build_mainactor pane grouping_switch)" "$REQUIRED_SAMPLE_COUNT"
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
    "$(metric_event_elapsed_count_query repo row_index pane grouping_switch)" \
    "$REQUIRED_MATERIALIZED_SAMPLE_COUNT"
)"

run_repo_explorer_key_mutation_phase
run_repo_explorer_interaction_phase

: >"$KEYED_WAKE_VALUES_FILE"
for key_class in rendered_repo_favorite rendered_worktree_fact unrelated_tab_arrangement_pane observed_tab_title unrendered_attendance relevant missing_declared_key; do
  for stage in capture_rebuild membership_path affected_row whole_surface atom_slot eager_admission projection_worker mainactor_apply final_projection; do
    printf '%s=%s\n' \
      "keyed_wake_${key_class}_${stage}" \
      "$(keyed_wake_count "$key_class" "$stage")" >>"$KEYED_WAKE_VALUES_FILE"
  done
done
eager_family_admission_count="$(keyed_wake_count relevant eager_admission)"
assert_keyed_wake_contract rendered_repo_favorite whole_surface 0
assert_keyed_wake_contract rendered_repo_favorite affected_row "$WORKLOAD_CYCLES"
assert_keyed_wake_contract rendered_repo_favorite capture_rebuild "$WORKLOAD_CYCLES"
assert_keyed_wake_contract rendered_worktree_fact whole_surface 0
assert_keyed_wake_contract rendered_worktree_fact affected_row "$WORKLOAD_CYCLES"
assert_keyed_wake_contract rendered_worktree_fact capture_rebuild "$WORKLOAD_CYCLES"
assert_keyed_wake_contract unrelated_tab_arrangement_pane capture_rebuild 0
assert_keyed_wake_contract unrendered_attendance capture_rebuild 0
assert_keyed_wake_contract relevant whole_surface 0
assert_keyed_wake_contract relevant affected_row "$WORKLOAD_CYCLES"
assert_keyed_wake_contract relevant capture_rebuild "$WORKLOAD_CYCLES"
assert_keyed_wake_contract missing_declared_key membership_path "$WORKLOAD_CYCLES"

reference_different_count="$(keyed_wake_outcome_count final_projection reference_different)"
if [ "$reference_different_count" != "0" ] && [ "$reference_different_count" != "0.0" ]; then
  echo "final_projection reference_different expected 0, got $reference_different_count" >&2
  exit 1
fi

semantic_input_count=$((WORKLOAD_CYCLES * 3))
semantic_fact_count="$(keyed_wake_stage_count affected_row)"
capture_admission_count="$(keyed_wake_stage_count capture_rebuild)"
execution_admission_count="$(keyed_wake_stage_count projection_worker)"
publication_count="$(keyed_wake_stage_count final_projection)"
materialization_count="$(keyed_wake_stage_count mainactor_apply)"
input_to_semantic_fact_contraction_ratio="$(ratio_value "$semantic_fact_count" "$semantic_input_count")"
semantic_fact_to_capture_admission_ratio="$(ratio_value "$capture_admission_count" "$semantic_fact_count")"
capture_to_execution_admission_ratio="$(ratio_value "$execution_admission_count" "$capture_admission_count")"
execution_to_publication_ratio="$(ratio_value "$publication_count" "$execution_admission_count")"
publication_to_materialization_ratio="$(ratio_value "$materialization_count" "$publication_count")"

trace_queue_dropped_record_count="$(wait_for_required_metric_value trace_queue_dropped_record_count \
  "max(agentstudio_performance_trace_queue_dropped_record_count{agent.proof.marker=\"$(metric_label_selector "$TRACE_MARKER_W")\"})")"
runtime_delivery_dropped_count="$(metric_value_or_empty \
  "max(agentstudio_performance_runtime_delivery_runtime_channel_outbound_dropped_count{agent.proof.marker=\"$(metric_label_selector "$TRACE_MARKER_W")\"}) + max(agentstudio_performance_runtime_delivery_eventbus_live_dropped_count{agent.proof.marker=\"$(metric_label_selector "$TRACE_MARKER_W")\"}) + max(agentstudio_performance_runtime_delivery_eventbus_replay_dropped_count{agent.proof.marker=\"$(metric_label_selector "$TRACE_MARKER_W")\"})")"
runtime_delivery_dropped_count="${runtime_delivery_dropped_count:-0}"
collector_loss_count=0
require_exact_fixture_count trace_queue_dropped_record_count "$trace_queue_dropped_record_count" 0
require_exact_fixture_count runtime_delivery_dropped_count "$runtime_delivery_dropped_count" 0

if [ "$mode" = "baseline" ]; then
  {
    echo "trace_name=$TRACE_NAME"
    echo "workload_fixture_key=$WORKLOAD_FIXTURE_KEY"
    echo "worktree_fixture_key=$WORKTREE_FIXTURE_KEY"
    echo "workload_cycles=$WORKLOAD_CYCLES"
    echo "repo_pane_projection_worker_elapsed_ms_p95=$repo_pane_projection_worker_elapsed_ms_p95"
    echo "repo_pane_projection_worker_elapsed_ms_max=$repo_pane_projection_worker_elapsed_ms_max"
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
    echo "repo_pane_request_build_mainactor_elapsed_ms_p95=$repo_pane_request_build_mainactor_elapsed_ms_p95"
    echo "repo_pane_request_build_mainactor_elapsed_ms_max=$repo_pane_request_build_mainactor_elapsed_ms_max"
    echo "repo_pane_row_index_elapsed_ms_p95=$repo_pane_row_index_elapsed_ms_p95"
    echo "repo_pane_row_index_elapsed_ms_max=$repo_pane_row_index_elapsed_ms_max"
  } >"$BASELINE_FILE"
  append_required_metric_values "$BASELINE_FILE"
fi

if [ "$mode" = "compare" ]; then
  compare_repo_pane_projection_worker_elapsed_ms_p95="$repo_pane_projection_worker_elapsed_ms_p95"
  compare_repo_pane_projection_worker_elapsed_ms_max="$repo_pane_projection_worker_elapsed_ms_max"
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
  compare_repo_pane_request_build_mainactor_elapsed_ms_p95="$repo_pane_request_build_mainactor_elapsed_ms_p95"
  compare_repo_pane_request_build_mainactor_elapsed_ms_max="$repo_pane_request_build_mainactor_elapsed_ms_max"
  compare_repo_pane_row_index_elapsed_ms_p95="$repo_pane_row_index_elapsed_ms_p95"
  compare_repo_pane_row_index_elapsed_ms_max="$repo_pane_row_index_elapsed_ms_max"
  compare_metric_values_file="$METRIC_VALUES_FILE"
  required_metric_keys="$(required_metric_keys_line)"
  for baseline_metric_key in \
    repo_pane_projection_worker_elapsed_ms_p95 \
    repo_pane_projection_worker_elapsed_ms_max \
    repo_sort_projection_worker_elapsed_ms_p95 \
    repo_sort_projection_worker_elapsed_ms_max \
    repo_sort_mainactor_apply_elapsed_ms_p95 \
    repo_sort_mainactor_apply_elapsed_ms_max \
    repo_sort_request_build_mainactor_elapsed_ms_p95 \
    repo_sort_request_build_mainactor_elapsed_ms_max \
    repo_sort_row_index_elapsed_ms_p95 \
    repo_sort_row_index_elapsed_ms_max \
    repo_tab_mainactor_apply_elapsed_ms_p95 \
    repo_tab_mainactor_apply_elapsed_ms_max \
    repo_pane_request_build_mainactor_elapsed_ms_p95 \
    repo_pane_request_build_mainactor_elapsed_ms_max \
    repo_pane_row_index_elapsed_ms_p95 \
    repo_pane_row_index_elapsed_ms_max
  do
    load_baseline_metric_value "$BASELINE_FILE" "$baseline_metric_key"
  done
  compare_required_metric_matrix "$BASELINE_FILE" "$compare_metric_values_file"
  performance_threshold_check repo_pane_projection_worker_elapsed_ms_p95 \
    "${repo_pane_projection_worker_elapsed_ms_p95:?missing baseline repo pane worker p95}" \
    "$compare_repo_pane_projection_worker_elapsed_ms_p95"
  performance_threshold_check repo_pane_projection_worker_elapsed_ms_max \
    "${repo_pane_projection_worker_elapsed_ms_max:?missing baseline repo pane worker max}" \
    "$compare_repo_pane_projection_worker_elapsed_ms_max"
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
  repo_pane_projection_worker_elapsed_ms_p95="$compare_repo_pane_projection_worker_elapsed_ms_p95"
  repo_pane_projection_worker_elapsed_ms_max="$compare_repo_pane_projection_worker_elapsed_ms_max"
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
  repo_pane_request_build_mainactor_elapsed_ms_p95="$compare_repo_pane_request_build_mainactor_elapsed_ms_p95"
  repo_pane_request_build_mainactor_elapsed_ms_max="$compare_repo_pane_request_build_mainactor_elapsed_ms_max"
  repo_pane_row_index_elapsed_ms_p95="$compare_repo_pane_row_index_elapsed_ms_p95"
  repo_pane_row_index_elapsed_ms_max="$compare_repo_pane_row_index_elapsed_ms_max"
fi

{
  echo "mode=$mode"
  echo "trace_name=$TRACE_NAME"
  echo "state_file=$STATE_FILE"
  echo "activation_mode=$activation_mode"
  echo "ipc_auth_mode=$ipc_auth_mode"
  echo "fixture_repo_count=$fixture_repo_count"
  echo "fixture_worktree_count=$fixture_worktree_count"
  echo "fixture_tab_count=$fixture_tab_count"
  echo "fixture_pane_count=$fixture_pane_count"
  echo "fixture_active_pty_count=$fixture_active_pty_count"
  echo "process_cpu_sample_count=$process_cpu_sample_count"
  echo "process_cpu_percent_p50=$process_cpu_percent_p50"
  echo "process_cpu_percent_p95=$process_cpu_percent_p95"
  echo "process_cpu_percent_max=$process_cpu_percent_max"
  echo "trace_queue_dropped_record_count=$trace_queue_dropped_record_count"
  echo "runtime_delivery_dropped_count=$runtime_delivery_dropped_count"
  echo "collector_loss_count=$collector_loss_count"
  echo "input_to_semantic_fact_contraction_ratio=$input_to_semantic_fact_contraction_ratio"
  echo "semantic_fact_to_capture_admission_ratio=$semantic_fact_to_capture_admission_ratio"
  echo "capture_to_execution_admission_ratio=$capture_to_execution_admission_ratio"
  echo "execution_to_publication_ratio=$execution_to_publication_ratio"
  echo "publication_to_materialization_ratio=$publication_to_materialization_ratio"
  echo "sidebar_projection.metric_result_count=$metrics_count"
  echo "repo_pane_projection_worker_elapsed_ms_p95=$repo_pane_projection_worker_elapsed_ms_p95"
  echo "repo_pane_projection_worker_elapsed_ms_max=$repo_pane_projection_worker_elapsed_ms_max"
  echo "repo_pane_projection_worker_elapsed_ms_count=$repo_pane_projection_worker_elapsed_ms_count"
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
  echo "repo_pane_request_build_mainactor_elapsed_ms_p95=$repo_pane_request_build_mainactor_elapsed_ms_p95"
  echo "repo_pane_request_build_mainactor_elapsed_ms_max=$repo_pane_request_build_mainactor_elapsed_ms_max"
  echo "repo_pane_request_build_mainactor_elapsed_ms_count=$repo_pane_request_build_mainactor_elapsed_ms_count"
  echo "repo_pane_row_index_elapsed_ms_p95=$repo_pane_row_index_elapsed_ms_p95"
  echo "repo_pane_row_index_elapsed_ms_max=$repo_pane_row_index_elapsed_ms_max"
  echo "repo_pane_row_index_elapsed_ms_count=$repo_pane_row_index_elapsed_ms_count"
  echo "repo_only_workload.ipc_sequence=grouping_and_sort"
  echo "repo_sort.ipc_sequence=descending,ascending,descending,ascending,descending,ascending"
  echo "eager_family_admission_count=$eager_family_admission_count"
  echo "marker_w=$TRACE_MARKER_W"
  echo "marker_k=$TRACE_MARKER_K"
  echo "marker_i=$TRACE_MARKER_I"
  echo "repo_explorer_key_mutation_phase=rendered_repo_favorite,rendered_worktree_fact,relevant_key,unrelated_tab_arrangement_pane,observed_tab_title_informational,unrendered_attendance,unread_facet_change,missing_key_insertion"
  echo "interaction_phase=command_bar_open,command_bar_close,tab_move_program_instrument_gap,cmd_r_program_instrument_gap,divider_program_instrument_gap"
  echo "divider_frame=program_instrument_gap"
  if [ "$mode" = "baseline" ] || [ "$mode" = "compare" ]; then
    echo "baseline_file=$BASELINE_FILE"
  fi
} >"$SUMMARY_FILE"
append_required_metric_values "$SUMMARY_FILE"
cat "$KEYED_WAKE_VALUES_FILE" >>"$SUMMARY_FILE"
echo "sidebar performance workload ok: $SUMMARY_FILE"
