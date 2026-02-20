#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZMX_DIR="${ZMX_DIR:-$HOME/.agentstudio/zmx}"

find_zmx_bin() {
  local candidates=(
    "$PROJECT_ROOT/.build/debug/zmx"
    "$PROJECT_ROOT/vendor/zmx/zig-out/bin/zmx"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  if command -v zmx >/dev/null 2>&1; then
    command -v zmx
    return 0
  fi
  return 1
}

extract_session_ids() {
  awk '
    {
      id=""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^session_name=/) {
          id = $i
          sub(/^session_name=/, "", id)
          print id
          next
        }
      }
      if (NF >= 1 && $1 !~ /=/) {
        print $1
      }
    }
  ' | grep -E '^(agentstudio--|agentstudio-d--)' | sort -u
}

ZMX_BIN="$(find_zmx_bin)" || {
  echo "zmx binary not found (checked .build/debug, vendor/zig-out, PATH)." >&2
  exit 1
}

echo "Using zmx binary: $ZMX_BIN"
echo "Using ZMX_DIR: $ZMX_DIR"

mapfile -t session_ids < <(
  ZMX_DIR="$ZMX_DIR" "$ZMX_BIN" list 2>/dev/null | extract_session_ids || true
)

if [[ "${#session_ids[@]}" -eq 0 ]]; then
  echo "No AgentStudio zmx sessions found."
else
  echo "Killing AgentStudio zmx sessions (${#session_ids[@]}):"
  for id in "${session_ids[@]}"; do
    echo "  - $id"
    ZMX_DIR="$ZMX_DIR" "$ZMX_BIN" kill "$id" >/dev/null 2>&1 || true
  done
fi

# Best-effort cleanup for stale attach clients.
mapfile -t attach_pids < <(pgrep -f 'zmx.*attach.*agentstudio' || true)
if [[ "${#attach_pids[@]}" -gt 0 ]]; then
  echo "Terminating stale zmx attach clients (${#attach_pids[@]}): ${attach_pids[*]}"
  kill "${attach_pids[@]}" >/dev/null 2>&1 || true
fi

echo "Done."
