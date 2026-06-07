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
    /usr/libexec/PlistBuddy -c "Set :$key \"$value\"" "$PLIST_PATH"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string \"$value\"" "$PLIST_PATH"
  fi
}

case "$RELEASE_CHANNEL" in
  stable)
    BUNDLE_IDENTIFIER="com.agentstudio.app"
    BUNDLE_NAME="AgentStudio"
    BUNDLE_DISPLAY_NAME="Agent Studio"
    OAUTH_CALLBACK_NAME="com.agentstudio.oauth"
    OAUTH_CALLBACK_SCHEME="agentstudio"
    ;;
  beta)
    BUNDLE_IDENTIFIER="com.agentstudio.app.beta"
    BUNDLE_NAME="AgentStudio Beta"
    BUNDLE_DISPLAY_NAME="Agent Studio Beta"
    OAUTH_CALLBACK_NAME="com.agentstudio.oauth.beta"
    OAUTH_CALLBACK_SCHEME="agentstudio-beta"
    ;;
  *)
    echo "unsupported release channel: $RELEASE_CHANNEL" >&2
    exit 1
    ;;
esac

set_plist_string CFBundleShortVersionString "$MARKETING_VERSION"
set_plist_string CFBundleVersion "$BUILD_VERSION"
set_plist_string AgentStudioReleaseChannel "$RELEASE_CHANNEL"
set_plist_string CFBundleIdentifier "$BUNDLE_IDENTIFIER"
set_plist_string CFBundleName "$BUNDLE_NAME"
set_plist_string CFBundleDisplayName "$BUNDLE_DISPLAY_NAME"
# The app has one URL type today; index 0 is the OAuth callback registration.
set_plist_string CFBundleURLTypes:0:CFBundleURLName "$OAUTH_CALLBACK_NAME"
set_plist_string CFBundleURLTypes:0:CFBundleURLSchemes:0 "$OAUTH_CALLBACK_SCHEME"
