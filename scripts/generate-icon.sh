#!/usr/bin/env bash
set -euo pipefail

# Generate AppIcon.icns from the canonical SVG source.
# Requires: rsvg-convert (brew install librsvg), iconutil (macOS built-in)
#
# Usage: ./scripts/generate-icon.sh
#    or: mise run generate-icon

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SVG="$PROJECT_ROOT/Sources/AgentStudio/Resources/AppIcon.svg"
ICONSET="$PROJECT_ROOT/Sources/AgentStudio/Resources/AppIcon.iconset"
ICNS="$PROJECT_ROOT/Sources/AgentStudio/Resources/AppIcon.icns"

if ! command -v rsvg-convert &>/dev/null; then
    echo "Error: rsvg-convert not found. Install with: brew install librsvg"
    exit 1
fi

if [ ! -f "$SVG" ]; then
    echo "Error: SVG not found at $SVG"
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Standard macOS iconset sizes (base + retina pairs)
declare -a SIZES=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
)

for entry in "${SIZES[@]}"; do
    name="${entry%%:*}"
    size="${entry##*:}"
    rsvg-convert -w "$size" -h "$size" "$SVG" -o "$ICONSET/$name"
done

echo "Generated ${#SIZES[@]} PNGs in $ICONSET"

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Generated $ICNS ($(du -h "$ICNS" | cut -f1 | xargs))"
