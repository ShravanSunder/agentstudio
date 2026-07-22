#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${AGENTSTUDIO_BRIDGE_REVIEW_MOMENTUM_PROBE_STATE_FILE:-tmp/bridge-review-momentum-scroll-state-probe/latest.env}"

echo "momentum scroll state probe requires live debug marker"

if [ ! -f "$STATE_FILE" ]; then
  echo "BLOCKED-SANDBOX: missing live debug marker at $STATE_FILE" >&2
  exit 77
fi

# shellcheck disable=SC1090
source "$STATE_FILE"

TRUNCATED_VISIBLE_ITEM_COUNT="${AGENTSTUDIO_BRIDGE_REVIEW_TRUNCATED_VISIBLE_ITEM_COUNT:-}"
UNTRACKED_ITEM_COUNT="${AGENTSTUDIO_BRIDGE_REVIEW_UNTRACKED_ITEM_COUNT:-}"

if [ "$TRUNCATED_VISIBLE_ITEM_COUNT" != "0" ]; then
  echo "truncatedVisibleItemCount expected 0, got ${TRUNCATED_VISIBLE_ITEM_COUNT:-unset}" >&2
  exit 1
fi

if [ "$UNTRACKED_ITEM_COUNT" != "0" ]; then
  echo "untrackedItemCount expected 0, got ${UNTRACKED_ITEM_COUNT:-unset}" >&2
  exit 1
fi

echo "momentum scroll state probe passed"
