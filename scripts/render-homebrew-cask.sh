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
    CONFLICT="agent-studio@beta"
    DATA_DIR=".agentstudio"
    ;;
  beta)
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]]; then
      echo "beta cask version must match X.Y.Z-beta.N" >&2
      exit 1
    fi
    TOKEN="agent-studio@beta"
    CONFLICT="agent-studio"
    DATA_DIR=".agent-studio-b"
    ;;
  *)
    echo "unsupported cask channel: $CHANNEL" >&2
    exit 1
    ;;
esac

cat <<EOF
cask "$TOKEN" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/ShravanSunder/agentstudio/releases/download/v#{version}/AgentStudio-v#{version}-macos.zip"
  name "Agent Studio"
  desc "Terminal application with Ghostty terminal emulator and project management"
  homepage "https://github.com/ShravanSunder/agentstudio"

  conflicts_with cask: "$CONFLICT"
  depends_on macos: :tahoe

  app "AgentStudio.app"

  zap trash: [
    "~/$DATA_DIR",
    "~/Library/Caches/com.agentstudio.app",
    "~/Library/Preferences/com.agentstudio.app.plist",
  ]
end
EOF
