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
elif [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]]; then
  VERSION="$TAG"
  MARKETING_VERSION="${TAG#v}"
  CHANNEL="beta"
  IS_PRERELEASE="true"
  CASK_TOKEN="agent-studio@beta"
  CASK_FILE="Casks/agent-studio@beta.rb"
  DATA_DIR_NAME=".agent-studio-b"
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
EOF
