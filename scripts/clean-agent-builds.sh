#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/swift-build-pool-lock.sh"
acquire_swift_build_pool_lock
trap release_swift_build_pool_lock EXIT
reaped=0
for directory in .build-agent-1 .build-agent-2; do
  claim="$directory/.slot-claim"
  [ -d "$claim" ] || continue
  owner_pid="$(cat "$claim/owner-pid" 2>/dev/null || true)"
  case "$owner_pid" in
    ''|*[!0-9]*|0|1)
      echo "[clean-agent-builds] preserving unknown owner: $claim"
      continue
      ;;
  esac
  if kill -0 "$owner_pid" 2>/dev/null; then
    echo "[clean-agent-builds] preserving live owner: $claim"
    continue
  fi
  # Descriptor 6 is inherited through the build process tree. Reclamation must
  # acquire a different open-file description, so surviving children exclude it.
  exec 6>".swift-build-slot-${directory##*-}.lock"
  if ! /usr/bin/lockf -s -t 0 6; then
    exec 6>&-
    echo "[clean-agent-builds] preserving surviving build descendants: $claim"
    continue
  fi
  # Also protect non-inheriting processes with open build files.
  if ! command -v lsof >/dev/null 2>&1; then
    echo "clean-agent-builds: lsof is required to verify dead-owner claims" >&2
    exit 1
  fi
  if ! swift_build_directory_is_idle "$directory"; then
    echo "[clean-agent-builds] preserving active or unverified build files: $claim"
    exec 6>&-
    continue
  fi
  rm -f "$claim/owner-pid"
  rmdir "$claim"
  exec 6>&-
  echo "[clean-agent-builds] reaped dead owner: $claim"
  reaped=$((reaped + 1))
done
echo "[clean-agent-builds] reaped $reaped stale claim(s)"
