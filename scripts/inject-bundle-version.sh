#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH="${1:?usage: inject-bundle-version.sh <plist> <marketing-version> <build-version> [stable|beta]}"
MARKETING_VERSION="${2:?missing marketing version}"
BUILD_VERSION="${3:?missing build version}"
RELEASE_CHANNEL="${4:-stable}"

set_plist_string() {
  local key="${1:?missing plist key}"
  local value="${2:?missing plist value}"

  if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST_PATH" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST_PATH"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST_PATH"
  fi
}

case "$RELEASE_CHANNEL" in
  stable)
    BUNDLE_IDENTIFIER="com.agentstudio.app"
    BUNDLE_NAME="AgentStudio"
    BUNDLE_DISPLAY_NAME="Agent Studio"
    ;;
  beta)
    BUNDLE_IDENTIFIER="com.agentstudio.app.beta"
    BUNDLE_NAME="AgentStudio Beta"
    BUNDLE_DISPLAY_NAME="Agent Studio Beta"
    ;;
  *)
    echo "unsupported release channel: $RELEASE_CHANNEL" >&2
    exit 1
    ;;
esac

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION}" "$PLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_VERSION}" "$PLIST_PATH"
set_plist_string AgentStudioReleaseChannel "$RELEASE_CHANNEL"
set_plist_string CFBundleIdentifier "$BUNDLE_IDENTIFIER"
set_plist_string CFBundleName "$BUNDLE_NAME"
set_plist_string CFBundleDisplayName "$BUNDLE_DISPLAY_NAME"
