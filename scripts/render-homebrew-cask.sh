#!/usr/bin/env bash
set -euo pipefail

CHANNEL="${1:?usage: render-homebrew-cask.sh <stable|beta> <version> <sha256>}"
VERSION="${2:?missing version}"
SHA256="${3:?missing sha256}"

if [[ ! "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "sha256 must be 64 lowercase hex characters" >&2
  exit 1
fi

case "$CHANNEL" in
  stable)
    if [[ "$VERSION" == *"-"* ]]; then
      echo "stable cask version must not contain a prerelease suffix" >&2
      exit 1
    fi
    TOKEN="agent-studio"
    DATA_DIR=".agentstudio"
    CASK_NAME="Agent Studio"
    APP_BUNDLE_NAME="AgentStudio.app"
    APP_CACHE_DOMAIN="com.agentstudio.app"
    ;;
  beta)
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]]; then
      echo "beta cask version must match X.Y.Z-beta.N" >&2
      exit 1
    fi
    TOKEN="agent-studio@beta"
    DATA_DIR=".agent-studio-b"
    CASK_NAME="Agent Studio Beta"
    APP_BUNDLE_NAME="AgentStudio Beta.app"
    APP_CACHE_DOMAIN="com.agentstudio.app.beta"
    ;;
  *)
    echo "unsupported cask channel: $CHANNEL" >&2
    exit 1
    ;;
esac

printf '%s\n' \
  "cask \"$TOKEN\" do" \
  "  version \"$VERSION\"" \
  "  sha256 \"$SHA256\"" \
  "" \
  "  url \"https://github.com/ShravanSunder/agentstudio/releases/download/v#{version}/AgentStudio-v#{version}-macos.zip\"" \
  "  name \"$CASK_NAME\"" \
  '  desc "Terminal application with Ghostty terminal emulator and project management"' \
  '  homepage "https://github.com/ShravanSunder/agentstudio"' \
  "" \
  "  depends_on macos: :tahoe" \
  "" \
  "  app \"$APP_BUNDLE_NAME\"" \
  "" \
  "  zap trash: [" \
  "    \"~/$DATA_DIR\"," \
  "    \"~/Library/Caches/$APP_CACHE_DOMAIN\"," \
  "    \"~/Library/Preferences/$APP_CACHE_DOMAIN.plist\"," \
  "    \"~/Library/Saved Application State/$APP_CACHE_DOMAIN.savedState\"," \
  "  ]" \
  "end"
