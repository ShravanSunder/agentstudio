#!/usr/bin/env bash
set -euo pipefail

CORE_DIR="${1:-Sources/AgentStudio/Core}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "$CORE_DIR" = /* ]]; then
  TARGET_DIR="$CORE_DIR"
else
  TARGET_DIR="${REPO_ROOT}/${CORE_DIR}"
fi

if [ ! -d "$TARGET_DIR" ]; then
  echo "Core boundary check skipped: directory not found: $TARGET_DIR"
  exit 0
fi

VIOLATIONS=$(rg -n --no-heading --color=never -g "*.swift" '^[[:space:]]*import[[:space:]]+Features\b|^[[:space:]]*import[[:space:]]+[A-Za-z0-9_]*[.]Features\b' "$TARGET_DIR" || true)

if [ -n "$VIOLATIONS" ]; then
  echo "Architecture violation: Core cannot import Features."
  echo "$VIOLATIONS"
  exit 1
fi

echo "Core boundary import check passed (no Features imports in Sources/AgentStudio/Core)."
