#!/usr/bin/env bash
# Picks one of the two local Swift build slots and exports SWIFT_BUILD_DIR.
# Slot ownership is an atomic `mkdir <dir>/.slot-claim`
# (POSIX guarantees mkdir is atomic), released by an EXIT trap on the calling
# shell. SwiftPM's own kernel-level flock handles within-slot serialization.
#
# Failure modes:
#   - Normal exit / Ctrl-C / SIGTERM: trap fires, .slot-claim removed.
#   - SIGKILL on the calling shell: trap doesn't fire, .slot-claim leaks.
#     Recover with `mise run clean-agent-builds`, which removes claim dirs
#     only when the recorded owner is dead and no build files remain open.
#
# Caller should source this without arguments:
#   source scripts/swift-build-slot.sh

# CI owns one fixed scratch path outside the local two-slot allocator.
if [ -n "${SWIFT_BUILD_DIR:-}" ]; then
  if { [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; } && \
    [ "$SWIFT_BUILD_DIR" = ".build-ci" ]
  then
    swift_build_slot_release() { :; }
    echo "[swift-build-slot] using CI build path $SWIFT_BUILD_DIR"
    return 0 2>/dev/null || exit 0
  fi
  echo "swift-build-slot: local SWIFT_BUILD_DIR overrides are not supported; use .build-agent-1 or .build-agent-2 through the allocator" >&2
  return 1 2>/dev/null || exit 1
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/swift-build-pool-lock.sh"
acquire_swift_build_pool_lock || { return 1 2>/dev/null || exit 1; }
trap release_swift_build_pool_lock EXIT

swift_build_slot_release() {
  # Closing our descriptor does not release copies held by surviving children.
  exec 6>&-
  acquire_swift_build_pool_lock || return 0
  exec 6>".swift-build-slot-${SWIFT_BUILD_DIR##*-}.lock"
  if /usr/bin/lockf -s -t 0 6; then
    rm -f "$SWIFT_BUILD_DIR/.slot-claim/owner-pid"
    rmdir "$SWIFT_BUILD_DIR/.slot-claim"
  fi
  exec 6>&-
  release_swift_build_pool_lock
}

for _swift_build_slot_n in 1 2; do
  _swift_build_slot_dir=".build-agent-${_swift_build_slot_n}"
  exec 6>".swift-build-slot-${_swift_build_slot_n}.lock"
  if ! /usr/bin/lockf -s -t 0 6; then
    exec 6>&-
    continue
  fi
  mkdir -p "$_swift_build_slot_dir"
  if mkdir "$_swift_build_slot_dir/.slot-claim" 2>/dev/null; then
    printf '%s\n' "$$" > "$_swift_build_slot_dir/.slot-claim/owner-pid"
    export SWIFT_BUILD_DIR="$_swift_build_slot_dir"
    break
  fi
  exec 6>&-
done

release_swift_build_pool_lock
trap - EXIT
if [ -n "${SWIFT_BUILD_DIR:-}" ]; then
  trap swift_build_slot_release EXIT
fi

if [ -z "${SWIFT_BUILD_DIR:-}" ]; then
  echo "swift-build-slot: all 2 slots are busy" >&2
  echo "swift-build-slot: if this looks wrong, run 'mise run clean-agent-builds' to reap stale claims" >&2
  return 1 2>/dev/null || exit 1
fi
echo "[swift-build-slot] using $SWIFT_BUILD_DIR"

unset _swift_build_slot_n _swift_build_slot_dir
