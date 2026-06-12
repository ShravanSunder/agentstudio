#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHA="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

stable_metadata="$("$ROOT_DIR/scripts/release-tag-metadata.sh" v0.0.54)"
beta_metadata="$("$ROOT_DIR/scripts/release-tag-metadata.sh" v0.0.54-beta.1)"

contains_line() {
  local haystack="${1:?missing haystack}"
  local needle="${2:?missing needle}"
  [[ "$haystack" == *"$needle"* ]]
}

contains_line "$stable_metadata" "channel=stable"
contains_line "$stable_metadata" "cask_token=agent-studio"
contains_line "$stable_metadata" "app_bundle_name=AgentStudio.app"
contains_line "$stable_metadata" "bundle_identifier=com.agentstudio.app"
contains_line "$stable_metadata" "app_cache_domain=com.agentstudio.app"
contains_line "$stable_metadata" "oauth_callback_scheme=agentstudio"
contains_line "$beta_metadata" "channel=beta"
contains_line "$beta_metadata" "cask_token=agent-studio@beta"
contains_line "$beta_metadata" "app_bundle_name=AgentStudio Beta.app"
contains_line "$beta_metadata" "bundle_identifier=com.agentstudio.app.beta"
contains_line "$beta_metadata" "app_cache_domain=com.agentstudio.app.beta"
contains_line "$beta_metadata" "oauth_callback_scheme=agentstudio-beta"

if "$ROOT_DIR/scripts/release-tag-metadata.sh" v0.0.54-beta >/dev/null 2>&1; then
  echo "malformed beta tag unexpectedly passed" >&2
  exit 1
fi

stable_cask="$("$ROOT_DIR/scripts/render-homebrew-cask.sh" stable 0.0.54 "$SHA")"
beta_cask="$("$ROOT_DIR/scripts/render-homebrew-cask.sh" beta 0.0.54-beta.1 "$SHA")"

contains_line "$stable_cask" 'cask "agent-studio" do'
contains_line "$stable_cask" 'name "Agent Studio"'
contains_line "$stable_cask" 'desc "Terminal application with Ghostty terminal emulator and project management"'
! contains_line "$stable_cask" 'conflicts_with cask: "agent-studio@beta"'
contains_line "$stable_cask" 'depends_on macos: :tahoe'
contains_line "$stable_cask" 'app "AgentStudio.app"'
contains_line "$stable_cask" '"~/.agentstudio"'
contains_line "$stable_cask" '"~/Library/Caches/com.agentstudio.app"'
contains_line "$stable_cask" '"~/Library/Preferences/com.agentstudio.app.plist"'
contains_line "$stable_cask" '"~/Library/Saved Application State/com.agentstudio.app.savedState"'
! contains_line "$stable_cask" 'desc "macOS'
! contains_line "$stable_cask" 'depends_on macos: ">= :tahoe"'
contains_line "$beta_cask" 'cask "agent-studio@beta" do'
contains_line "$beta_cask" 'name "Agent Studio Beta"'
contains_line "$beta_cask" 'desc "Terminal application with Ghostty terminal emulator and project management"'
! contains_line "$beta_cask" 'conflicts_with cask: "agent-studio"'
contains_line "$beta_cask" 'depends_on macos: :tahoe'
contains_line "$beta_cask" 'app "AgentStudio Beta.app"'
contains_line "$beta_cask" '"~/.agent-studio-b"'
contains_line "$beta_cask" '"~/Library/Caches/com.agentstudio.app.beta"'
contains_line "$beta_cask" '"~/Library/Preferences/com.agentstudio.app.beta.plist"'
contains_line "$beta_cask" '"~/Library/Saved Application State/com.agentstudio.app.beta.savedState"'
! contains_line "$beta_cask" 'desc "macOS'
! contains_line "$beta_cask" 'depends_on macos: ">= :tahoe"'

if ! printf '%s\n' "$beta_cask" | awk '
  /depends_on macos: :tahoe/ { depends = NR }
  /app "AgentStudio Beta.app"/ { app = NR }
  END {
    if (!depends || !app || depends >= app) {
      exit 1
    }
  }
'; then
  echo "beta cask stanza order is incorrect or missing expected stanzas" >&2
  exit 1
fi

if ! printf '%s\n' "$beta_cask" | awk '
  /"~\/\.agent-studio-b",/ { data = NR }
  /"~\/Library\/Caches\/com\.agentstudio\.app\.beta",/ { cache = NR }
  /"~\/Library\/Preferences\/com\.agentstudio\.app\.beta\.plist",/ { preferences = NR }
  /"~\/Library\/Saved Application State\/com\.agentstudio\.app\.beta\.savedState",/ { saved_state = NR }
  END {
    if (!data || !cache || !preferences || !saved_state || data >= cache || cache >= preferences || preferences >= saved_state) {
      exit 1
    }
  }
'; then
  echo "beta cask zap trash order is incorrect or missing expected paths" >&2
  exit 1
fi

tap_dir="$(mktemp -d)"
cleanup() {
  find "$tap_dir" -mindepth 1 -delete
  rmdir "$tap_dir"
}
trap cleanup EXIT
mkdir -p "$tap_dir/Casks"

plist_under_test="$tap_dir/Info.plist"
cp "$ROOT_DIR/Sources/AgentStudio/Resources/Info.plist" "$plist_under_test"
bash "$ROOT_DIR/scripts/inject-bundle-version.sh" "$plist_under_test" 0.0.54-beta.1 123 beta
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLName' "$plist_under_test")" = "com.agentstudio.oauth.beta"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$plist_under_test")" = "agentstudio-beta"

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
