#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/cleanup-debug-zmx-sessions.sh --dry-run
  scripts/cleanup-debug-zmx-sessions.sh --execute
  scripts/cleanup-debug-zmx-sessions.sh --inventory-exact-root <root> --zmx-bin <binary>

Inventories zmx sessions under ~/.agentstudio-db/*/z. --dry-run prints the
corresponding `zmx kill` commands for review. --execute runs those commands
only for sessions found in those debug roots, then verifies the roots.

Stable production (~/.agentstudio/z), beta (~/.agent-studio-b/z), and zmx
roots outside ~/.agentstudio-db/*/z are outside this script's scope.
USAGE
}

canonical_path() {
  /usr/bin/python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

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

if [[ $# -eq 4 && "$1" == "--inventory-exact-root" && "$3" == "--zmx-bin" ]]; then
  exact_root="$2"
  exact_zmx_bin="$4"
  canonical_home="$(canonical_path "$HOME")"
  canonical_root="$(canonical_path "$exact_root")"
  canonical_zmx_bin="$(canonical_path "$exact_zmx_bin")"
  if ! /usr/bin/python3 - "$canonical_home" "$canonical_root" <<'PY'
import os
import re
import sys

home, root = sys.argv[1:]
expected_base = os.path.join(home, ".agentstudio-db")
relative = os.path.relpath(root, expected_base)
if not re.fullmatch(r"[0-9a-z]{4}/z", relative):
    sys.exit(1)
PY
  then
    echo "exact inventory root is outside isolated debug root: $exact_root" >&2
    exit 2
  fi
  debug_data_root="${canonical_root%/z}"
  expected_zmx_bin="$debug_data_root/bin/zmx"
  if [[ ! -d "$canonical_root" || ! -x "$canonical_zmx_bin" ||
    "$canonical_zmx_bin" != "$(canonical_path "$expected_zmx_bin")" ]]; then
    echo "exact inventory zmx binary must be the isolated debug root copy: $expected_zmx_bin" >&2
    exit 2
  fi

  exact_listing=""
  if ! exact_listing="$(ZMX_DIR="$canonical_root" "$canonical_zmx_bin" list 2>/dev/null)"; then
    printf 'inventory_root=%s status=list_failed\n' "$canonical_root" >&2
    exit 1
  fi
  exact_rows="$(printf '%s\n' "$exact_listing" | parse_session_rows)"
  if [[ -n "$exact_listing" ]]; then
    listing_line_count="$(printf '%s\n' "$exact_listing" | awk 'NF { count++ } END { print count + 0 }')"
    row_count="$(printf '%s\n' "$exact_rows" | awk 'NF { count++ } END { print count + 0 }')"
    if [[ "$listing_line_count" -ne "$row_count" ]] ||
      ! printf '%s\n' "$exact_rows" | awk -F '\t' '
        NF && ($1 == "" || $2 !~ /^[0-9]+$/ || $3 == "" || seen[$1]++) { invalid = 1 }
        END { exit invalid ? 1 : 0 }
      '
    then
      printf 'inventory_root=%s status=malformed_listing\n' "$canonical_root" >&2
      exit 1
    fi
  fi

  session_count="$(printf '%s\n' "$exact_rows" | awk 'NF { count++ } END { print count + 0 }')"
  printf 'inventory_root=%s status=ok session_count=%s\n' "$canonical_root" "$session_count"
  if [[ -n "$exact_rows" ]]; then
    while IFS=$'\t' read -r session_name clients start_dir; do
      [[ -n "$session_name" ]] || continue
      printf 'session=%s clients=%s start_dir=%s\n' "$session_name" "$clients" "$start_dir"
    done <<< "$exact_rows"
  fi
  exit 0
fi

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
