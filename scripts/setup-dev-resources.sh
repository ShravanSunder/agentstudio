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

# --- zmx Binary ---
# zmx is the session multiplexer that provides terminal persistence.
# SessionConfiguration.findZmx() checks vendor/zmx/zig-out/bin/zmx as a
# fallback for dev builds. Build it from source so swift build picks it up.

ZMX_DIR="$PROJECT_ROOT/vendor/zmx"
ZMX_BIN="$ZMX_DIR/zig-out/bin/zmx"

if [ ! -f "$ZMX_DIR/build.zig" ]; then
    echo "⚠️  vendor/zmx/ not found — skipping zmx build"
    echo "   Session persistence will not be available in dev builds."
else
    if ! command -v zig &> /dev/null; then
        echo "⚠️  Zig not installed — skipping zmx build"
        echo "   Install Zig to enable session persistence: brew install zig"
    else
        echo "🏗️  Building zmx..."
        cd "$ZMX_DIR"
        zig build -Doptimize=ReleaseFast
        cd "$PROJECT_ROOT"
        if [ -f "$ZMX_BIN" ]; then
            echo "✅ zmx → $ZMX_BIN"
        else
            echo "⚠️  zmx build completed but binary not found at $ZMX_BIN"
        fi
    fi
fi
