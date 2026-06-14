#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="$PROJECT_ROOT/scripts/agentstudio-architecture-swiftlint.env"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "missing AgentStudio architecture SwiftLint config: $CONFIG_FILE" >&2
  exit 1
fi

source "$CONFIG_FILE"

required_vars=(
  AGENTSTUDIO_ARCH_SWIFTLINT_REPO_URL
  AGENTSTUDIO_ARCH_SWIFTLINT_REF
  AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT
  AGENTSTUDIO_ARCH_SWIFTLINT_SUBDIR
)
for var_name in "${required_vars[@]}"; do
  if [ -z "${!var_name:-}" ]; then
    echo "missing required config variable: $var_name" >&2
    exit 1
  fi
done

LOCAL_AI_TOOLS_ROOT="${AGENTSTUDIO_AI_TOOLS_ROOT:-$HOME/dev/ai-tools}"
CACHE_ROOT="${AGENTSTUDIO_ARCH_SWIFTLINT_CACHE_ROOT:-$PROJECT_ROOT/tmp/tooling/ai-tools-swiftlint}"
CACHE_REPO="$CACHE_ROOT/$AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT"

has_commit() {
  local repo="$1"
  git -C "$repo" cat-file -e "$AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT^{commit}" >/dev/null 2>&1
}

is_tool_subtree_clean() {
  local repo="$1"
  git -C "$repo" diff --quiet -- "$AGENTSTUDIO_ARCH_SWIFTLINT_SUBDIR" &&
    git -C "$repo" diff --cached --quiet -- "$AGENTSTUDIO_ARCH_SWIFTLINT_SUBDIR"
}

print_identity() {
  cat <<EOF
repo_url=$AGENTSTUDIO_ARCH_SWIFTLINT_REPO_URL
ref=$AGENTSTUDIO_ARCH_SWIFTLINT_REF
commit=$AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT
subdir=$AGENTSTUDIO_ARCH_SWIFTLINT_SUBDIR
local_candidate=$LOCAL_AI_TOOLS_ROOT
cache_repo=$CACHE_REPO
EOF
}

if [ "${1:-}" = "--print-tool-identity" ]; then
  print_identity
  exit 0
fi

resolve_tool_root() {
  if [ -d "$LOCAL_AI_TOOLS_ROOT/.git" ] &&
    [ "$(git -C "$LOCAL_AI_TOOLS_ROOT" rev-parse HEAD)" = "$AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT" ] &&
    is_tool_subtree_clean "$LOCAL_AI_TOOLS_ROOT"
  then
    echo "$LOCAL_AI_TOOLS_ROOT"
    return
  fi

  mkdir -p "$CACHE_ROOT"
  if [ ! -d "$CACHE_REPO/.git" ]; then
    git clone "$AGENTSTUDIO_ARCH_SWIFTLINT_REPO_URL" "$CACHE_REPO"
  fi
  if ! has_commit "$CACHE_REPO"; then
    git -C "$CACHE_REPO" fetch --quiet origin "$AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT" ||
      git -C "$CACHE_REPO" fetch --quiet origin "$AGENTSTUDIO_ARCH_SWIFTLINT_REF"
  fi
  has_commit "$CACHE_REPO"
  git -C "$CACHE_REPO" checkout --quiet --detach "$AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT"
  if ! is_tool_subtree_clean "$CACHE_REPO"; then
    echo "cached AgentStudio architecture SwiftLint repo is dirty: $CACHE_REPO" >&2
    echo "remove the cache directory or set AGENTSTUDIO_ARCH_SWIFTLINT_CACHE_ROOT to a clean cache" >&2
    exit 1
  fi
  echo "$CACHE_REPO"
}

TOOL_ROOT="$(resolve_tool_root)"
TOOL_DIR="$TOOL_ROOT/$AGENTSTUDIO_ARCH_SWIFTLINT_SUBDIR"
BUILD_SCRIPT="$TOOL_DIR/scripts/build-agentstudio-swiftlint.sh"
VERIFY_SCRIPT="$TOOL_DIR/scripts/verify-agentstudio-swiftlint.sh"

if [ ! -x "$BUILD_SCRIPT" ]; then
  echo "missing executable custom SwiftLint build script: $BUILD_SCRIPT" >&2
  exit 1
fi

if [ "${1:-}" = "--verify-fixtures" ]; then
  if [ ! -x "$VERIFY_SCRIPT" ]; then
    echo "missing executable custom SwiftLint verifier: $VERIFY_SCRIPT" >&2
    exit 1
  fi
  "$VERIFY_SCRIPT"
  exit $?
fi

BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/agentstudio-architecture-swiftlint-build.XXXXXX")"
trap 'rm -f "$BUILD_LOG"' EXIT

echo "agentstudio architecture SwiftLint source=$TOOL_ROOT commit=$AGENTSTUDIO_ARCH_SWIFTLINT_COMMIT" >&2
"$BUILD_SCRIPT" 2>&1 | tee "$BUILD_LOG" >&2
BINARY="$(sed -n 's/^AGENTSTUDIO_SWIFTLINT_BINARY=//p' "$BUILD_LOG" | tail -n 1)"
if [ -z "$BINARY" ] || [ ! -x "$BINARY" ]; then
  echo "could not locate built AgentStudio SwiftLint binary" >&2
  exit 1
fi

exec "$BINARY" "$@"
