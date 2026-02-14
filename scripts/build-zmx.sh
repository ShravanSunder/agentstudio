#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZMX_DIR="$PROJECT_ROOT/vendor/zmx"

echo "Building zmx..."
echo "Project root: $PROJECT_ROOT"
echo "zmx source: $ZMX_DIR"

# Check if Zig is installed
if ! command -v zig &> /dev/null; then
    echo "Error: Zig is not installed."
    echo "Please install Zig from: https://ziglang.org/download/"
    echo "Or use Homebrew: brew install zig"
    exit 1
fi

echo "Zig found: $(zig version)"

# Check if zmx source exists
if [ ! -f "$ZMX_DIR/build.zig" ]; then
    echo "Error: zmx source not found at $ZMX_DIR"
    echo "Did you initialize git submodules? Try: git submodule update --init --recursive"
    exit 1
fi

# Navigate to zmx directory
cd "$ZMX_DIR"

# Build zmx in release mode
echo "Building zmx binary..."
zig build -Doptimize=ReleaseFast

# Verify binary was produced
ZMX_BIN="$ZMX_DIR/zig-out/bin/zmx"
if [ ! -f "$ZMX_BIN" ]; then
    echo "Error: zmx binary not found at $ZMX_BIN"
    echo "Build may have failed. Check the output above."
    exit 1
fi

# Show binary size
SIZE=$(ls -lh "$ZMX_BIN" | awk '{print $5}')
echo "zmx binary built: $ZMX_BIN ($SIZE)"

# Copy to .build/debug/ if it exists (convenience for dev builds)
DEBUG_DIR="$PROJECT_ROOT/.build/debug"
if [ -d "$DEBUG_DIR" ]; then
    cp "$ZMX_BIN" "$DEBUG_DIR/zmx"
    echo "Copied zmx to $DEBUG_DIR/zmx"
fi

echo "Build complete!"
