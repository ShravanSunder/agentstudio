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
rm -rf .zig-cache zig-out macos/build macos/*.xcframework

# Build Ghostty XCFramework for macOS
echo "🏗️  Building Ghostty XCFramework..."
zig build -Doptimize=ReleaseFast -Demit-xcframework=true

# Copy XCFramework from macos/ to Frameworks directory
echo "📋 Copying XCFramework to Frameworks directory..."
mkdir -p "$FRAMEWORKS_DIR"
rm -rf "$FRAMEWORKS_DIR/GhosttyKit.xcframework"

if [ -d "macos/GhosttyKit.xcframework" ]; then
    cp -R "macos/GhosttyKit.xcframework" "$FRAMEWORKS_DIR/"
    echo "✅ GhosttyKit.xcframework built!"
    echo "GhosttyKit.xcframework is now available at: $FRAMEWORKS_DIR/GhosttyKit.xcframework"
else
    echo "❌ Error: XCFramework not found at macos/GhosttyKit.xcframework"
    echo "Build may have failed. Check the output above."
    exit 1
fi

# Build Swift application
echo ""
echo "🏗️  Building Swift application..."
cd "$PROJECT_ROOT"
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Swift build failed"
    exit 1
fi

# Create .app bundle
echo ""
echo "📦 Creating AgentStudio.app bundle..."
APP_DIR="$PROJECT_ROOT/AgentStudio.app/Contents"
rm -rf "$PROJECT_ROOT/AgentStudio.app"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"
mkdir -p "$APP_DIR/Frameworks"

# Copy binary
cp "$PROJECT_ROOT/.build/release/AgentStudio" "$APP_DIR/MacOS/"

# Copy Info.plist
cp "$PROJECT_ROOT/Sources/AgentStudio/Resources/Info.plist" "$APP_DIR/"

# Copy GhosttyKit framework
cp -R "$FRAMEWORKS_DIR/GhosttyKit.xcframework" "$APP_DIR/Frameworks/"

# Ad-hoc sign the app
echo "🔏 Signing app..."
codesign --force --deep --sign - "$PROJECT_ROOT/AgentStudio.app"

echo ""
echo "✅ Build complete!"
echo "App bundle: $PROJECT_ROOT/AgentStudio.app"
echo ""
echo "To run: open AgentStudio.app"
echo "For development: swift run AgentStudio"
