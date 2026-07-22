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
#     under any .build-agent-* whose `lsof +D` shows no open file descriptors.
#
# Caller should source this without arguments:
#   source scripts/swift-build-slot.sh

# CI owns one fixed scratch path outside the local two-slot allocator.
if [ -n "${SWIFT_BUILD_DIR:-}" ]; then
  if { [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; } && \
    [ "$SWIFT_BUILD_DIR" = ".build-ci" ]
  then
    echo "[swift-build-slot] using CI build path $SWIFT_BUILD_DIR"
    return 0 2>/dev/null || exit 0
  fi
  echo "swift-build-slot: local SWIFT_BUILD_DIR overrides are not supported; use .build-agent-1 or .build-agent-2 through the allocator" >&2
  return 1 2>/dev/null || exit 1
fi

for _swift_build_slot_n in 1 2; do
  _swift_build_slot_dir=".build-agent-${_swift_build_slot_n}"
  mkdir -p "$_swift_build_slot_dir"
  if mkdir "$_swift_build_slot_dir/.slot-claim" 2>/dev/null; then
    trap "rm -rf '$_swift_build_slot_dir/.slot-claim'" EXIT
    export SWIFT_BUILD_DIR="$_swift_build_slot_dir"
    break
  fi
done

if [ -z "${SWIFT_BUILD_DIR:-}" ]; then
  echo "swift-build-slot: all 2 slots are busy" >&2
  echo "swift-build-slot: if this looks wrong, run 'mise run clean-agent-builds' to reap stale claims" >&2
  return 1 2>/dev/null || exit 1
fi
echo "[swift-build-slot] using $SWIFT_BUILD_DIR"

unset _swift_build_slot_n _swift_build_slot_dir
