#!/usr/bin/env bash
# Descriptor 8 owns the short-lived worktree allocation/maintenance lock.
# BSD flock ownership survives lockf's exit and is released by closing the fd.
acquire_swift_build_pool_lock() {
  exec 8>.swift-build-pool.lock
  if ! /usr/bin/lockf -s -t 5 8; then
    exec 8>&-
    echo "swift-build-pool: allocation or maintenance is still in progress" >&2
    return 1
  fi
}

release_swift_build_pool_lock() {
  exec 8>&-
}

# Return success only for a complete lsof inspection with no open descriptors.
# Permission/traversal errors are not evidence that artifacts are idle.
swift_build_directory_is_idle() {
  local inspection_output
  local inspection_status=0
  inspection_output="$(lsof +D "$1" 2>&1)" || inspection_status=$?
  if [ "$inspection_status" -eq 1 ] && [ -z "$inspection_output" ]; then
    return 0
  fi
  return 1
}
