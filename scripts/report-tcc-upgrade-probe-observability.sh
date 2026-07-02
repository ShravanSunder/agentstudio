#!/bin/bash
set -euo pipefail

LOGS_QUERY_URL="${AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
CURL_BIN="${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}"
require_identity_discontinuity=false
require_access_denied=false

usage() {
  cat <<'USAGE'
Usage: report-tcc-upgrade-probe-observability.sh [--state-file <path>]
       report-tcc-upgrade-probe-observability.sh [--require-identity-discontinuity] [--require-access-denied]

Queries marker-scoped VictoriaLogs for tcc-upgrade-probe identity and access
rows. The report is read-only; it does not launch apps, replace bundles, or
change macOS privacy settings.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-file)
      STATE_FILE="${2:?missing value for --state-file}"
      shift 2
      ;;
    --require-identity-discontinuity)
      require_identity_discontinuity=true
      shift
      ;;
    --require-access-denied)
      require_access_denied=true
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

portable_utc_time() {
  local macos_offset="$1"
  local gnu_offset="$2"
  date -u -v"${macos_offset}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null ||
    date -u -d "$gnu_offset" +"%Y-%m-%dT%H:%M:%SZ"
}

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

state_marker=""
state_proof_token=""
state_query_start=""
state_runtime_flavor=""
state_startup_diagnostic_action=""
if [ -f "$STATE_FILE" ]; then
  while IFS='=' read -r key value || [ -n "$key" ]; do
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
      AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR)
        state_runtime_flavor="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION)
        state_startup_diagnostic_action="$decoded_value"
        ;;
    esac
  done <"$STATE_FILE"
fi

MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-$state_marker}"
if [ -z "$MARKER" ]; then
  echo "missing AgentStudio observability marker; pass --state-file or set AGENTSTUDIO_OBSERVABILITY_MARKER" >&2
  exit 1
fi

startup_diagnostic_action="${AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION:-$state_startup_diagnostic_action}"
if [ "$startup_diagnostic_action" != "tcc-upgrade-probe" ]; then
  echo "observability state is not for tcc-upgrade-probe: ${startup_diagnostic_action:-<missing>}" >&2
  echo "state file: $STATE_FILE" >&2
  exit 1
fi

validate_loopback_url AI_TOOLS_OBSERVABILITY_LOGS_QUERY_URL "$LOGS_QUERY_URL"

runtime_flavor="${AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR:-$state_runtime_flavor}"
stream_query="{service.name=\"AgentStudio\"}"
if [ -n "$runtime_flavor" ]; then
  stream_query="{service.name=\"AgentStudio\",dev.runtime.flavor=\"$runtime_flavor\"}"
fi
marker_query="$(logsql_exact_filter "agent.proof.marker" "$MARKER")"
query="$stream_query $marker_query"
if [ -n "$state_proof_token" ]; then
  proof_token_query="$(logsql_exact_filter "agent.proof.launch" "$state_proof_token")"
  query="$query $proof_token_query"
fi
startup_diagnostic_action_filter="$(
  logsql_exact_filter agentstudio.startup_diagnostic.action "$startup_diagnostic_action"
)"
tcc_identity_event_query="$(logsql_exact_filter "_msg" "terminal.tcc.app_identity_snapshot")"
tcc_probe_event_query="$(logsql_exact_filter "_msg" "terminal.tcc.access_probe")"
diagnostic_query="$query $startup_diagnostic_action_filter"
QUERY_START="${AGENTSTUDIO_OBSERVABILITY_QUERY_START:-${state_query_start:-$(portable_utc_time -4H '4 hours ago')}}"
QUERY_END="${AGENTSTUDIO_OBSERVABILITY_QUERY_END:-$(portable_utc_time +5M '5 minutes')}"

tcc_identity_response="$(
  query_logs \
    "$diagnostic_query $tcc_identity_event_query | fields _time,_msg,agentstudio.tcc.probe.sequence,agentstudio.tcc.bundle.kind,agentstudio.tcc.code_identity.kind,agentstudio.tcc.bundle.changed,agentstudio.tcc.bundle.executable.reachable | limit 1000"
)"
tcc_probe_response="$(
  query_logs \
    "$diagnostic_query $tcc_probe_event_query | fields _time,_msg,agentstudio.tcc.probe.sequence,agentstudio.tcc.subject,agentstudio.tcc.access.target,agentstudio.tcc.access.result,agentstudio.tcc.responsible.kind,agentstudio.tcc.command.exit_class | limit 1000"
)"

if [ -z "$tcc_identity_response" ]; then
  echo "no TCC identity snapshot rows found for marker $MARKER" >&2
  exit 1
fi
if [ -z "$tcc_probe_response" ]; then
  echo "no TCC access probe rows found for marker $MARKER" >&2
  exit 1
fi

identity_discontinuity=false
if grep -Eq '"agentstudio.tcc.code_identity.kind":"(different_disk_identity|missing)"' <<<"$tcc_identity_response" ||
  grep -Eq '"agentstudio.tcc.bundle.changed":("?true"?)([,}[:space:]]|$)' <<<"$tcc_identity_response" ||
  grep -Eq '"agentstudio.tcc.bundle.executable.reachable":("?false"?)([,}[:space:]]|$)' <<<"$tcc_identity_response"
then
  identity_discontinuity=true
fi

access_denied=false
if grep -Eq '"agentstudio.tcc.access.result":"denied_(eacces|eperm)"' <<<"$tcc_probe_response" ||
  grep -Eq '"agentstudio.tcc.command.exit_class":"permission_denied"' <<<"$tcc_probe_response"
then
  access_denied=true
fi

if [ "$require_identity_discontinuity" = true ] && [ "$identity_discontinuity" != true ]; then
  echo "TCC identity discontinuity was required but not observed for marker $MARKER" >&2
  echo "$tcc_identity_response" >&2
  exit 1
fi
if [ "$require_access_denied" = true ] && [ "$access_denied" != true ]; then
  echo "TCC access denial was required but not observed for marker $MARKER" >&2
  echo "$tcc_probe_response" >&2
  exit 1
fi

echo "tcc upgrade probe report:"
echo "marker: $MARKER"
echo "runtime flavor: ${runtime_flavor:-<any>}"
echo "query window: $QUERY_START..$QUERY_END"
echo "identity discontinuity observed: $identity_discontinuity"
echo "access denied observed: $access_denied"
echo
echo "identity rows:"
printf '%s\n' "$tcc_identity_response"
echo
echo "access rows:"
printf '%s\n' "$tcc_probe_response"
