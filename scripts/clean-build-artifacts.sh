#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
source "$PROJECT_ROOT/scripts/swift-build-pool-lock.sh"
acquire_swift_build_pool_lock
trap release_swift_build_pool_lock EXIT

# Hold the allocation lock through deletion, so a new builder cannot race the check.
for claim in .build-agent-1/.slot-claim .build-agent-2/.slot-claim; do
  if [ -d "$claim" ]; then
    echo "clean-artifacts: refusing to remove claimed artifacts: $claim" >&2
    exit 1
  fi
done
command -v lsof >/dev/null 2>&1 || { echo "clean-artifacts: lsof is required" >&2; exit 1; }
shopt -s nullglob
# Published artifacts have consumers between commands; generic scratch cleanup
# must not delete the prepared Bridge server or published app bundles.
artifacts=(.build .build-agent-* .build-ci)
for slot_number in 1 2; do
  exec 6>".swift-build-slot-$slot_number.lock"
  if ! /usr/bin/lockf -s -t 0 6; then
    echo "clean-artifacts: refusing to remove a slot with surviving descendants" >&2
    exit 1
  fi
  exec 6>&-
done
for artifact in "${artifacts[@]}"; do
  [ -d "$artifact" ] || continue
  if ! swift_build_directory_is_idle "$artifact"; then
    echo "clean-artifacts: refusing to remove open or unverified artifacts: $artifact" >&2
    exit 1
  fi
done
rm -rf -- "${artifacts[@]}"
echo "Cleaned Swift build directories in $PROJECT_ROOT"
