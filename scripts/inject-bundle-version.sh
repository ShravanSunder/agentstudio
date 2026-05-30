#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="${1:?usage: inject-bundle-version.sh <plist> <marketing-version> <build-version>}"
MARKETING_VERSION="${2:?missing marketing version}"
BUILD_VERSION="${3:?missing build version}"
RELEASE_CHANNEL="${4:-stable}"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION}" "$PLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION}" "$PLIST_PATH"
if /usr/libexec/PlistBuddy -c "Print :AgentStudioReleaseChannel" "$PLIST_PATH" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :AgentStudioReleaseChannel ${RELEASE_CHANNEL}" "$PLIST_PATH"
else
  /usr/libexec/PlistBuddy -c "Add :AgentStudioReleaseChannel string ${RELEASE_CHANNEL}" "$PLIST_PATH"
fi
