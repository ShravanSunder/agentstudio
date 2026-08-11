#!/bin/bash
set -euo pipefail

LOGS_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
METRICS_URL="${AI_TOOLS_OBSERVABILITY_METRICS_QUERY_URL:-http://127.0.0.1:8428/api/v1/query}"
CANDIDATE=""
BASELINE=""
CHANNEL="stable"
LANE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --candidate) CANDIDATE="${2:?missing candidate selector}"; shift 2 ;;
    --baseline) BASELINE="${2:?missing baseline selector}"; shift 2 ;;
    --channel) CHANNEL="${2:?missing channel}"; shift 2 ;;
    --lane) LANE="${2:?missing lane}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

export AGENTSTUDIO_PERF_REPORT_LOGS_URL="$LOGS_URL"
export AGENTSTUDIO_PERF_REPORT_METRICS_URL="$METRICS_URL"
export AGENTSTUDIO_PERF_REPORT_CANDIDATE="$CANDIDATE"
export AGENTSTUDIO_PERF_REPORT_BASELINE="$BASELINE"
export AGENTSTUDIO_PERF_REPORT_CHANNEL="$CHANNEL"
export AGENTSTUDIO_PERF_REPORT_LANE="$LANE"

/usr/bin/python3 <<'PY'
import datetime
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

# Reviewed completion resolver; unknown runner families are in-flight.
COMPLETION_RESOLVERS = {
    "command-bar-repo-filter": "app.startup_diagnostic_action.completed",
    "sidebar-performance-proof": "app.startup_diagnostic_action.completed",
}

logs_url = os.environ["AGENTSTUDIO_PERF_REPORT_LOGS_URL"]
metrics_url = os.environ["AGENTSTUDIO_PERF_REPORT_METRICS_URL"]
channel = os.environ["AGENTSTUDIO_PERF_REPORT_CHANNEL"]
candidate_selector = os.environ["AGENTSTUDIO_PERF_REPORT_CANDIDATE"]
baseline_selector = os.environ["AGENTSTUDIO_PERF_REPORT_BASELINE"]
lane_filter = os.environ["AGENTSTUDIO_PERF_REPORT_LANE"]

def fetch(url, parameters):
    request_url = url + "?" + urllib.parse.urlencode(parameters)
    try:
        with urllib.request.urlopen(request_url, timeout=5) as response:
            return response.read().decode("utf-8")
    except (OSError, urllib.error.URLError) as error:
        print(f"stack endpoint unreachable: {url}: {error}", file=sys.stderr)
        sys.exit(3)

def parse_logs(raw):
    raw = raw.strip()
    if not raw:
        return []
    try:
        decoded = json.loads(raw)
        return decoded if isinstance(decoded, list) else decoded.get("data", decoded.get("records", []))
    except json.JSONDecodeError:
        return [json.loads(line) for line in raw.splitlines() if line.strip()]

logs_fixture = os.environ.get("AGENTSTUDIO_PERF_REPORT_LOGS_RESPONSE")
if logs_fixture is None:
    logs_fixture = fetch(
        logs_url,
        {"query": f'dev.release.channel:="{channel}" | limit 10000'},
    )
records = parse_logs(logs_fixture)

def record_value(record, key):
    return str(record.get(key, ""))

def selector_matches(record, selector):
    return selector in {
        record_value(record, "agent.proof.marker"),
        record_value(record, "service.version"),
        record_value(record, "dev.version"),
    }

completed = []
for record in records:
    if record_value(record, "dev.release.channel") != channel:
        continue
    family = record_value(record, "agentstudio.startup_diagnostic.action")
    expected_message = COMPLETION_RESOLVERS.get(family)
    marker = record_value(record, "agent.proof.marker")
    if expected_message and marker and record_value(record, "_msg") == expected_message:
        completed.append(record)
completed.sort(key=lambda record: record_value(record, "_time"))

def select_named(selector):
    matches = [record for record in completed if selector_matches(record, selector)]
    return matches[-1] if matches else None

candidate = select_named(candidate_selector) if candidate_selector else (completed[-1] if completed else None)
if candidate is None:
    print(f"candidate selection failed: {candidate_selector or '<latest completed>'}", file=sys.stderr)
    sys.exit(4)

if baseline_selector:
    baseline = select_named(baseline_selector)
else:
    candidate_index = completed.index(candidate)
    baseline = completed[candidate_index - 1] if candidate_index > 0 else None
if baseline is None:
    print(f"baseline selection failed: {baseline_selector or '<preceding completed>'}", file=sys.stderr)
    sys.exit(5)

candidate_marker = record_value(candidate, "agent.proof.marker")
baseline_marker = record_value(baseline, "agent.proof.marker")

metrics_fixture = os.environ.get("AGENTSTUDIO_PERF_REPORT_METRICS_RESPONSE")
def query_metrics(marker):
    if metrics_fixture is not None:
        return json.loads(metrics_fixture).get(marker, [])
    selector = f'agent.proof.marker="{marker}"'
    query = (
        "histogram_quantile(0.95, sum by (le,event) "
        f"(increase(agentstudio_performance_event_elapsed_ms_bucket{{{selector}}}[24h])))"
    )
    raw = fetch(metrics_url, {"query": query})
    decoded = json.loads(raw)
    rows = []
    for result in decoded.get("data", {}).get("result", []):
        event = result.get("metric", {}).get("event", "unknown")
        value = float(result.get("value", [0, 0])[1])
        rows.append({"lane": event, "p95": value, "waste_ratio": None})
    return rows

baseline_rows = {row["lane"]: row for row in query_metrics(baseline_marker)}
candidate_rows = {row["lane"]: row for row in query_metrics(candidate_marker)}
lanes = sorted(set(baseline_rows) | set(candidate_rows))
if lane_filter:
    lanes = [lane for lane in lanes if lane == lane_filter]

print("AgentStudio performance report")
print(f"channel: {channel}")
print(f"candidate: {candidate_marker}")
print(f"baseline: {baseline_marker}")
print("lane ranking (candidate p95 descending)")
ranked = sorted(lanes, key=lambda lane: candidate_rows.get(lane, {}).get("p95", -1), reverse=True)
for lane in ranked:
    before = baseline_rows.get(lane)
    after = candidate_rows.get(lane)
    if before is None or after is None:
        print(f"- {lane}: absent ({'baseline' if before is None else 'candidate'})")
        continue
    delta = after["p95"] - before["p95"]
    waste = after.get("waste_ratio")
    waste_text = "absent" if waste is None else f"{waste:.3f}"
    print(f"- {lane}: p95={after['p95']:.3f} ms; waste ratio={waste_text}; delta={delta:+.3f} ms")
if not ranked:
    print("- all lanes: absent")
PY
