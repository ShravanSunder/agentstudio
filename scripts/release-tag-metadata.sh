#!/usr/bin/env bash
set -euo pipefail

TAG="${1:?usage: release-tag-metadata.sh <tag>}"

if [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  VERSION="$TAG"
  MARKETING_VERSION="${TAG#v}"
  CHANNEL="stable"
  IS_PRERELEASE="false"
  CASK_TOKEN="agent-studio"
  CASK_FILE="Casks/agent-studio.rb"
  DATA_DIR_NAME=".agentstudio"
  APP_BUNDLE_NAME="AgentStudio.app"
  BUNDLE_IDENTIFIER="com.agentstudio.app"
  BUNDLE_NAME="AgentStudio"
  BUNDLE_DISPLAY_NAME="Agent Studio"
  APP_CACHE_DOMAIN="com.agentstudio.app"
elif [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]]; then
  VERSION="$TAG"
  MARKETING_VERSION="${TAG#v}"
  CHANNEL="beta"
  IS_PRERELEASE="true"
  CASK_TOKEN="agent-studio@beta"
  CASK_FILE="Casks/agent-studio@beta.rb"
  DATA_DIR_NAME=".agent-studio-b"
  APP_BUNDLE_NAME="AgentStudio Beta.app"
  BUNDLE_IDENTIFIER="com.agentstudio.app.beta"
  BUNDLE_NAME="AgentStudio Beta"
  BUNDLE_DISPLAY_NAME="Agent Studio Beta"
  APP_CACHE_DOMAIN="com.agentstudio.app.beta"
else
  echo "unsupported release tag: $TAG" >&2
  exit 1
fi

cat <<EOF
version=$VERSION
marketing_version=$MARKETING_VERSION
channel=$CHANNEL
is_prerelease=$IS_PRERELEASE
cask_token=$CASK_TOKEN
cask_file=$CASK_FILE
data_dir_name=$DATA_DIR_NAME
app_bundle_name=$APP_BUNDLE_NAME
bundle_identifier=$BUNDLE_IDENTIFIER
bundle_name=$BUNDLE_NAME
bundle_display_name=$BUNDLE_DISPLAY_NAME
app_cache_domain=$APP_CACHE_DOMAIN
EOF
