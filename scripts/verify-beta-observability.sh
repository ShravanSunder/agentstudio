#!/usr/bin/env bash
set -euo pipefail

LOGS_QUERY_URL="${SHRAVAN_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/beta-observability/latest-observability.env}"

state_marker=""
state_service_version=""
state_query_start=""
if [ -f "$STATE_FILE" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      AGENTSTUDIO_OBSERVABILITY_MARKER)
        state_marker="$value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_SERVICE_VERSION)
        state_service_version="$value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_QUERY_START)
        state_query_start="$value"
        ;;
    esac
  done <"$STATE_FILE"
fi

MARKER="${AGENTSTUDIO_OBSERVABILITY_MARKER:-$state_marker}"
SERVICE_VERSION="${AGENTSTUDIO_OBSERVABILITY_SERVICE_VERSION:-$state_service_version}"

if [ -z "$MARKER" ]; then
  echo "missing AgentStudio observability marker; run mise run run-beta-observability first" >&2
  exit 1
fi

portable_utc_time() {
  local macos_offset="$1"
  local gnu_offset="$2"
  date -u -v"${macos_offset}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null ||
    date -u -d "$gnu_offset" +"%Y-%m-%dT%H:%M:%SZ"
}

QUERY_START="${AGENTSTUDIO_OBSERVABILITY_QUERY_START:-${state_query_start:-$(portable_utc_time -4H '4 hours ago')}}"
QUERY_END="${AGENTSTUDIO_OBSERVABILITY_QUERY_END:-$(portable_utc_time +5M '5 minutes')}"

query="{service.name=\"AgentStudio\",dev.release.channel=\"beta\",agentstudio.trace.name=\"${MARKER}\"}"

query_logs() {
  local logsql="$1"
  curl --fail --silent --show-error --get \
    --data-urlencode "query=$logsql" \
    --data-urlencode "start=$QUERY_START" \
    --data-urlencode "end=$QUERY_END" \
    "$LOGS_QUERY_URL"
}

positive_response="$(query_logs "$query | fields service.name,service.version,dev.release.channel,dev.runtime.flavor,_msg | limit 20")"
if [ -z "$positive_response" ]; then
  echo "no AgentStudio beta records found in VictoriaLogs for query window $QUERY_START..$QUERY_END" >&2
  exit 1
fi
if [ -n "$SERVICE_VERSION" ] && ! grep -q "\"service.version\":\"${SERVICE_VERSION}\"" <<<"$positive_response"; then
  echo "AgentStudio beta records did not include expected service.version=$SERVICE_VERSION" >&2
  echo "$positive_response" >&2
  exit 1
fi

sensitive_fields=(
  agentstudio.session.id
  agentstudio.pane.id
  agentstudio.repo.id
  agentstudio.sqlite.database_path
  agentstudio.surface.id
  agentstudio.trace.name.raw
  agentstudio.worktree.id
  agentstudio.workspace.id
  agentstudio.zmx.session_id
  db.statement
  dev.repo.name
  error
  error.message
  exception.message
  payload
  process.pid
  secret
  token
)

for field in "${sensitive_fields[@]}"; do
  sensitive_response="$(query_logs "$query ${field}:* | limit 1")"
  if [ -n "$sensitive_response" ]; then
    echo "sensitive field survived AgentStudio OTLP export: $field" >&2
    echo "$sensitive_response" >&2
    exit 1
  fi
done

echo "beta observability ok:"
echo "$positive_response" | head -n 5
