#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="${1:?usage: inject-bundle-version.sh <plist> <marketing-version> <build-version>}"
MARKETING_VERSION="${2:?missing marketing version}"
BUILD_VERSION="${3:?missing build version}"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION}" "$PLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION}" "$PLIST_PATH"
