#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/verify-notification-osc-smoke.sh <trace-file.jsonl> [--expect-bell-notified]

Verifies the JSONL trace produced by the notification OSC/BEL smoke run.
The default contract requires OSC desktop notification observation,
classification, promotion, and append records. Bell is optional because it
depends on the user's bell preference; pass --expect-bell-notified when the
smoke run enabled bell notifications.
USAGE
}

trace_file="${1:-}"
expect_bell_notified=0
if [[ "${2:-}" == "--expect-bell-notified" ]]; then
  expect_bell_notified=1
elif [[ -n "${2:-}" ]]; then
  echo "unknown option: $2" >&2
  usage
  exit 2
fi

if [[ -n "${3:-}" ]]; then
  echo "too many arguments" >&2
  usage
  exit 2
fi

if [[ -z "$trace_file" || "$trace_file" == "-h" || "$trace_file" == "--help" ]]; then
  usage
  exit 2
fi

if [[ ! -f "$trace_file" ]]; then
  echo "trace file not found: $trace_file" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to verify notification smoke traces" >&2
  exit 2
fi

require_record() {
  local description="$1"
  local filter="$2"
  if ! jq -e "$filter" "$trace_file" >/dev/null; then
    echo "missing: $description" >&2
    exit 1
  fi
  echo "ok: $description"
}

require_record \
  "Ghostty OSC desktop notification reached terminal activity tracing" \
  'select(.body == "terminal.activity.observed" and .attributes["agentstudio.runtime.event"] == "terminal.desktopNotificationRequested")'

require_record \
  "OSC desktop notification was classified as a notify decision" \
  'select(.body == "inbox.classify" and .attributes["agentstudio.runtime.event"] == "terminal.desktopNotificationRequested" and .attributes["agentstudio.inbox.decision"] == "notify")'

require_record \
  "OSC desktop notification was promoted into the inbox" \
  'select(.body == "inbox.promote" and .attributes["agentstudio.inbox.kind"] == "agentDesktopNotification" and .attributes["agentstudio.inbox.decision"] == "promote")'

require_record \
  "OSC desktop notification appended an inbox row" \
  'select(.body == "inbox.notification.appended" and .attributes["agentstudio.inbox.kind"] == "agentDesktopNotification")'

if [[ "$expect_bell_notified" == "1" ]]; then
  require_record \
    "Bell reached terminal activity tracing" \
    'select(.body == "terminal.activity.observed" and .attributes["agentstudio.runtime.event"] == "terminal.bellRang")'

  require_record \
    "Bell appended an inbox row" \
    'select(.body == "inbox.notification.appended" and .attributes["agentstudio.inbox.kind"] == "bellRang")'
fi

echo "notification OSC smoke trace verified: $trace_file"
