#!/usr/bin/env bash
# Picks an available .build-agent-N (or .build-release-agent-N) slot in 1..4
# and exports SWIFT_BUILD_DIR. Slot ownership is an atomic `mkdir <dir>/.slot-claim`
# (POSIX guarantees mkdir is atomic), released by an EXIT trap on the calling
# shell. SwiftPM's own kernel-level flock handles within-slot serialization.
#
# Failure modes:
#   - Normal exit / Ctrl-C / SIGTERM: trap fires, .slot-claim removed.
#   - SIGKILL on the calling shell: trap doesn't fire, .slot-claim leaks.
#     Recover with `mise run clean-agent-builds`, which removes claim dirs
#     under any .build-agent-* whose `lsof +D` shows no open file descriptors.
#
# Caller should source this with the build kind:
#   source scripts/swift-build-slot.sh debug
#   source scripts/swift-build-slot.sh release

_swift_build_slot_kind="${1:-debug}"
case "$_swift_build_slot_kind" in
  debug)   _swift_build_slot_prefix=".build-agent" ;;
  release) _swift_build_slot_prefix=".build-release-agent" ;;
  *) echo "swift-build-slot: unknown kind '$_swift_build_slot_kind'" >&2; return 1 2>/dev/null || exit 1 ;;
esac

# Honor a caller-provided SWIFT_BUILD_DIR (CI sets this; users can pin a slot).
if [ -n "${SWIFT_BUILD_DIR:-}" ]; then
  echo "[swift-build-slot] honoring SWIFT_BUILD_DIR=$SWIFT_BUILD_DIR"
  unset _swift_build_slot_kind _swift_build_slot_prefix
  return 0 2>/dev/null || exit 0
fi

for _swift_build_slot_n in 1 2 3 4; do
  _swift_build_slot_dir="${_swift_build_slot_prefix}-${_swift_build_slot_n}"
  mkdir -p "$_swift_build_slot_dir"
  if mkdir "$_swift_build_slot_dir/.slot-claim" 2>/dev/null; then
    trap "rm -rf '$_swift_build_slot_dir/.slot-claim'" EXIT
    export SWIFT_BUILD_DIR="$_swift_build_slot_dir"
    break
  fi
done

if [ -z "${SWIFT_BUILD_DIR:-}" ]; then
  echo "swift-build-slot: all 4 ${_swift_build_slot_kind} slots are busy" >&2
  echo "swift-build-slot: if this looks wrong, run 'mise run clean-agent-builds' to reap stale claims" >&2
  return 1 2>/dev/null || exit 1
fi
echo "[swift-build-slot] using $SWIFT_BUILD_DIR"

unset _swift_build_slot_kind _swift_build_slot_prefix _swift_build_slot_n _swift_build_slot_dir
