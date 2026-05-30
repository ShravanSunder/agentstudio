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
grep -q 'desc "Terminal application with Ghostty terminal emulator and project management"' <<<"$stable_cask"
grep -q 'conflicts_with cask: "agent-studio@beta"' <<<"$stable_cask"
grep -q 'depends_on macos: :tahoe' <<<"$stable_cask"
grep -q '"~/.agentstudio"' <<<"$stable_cask"
! grep -q 'desc "macOS' <<<"$stable_cask"
! grep -q 'depends_on macos: ">= :tahoe"' <<<"$stable_cask"
grep -q 'cask "agent-studio@beta" do' <<<"$beta_cask"
grep -q 'desc "Terminal application with Ghostty terminal emulator and project management"' <<<"$beta_cask"
grep -q 'conflicts_with cask: "agent-studio"' <<<"$beta_cask"
grep -q 'depends_on macos: :tahoe' <<<"$beta_cask"
grep -q '"~/.agent-studio-b"' <<<"$beta_cask"
! grep -q 'desc "macOS' <<<"$beta_cask"
! grep -q 'depends_on macos: ">= :tahoe"' <<<"$beta_cask"

beta_conflicts_line="$(grep -n 'conflicts_with cask: "agent-studio"' <<<"$beta_cask" | cut -d: -f1)"
beta_depends_line="$(grep -n 'depends_on macos: :tahoe' <<<"$beta_cask" | cut -d: -f1)"
beta_app_line="$(grep -n 'app "AgentStudio.app"' <<<"$beta_cask" | cut -d: -f1)"
beta_data_line="$(grep -n '"~/.agent-studio-b",' <<<"$beta_cask" | cut -d: -f1)"
beta_cache_line="$(grep -n '"~/Library/Caches/com.agentstudio.app",' <<<"$beta_cask" | cut -d: -f1)"
beta_preferences_line="$(grep -n '"~/Library/Preferences/com.agentstudio.app.plist",' <<<"$beta_cask" | cut -d: -f1)"

test "$beta_conflicts_line" -lt "$beta_depends_line"
test "$beta_depends_line" -lt "$beta_app_line"
test "$beta_data_line" -lt "$beta_cache_line"
test "$beta_cache_line" -lt "$beta_preferences_line"

tap_dir="$(mktemp -d)"
cleanup() {
  find "$tap_dir" -mindepth 1 -delete
  rmdir "$tap_dir"
}
trap cleanup EXIT
mkdir -p "$tap_dir/Casks"
HOMEBREW_TAP_LOCAL_PATH="$tap_dir" DRY_RUN=1 SKIP_BREW_STYLE=1 \
  "$ROOT_DIR/scripts/update-homebrew-tap.sh" beta v0.0.54-beta.1 "$SHA" >/dev/null

test -f "$tap_dir/Casks/agent-studio@beta.rb"
test ! -f "$tap_dir/Casks/agent-studio.rb"

fake_bin="$tap_dir/fake-bin"
fake_homebrew="$tap_dir/fake-homebrew"
mkdir -p "$fake_bin" "$fake_homebrew/Library/Taps"

cat > "$fake_bin/brew" <<'FAKE_BREW'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --repository)
    if [[ "${FAKE_BREW_REPOSITORY_FAIL:-0}" == "1" ]]; then
      exit 42
    fi
    echo "$FAKE_HOMEBREW_REPOSITORY"
    ;;
  style)
    if [[ "$(pwd)" != "$FAKE_HOMEBREW_REPOSITORY"/Library/Taps/* ]]; then
      echo "Homebrew requires casks to be in a tap, rejecting:" >&2
      echo "  $(pwd)/${3:-}" >&2
      exit 1
    fi
    ;;
  *)
    echo "unexpected fake brew invocation: $*" >&2
    exit 1
    ;;
esac
FAKE_BREW
chmod +x "$fake_bin/brew"

cat > "$fake_bin/git" <<'FAKE_GIT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "clone" ]]; then
  mkdir -p "${3:?missing clone destination}/Casks"
  exit 0
fi

echo "unexpected fake git invocation: $*" >&2
exit 1
FAKE_GIT
chmod +x "$fake_bin/git"

PATH="$fake_bin:$PATH" FAKE_HOMEBREW_REPOSITORY="$fake_homebrew" HOMEBREW_TAP_TOKEN=fake \
  DRY_RUN=1 "$ROOT_DIR/scripts/update-homebrew-tap.sh" beta v0.0.54-beta.1 "$SHA" >/dev/null

PATH="$fake_bin:$PATH" FAKE_BREW_REPOSITORY_FAIL=1 HOMEBREW_TAP_TOKEN=fake \
  DRY_RUN=1 SKIP_BREW_STYLE=1 "$ROOT_DIR/scripts/update-homebrew-tap.sh" beta v0.0.54-beta.1 "$SHA" >/dev/null

echo "release script verification passed"
