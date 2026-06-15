#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

latest_beta_tag="$(git tag --list 'v*-beta.*' --sort=-v:refname | head -n 1)"
if [[ "$latest_beta_tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-beta\.([0-9]+)$ ]]; then
  beta_base="${BASH_REMATCH[1]}"
  beta_number="$((BASH_REMATCH[2] + 1))"
  default_marketing_version="${beta_base}-beta.${beta_number}"
else
  default_marketing_version="0.0.1-beta.local"
fi

marketing_version="${APP_MARKETING_VERSION:-$default_marketing_version}"
build_version="${APP_BUILD_VERSION:-$(git rev-list --count HEAD)}"
beta_artifact_root="${AGENTSTUDIO_BETA_ARTIFACT_ROOT:-$HOME/.agentstudio-db/beta-observability}"
artifact_dir="${AGENTSTUDIO_LOCAL_BETA_DIR:-$beta_artifact_root/$marketing_version}"
bundle_path="$artifact_dir/AgentStudio Beta.app"
signing_identity="${SIGNING_IDENTITY:--}"
signing_timestamp="${SIGNING_TIMESTAMP:-0}"

mkdir -p "$artifact_dir"
if [ -e "$bundle_path" ]; then
  artifact_dir="$beta_artifact_root/${marketing_version}-$(date +%Y%m%d%H%M%S)"
  bundle_path="$artifact_dir/AgentStudio Beta.app"
  mkdir -p "$artifact_dir"
fi

APP_MARKETING_VERSION="$marketing_version" \
APP_BUILD_VERSION="$build_version" \
APP_RELEASE_CHANNEL=beta \
SIGNING_IDENTITY="$signing_identity" \
SIGNING_TIMESTAMP="$signing_timestamp" \
  mise run create-app-bundle

/usr/bin/ditto "$PROJECT_ROOT/AgentStudio.app" "$bundle_path"

echo "local beta bundle: $bundle_path"
echo "signing identity: $signing_identity"
echo "signing timestamp: $signing_timestamp"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$bundle_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_path/Contents/Info.plist"
codesign --verify --deep --strict "$bundle_path"
