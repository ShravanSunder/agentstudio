#!/bin/bash
set -e

# Populates build-artifact resources needed for development (swift build) without
# requiring a full Zig build of Ghostty. Safe to re-run at any time.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_DIR="$PROJECT_ROOT/vendor/ghostty"

# --- Shell Integration ---
# Ghostty's shell integration scripts (zsh, bash, fish, etc.) are needed at
# Sources/AgentStudio/Resources/ghostty/shell-integration/ for SPM resource
# bundling. The full build (build-ghostty.sh) copies from zig-out; this script
# copies directly from the vendor source tree as a lightweight alternative.

SHELL_INTEGRATION_SRC="$GHOSTTY_DIR/src/shell-integration"
SHELL_INTEGRATION_DEV="$PROJECT_ROOT/Sources/AgentStudio/Resources/ghostty/shell-integration"

if [ ! -d "$SHELL_INTEGRATION_SRC" ]; then
    echo "❌ Error: vendor/ghostty/src/shell-integration/ not found."
    echo "Did you initialize the ghostty submodule? Run: git submodule update --init"
    exit 1
fi

echo "📋 Copying shell-integration from vendor source..."
mkdir -p "$(dirname "$SHELL_INTEGRATION_DEV")"
rm -rf "$SHELL_INTEGRATION_DEV"
cp -R "$SHELL_INTEGRATION_SRC" "$SHELL_INTEGRATION_DEV"
echo "✅ shell-integration → $SHELL_INTEGRATION_DEV"
