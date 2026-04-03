#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" == "Darwin" ]]; then
  if [[ -x "/opt/homebrew/bin/zig" ]]; then
    exec /opt/homebrew/bin/zig "$@"
  fi

  if [[ -x "/usr/local/bin/zig" ]]; then
    exec /usr/local/bin/zig "$@"
  fi
fi

exec zig "$@"
