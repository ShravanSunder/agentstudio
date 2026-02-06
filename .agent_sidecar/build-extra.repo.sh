#!/bin/bash
# =============================================================================
# build-extra.repo.sh - Custom Build-Time Installations
# =============================================================================
# Runs as root at Docker build time with FULL NETWORK ACCESS.
# Use for: AppImages, binaries, tools that agent needs but can't download.
#
# This script is:
#   - Executed during `docker build` (host-controlled)
#   - Deleted after running (agent cannot access it)
#   - NOT subject to firewall restrictions
#
# Requires: --reset to rebuild when changed
# =============================================================================

set -e

# Example: Install an AppImage (architecture-aware)
# ARCH=$(dpkg --print-architecture)
# case "$ARCH" in
#     amd64) URL="https://example.com/app-amd64.AppImage" ;;
#     arm64) URL="https://example.com/app-arm64.AppImage" ;;
# esac
#
# apt-get update && apt-get install -y --no-install-recommends squashfs-tools
# curl -L "$URL" -o /tmp/app.AppImage
# cd /tmp
# OFFSET=$(LC_ALL=C grep -aobF 'hsqs' app.AppImage | head -1 | cut -d: -f1)
# tail -c +$((OFFSET + 1)) app.AppImage > app.squashfs
# unsquashfs -d /opt/myapp app.squashfs
# ln -s /opt/myapp/myapp /usr/local/bin/myapp
# rm /tmp/app.AppImage /tmp/app.squashfs
# apt-get clean && rm -rf /var/lib/apt/lists/*

echo "ℹ️  build-extra.repo.sh: No custom installations configured"
