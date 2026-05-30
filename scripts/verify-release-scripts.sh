#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHA="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

stable_metadata="$("$ROOT_DIR/scripts/release-tag-metadata.sh" v0.0.54)"
beta_metadata="$("$ROOT_DIR/scripts/release-tag-metadata.sh" v0.0.54-beta.1)"

grep -q "channel=stable" <<<"$stable_metadata"
grep -q "cask_token=agent-studio" <<<"$stable_metadata"
grep -q "channel=beta" <<<"$beta_metadata"
grep -q "cask_token=agent-studio@beta" <<<"$beta_metadata"

if "$ROOT_DIR/scripts/release-tag-metadata.sh" v0.0.54-beta >/dev/null 2>&1; then
  echo "malformed beta tag unexpectedly passed" >&2
  exit 1
fi

stable_cask="$("$ROOT_DIR/scripts/render-homebrew-cask.sh" stable 0.0.54 "$SHA")"
beta_cask="$("$ROOT_DIR/scripts/render-homebrew-cask.sh" beta 0.0.54-beta.1 "$SHA")"

grep -q 'cask "agent-studio" do' <<<"$stable_cask"
grep -q 'conflicts_with cask: "agent-studio@beta"' <<<"$stable_cask"
grep -q '"~/.agentstudio"' <<<"$stable_cask"
grep -q 'cask "agent-studio@beta" do' <<<"$beta_cask"
grep -q 'conflicts_with cask: "agent-studio"' <<<"$beta_cask"
grep -q '"~/.agent-studio-b"' <<<"$beta_cask"

tap_dir="$(mktemp -d)"
mkdir -p "$tap_dir/Casks"
HOMEBREW_TAP_LOCAL_PATH="$tap_dir" DRY_RUN=1 SKIP_BREW_STYLE=1 \
  "$ROOT_DIR/scripts/update-homebrew-tap.sh" beta v0.0.54-beta.1 "$SHA" >/dev/null

test -f "$tap_dir/Casks/agent-studio@beta.rb"
test ! -f "$tap_dir/Casks/agent-studio.rb"

echo "release script verification passed"
