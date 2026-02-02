#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOSTTY_DIR="$PROJECT_ROOT/vendor/ghostty"
FRAMEWORKS_DIR="$PROJECT_ROOT/Frameworks"

echo "🔨 Building Ghostty..."
echo "Project root: $PROJECT_ROOT"
echo "Ghostty source: $GHOSTTY_DIR"

# Check if Zig is installed
if ! command -v zig &> /dev/null; then
    echo "❌ Error: Zig is not installed."
    echo "Please install Zig from: https://ziglang.org/download/"
    echo "Or use Homebrew: brew install zig"
    exit 1
fi

echo "✅ Zig found: $(zig version)"

# Navigate to Ghostty directory
cd "$GHOSTTY_DIR"

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf .zig-cache zig-out macos/build

# Build Ghostty for macOS
echo "🏗️  Building Ghostty XCFramework..."
zig build -Doptimize=ReleaseFast

# Build the XCFramework
cd macos
echo "📦 Creating XCFramework..."
./build.sh

# Copy XCFramework to Frameworks directory
echo "📋 Copying XCFramework to Frameworks directory..."
mkdir -p "$FRAMEWORKS_DIR"
rm -rf "$FRAMEWORKS_DIR/GhosttyKit.xcframework"
cp -R "GhosttyKit.xcframework" "$FRAMEWORKS_DIR/"

echo "✅ Build complete!"
echo "GhosttyKit.xcframework is now available at: $FRAMEWORKS_DIR/GhosttyKit.xcframework"
echo ""
echo "You can now build your Swift package with: swift build"
