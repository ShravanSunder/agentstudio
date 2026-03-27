#!/usr/bin/env bash
# Shared xcbeautify pipe helper. Sourced by swift-test-helpers.sh and mise tasks.
#
# Optional variables:
#   XCB_EXTRA_ARGS - Extra xcbeautify flags (e.g. "--renderer github-actions")
#   _XCB_BYPASS    - Set to "1" to force raw output (skips xcbeautify)

set -o pipefail

_xcb_pipe() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local filter_script="${script_dir}/filter-known-linker-warnings.sh"

  if [ "${_XCB_BYPASS:-0}" = "1" ]; then
    bash "$filter_script"
    return
  fi

  if command -v xcbeautify >/dev/null 2>&1; then
    local extra_args=()
    if [ -n "${XCB_EXTRA_ARGS:-}" ]; then
      read -r -a extra_args <<<"${XCB_EXTRA_ARGS}"
    fi
    bash "$filter_script" | xcbeautify "${extra_args[@]}"
    return
  fi

  bash "$filter_script"
}

_xcb_pipe_cmd() {
  echo "_xcb_pipe"
}
