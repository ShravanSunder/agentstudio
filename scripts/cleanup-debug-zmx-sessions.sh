#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/cleanup-debug-zmx-sessions.sh --dry-run
  scripts/cleanup-debug-zmx-sessions.sh --execute

Inventories zmx sessions under ~/.agentstudio-db/*/z. --dry-run prints the
corresponding `zmx kill` commands for review. --execute runs those commands
only for sessions found in those debug roots, then verifies the roots.

Stable production (~/.agentstudio/z), beta (~/.agent-studio-b/z), and zmx
roots outside ~/.agentstudio-db/*/z are outside this script's scope.
USAGE
}

if [[ $# -eq 1 && "$1" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 || ("$1" != "--dry-run" && "$1" != "--execute") ]]; then
  echo "expected exactly one mode: --dry-run or --execute" >&2
  usage >&2
  exit 2
fi

mode="$1"

zmx_bin="$(command -v zmx || true)"
if [[ -z "$zmx_bin" ]]; then
  echo "zmx was not found on PATH" >&2
  exit 2
fi

debug_root_base="$HOME/.agentstudio-db"
printf '=== Debug zmx cleanup (%s) ===\n' "$mode"
printf 'scope=%s/*/z\n' "$debug_root_base"
printf '%s\n' 'excluded stable: ~/.agentstudio/z'
printf '%s\n' 'excluded beta:   ~/.agent-studio-b/z'
printf '%s\n' 'excluded zmx roots: everything outside ~/.agentstudio-db/*/z'
printf 'zmx=%s\n\n' "$zmx_bin"

root_count=0
session_count=0
failed_root_count=0
kill_attempt_count=0
kill_success_count=0
kill_failure_count=0

parse_session_rows() {
  awk -F '\t' '
    {
      name = ""
      clients = ""
      start_dir = ""
      for (field = 1; field <= NF; field++) {
        value = $field
        sub(/^[[:space:]]+/, "", value)
        if (value ~ /^name=/) {
          name = value
          sub(/^name=/, "", name)
        } else if (value ~ /^clients=/) {
          clients = value
          sub(/^clients=/, "", clients)
        } else if (value ~ /^start_dir=/) {
          start_dir = value
          sub(/^start_dir=/, "", start_dir)
        }
      }
      if (name != "") {
        printf "%s\t%s\t%s\n", name, clients, start_dir
      }
    }
  '
}

for debug_root in "$debug_root_base"/*/z; do
  [[ -d "$debug_root" ]] || continue

  root_listing=""
  if ! root_listing="$(ZMX_DIR="$debug_root" "$zmx_bin" list 2>/dev/null)"; then
    printf 'root=%s status=list_failed\n' "$debug_root" >&2
    failed_root_count=$((failed_root_count + 1))
    continue
  fi

  session_rows="$(printf '%s\n' "$root_listing" | parse_session_rows)"

  [[ -n "$session_rows" ]] || continue

  root_count=$((root_count + 1))
  root_session_count=0
  printf 'root=%s\n' "$debug_root"
  while IFS=$'\t' read -r session_name clients start_dir; do
    [[ -n "$session_name" ]] || continue
    root_session_count=$((root_session_count + 1))
    session_count=$((session_count + 1))
    printf '  session=%s clients=%s start_dir=%s\n' \
      "$session_name" "${clients:-unknown}" "${start_dir:-unknown}"
    if [[ "$mode" == "--dry-run" ]]; then
      printf '    ZMX_DIR=%q zmx kill %q\n' "$debug_root" "$session_name"
    else
      kill_attempt_count=$((kill_attempt_count + 1))
      if ZMX_DIR="$debug_root" "$zmx_bin" kill "$session_name" >/dev/null 2>&1; then
        kill_success_count=$((kill_success_count + 1))
        printf '    kill_status=success\n'
      else
        kill_failure_count=$((kill_failure_count + 1))
        printf '    kill_status=failed\n' >&2
      fi
    fi
  done <<< "$session_rows"
  printf '  root_sessions=%d\n\n' "$root_session_count"
done

printf '%s\n' '=== Summary ==='
printf 'debug_roots_with_sessions=%d\n' "$root_count"
printf 'candidate_sessions=%d\n' "$session_count"
printf 'roots_with_list_errors=%d\n' "$failed_root_count"

if [[ "$mode" == "--dry-run" ]]; then
  printf '%s\n' 'No zmx kill command was executed.'
  exit 0
fi

remaining_session_count=0
verification_error_count=0
for debug_root in "$debug_root_base"/*/z; do
  [[ -d "$debug_root" ]] || continue
  verification_listing=""
  if ! verification_listing="$(ZMX_DIR="$debug_root" "$zmx_bin" list 2>/dev/null)"; then
    verification_error_count=$((verification_error_count + 1))
    printf 'verify_root=%s status=list_failed\n' "$debug_root" >&2
    continue
  fi
  verification_rows="$(printf '%s\n' "$verification_listing" | parse_session_rows)"
  if [[ -n "$verification_rows" ]]; then
    root_remaining_count="$(printf '%s\n' "$verification_rows" | awk 'NF {n++} END {print n+0}')"
    remaining_session_count=$((remaining_session_count + root_remaining_count))
    printf 'verify_root=%s remaining=%d\n' "$debug_root" "$root_remaining_count"
  fi
done

printf 'kill_attempts=%d\n' "$kill_attempt_count"
printf 'kill_successes=%d\n' "$kill_success_count"
printf 'kill_failures=%d\n' "$kill_failure_count"
printf 'remaining_sessions=%d\n' "$remaining_session_count"
printf 'verification_list_errors=%d\n' "$verification_error_count"

if [[ "$failed_root_count" -ne 0 || "$kill_failure_count" -ne 0 || \
  "$remaining_session_count" -ne 0 || "$verification_error_count" -ne 0 ]]; then
  exit 1
fi
