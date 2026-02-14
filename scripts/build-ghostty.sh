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

TERMINFO_DEV="$PROJECT_ROOT/Sources/AgentStudio/Resources/terminfo"

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

    # Copy Ghostty terminfo for development (SPM builds).
    # IMPORTANT: Only update Ghostty-provided entries (xterm-ghostty, ghostty).
    # Do NOT delete the entire directory — it contains our custom xterm-256color
    # (git-tracked in Resources/terminfo/78/xterm-256color) with full Ghostty
    # capabilities tuned for zmx sessions.
    TERMINFO_SRC="$GHOSTTY_DIR/zig-out/share/terminfo"
    if [ -d "$TERMINFO_SRC" ]; then
        echo "📋 Copying Ghostty terminfo for development (preserving custom entries)..."
        mkdir -p "$TERMINFO_DEV/78" "$TERMINFO_DEV/67"
        # Only copy Ghostty-provided entries
        [ -f "$TERMINFO_SRC/78/xterm-ghostty" ] && cp "$TERMINFO_SRC/78/xterm-ghostty" "$TERMINFO_DEV/78/"
        [ -f "$TERMINFO_SRC/67/ghostty" ] && cp "$TERMINFO_SRC/67/ghostty" "$TERMINFO_DEV/67/"
        echo "✅ Ghostty terminfo updated (custom xterm-256color preserved)"
    else
        echo "⚠️  terminfo not found at $TERMINFO_SRC — xterm-ghostty will not be available"
    fi

    # Copy shell-integration for development (SPM builds)
    # Prefer zig-out (built artifacts); fall back to vendor source tree
    SHELL_INTEGRATION_ZIG="$GHOSTTY_DIR/zig-out/share/ghostty/shell-integration"
    SHELL_INTEGRATION_VENDOR="$GHOSTTY_DIR/src/shell-integration"
    SHELL_INTEGRATION_DEV="$PROJECT_ROOT/Sources/AgentStudio/Resources/ghostty/shell-integration"
    if [ -d "$SHELL_INTEGRATION_ZIG" ]; then
        SHELL_INTEGRATION_SRC="$SHELL_INTEGRATION_ZIG"
    elif [ -d "$SHELL_INTEGRATION_VENDOR" ]; then
        SHELL_INTEGRATION_SRC="$SHELL_INTEGRATION_VENDOR"
    else
        SHELL_INTEGRATION_SRC=""
    fi
    if [ -n "$SHELL_INTEGRATION_SRC" ]; then
        echo "📋 Copying shell-integration for development..."
        mkdir -p "$(dirname "$SHELL_INTEGRATION_DEV")"
        rm -rf "$SHELL_INTEGRATION_DEV"
        cp -R "$SHELL_INTEGRATION_SRC" "$SHELL_INTEGRATION_DEV"
        echo "✅ shell-integration copied to $SHELL_INTEGRATION_DEV"
    else
        echo "⚠️  shell-integration not found (checked zig-out and vendor source)"
    fi
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

# Copy app icon
cp "$PROJECT_ROOT/Sources/AgentStudio/Resources/AppIcon.icns" "$APP_DIR/Resources/"

# Copy terminfo to app bundle
if [ -d "$TERMINFO_DEV" ]; then
    cp -R "$TERMINFO_DEV" "$APP_DIR/Resources/"
    echo "✅ terminfo copied to app bundle"
fi

# Build and copy zmx binary to app bundle (Contents/MacOS/zmx)
ZMX_DIR="$PROJECT_ROOT/vendor/zmx"
if [ -f "$ZMX_DIR/build.zig" ]; then
    echo "🏗️  Building zmx..."
    cd "$ZMX_DIR"
    zig build -Doptimize=ReleaseFast
    ZMX_BIN="$ZMX_DIR/zig-out/bin/zmx"
    if [ -f "$ZMX_BIN" ]; then
        cp "$ZMX_BIN" "$APP_DIR/MacOS/"
        echo "✅ zmx binary copied to app bundle"
    else
        echo "⚠️  zmx binary not found at $ZMX_BIN — session persistence will use PATH fallback"
    fi
    cd "$PROJECT_ROOT"
else
    echo "⚠️  zmx source not found — session persistence will use PATH fallback"
fi

# Copy ghostty resources (shell-integration) to app bundle
GHOSTTY_RES_DEV="$PROJECT_ROOT/Sources/AgentStudio/Resources/ghostty"
if [ -d "$GHOSTTY_RES_DEV" ]; then
    mkdir -p "$APP_DIR/Resources/ghostty"
    cp -R "$GHOSTTY_RES_DEV/." "$APP_DIR/Resources/ghostty/"
    echo "✅ ghostty resources copied to app bundle"
fi

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
