#!/usr/bin/env bash
set -euo pipefail

if command -v mise >/dev/null 2>&1; then
  mise_zig="$(mise which zig 2>/dev/null || true)"
  if [[ -n "$mise_zig" && -x "$mise_zig" ]]; then
    exec "$mise_zig" "$@"
  fi
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  if [[ -x "/opt/homebrew/bin/zig" ]]; then
    exec /opt/homebrew/bin/zig "$@"
  fi

  if [[ -x "/usr/local/bin/zig" ]]; then
    exec /usr/local/bin/zig "$@"
  fi
fi

exec zig "$@"
