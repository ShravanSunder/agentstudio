#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"
bash "$PROJECT_ROOT/scripts/vendor-worktree.sh" verify
source "${PROJECT_ROOT}/scripts/xcb-helpers.sh"
source "${PROJECT_ROOT}/scripts/swift-build-slot.sh"
BUILD_PATH="$SWIFT_BUILD_DIR"
# The destination is shared even when two callers have different Swift slots.
exec 7>.agentstudio-app-bundle.lock
if ! /usr/bin/lockf -s -t 0 7; then
  echo "create-app-bundle: another bundle publication is in progress" >&2
  exit 1
fi
echo "[create-app-bundle] BUILD_PATH=$BUILD_PATH"
xcb_pipe=$(_xcb_pipe_cmd)
swift build -c release --build-path "$BUILD_PATH" 2>&1 | $xcb_pipe
destination_bundle="${APP_BUNDLE_PATH:-$PROJECT_ROOT/AgentStudio.app}"
mkdir -p "$(dirname "$destination_bundle")"
staging_root="$(mktemp -d "$(dirname "$destination_bundle")/.agentstudio-package.XXXXXX")"
staged_bundle="$staging_root/$(basename "$destination_bundle")"
cleanup_packaging() {
  find "$staging_root" -depth -delete
  swift_build_slot_release
}
trap cleanup_packaging EXIT
APP_DIR="$staged_bundle/Contents"
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Resources"

# Binary
cp "$BUILD_PATH/release/AgentStudio" "$APP_DIR/MacOS/"

# zmx
if [ ! -x "vendor/zmx/zig-out/bin/zmx" ] || [ -L "vendor/zmx/zig-out/bin/zmx" ]; then
  echo "create-app-bundle: verified zmx executable is missing or unsafe" >&2
  exit 1
fi
cp vendor/zmx/zig-out/bin/zmx "$APP_DIR/MacOS/"

# Info.plist + icon
cp Sources/AgentStudio/Resources/Info.plist "$APP_DIR/"
MARKETING_VERSION="${APP_MARKETING_VERSION:-0.0.1-dev}"
BUILD_VERSION="${APP_BUILD_VERSION:-$(git rev-list --count HEAD)}"
RELEASE_CHANNEL="${APP_RELEASE_CHANNEL:-stable}"
/bin/bash scripts/inject-bundle-version.sh "$APP_DIR/Info.plist" "$MARKETING_VERSION" "$BUILD_VERSION" "$RELEASE_CHANNEL"
cp Sources/AgentStudio/Resources/AppIcon.icns "$APP_DIR/Resources/"

# terminfo
TERMINFO="Sources/AgentStudio/Resources/terminfo"
[ -d "$TERMINFO" ] && cp -R "$TERMINFO" "$APP_DIR/Resources/"

# shell-integration
GHOSTTY_RES="Sources/AgentStudio/Resources/ghostty"
[ -d "$GHOSTTY_RES" ] && { mkdir -p "$APP_DIR/Resources/ghostty"; cp -R "$GHOSTTY_RES/." "$APP_DIR/Resources/ghostty/"; }

# GhosttyKit is a static library — already linked into the binary at build time.
# Do NOT embed the xcframework; it's only needed at build time for SwiftPM.

# SwiftPM resource bundle — Bundle.appResources looks in Contents/Resources/
resource_bundles=()
while IFS= read -r -d '' resource_bundle; do
  resource_bundles+=("$resource_bundle")
done < <(find "$BUILD_PATH" -path '*/release/AgentStudio_AgentStudio.bundle' -type d -print0)
if [ "${#resource_bundles[@]}" -ne 1 ]; then
  echo "create-app-bundle: expected exactly one SwiftPM resource bundle" >&2
  exit 1
fi
cp -R "${resource_bundles[0]}" "$APP_DIR/Resources/"

# Sign — uses Developer ID if SIGNING_IDENTITY is set, else ad-hoc
ENTITLEMENTS="Sources/AgentStudio/Resources/AgentStudio.entitlements"
IDENTITY="${SIGNING_IDENTITY:--}"
TIMESTAMP_ARGS=()
if [ "${SIGNING_TIMESTAMP:-1}" != "0" ]; then
  TIMESTAMP_ARGS=(--timestamp)
elif [ "$IDENTITY" != "-" ]; then
  echo "Signing timestamp disabled (SIGNING_TIMESTAMP=0)"
fi

if [ "$IDENTITY" != "-" ]; then
  echo "Signing with: $IDENTITY"
  if [ -d "$staged_bundle/Contents/Frameworks" ]; then
    find "$staged_bundle/Contents/Frameworks" -name "*.dylib" -o -name "*.framework" | while read item; do
      codesign --force --sign "$IDENTITY" "${TIMESTAMP_ARGS[@]}" --options runtime "$item"
    done
  fi
  [ -f "$staged_bundle/Contents/MacOS/zmx" ] && \
    codesign --force --sign "$IDENTITY" "${TIMESTAMP_ARGS[@]}" --options runtime --entitlements "$ENTITLEMENTS" "$staged_bundle/Contents/MacOS/zmx"
  codesign --force --sign "$IDENTITY" "${TIMESTAMP_ARGS[@]}" --options runtime --entitlements "$ENTITLEMENTS" "$staged_bundle"
else
  echo "Ad-hoc signing (set SIGNING_IDENTITY for Developer ID)"
  codesign --force --deep --sign - "$staged_bundle"
fi

codesign --verify --deep --strict "$staged_bundle"
/bin/bash "$PROJECT_ROOT/scripts/publish-app-bundle.sh" "$staged_bundle" "$destination_bundle"
echo "App bundle created and signed: $destination_bundle"
