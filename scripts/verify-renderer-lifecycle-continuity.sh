#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METRICS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL:-http://127.0.0.1:8428/api/v1/query}"
LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
BASE_TRACE_NAME="${AGENTSTUDIO_TRACE_NAME:-renderer-lifecycle-$(date +%Y%m%d%H%M%S)-$$}"
case "$BASE_TRACE_NAME" in
  ""|*/*|*\\*|*[!A-Za-z0-9_.-]*) echo "unsafe AGENTSTUDIO_TRACE_NAME" >&2; exit 2 ;;
esac
validate_proof_root() {
  /usr/bin/python3 - "${1:?missing proof root}" <<'PY'
import os, sys
resolved = os.path.realpath(sys.argv[1])
if not resolved.startswith("/private/tmp/agentstudio-renderer-lifecycle."):
    raise SystemExit("renderer lifecycle proof root must use the dedicated /tmp namespace")
print(resolved)
PY
}
if [ -n "${AGENTSTUDIO_RENDERER_LIFECYCLE_PROOF_ROOT:-}" ]; then
  PROOF_ROOT="$(validate_proof_root "$AGENTSTUDIO_RENDERER_LIFECYCLE_PROOF_ROOT")"
else
  PROOF_ROOT="$(validate_proof_root "$(mktemp -d /tmp/agentstudio-renderer-lifecycle.XXXXXX)")"
fi
DATA_ROOT="$PROOF_ROOT/data"
RESTART_MANIFEST="$PROOF_ROOT/restart-manifest.json"
TRACE_NAME=""
STATE_FILE=""
APP_PID=""
APP_PROOF_LAUNCH=""
INITIAL_PID=""
INITIAL_EXECUTABLE=""
INITIAL_ZMX_DIR=""

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
    raise SystemExit(1)
print(max(values))
PY
}

launch_phase() {
  local phase="${1:?missing renderer lifecycle phase}"
  TRACE_NAME="$BASE_TRACE_NAME-$phase"
  STATE_FILE="$PROOF_ROOT/debug-observability-$phase.env"
  APP_PID=""
  env \
    AGENTSTUDIO_DEBUG_LAUNCH_ACTIVATE=1 \
    AGENTSTUDIO_DEBUG_DATA_DIR="$DATA_ROOT" \
    AGENTSTUDIO_TRACE_TAGS="performance,app.startup,terminal.startup" \
    AGENTSTUDIO_TRACE_NAME="$TRACE_NAME" \
    AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=renderer-lifecycle-continuity \
    AGENTSTUDIO_STARTUP_WATCH_FOLDER="$PROJECT_ROOT" \
    AGENTSTUDIO_RENDERER_LIFECYCLE_PHASE="$phase" \
    AGENTSTUDIO_RENDERER_LIFECYCLE_RESTART_MANIFEST="$RESTART_MANIFEST" \
    AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
    "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach

  for _ in $(seq 1 90); do
    if [ -f "$STATE_FILE" ] && [ "$(decode_state AGENTSTUDIO_OBSERVABILITY_STATUS)" = running ]; then
      break
    fi
    /bin/sleep 1
  done
  [ -f "$STATE_FILE" ] || { echo "renderer lifecycle launch state missing for $phase" >&2; exit 1; }
  [ "$(decode_state AGENTSTUDIO_OBSERVABILITY_STATUS)" = running ] || {
    echo "renderer lifecycle debug app did not start for $phase" >&2
    exit 1
  }
  [ "$(decode_state AGENTSTUDIO_OBSERVABILITY_MARKER)" = "$TRACE_NAME" ] || {
    echo "renderer lifecycle marker mismatch for $phase" >&2
    exit 1
  }
  [ "$(decode_state AGENTSTUDIO_OBSERVABILITY_DATA_DIR)" = "$DATA_ROOT" ] || {
    echo "renderer lifecycle data root mismatch for $phase" >&2
    exit 1
  }
  [ "$(decode_state AGENTSTUDIO_OBSERVABILITY_ZMX_DIR)" = "$DATA_ROOT/z" ] || {
    echo "renderer lifecycle zmx root mismatch for $phase" >&2
    exit 1
  }
  APP_PID="$(decode_state AGENTSTUDIO_OBSERVABILITY_PID)"
  case "$APP_PID" in
    ""|*[!0-9]*) echo "renderer lifecycle state missing numeric PID for $phase" >&2; exit 1 ;;
  esac
  APP_PROOF_LAUNCH="$(decode_state AGENTSTUDIO_OBSERVABILITY_PROOF_TOKEN)"
  case "$APP_PROOF_LAUNCH" in
    ""|*[!A-Za-z0-9_.-]*) echo "renderer lifecycle state missing safe proof launch identity for $phase" >&2; exit 1 ;;
  esac
  local recorded_executable
  local running_executable
  recorded_executable="$(decode_state AGENTSTUDIO_OBSERVABILITY_EXECUTABLE)"
  running_executable="$(/bin/ps -p "$APP_PID" -o comm= | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -n "$recorded_executable" ] && [ "$running_executable" = "$recorded_executable" ] || {
    echo "renderer lifecycle executable mismatch for $phase" >&2
    exit 1
  }
}

wait_for_diagnostic_completion() {
  local phase="${1:?missing renderer lifecycle phase}"
  local timeout_seconds="${2:?missing completion timeout}"
  /usr/bin/python3 - "$LOGS_QUERY_URL" "$TRACE_NAME" "$phase" "$timeout_seconds" <<'PY'
import json, sys, time, urllib.parse, urllib.request
logs_url, marker, expected_phase, timeout_text = sys.argv[1:5]
def is_true(value):
    return value is True or (isinstance(value, str) and value.lower() == "true")
query = f'agent.proof.marker:="{marker}"'
deadline = time.monotonic() + float(timeout_text)
while time.monotonic() < deadline:
    url = logs_url + "?" + urllib.parse.urlencode({"query": query})
    with urllib.request.urlopen(url, timeout=10) as response:
        lines = response.read().decode().splitlines()
    records = []
    for line in lines:
        if not line.strip():
            continue
        decoded = json.loads(line)
        records.extend(decoded if isinstance(decoded, list) else [decoded])
    blocked = [record for record in records if record.get("_msg") == "app.startup_diagnostic_action.blocked"]
    if blocked:
        reason = blocked[-1].get("agentstudio.startup_diagnostic.skip_reason", "unknown")
        raise SystemExit(f"renderer lifecycle diagnostic blocked: {reason}")
    completed = [record for record in records if record.get("_msg") == "app.startup_diagnostic_action.completed"]
    if completed:
        record = completed[-1]
        if record.get("agentstudio.startup_diagnostic.renderer_lifecycle.phase") != expected_phase:
            raise SystemExit("renderer lifecycle diagnostic phase mismatch")
        if int(float(record.get("agentstudio.startup_diagnostic.created_pane.count", 0))) != 20:
            raise SystemExit("renderer lifecycle diagnostic did not prove exactly 20 panes")
        if not is_true(record.get("agentstudio.startup_diagnostic.render_proof.succeeded")):
            raise SystemExit("renderer lifecycle render proof did not succeed")
        if not is_true(record.get("agentstudio.startup_diagnostic.projection_proof.succeeded")):
            raise SystemExit("renderer lifecycle projection proof did not succeed")
        break
    time.sleep(0.5)
else:
    raise SystemExit("timed out waiting for renderer lifecycle diagnostic completion")
PY
}

wait_for_exact_process_exit() {
  for _ in $(seq 1 90); do
    if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
      return 0
    fi
    /bin/sleep 1
  done
  echo "renderer lifecycle app did not terminate through the normal app path" >&2
  return 1
}

renderer_metric() {
  local label="${1:?missing renderer metric label}"
  local selector
  selector='service.name="AgentStudio",dev.runtime.flavor="debug",agent.proof.marker="'"$TRACE_NAME"'",agent.proof.launch="'"$APP_PROOF_LAUNCH"'",event="performance.renderer.lifecycle"'
  query_metric "max($label{$selector})"
}

verify_phase_ledger() {
  local phase="${1:?missing renderer lifecycle phase}"
  local expected_created expected_released expected_freed
  case "$phase" in
    initial) expected_created=41; expected_released=21; expected_freed=21 ;;
    restart) expected_created=20; expected_released=0; expected_freed=0 ;;
    *) echo "unknown renderer lifecycle phase: $phase" >&2; return 2 ;;
  esac
  local created_total release_total free_total active_current hidden_current live_current
  local manager_owned_current close_undo_current orphan_current lifecycle_valid sample_sequence
  local visibility_total visibility_equal_total projection_total
  local phase_ledger_deadline phase_ledger_result last_phase_ledger_failure
  phase_ledger_deadline=$((SECONDS + 120))
  last_phase_ledger_failure="required renderer lifecycle metric is missing"
  while [ "$SECONDS" -lt "$phase_ledger_deadline" ]; do
    if created_total="$(renderer_metric agentstudio_performance_renderer_created_total)" &&
      release_total="$(renderer_metric agentstudio_performance_renderer_release_total)" &&
      free_total="$(renderer_metric agentstudio_performance_renderer_free_total)" &&
      active_current="$(renderer_metric agentstudio_performance_renderer_active_current)" &&
      hidden_current="$(renderer_metric agentstudio_performance_renderer_hidden_current)" &&
      live_current="$(renderer_metric agentstudio_performance_renderer_live_current)" &&
      manager_owned_current="$(renderer_metric agentstudio_performance_renderer_manager_owned_current)" &&
      close_undo_current="$(renderer_metric agentstudio_performance_renderer_close_undo_current)" &&
      orphan_current="$(renderer_metric agentstudio_performance_renderer_orphan_candidate_current)" &&
      lifecycle_valid="$(renderer_metric agentstudio_performance_renderer_lifecycle_valid)" &&
      sample_sequence="$(renderer_metric agentstudio_performance_renderer_sample_sequence)" &&
      visibility_total="$(renderer_metric agentstudio_performance_renderer_visibility_delivery_total)" &&
      visibility_equal_total="$(renderer_metric agentstudio_performance_renderer_visibility_equal_suppressed_total)" &&
      projection_total="$(renderer_metric agentstudio_performance_renderer_projection_evaluation_total)" &&
      phase_ledger_result="$(/usr/bin/python3 - \
    "$phase" "$expected_created" "$expected_released" "$expected_freed" \
    "$created_total" "$release_total" "$free_total" "$active_current" "$hidden_current" \
    "$live_current" "$manager_owned_current" "$close_undo_current" "$orphan_current" \
    "$lifecycle_valid" "$sample_sequence" "$visibility_total" "$visibility_equal_total" \
    "$projection_total" 2>&1 <<'PY'
import sys
(
    phase, expected_created, expected_released, expected_freed,
    created, released, freed, active, hidden, live, manager_owned, close_undo,
    orphan, valid, sequence, visibility, visibility_equal, projection,
) = sys.argv[1:]
values = list(map(float, [
    expected_created, expected_released, expected_freed, created, released, freed,
    active, hidden, live, manager_owned, close_undo, orphan, valid, sequence,
    visibility, visibility_equal, projection,
]))
(
    expected_created, expected_released, expected_freed, created, released, freed,
    active, hidden, live, manager_owned, close_undo, orphan, valid, sequence,
    visibility, visibility_equal, projection,
) = values
if (created, released, freed) != (expected_created, expected_released, expected_freed):
    raise SystemExit(
        f"{phase} lifecycle totals mismatch: created={created} released={released} freed={freed}"
    )
if live != 20 or manager_owned != 20 or active + hidden + close_undo != manager_owned:
    raise SystemExit(
        f"{phase} renderer conservation failed: active={active} hidden={hidden} "
        f"undo={close_undo} live={live} manager_owned={manager_owned}"
    )
if close_undo != 0 or orphan != 0 or valid != 1 or sequence <= 0:
    raise SystemExit(
        f"{phase} renderer settlement failed: close_undo={close_undo} orphan={orphan} "
        f"valid={valid} sequence={sequence}"
    )
if visibility <= 0 or projection <= 0:
    raise SystemExit(
        f"{phase} renderer visibility proof missing: delivery={visibility} projection={projection}"
    )
if phase == "initial" and visibility_equal <= 0:
    raise SystemExit("initial renderer equality-suppression proof missing")
print(
    f"renderer lifecycle {phase} ledger ok: created={created:.0f} released={released:.0f} "
    f"freed={freed:.0f} live={live:.0f} visibility={visibility:.0f} projection={projection:.0f}"
)
PY
)"
    then
      printf '%s\n' "$phase_ledger_result"
      return 0
    fi
    if [ -n "${phase_ledger_result:-}" ]; then
      last_phase_ledger_failure="$phase_ledger_result"
    fi
    /bin/sleep 1
  done
  echo "$last_phase_ledger_failure" >&2
  return 1
}

launch_phase initial
INITIAL_PID="$APP_PID"
INITIAL_EXECUTABLE="$(decode_state AGENTSTUDIO_OBSERVABILITY_EXECUTABLE)"
INITIAL_ZMX_DIR="$(decode_state AGENTSTUDIO_OBSERVABILITY_ZMX_DIR)"
wait_for_diagnostic_completion initial 780
wait_for_exact_process_exit
verify_phase_ledger initial
[ -f "$RESTART_MANIFEST" ] || { echo "renderer lifecycle restart manifest missing" >&2; exit 1; }

launch_phase restart
[ "$APP_PID" != "$INITIAL_PID" ] || { echo "renderer lifecycle restart reused process PID" >&2; exit 1; }
[ "$(decode_state AGENTSTUDIO_OBSERVABILITY_EXECUTABLE)" = "$INITIAL_EXECUTABLE" ] || {
  echo "renderer lifecycle restart executable changed" >&2
  exit 1
}
[ "$(decode_state AGENTSTUDIO_OBSERVABILITY_ZMX_DIR)" = "$INITIAL_ZMX_DIR" ] || {
  echo "renderer lifecycle restart zmx root changed" >&2
  exit 1
}
wait_for_diagnostic_completion restart 180
wait_for_exact_process_exit
verify_phase_ledger restart

echo "renderer lifecycle continuity and restart proof ok"
echo "renderer lifecycle proof root: $PROOF_ROOT"
