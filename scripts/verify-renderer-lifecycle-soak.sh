#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METRICS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL:-http://127.0.0.1:8428/api/v1/query}"
LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
TRACE_NAME="${AGENTSTUDIO_TRACE_NAME:-renderer-lifecycle-soak-$(date +%Y%m%d%H%M%S)-$$}"
case "$TRACE_NAME" in
  ""|*/*|*\\*|*[!A-Za-z0-9_.-]*) echo "unsafe AGENTSTUDIO_TRACE_NAME" >&2; exit 2 ;;
esac
validate_proof_root() {
  /usr/bin/python3 - "${1:?missing proof root}" <<'PY'
import os, sys
resolved = os.path.realpath(sys.argv[1])
if not resolved.startswith("/private/tmp/agentstudio-renderer-soak."):
    raise SystemExit("renderer lifecycle soak root must use the dedicated /tmp namespace")
print(resolved)
PY
}
if [ -n "${AGENTSTUDIO_RENDERER_LIFECYCLE_SOAK_ROOT:-}" ]; then
  PROOF_ROOT="$(validate_proof_root "$AGENTSTUDIO_RENDERER_LIFECYCLE_SOAK_ROOT")"
else
  PROOF_ROOT="$(validate_proof_root "$(mktemp -d /tmp/agentstudio-renderer-soak.XXXXXX)")"
fi
DATA_ROOT="$PROOF_ROOT/data"
RAW_ROOT="$PROOF_ROOT/raw"
STATE_FILE="$PROOF_ROOT/debug-observability.env"
SAMPLES_FILE="$PROOF_ROOT/samples.jsonl"
PROGRESS_FILE="$PROOF_ROOT/progress.jsonl"
REPORT_FILE="$PROOF_ROOT/report.json"
APP_PID=""
APP_PROOF_LAUNCH=""
WINDOWSERVER_PID=""
APP_EXECUTABLE=""

mkdir -p "$RAW_ROOT"
: >"$SAMPLES_FILE"
: >"$PROGRESS_FILE"

if [ -n "${AGENTSTUDIO_IPC_UNSAFE_NO_AUTH:-}" ]; then
  echo "renderer lifecycle soak refuses unsafe IPC mode" >&2
  exit 2
fi
for required_command in /usr/bin/footprint /usr/bin/vm_stat /usr/sbin/sysctl /usr/bin/curl /usr/bin/python3 /bin/ps; do
  [ -x "$required_command" ] || { echo "missing required sampler: $required_command" >&2; exit 2; }
done

decode_state() {
  local key="${1:?missing state key}"
  local raw
  raw="$(sed -n "s/^$key=//p" "$STATE_FILE" | tail -1)"
  /usr/bin/python3 - "$raw" <<'PY'
import shlex, sys
parts = shlex.split(sys.argv[1]) if sys.argv[1] else []
print(parts[0] if parts else "")
PY
}

cleanup() {
  case "$APP_PID" in
    ""|*[!0-9]*) return 0 ;;
  esac
  if kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

query_metric() {
  local response
  response="$(/usr/bin/curl --fail --silent --show-error --max-time 10 --get \
    --data-urlencode "query=$1" "$METRICS_QUERY_URL")"
  /usr/bin/python3 - "$response" <<'PY'
import json, sys
results = json.loads(sys.argv[1]).get("data", {}).get("result", [])
values = []
for result in results:
    try:
        values.append(float(result["value"][1]))
    except (KeyError, IndexError, TypeError, ValueError):
        pass
if not values:
    raise SystemExit("required renderer lifecycle metric is missing")
print(max(values))
PY
}

renderer_metric() {
  local metric_name="${1:?missing renderer metric name}"
  local selector
  selector='service.name="AgentStudio",dev.runtime.flavor="debug",agent.proof.marker="'"$TRACE_NAME"'",agent.proof.launch="'"$APP_PROOF_LAUNCH"'",event="performance.renderer.lifecycle"'
  query_metric "max($metric_name{$selector})"
}

discover_windowserver_pid() {
  /bin/ps -axo pid=,comm= | /usr/bin/awk '$2 ~ /\/WindowServer$/ {print $1}'
}

fetch_progress_record() {
  local stage="${1:?missing stage}"
  local scenario="${2:-none}"
  local query
  query='agent.proof.marker:="'"$TRACE_NAME"'" _msg:app.startup_diagnostic_action.command_exercised agentstudio.app.startup.phase:="'"$stage"'" agentstudio.startup_diagnostic.skip_reason:="'"$scenario"'"'
  /usr/bin/curl --fail --silent --show-error --max-time 10 --get \
    --data-urlencode "query=$query | fields agentstudio.startup_diagnostic.created_pane.count,agentstudio.startup_diagnostic.expected_visible_pane.count | limit 1" \
    "$LOGS_QUERY_URL" | /usr/bin/python3 -c '
import json, sys
records = []
for line in sys.stdin:
    if not line.strip():
        continue
    decoded = json.loads(line)
    records.extend(decoded if isinstance(decoded, list) else [decoded])
if not records:
    raise SystemExit(1)
record = records[0]
completed = record.get("agentstudio.startup_diagnostic.created_pane.count")
expected = record.get("agentstudio.startup_diagnostic.expected_visible_pane.count")
try:
    completed_value = int(float(completed))
    expected_value = int(float(expected))
except (TypeError, ValueError):
    raise SystemExit("progress record missing emitted completed/expected counts")
print(completed_value, expected_value)
'
}

append_progress() {
  local stage="${1:?missing stage}"
  local scenario="${2:-none}"
  local completed_count="${3:-0}"
  local expected_count="${4:-0}"
  /usr/bin/python3 - "$PROGRESS_FILE" "$TRACE_NAME" "$APP_PID" "$WINDOWSERVER_PID" \
    "$stage" "$scenario" "$completed_count" "$expected_count" "$(date +%s)" <<'PY'
import json, sys
path, marker, app_pid, ws_pid, stage, scenario, completed, expected, timestamp = sys.argv[1:]
with open(path, "a", encoding="utf-8") as stream:
    stream.write(json.dumps({
        "marker": marker,
        "app_pid": int(app_pid),
        "windowserver_pid": int(ws_pid),
        "stage": stage,
        "scenario": scenario,
        "completed_count": int(completed),
        "expected_count": int(expected),
        "timestamp_seconds": float(timestamp),
    }, separators=(",", ":")) + "\n")
PY
}

parse_footprint() {
  local path="${1:?missing footprint path}"
  local require_categories="${2:?missing category policy}"
  /usr/bin/python3 - "$path" "$require_categories" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
def first_integer(line):
    values = re.findall(r"(?<![A-Za-z])[0-9][0-9,]*(?![A-Za-z])", line)
    return int(values[0].replace(",", "")) if values else None
footprint = None
iosurface = None
ioaccelerator = None
for line in text.splitlines():
    stripped = line.strip()
    footprint_match = re.search(r"(?:Physical\s+)?Footprint:\s*([0-9][0-9,]*)\s+B", stripped, re.IGNORECASE)
    if footprint_match:
        footprint = int(footprint_match.group(1).replace(",", ""))
    if stripped.endswith("IOSurface"):
        iosurface = first_integer(stripped)
    if stripped.endswith("IOAccelerator") or stripped.endswith("IOAccelerator graphics"):
        ioaccelerator = first_integer(stripped)
if footprint is None:
    raise SystemExit("footprint total missing")
if sys.argv[2] == "categories" and (iosurface is None or ioaccelerator is None):
    raise SystemExit("IOSurface or IOAccelerator footprint category missing")
print(footprint, iosurface or 0, ioaccelerator or 0)
PY
}

system_memory_values() {
  local vm_stat_path="${1:?missing vm_stat path}"
  local swap_path="${2:?missing swap path}"
  /usr/bin/python3 - "$vm_stat_path" "$swap_path" <<'PY'
import re, sys
vm_text = open(sys.argv[1], encoding="utf-8").read()
swap_text = open(sys.argv[2], encoding="utf-8").read()
page_match = re.search(r"page size of ([0-9]+) bytes", vm_text)
free_match = re.search(r"Pages free:\s*([0-9.]+)", vm_text)
compressor_match = re.search(r"Pages occupied by compressor:\s*([0-9.]+)", vm_text)
swap_match = re.search(r"used\s*=\s*([0-9.]+)([KMG])", swap_text)
if not all((page_match, free_match, compressor_match, swap_match)):
    raise SystemExit("required vm_stat or swap series missing")
page_size = int(page_match.group(1))
free_pages = int(free_match.group(1).replace(".", ""))
compressor_pages = int(compressor_match.group(1).replace(".", ""))
units = {"K": 1024, "M": 1024**2, "G": 1024**3}
swap_bytes = int(float(swap_match.group(1)) * units[swap_match.group(2)])
print(compressor_pages * page_size, swap_bytes, free_pages * page_size)
PY
}

sample_row() {
  local window="${1:?missing sample window}"
  local elapsed_seconds="${2:?missing elapsed seconds}"
  local sample_index="${3:?missing sample index}"
  kill -0 "$APP_PID" >/dev/null 2>&1 || { echo "bound app PID exited" >&2; return 1; }
  [ "$(discover_windowserver_pid)" = "$WINDOWSERVER_PID" ] || {
    echo "WindowServer PID changed during renderer lifecycle soak" >&2
    return 1
  }
  local prefix="$RAW_ROOT/${window}-${sample_index}"
  local app_footprint_pid windowserver_footprint_pid vm_stat_pid swap_pid
  /usr/bin/footprint --pid "$APP_PID" --format bytes --wide >"$prefix-app-footprint.txt" 2>&1 &
  app_footprint_pid=$!
  /usr/bin/footprint --pid "$WINDOWSERVER_PID" --format bytes --wide >"$prefix-ws-footprint.txt" 2>&1 &
  windowserver_footprint_pid=$!
  /usr/bin/vm_stat >"$prefix-vm-stat.txt" &
  vm_stat_pid=$!
  /usr/sbin/sysctl vm.swapusage >"$prefix-swap.txt" &
  swap_pid=$!
  wait "$app_footprint_pid"
  wait "$windowserver_footprint_pid"
  wait "$vm_stat_pid"
  wait "$swap_pid"
  local app_physical app_iosurface app_ioaccelerator ws_footprint ignored_one ignored_two
  read -r app_physical app_iosurface app_ioaccelerator < <(parse_footprint "$prefix-app-footprint.txt" categories)
  read -r ws_footprint ignored_one ignored_two < <(parse_footprint "$prefix-ws-footprint.txt" total)
  local compressor_bytes swap_used_bytes free_memory_bytes
  read -r compressor_bytes swap_used_bytes free_memory_bytes < <(
    system_memory_values "$prefix-vm-stat.txt" "$prefix-swap.txt"
  )
  local metric_values=()
  local metric
  for metric in \
    agentstudio_performance_renderer_created_total \
    agentstudio_performance_renderer_active_current \
    agentstudio_performance_renderer_hidden_current \
    agentstudio_performance_renderer_close_undo_current \
    agentstudio_performance_renderer_release_total \
    agentstudio_performance_renderer_free_total \
    agentstudio_performance_renderer_live_current \
    agentstudio_performance_renderer_manager_owned_current \
    agentstudio_performance_renderer_orphan_candidate_current \
    agentstudio_performance_renderer_visibility_delivery_total \
    agentstudio_performance_renderer_visibility_equal_suppressed_total \
    agentstudio_performance_renderer_projection_evaluation_total \
    agentstudio_performance_renderer_projection_changed_surface_total \
    agentstudio_performance_renderer_projection_equal_surface_total \
    agentstudio_performance_renderer_lifecycle_valid \
    agentstudio_performance_renderer_sample_sequence; do
    metric_values+=("$(renderer_metric "$metric")")
  done
  /usr/bin/python3 - "$SAMPLES_FILE" "$TRACE_NAME" "$APP_PID" "$WINDOWSERVER_PID" \
    "$window" "$elapsed_seconds" "$(date +%s)" \
    "${metric_values[@]}" "$app_physical" "$app_iosurface" "$app_ioaccelerator" \
    "$ws_footprint" "$compressor_bytes" "$swap_used_bytes" "$free_memory_bytes" <<'PY'
import json, sys
keys = [
    "created_total", "active_current", "hidden_current", "close_undo_current",
    "release_total", "free_total", "live_current", "manager_owned_current", "orphan_current",
    "visibility_delivery_total", "visibility_equal_suppressed_total", "projection_evaluation_total",
    "projection_changed_surface_total", "projection_equal_surface_total",
    "lifecycle_valid", "sample_sequence", "app_physical_bytes", "app_iosurface_bytes",
    "app_ioaccelerator_bytes", "windowserver_footprint_bytes", "compressor_bytes", "swap_used_bytes",
    "raw_free_memory_bytes",
]
path, marker, app_pid, ws_pid, window, elapsed, timestamp, *values = sys.argv[1:]
if len(values) != len(keys):
    raise SystemExit("sample value count mismatch")
row = {
    "marker": marker,
    "app_pid": int(app_pid),
    "windowserver_pid": int(ws_pid),
    "window": window,
    "window_elapsed_seconds": float(elapsed),
    "timestamp_seconds": float(timestamp),
}
row.update({key: float(value) for key, value in zip(keys, values)})
with open(path, "a", encoding="utf-8") as stream:
    stream.write(json.dumps(row, separators=(",", ":")) + "\n")
PY
}

wait_for_progress() {
  local stage="${1:?missing stage}"
  local scenario="${2:-none}"
  local completed="${3:-0}"
  local expected="${4:-0}"
  local timeout_seconds="${5:-120}"
  local sample_while_waiting="${6:-1}"
  local deadline=$(( $(date +%s) + timeout_seconds ))
  local workload_sample=0
  local observed_counts observed_completed observed_expected
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if observed_counts="$(fetch_progress_record "$stage" "$scenario")"; then
      read -r observed_completed observed_expected <<<"$observed_counts"
      if [ "$observed_completed" -ne "$completed" ] || [ "$observed_expected" -ne "$expected" ]; then
        echo "renderer lifecycle progress count mismatch for $stage/$scenario: observed=$observed_completed/$observed_expected expected=$completed/$expected" >&2
        return 1
      fi
      append_progress "$stage" "$scenario" "$observed_completed" "$observed_expected"
      return 0
    fi
    /bin/sleep 10
    if [ "$sample_while_waiting" = 1 ]; then
      workload_sample=$((workload_sample + 1))
      sample_row workload "$((workload_sample * 10))" "$stage-$scenario-$workload_sample"
    fi
  done
  echo "timed out waiting for renderer lifecycle soak progress: $stage/$scenario" >&2
  return 1
}

sample_fixed_window() {
  local window="${1:?missing window}"
  local count="${2:?missing sample count}"
  local start_epoch
  start_epoch="$(date +%s)"
  local index target now remaining
  for index in $(seq 1 "$count"); do
    target=$((start_epoch + index * 10))
    now="$(date +%s)"
    remaining=$((target - now))
    [ "$remaining" -le 0 ] || /bin/sleep "$remaining"
    sample_row "$window" "$((index * 10))" "$index"
  done
}

env \
  AGENTSTUDIO_DEBUG_LAUNCH_ACTIVATE=1 \
  AGENTSTUDIO_DEBUG_DATA_DIR="$DATA_ROOT" \
  AGENTSTUDIO_TRACE_TAGS="performance,app.startup,terminal.startup" \
  AGENTSTUDIO_TRACE_NAME="$TRACE_NAME" \
  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=renderer-lifecycle-continuity \
  AGENTSTUDIO_RENDERER_LIFECYCLE_PHASE=soak \
  AGENTSTUDIO_STARTUP_WATCH_FOLDER="$PROJECT_ROOT" \
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
  "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach

for _ in $(seq 1 90); do
  if [ -f "$STATE_FILE" ] && [ "$(decode_state AGENTSTUDIO_OBSERVABILITY_STATUS)" = running ]; then break; fi
  /bin/sleep 1
done
[ -f "$STATE_FILE" ] || { echo "renderer lifecycle soak launch state missing" >&2; exit 1; }
[ "$(decode_state AGENTSTUDIO_OBSERVABILITY_MARKER)" = "$TRACE_NAME" ] || { echo "marker mismatch" >&2; exit 1; }
[ "$(decode_state AGENTSTUDIO_OBSERVABILITY_DATA_DIR)" = "$DATA_ROOT" ] || { echo "data root mismatch" >&2; exit 1; }
[ "$(decode_state AGENTSTUDIO_OBSERVABILITY_ZMX_DIR)" = "$DATA_ROOT/z" ] || { echo "zmx root mismatch" >&2; exit 1; }
APP_PID="$(decode_state AGENTSTUDIO_OBSERVABILITY_PID)"
case "$APP_PID" in ""|*[!0-9]*) echo "missing numeric app PID" >&2; exit 1 ;; esac
APP_PROOF_LAUNCH="$(decode_state AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN)"
case "$APP_PROOF_LAUNCH" in
  ""|*[!A-Za-z0-9_.-]*) echo "missing safe proof launch identity" >&2; exit 1 ;;
esac
APP_EXECUTABLE="$(decode_state AGENTSTUDIO_OBSERVABILITY_EXECUTABLE)"
[ "$(/bin/ps -p "$APP_PID" -o comm= | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" = "$APP_EXECUTABLE" ] || {
  echo "app executable mismatch" >&2; exit 1;
}
WINDOWSERVER_PID="$(discover_windowserver_pid)"
case "$WINDOWSERVER_PID" in ""|*[!0-9]*) echo "missing exact WindowServer PID" >&2; exit 1 ;; esac

wait_for_progress fixture_ready none 0 0 120 0
wait_for_progress equal_reconciliation_verified none 20 20 60 0
wait_for_progress changed_delivery_verified none 40 40 60 0
sample_row preflight 0 0
wait_for_progress warmup_started none 0 0 60 0
sample_fixed_window warmup 60
wait_for_progress warmup_completed none 0 0 60
for scenario in tab_switch drawer_toggle arrangement_switch background_reactivate zoom_retarget \
  parent_minimize drawer_minimize window_minimize window_occlusion repair_recreate; do
  wait_for_progress scenario_completed "$scenario" 20 20 600
done
wait_for_progress scenario_completed close_immediate_undo 10 10 300
wait_for_progress scenario_completed close_expiry 10 10 420
wait_for_progress final_window_started none 0 0 120
sample_fixed_window final 180
wait_for_progress final_window_completed none 0 0 60

/usr/bin/python3 "$PROJECT_ROOT/scripts/analyze-renderer-lifecycle-soak.py" \
  --samples "$SAMPLES_FILE" --progress "$PROGRESS_FILE" --report "$REPORT_FILE"
echo "renderer lifecycle soak proof root: $PROOF_ROOT"
echo "renderer lifecycle soak report: $REPORT_FILE"
