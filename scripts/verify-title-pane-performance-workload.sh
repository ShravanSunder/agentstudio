#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METRICS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL:-http://127.0.0.1:8428/api/v1/query}"
LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"

validate_fixture() {
  /usr/bin/python3 - "$1" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    proof = json.load(stream)
records = proof["drainRecords"]
by_class = {record["drainClass"]: record for record in records}
for drain_class in ("immediate", "title_deadline", "exact_barrier"):
    if drain_class not in by_class:
        print(f"missing {drain_class} drain", file=sys.stderr)
        raise SystemExit(1)
deadline = by_class["title_deadline"]["elapsedMilliseconds"]
if deadline > 1000:
    print("title_deadline queue age exceeded 1000ms", file=sys.stderr)
    raise SystemExit(1)
metric = proof.get("titleDeadlineMetricMilliseconds")
if metric is None:
    print("missing title_deadline Victoria metric", file=sys.stderr)
    raise SystemExit(1)
ipc = proof["ipc"]
if not ipc["titleReadbackSucceeded"]:
    print("terminal title readback did not advance", file=sys.stderr)
    raise SystemExit(1)
if not ipc["titleWaitSucceeded"] or not ipc["commandFinishedWaitSucceeded"]:
    print("terminal title wait did not succeed", file=sys.stderr)
    raise SystemExit(1)
immediate_time = by_class["immediate"]["timeUnixNanoseconds"]
if not ipc["workloadStartUnixNanoseconds"] <= immediate_time <= ipc["workloadEndUnixNanoseconds"]:
    print("immediate activity drain was not inside pending title interval", file=sys.stderr)
    raise SystemExit(1)
rendered = proof["renderedOTLP"]
if any(value and value in rendered for value in proof["sensitiveValues"]):
    print("sensitive terminal content survived OTLP projection", file=sys.stderr)
    raise SystemExit(1)
pane = proof["pane"]
if pane["tabBarAffectedItemCount"] != 1:
    print("tabbar affected-item count must be 1", file=sys.stderr)
    raise SystemExit(1)
if any(pane[key] != 0 for key in (
    "titleRepoProjectionDelta",
    "titleRepoCommandEventDelta",
    "titleRepoCommandResolutionDelta",
    "titleRepoCapabilitySnapshotDelta",
    "titleStructuralAcceptedMutationDelta",
)):
    print("title mutation performed structural or Repo command work", file=sys.stderr)
    raise SystemExit(1)
if pane["titleCanonicalAcceptedMutationDelta"] != 1:
    print("title mutation did not accept exactly one canonical pane change", file=sys.stderr)
    raise SystemExit(1)
if not 1 <= pane["paneStructuralCanonicalAcceptedMutationDelta"] <= 8:
    print("pane structural phase canonical work was not bounded", file=sys.stderr)
    raise SystemExit(1)
if not 1 <= pane["paneStructuralAcceptedMutationDelta"] <= 8:
    print("pane structural phase structural work was not bounded", file=sys.stderr)
    raise SystemExit(1)
if not 1 <= pane["paneMembershipAcceptedMutationDelta"] <= 8:
    print("pane structural phase membership work was not bounded", file=sys.stderr)
    raise SystemExit(1)
if pane["capabilityRepoCommandEventDelta"] != 1 or pane["capabilityRepoAffectedItemCount"] <= 0:
    print("missing capability-driven Repo Explorer command refresh", file=sys.stderr)
    raise SystemExit(1)
if not 1 <= pane["capabilityRepoCommandResolutionCount"] == pane["capabilityVisibleRequestCount"]:
    print("unbounded command resolutions", file=sys.stderr)
    raise SystemExit(1)
if pane["capabilityRepoCapabilitySnapshotCount"] != 1:
    print("capability snapshots per refresh must be 1", file=sys.stderr)
    raise SystemExit(1)
if pane["capabilityTabBarAffectedItemCount"] != 0:
    print("capability phase affected unrelated tab items", file=sys.stderr)
    raise SystemExit(1)
print("title and pane performance proof ok")
PY
}

case "${1:-}" in
  --validate-fixture)
    [ "$#" -eq 2 ] || { echo "missing fixture path" >&2; exit 2; }
    validate_fixture "$2"
    exit 0
    ;;
  --proof) ;;
  *) echo "usage: $0 --proof | --validate-fixture FILE" >&2; exit 2 ;;
esac

if [ -n "${AGENTSTUDIO_IPC_UNSAFE_NO_AUTH:-}" ]; then
  echo "title/pane proof refuses AGENTSTUDIO_IPC_UNSAFE_NO_AUTH" >&2
  exit 2
fi
TRACE_NAME="${AGENTSTUDIO_TRACE_NAME:-title-pane-$(date +%Y%m%d%H%M%S)-$$}"
case "$TRACE_NAME" in ""|*/*|*\\*|*[!A-Za-z0-9_.-]*) echo "unsafe AGENTSTUDIO_TRACE_NAME" >&2; exit 2;; esac
TRACE_NONCE="$(/usr/bin/uuidgen)"
TRACE_MARKER="$(printf '%s:%s' "$TRACE_NAME" "$TRACE_NONCE" | /usr/bin/shasum -a 256 | awk '{print "title-pane-" substr($1,1,20)}')"
PROOF_ROOT="${AGENTSTUDIO_TITLE_PANE_PROOF_ROOT:-/tmp/agentstudio-title-pane-performance}"
ARTIFACT="$PROOF_ROOT/$TRACE_NAME"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$ARTIFACT/debug-observability.env}"
APP_PID=""
mkdir -p "$ARTIFACT" "$(dirname "$STATE_FILE")"

decode_state() {
  local raw
  raw="$(sed -n "s/^$1=//p" "$STATE_FILE" | tail -1)"
  /usr/bin/python3 - "$raw" <<'PY'
import shlex, sys
parts = shlex.split(sys.argv[1]) if sys.argv[1] else []
print(parts[0] if parts else "")
PY
}

ipc_runtime_matches_app_pid() {
  /usr/bin/python3 - "$1" "$2" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        runtime = json.load(stream)
    expected_pid = int(sys.argv[2])
except (OSError, TypeError, ValueError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if runtime.get("processIdentifier") == expected_pid else 1)
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

cleanup() {
  local cleanup_pid="$APP_PID"
  if [ -z "$cleanup_pid" ] && [ -f "$STATE_FILE" ] \
    && [ "$(decode_state AGENTSTUDIO_OBSERVABILITY_MARKER)" = "$TRACE_MARKER" ]
  then
    cleanup_pid="$(decode_state AGENTSTUDIO_OBSERVABILITY_PID)"
  fi
  case "$cleanup_pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  stop_pid "$cleanup_pid"
}

trap cleanup EXIT INT TERM

query_value() {
  local response
  response="$(/usr/bin/curl --fail --silent --show-error --max-time 10 --get --data-urlencode "query=$1" "$METRICS_QUERY_URL")"
  /usr/bin/python3 - "$response" <<'PY'
import json, sys
data = json.loads(sys.argv[1]).get("data", {}).get("result", [])
values = []
for item in data:
    try: values.append(float(item["value"][1]))
    except (KeyError, IndexError, TypeError, ValueError): pass
print(max(values) if values else 0)
PY
}

env \
  AGENTSTUDIO_TRACE_TAGS="performance,atoms,app.startup,terminal.startup" \
  AGENTSTUDIO_TRACE_NAME="$TRACE_MARKER" \
  AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
  AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=sidebar-performance-proof \
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$STATE_FILE" \
  "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach
for _ in $(seq 1 60); do
  [ -f "$STATE_FILE" ] && [ "$(decode_state AGENTSTUDIO_OBSERVABILITY_STATUS)" = running ] && break
  /bin/sleep 1
done
[ "$(decode_state AGENTSTUDIO_OBSERVABILITY_STATUS)" = running ] || { echo "debug app did not start" >&2; exit 1; }
[ "$(decode_state AGENTSTUDIO_OBSERVABILITY_IPC_AUTH_MODE)" = authenticated ] || { echo "authenticated IPC required" >&2; exit 1; }
[ "$(decode_state AGENTSTUDIO_OBSERVABILITY_MARKER)" = "$TRACE_MARKER" ] || { echo "debug app marker mismatch" >&2; exit 1; }
APP_PID="$(decode_state AGENTSTUDIO_OBSERVABILITY_PID)"
case "$APP_PID" in
  ''|*[!0-9]*) echo "debug app state missing numeric PID" >&2; exit 1 ;;
esac
DATA_DIR="$(decode_state AGENTSTUDIO_OBSERVABILITY_DATA_DIR)"
IPC_RUNTIME_FILE="$DATA_DIR/ipc/runtime.json"
IPC_DEBUG_TOKEN_FILE="$DATA_DIR/ipc/debug-token"
IPC_READINESS_ATTEMPTS=80
METRIC_EXPORT_ATTEMPTS=45
ipc_readiness_attempt=0
while [ "$ipc_readiness_attempt" -lt "$IPC_READINESS_ATTEMPTS" ]; do
  if [ -s "$IPC_DEBUG_TOKEN_FILE" ] \
    && ipc_runtime_matches_app_pid "$IPC_RUNTIME_FILE" "$APP_PID"
  then
    break
  fi
  ipc_readiness_attempt=$((ipc_readiness_attempt + 1))
  /bin/sleep 0.25
done
if [ ! -s "$IPC_DEBUG_TOKEN_FILE" ] \
  || ! ipc_runtime_matches_app_pid "$IPC_RUNTIME_FILE" "$APP_PID"
then
  echo "authenticated IPC for the launched PID did not become ready before timeout" >&2
  exit 1
fi

/usr/bin/python3 - "$IPC_RUNTIME_FILE" "$IPC_DEBUG_TOKEN_FILE" "$LOGS_QUERY_URL" "$TRACE_MARKER" <<'PY'
import datetime, json, socket, sys, time, urllib.parse, urllib.request
with open(sys.argv[1], encoding="utf-8") as stream: socket_path = json.load(stream)["socketPath"]
with open(sys.argv[2], encoding="utf-8") as stream: token = stream.read().strip()
logs_url, marker = sys.argv[3:5]
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); sock.settimeout(20); sock.connect(socket_path)
reader = sock.makefile("rb"); request_id = 0
def request(method, params):
    global request_id
    request_id += 1
    sock.sendall((json.dumps({"jsonrpc":"2.0","id":request_id,"method":method,"params":params}, separators=(",",":"))+"\n").encode())
    while True:
        line = reader.readline()
        if not line: raise RuntimeError(f"socket closed during {method}")
        response = json.loads(line)
        if response.get("id") == request_id:
            if response.get("error") is not None: raise RuntimeError(f"{method}: {response['error']}")
            return response.get("result", {})
def marker_records():
    query = f'agent.proof.marker:="{marker}"'
    url = logs_url + "?" + urllib.parse.urlencode({"query": query})
    with urllib.request.urlopen(url, timeout=10) as response:
        lines = response.read().decode().splitlines()
    records = []
    for line in lines:
        if not line.strip(): continue
        decoded = json.loads(line)
        records.extend(decoded if isinstance(decoded, list) else [decoded])
    return records
def numeric(record, key):
    try: return int(float(record.get(key, 0)))
    except (TypeError, ValueError): return 0
def snapshot():
    records = marker_records()
    repo = [record for record in records if record.get("_msg") == "performance.repo_explorer.command_presentation"]
    tab = [record for record in records if record.get("_msg") == "performance.tabbar.refresh"]
    atom_mutations = [record for record in records if record.get("_msg") == "performance.atom.mutation"]
    canonical = [record for record in atom_mutations if record.get("agentstudio.performance.atom.label") == "pane_graph_canonical"]
    structural = [record for record in atom_mutations if record.get("agentstudio.performance.atom.label") == "pane_graph_structural"]
    return {
        "repo_events": len(repo),
        "repo_affected": sum(numeric(record, "agentstudio.performance.repo_explorer.affected_item.count") for record in repo),
        "repo_resolutions": sum(numeric(record, "agentstudio.performance.repo_explorer.command_resolution.count") for record in repo),
        "repo_capability_snapshots": sum(numeric(record, "agentstudio.performance.repo_explorer.capability_snapshot.count") for record in repo),
        "repo_projection": sum(1 for record in records if record.get("_msg") == "performance.sidebar.projection" and record.get("agentstudio.performance.sidebar.surface") == "repo"),
        "tab_affected": sum(numeric(record, "agentstudio.performance.tabbar.affected_item.count") for record in tab),
        "canonical_accepted": sum(numeric(record, "agentstudio.performance.atom.accepted_change.count") for record in canonical),
        "structural_accepted": sum(numeric(record, "agentstudio.performance.atom.accepted_change.count") for record in structural),
        "membership_accepted": sum(numeric(record, "agentstudio.performance.atom.accepted_change.count") for record in structural if record.get("agentstudio.performance.atom.operation") in ("set", "remove")),
    }
def delta(before, after):
    return {key: after[key] - before[key] for key in before}
def wait_for_delta(before, predicate, description, timeout=20):
    deadline = time.monotonic() + timeout
    latest = delta(before, snapshot())
    while time.monotonic() < deadline:
        if predicate(latest): return latest
        time.sleep(0.25)
        latest = delta(before, snapshot())
    raise RuntimeError(f"timed out waiting for {description}: {latest}")
def quiescent_snapshot(timeout=10):
    deadline = time.monotonic() + timeout
    previous = snapshot()
    stable_samples = 0
    while time.monotonic() < deadline:
        time.sleep(0.25)
        current = snapshot()
        if current == previous:
            stable_samples += 1
            if stable_samples == 4: return current
        else:
            stable_samples = 0
        previous = current
    raise RuntimeError(f"performance records did not quiesce: {previous}")
def wait_for_terminal_pane(timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        panes = request("pane.list", {}).get("panes", [])
        pane = next((item for item in panes if item.get("contentKind") == "terminal"), None)
        if pane is not None: return pane
        time.sleep(0.25)
    raise RuntimeError("timed out waiting for sidebar-performance-proof terminal")
def wait_for_startup_diagnostic_completion(timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        records = marker_records()
        if any(record.get("_msg") == "app.startup_diagnostic_action.completed" for record in records):
            return
        if any(record.get("_msg") == "app.startup_diagnostic_action.blocked" for record in records):
            raise RuntimeError("startup diagnostic reported blocked")
        time.sleep(0.25)
    raise RuntimeError("timed out waiting for startup diagnostic completion")
def record_time_ns(record):
    timestamp = str(record.get("_time", "")).replace("Z", "+00:00")
    parsed = datetime.datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%S.%f%z")
    return int(parsed.timestamp() * 1_000_000_000)
request("auth.login", {"token":token})
request("command.execute", {"commandId":"showWorktreeSidebar","targetHandle":None,"arguments":{}})
pane = wait_for_terminal_pane()
wait_for_startup_diagnostic_completion()
handle = f"pane:{pane['id']}"
repo_sort_baseline_result = request(
    "command.execute",
    {
        "commandId":"setRepoSidebarSortOrder",
        "targetHandle":None,
        "arguments":{"order":"ascending"},
    },
)
if repo_sort_baseline_result.get("applied") is not True:
    raise RuntimeError(f"repo sort baseline did not apply: {repo_sort_baseline_result}")
title_baseline = quiescent_snapshot()
private_title = "cadence-private-title"
private_payload = "printf-private-payload"
ordinary_command = (
    "printf '\\033]0;cadence-private-title\\007'; "
    "i=0; while [ \"$i\" -lt 256 ]; do printf 'printf-private-payload-%03d\\n' \"$i\"; "
    "i=$((i+1)); done; sleep 2\n"
)
title_interval_start_ns = time.time_ns()
request("terminal.send", {"handle":handle,"input":ordinary_command})
request("terminal.wait", {"handle":handle,"condition":"titleChanged","timeoutSeconds":5})
title_interval_end_ns = time.time_ns()
request("terminal.wait", {"handle":handle,"condition":"commandFinished","timeoutSeconds":5})
title_delta = wait_for_delta(title_baseline, lambda value: value["canonical_accepted"] >= 1 and value["tab_affected"] >= 1, "title publication telemetry")
title_after = quiescent_snapshot()
title_delta = delta(title_baseline, title_after)
if title_delta["canonical_accepted"] != 1:
    raise RuntimeError(f"title phase expected one canonical mutation: {title_delta}")
if title_delta["structural_accepted"] != 0:
    raise RuntimeError(f"title phase accepted structural mutation: {title_delta}")
if any(title_delta[key] != 0 for key in ("repo_events", "repo_affected", "repo_resolutions", "repo_capability_snapshots", "repo_projection")):
    raise RuntimeError(f"title phase performed Repo work: {title_delta}")
if title_delta["tab_affected"] != 1:
    raise RuntimeError(f"title phase must affect exactly the owning tab: {title_delta}")
immediate_records = [
    record for record in marker_records()
    if record.get("_msg") == "performance.terminal.accumulator_drain"
    and record.get("agentstudio.performance.terminal.accumulator.drain.class") == "immediate"
]
if not any(title_interval_start_ns <= record_time_ns(record) <= title_interval_end_ns for record in immediate_records):
    raise RuntimeError("immediate drain did not occur inside the pending-title interval")
request("terminal.send", {"handle":handle,"input":"printf '\\033]0;Cadence Barrier\\007\\033]7;file://localhost/tmp\\007'\n"})
request("terminal.wait", {"handle":handle,"condition":"commandFinished","timeoutSeconds":5})
pane_structural_baseline = quiescent_snapshot()
before = {item["id"] for item in request("pane.list", {}).get("panes", [])}
request("pane.split", {"handle":handle,"direction":"right","correlationId":None})
after = request("pane.list", {}).get("panes", [])
created = next((item for item in after if item["id"] not in before), None)
if created is None: raise RuntimeError("pane.split did not create a pane")
created_handle = f"pane:{created['id']}"
request("pane.snapshot", {"handle":created_handle})
request("pane.close", {"handle":created_handle,"correlationId":None})
if created["id"] in {item["id"] for item in request("pane.list", {}).get("panes", [])}:
    raise RuntimeError("pane.close readback retained the created pane")
pane_structural_delta = wait_for_delta(
    pane_structural_baseline,
    lambda value: value["canonical_accepted"] >= 2 and value["structural_accepted"] >= 2,
    "pane structural telemetry",
)
pane_structural_after = quiescent_snapshot()
pane_structural_delta = delta(pane_structural_baseline, pane_structural_after)
if not 1 <= pane_structural_delta["canonical_accepted"] <= 8:
    raise RuntimeError(f"pane structural canonical work was not bounded: {pane_structural_delta}")
if not 1 <= pane_structural_delta["structural_accepted"] <= 8:
    raise RuntimeError(f"pane structural projection work was not bounded: {pane_structural_delta}")
if not 1 <= pane_structural_delta["membership_accepted"] <= 8:
    raise RuntimeError(f"pane membership work was not bounded: {pane_structural_delta}")
capability_baseline = quiescent_snapshot()
capability_result = request(
    "command.execute",
    {
        "commandId":"setRepoSidebarSortOrder",
        "targetHandle":None,
        "arguments":{"order":"descending"},
    },
)
if capability_result.get("applied") is not True:
    raise RuntimeError(f"repo sort change did not apply: {capability_result}")
capability_delta = wait_for_delta(capability_baseline, lambda value: value["repo_events"] >= 1, "capability presentation telemetry")
capability_after = quiescent_snapshot()
capability_delta = delta(capability_baseline, capability_after)
if capability_delta["repo_events"] != 1 or capability_delta["repo_affected"] <= 0:
    raise RuntimeError(f"capability phase expected one affected Repo command batch: {capability_delta}")
if not 1 <= capability_delta["repo_resolutions"] <= 64:
    raise RuntimeError(f"capability command resolutions were not bounded: {capability_delta}")
if capability_delta["repo_capability_snapshots"] != 1:
    raise RuntimeError(f"capability phase expected one coherent snapshot: {capability_delta}")
if capability_delta["tab_affected"] != 0:
    raise RuntimeError(f"capability phase affected unrelated tab items: {capability_delta}")
rendered_marker_records = json.dumps(marker_records(), sort_keys=True)
if private_title in rendered_marker_records or private_payload in rendered_marker_records:
    raise RuntimeError("sensitive title or payload survived marker-scoped OTLP projection")
reader.close(); sock.close()
PY

marker='agent.proof.marker="'"$TRACE_MARKER"'"'
drain_event='event="performance.terminal.accumulator_drain"'
deadline_query='agentstudio_performance_event_elapsed_ms_max{'"$marker"','"$drain_event"',drain_class="title_deadline"}'
immediate_query='agentstudio_performance_events_total{'"$marker"','"$drain_event"',drain_class="immediate"}'
barrier_query='agentstudio_performance_events_total{'"$marker"','"$drain_event"',drain_class="exact_barrier"}'
for _ in $(seq 1 "$METRIC_EXPORT_ATTEMPTS"); do
  deadline_ms="$(query_value "$deadline_query")"
  immediate_count="$(query_value "$immediate_query")"
  barrier_count="$(query_value "$barrier_query")"
  [ "$deadline_ms" != 0 ] && [ "$immediate_count" != 0 ] && [ "$barrier_count" != 0 ] && break
  /bin/sleep 2
done
/usr/bin/python3 - "$deadline_ms" "$immediate_count" "$barrier_count" <<'PY'
import sys
deadline, immediate, barrier = map(float, sys.argv[1:])
if not 0 < deadline <= 1000: raise SystemExit(f"title_deadline outside bound: {deadline}")
if immediate < 1: raise SystemExit("missing immediate drain")
if barrier < 1: raise SystemExit("missing exact_barrier drain")
PY
echo "title and pane performance proof ok: marker=$TRACE_MARKER"
