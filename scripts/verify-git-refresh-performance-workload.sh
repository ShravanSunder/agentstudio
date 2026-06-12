#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_HELPER="${SHRAVAN_OBSERVABILITY_STACK_HELPER:-$HOME/dev/devfiles/shared/observability/observability-stack}"
COLLECTOR_HEALTH_URL="${SHRAVAN_OBSERVABILITY_COLLECTOR_HEALTH_URL:-http://127.0.0.1:13133/}"

DEFAULT_PROOF_ROOT="$PROJECT_ROOT/tmp/debug-workflows/2026-06-11-agent-studio-performance-issues-cmdp-slowdown/proofs"
DEFAULT_UI_PROOF_ROOT="/tmp/asperf"

usage() {
  cat <<'USAGE'
Usage: verify-git-refresh-performance-workload.sh [--prepare-only]

Creates a disposable 118-repo / 163-worktree / 14-pane AgentStudio workspace,
launches a debug or beta AgentStudio process with isolated AGENTSTUDIO_DATA_DIR,
runs five fixture git writers, and captures marker-scoped JSONL/OTLP performance
trace evidence.

Environment overrides:
  AGENTSTUDIO_PERF_APP_BINARY       Use an existing AgentStudio executable.
  AGENTSTUDIO_PERF_APP_BUNDLE       Launch an existing AgentStudio .app bundle with open(1).
  AGENTSTUDIO_PERF_PROOF_ROOT       Parent directory for timestamped artifacts.
                                      Default: repo tmp for git-only runs, /tmp for UI-driven runs.
  AGENTSTUDIO_PERF_REPO_COUNT       Repo count. Default: 118.
  AGENTSTUDIO_PERF_WORKTREE_COUNT   Worktree count. Default: 163.
  AGENTSTUDIO_PERF_ACTIVE_PANES     Pane-owned active worktrees. Default: 14.
  AGENTSTUDIO_PERF_WRITER_COUNT     Concurrent git writers. Default: 5.
  AGENTSTUDIO_PERF_DURATION_SECONDS Busy workload duration. Default: 60.
                                      Set >=255 when this script is used to cover
                                      a full 16-stripe background refresh cycle.
  AGENTSTUDIO_PERF_DRIVE_COMMAND_BAR
                                      Set to 0 to skip startup command-bar repo filter smoke. Default: 1.
  AGENTSTUDIO_PERF_SKIP_BUILD       Set to 1 when AGENTSTUDIO_PERF_APP_BINARY is supplied.
  AGENTSTUDIO_PERF_TRACE_BACKEND    jsonl|both. Default: both when collector is healthy, else jsonl.

The script never reads or mutates the user's live AgentStudio app data, user
worktrees, or global git config. Cleanup kills only PIDs launched by this script.
USAGE
}

prepare_only=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prepare-only)
      prepare_only=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

REPO_COUNT="${AGENTSTUDIO_PERF_REPO_COUNT:-118}"
WORKTREE_COUNT="${AGENTSTUDIO_PERF_WORKTREE_COUNT:-163}"
ACTIVE_PANE_COUNT="${AGENTSTUDIO_PERF_ACTIVE_PANES:-14}"
WRITER_COUNT="${AGENTSTUDIO_PERF_WRITER_COUNT:-5}"
DURATION_SECONDS="${AGENTSTUDIO_PERF_DURATION_SECONDS:-60}"
DRIVE_COMMAND_BAR="${AGENTSTUDIO_PERF_DRIVE_COMMAND_BAR:-1}"
if [ -n "${AGENTSTUDIO_PERF_PROOF_ROOT:-}" ]; then
  PROOF_ROOT="$AGENTSTUDIO_PERF_PROOF_ROOT"
elif [ "$DRIVE_COMMAND_BAR" = "1" ]; then
  PROOF_ROOT="$DEFAULT_UI_PROOF_ROOT"
else
  PROOF_ROOT="$DEFAULT_PROOF_ROOT"
fi

validate_trace_name() {
  local trace_name="$1"
  if [ -z "$trace_name" ]; then
    echo "AGENTSTUDIO_TRACE_NAME must not be empty" >&2
    exit 2
  fi
  case "$trace_name" in
    "."|".."|*"/"*|*"\\"*|*".."*|*"*"*|*"?"*|*"["*|*"]"*|*"{"*|*"}"*)
      echo "AGENTSTUDIO_TRACE_NAME must be a safe path component: $trace_name" >&2
      exit 2
      ;;
  esac
  case "$trace_name" in
    *[!A-Za-z0-9_.-]*)
      echo "AGENTSTUDIO_TRACE_NAME may only contain letters, numbers, '.', '_' and '-': $trace_name" >&2
      exit 2
      ;;
  esac
  printf '%s\n' "$trace_name"
}

if [ -n "${AGENTSTUDIO_TRACE_NAME:-}" ]; then
  TRACE_NAME="$(validate_trace_name "$AGENTSTUDIO_TRACE_NAME")"
elif [ "$DRIVE_COMMAND_BAR" = "1" ]; then
  TRACE_NAME="$(validate_trace_name "perf-$(date +%H%M%S)-$$")"
else
  TRACE_NAME="$(validate_trace_name "git-refresh-performance-$(date +%Y%m%d%H%M%S)-$$")"
fi
ARTIFACT="$PROOF_ROOT/$TRACE_NAME"
FIXTURE_ROOT="$ARTIFACT/fixtures"
APP_DATA_DIR="$ARTIFACT/app-data"
TRACE_DIR="$ARTIFACT/traces"
PID_DIR="$ARTIFACT/pids"
COMMAND_LOG="$ARTIFACT/commands.log"
SUMMARY_FILE="$ARTIFACT/summary.txt"

APP_PID=""
APP_BINARY=""
APP_LAUNCH_BUNDLE=""
WRITER_PIDS=()

log_command() {
  printf '+ %s\n' "$*" | tee -a "$COMMAND_LOG"
}

stop_pid() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  local cleanup_log="$ARTIFACT/cleanup.log"
  mkdir -p "$ARTIFACT"
  {
    echo "cleanup started $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    for pid in "${WRITER_PIDS[@]:-}"; do
      stop_pid "$pid"
      echo "writer pid stopped: $pid"
    done
    if [ -n "$APP_PID" ]; then
      stop_pid "$APP_PID"
      echo "app pid stopped: $APP_PID"
    fi
    local live_writers=0
    for pid_file in "$PID_DIR"/writer-*.pid; do
      [ -f "$pid_file" ] || continue
      local pid
      pid="$(cat "$pid_file")"
      if kill -0 "$pid" >/dev/null 2>&1; then
        live_writers=$((live_writers + 1))
      fi
    done
    echo "live writer pids after cleanup: $live_writers"
    echo "cleanup finished $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } >>"$cleanup_log"
}

trap cleanup EXIT INT TERM

require_positive_integer() {
  local name="$1"
  local value="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "$name must be a positive integer: $value" >&2
      exit 2
      ;;
  esac
  if [ "$value" -le 0 ]; then
    echo "$name must be a positive integer: $value" >&2
    exit 2
  fi
}

require_positive_integer AGENTSTUDIO_PERF_REPO_COUNT "$REPO_COUNT"
require_positive_integer AGENTSTUDIO_PERF_WORKTREE_COUNT "$WORKTREE_COUNT"
require_positive_integer AGENTSTUDIO_PERF_ACTIVE_PANES "$ACTIVE_PANE_COUNT"
require_positive_integer AGENTSTUDIO_PERF_WRITER_COUNT "$WRITER_COUNT"
require_positive_integer AGENTSTUDIO_PERF_DURATION_SECONDS "$DURATION_SECONDS"
if [ "$DRIVE_COMMAND_BAR" != "0" ] && [ "$DRIVE_COMMAND_BAR" != "1" ]; then
  echo "AGENTSTUDIO_PERF_DRIVE_COMMAND_BAR must be 0 or 1" >&2
  exit 2
fi

if [ "$WORKTREE_COUNT" -lt "$REPO_COUNT" ]; then
  echo "AGENTSTUDIO_PERF_WORKTREE_COUNT must be >= repo count" >&2
  exit 2
fi
if [ "$WORKTREE_COUNT" -gt $((REPO_COUNT * 2)) ]; then
  echo "AGENTSTUDIO_PERF_WORKTREE_COUNT must be <= 2x repo count for this fixture generator" >&2
  exit 2
fi
if [ "$ACTIVE_PANE_COUNT" -gt "$WORKTREE_COUNT" ]; then
  echo "AGENTSTUDIO_PERF_ACTIVE_PANES must be <= worktree count" >&2
  exit 2
fi

mkdir -p "$ARTIFACT" "$FIXTURE_ROOT" "$APP_DATA_DIR/workspaces" "$TRACE_DIR" "$PID_DIR"
: >"$COMMAND_LOG"

uuid_v7() {
  local seconds millis ts_hex random_hex
  seconds="$(date +%s)"
  millis=$((seconds * 1000))
  printf -v ts_hex '%012x' "$millis"
  random_hex="$(openssl rand -hex 10 | tr '[:upper:]' '[:lower:]')"
  printf '%s-%s-7%s-8%s-%s\n' \
    "${ts_hex:0:8}" \
    "${ts_hex:8:4}" \
    "${random_hex:0:3}" \
    "${random_hex:3:3}" \
    "${random_hex:6:12}"
}

uuid_any() {
  uuidgen | tr '[:upper:]' '[:lower:]'
}

json_url() {
  printf 'file://%s' "$1"
}

json_string() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

init_repo() {
  local repo_dir="$1"
  mkdir -p "$repo_dir"
  log_command git init "$repo_dir"
  git init "$repo_dir" >>"$ARTIFACT/fixture-setup.log" 2>&1
  git -C "$repo_dir" config user.email agentstudio-perf@example.invalid
  git -C "$repo_dir" config user.name 'AgentStudio Perf Fixture'
  git -C "$repo_dir" config commit.gpgsign false
  git -C "$repo_dir" config tag.gpgsign false
  printf 'initial\n' >"$repo_dir/README.md"
  git -C "$repo_dir" add README.md >>"$ARTIFACT/fixture-setup.log" 2>&1
  git -C "$repo_dir" commit -m initial >>"$ARTIFACT/fixture-setup.log" 2>&1
}

create_linked_worktree() {
  local repo_dir="$1"
  local worktree_dir="$2"
  local branch_name="$3"
  log_command git -C "$repo_dir" worktree add -b "$branch_name" "$worktree_dir"
  git -C "$repo_dir" worktree add -b "$branch_name" "$worktree_dir" >>"$ARTIFACT/fixture-setup.log" 2>&1
  git -C "$worktree_dir" config user.email agentstudio-perf@example.invalid
  git -C "$worktree_dir" config user.name 'AgentStudio Perf Fixture'
  git -C "$worktree_dir" config commit.gpgsign false
  git -C "$worktree_dir" config tag.gpgsign false
}

write_workspace_json() {
  local workspace_id="$1"
  local workspace_file="$APP_DATA_DIR/workspaces/$workspace_id.workspace.state.json"
  local timestamp=0

  {
    printf '{\n'
    printf '  "schemaVersion": 1,\n'
    printf '  "id": "%s",\n' "$workspace_id"
    printf '  "name": "Git Refresh Performance Fixture",\n'
    printf '  "repos": [\n'
    local repo_index
    for repo_index in $(seq 0 $((REPO_COUNT - 1))); do
      [ "$repo_index" -gt 0 ] && printf ',\n'
      printf '    {"id": "%s", "name": "repo-%03d", "repoPath": "%s", "createdAt": %s}' \
        "${REPO_IDS[$repo_index]}" \
        "$repo_index" \
        "$(json_url "${REPO_PATHS[$repo_index]}")" \
        "$timestamp"
    done
    printf '\n  ],\n'

    printf '  "worktrees": [\n'
    local worktree_index
    for worktree_index in $(seq 0 $((WORKTREE_COUNT - 1))); do
      [ "$worktree_index" -gt 0 ] && printf ',\n'
      printf '    {"id": "%s", "repoId": "%s", "name": "%s", "path": "%s", "isMainWorktree": %s}' \
        "${WORKTREE_IDS[$worktree_index]}" \
        "${WORKTREE_REPO_IDS[$worktree_index]}" \
        "$(json_string "${WORKTREE_NAMES[$worktree_index]}")" \
        "$(json_url "${WORKTREE_PATHS[$worktree_index]}")" \
        "${WORKTREE_IS_MAIN[$worktree_index]}"
    done
    printf '\n  ],\n'
    printf '  "unavailableRepoIds": [],\n'

    printf '  "panes": [\n'
    local pane_index
    for pane_index in $(seq 0 $((ACTIVE_PANE_COUNT - 1))); do
      [ "$pane_index" -gt 0 ] && printf ',\n'
      local pane_id="${PANE_IDS[$pane_index]}"
      local repo_id="${WORKTREE_REPO_IDS[$pane_index]}"
      local worktree_id="${WORKTREE_IDS[$pane_index]}"
      local worktree_path="${WORKTREE_PATHS[$pane_index]}"
      local title="repo-pane-$pane_index"
      printf '    {\n'
      printf '      "id": "%s",\n' "$pane_id"
      printf '      "content": {"version": 2, "type": "terminal", "state": {"provider": "zmx", "lifetime": "persistent"}},\n'
      printf '      "metadata": {\n'
      printf '        "paneId": "%s",\n' "$pane_id"
      printf '        "contentType": {"terminal": {}},\n'
      printf '        "source": {"worktree": {"worktreeId": "%s", "repoId": "%s", "launchDirectory": "%s"}},\n' \
        "$worktree_id" "$repo_id" "$(json_url "$worktree_path")"
      printf '        "executionBackend": {"local": {}},\n'
      printf '        "createdAt": %s,\n' "$timestamp"
      printf '        "title": "%s",\n' "$title"
      printf '        "facets": {"repoId": "%s", "worktreeId": "%s", "cwd": "%s", "tags": []},\n' \
        "$repo_id" "$worktree_id" "$(json_url "$worktree_path")"
      printf '        "checkoutRef": null,\n'
      printf '        "note": null\n'
      printf '      },\n'
      printf '      "residency": {"active": {}},\n'
      printf '      "kind": {"layout": {"drawer": {"drawerId": "%s", "parentPaneId": "%s", "paneIds": [], "isExpanded": false}}}\n' \
        "${DRAWER_IDS[$pane_index]}" "$pane_id"
      printf '    }'
    done
    printf '\n  ],\n'

    printf '  "tabs": [\n'
    printf '    {\n'
    printf '      "id": "%s",\n' "$TAB_ID"
    printf '      "name": "Performance",\n'
    printf '      "panes": ['
    local tab_pane_index
    for tab_pane_index in $(seq 0 $((ACTIVE_PANE_COUNT - 1))); do
      [ "$tab_pane_index" -gt 0 ] && printf ', '
      printf '"%s"' "${PANE_IDS[$tab_pane_index]}"
    done
    printf '],\n'
    printf '      "arrangements": [\n'
    printf '        {\n'
    printf '          "id": "%s",\n' "$ARRANGEMENT_ID"
    printf '          "name": "Default",\n'
    printf '          "isDefault": true,\n'
    printf '          "layout": {"panes": ['
    for tab_pane_index in $(seq 0 $((ACTIVE_PANE_COUNT - 1))); do
      [ "$tab_pane_index" -gt 0 ] && printf ', '
      printf '{"paneId": "%s", "ratio": %.8f}' \
        "${PANE_IDS[$tab_pane_index]}" \
        "$(awk "BEGIN { printf \"%.8f\", 1 / $ACTIVE_PANE_COUNT }")"
    done
    printf '], "dividerIds": ['
    if [ "$ACTIVE_PANE_COUNT" -gt 1 ]; then
      local divider_index
      for divider_index in $(seq 0 $((ACTIVE_PANE_COUNT - 2))); do
        [ "$divider_index" -gt 0 ] && printf ', '
        printf '"%s"' "${DIVIDER_IDS[$divider_index]}"
      done
    fi
    printf ']},\n'
    printf '          "minimizedPaneIds": [],\n'
    printf '          "showsMinimizedPanes": true,\n'
    printf '          "activePaneId": "%s",\n' "${PANE_IDS[0]}"
    printf '          "drawerViews": []\n'
    printf '        }\n'
    printf '      ],\n'
    printf '      "activeArrangementId": "%s"\n' "$ARRANGEMENT_ID"
    printf '    }\n'
    printf '  ],\n'
    printf '  "activeTabId": "%s",\n' "$TAB_ID"
    printf '  "sidebarWidth": 250,\n'
    printf '  "windowFrame": null,\n'
    printf '  "watchedPaths": [],\n'
    printf '  "createdAt": %s,\n' "$timestamp"
    printf '  "updatedAt": %s\n' "$timestamp"
    printf '}\n'
  } >"$workspace_file"

  echo "$workspace_file"
}

prepare_fixture() {
  REPO_IDS=()
  REPO_PATHS=()
  WORKTREE_IDS=()
  WORKTREE_REPO_IDS=()
  WORKTREE_PATHS=()
  WORKTREE_NAMES=()
  WORKTREE_IS_MAIN=()
  PANE_IDS=()
  DRAWER_IDS=()
  DIVIDER_IDS=()

  local linked_worktrees_needed=$((WORKTREE_COUNT - REPO_COUNT))
  local worktree_index=0
  local repo_index
  for repo_index in $(seq 0 $((REPO_COUNT - 1))); do
    local repo_id repo_dir
    repo_id="$(uuid_any)"
    repo_dir="$FIXTURE_ROOT/repos/repo-$(printf '%03d' "$repo_index")"
    init_repo "$repo_dir"

    REPO_IDS[$repo_index]="$repo_id"
    REPO_PATHS[$repo_index]="$repo_dir"

    WORKTREE_IDS[$worktree_index]="$(uuid_any)"
    WORKTREE_REPO_IDS[$worktree_index]="$repo_id"
    WORKTREE_PATHS[$worktree_index]="$repo_dir"
    WORKTREE_NAMES[$worktree_index]="main"
    WORKTREE_IS_MAIN[$worktree_index]="true"
    worktree_index=$((worktree_index + 1))

    if [ "$linked_worktrees_needed" -gt 0 ]; then
      local linked_dir branch_name
      branch_name="perf-$repo_index"
      linked_dir="$FIXTURE_ROOT/linked/repo-$(printf '%03d' "$repo_index")-$branch_name"
      create_linked_worktree "$repo_dir" "$linked_dir" "$branch_name"
      WORKTREE_IDS[$worktree_index]="$(uuid_any)"
      WORKTREE_REPO_IDS[$worktree_index]="$repo_id"
      WORKTREE_PATHS[$worktree_index]="$linked_dir"
      WORKTREE_NAMES[$worktree_index]="$branch_name"
      WORKTREE_IS_MAIN[$worktree_index]="false"
      worktree_index=$((worktree_index + 1))
      linked_worktrees_needed=$((linked_worktrees_needed - 1))
    fi
  done

  local pane_index
  for pane_index in $(seq 0 $((ACTIVE_PANE_COUNT - 1))); do
    PANE_IDS[$pane_index]="$(uuid_v7)"
    DRAWER_IDS[$pane_index]="$(uuid_any)"
  done
  if [ "$ACTIVE_PANE_COUNT" -gt 1 ]; then
    local divider_index
    for divider_index in $(seq 0 $((ACTIVE_PANE_COUNT - 2))); do
      DIVIDER_IDS[$divider_index]="$(uuid_any)"
    done
  fi
  TAB_ID="$(uuid_any)"
  ARRANGEMENT_ID="$(uuid_any)"
  WORKSPACE_ID="$(uuid_any)"
  WORKSPACE_FILE="$(write_workspace_json "$WORKSPACE_ID")"
}

resolve_app_binary() {
  if [ -n "${AGENTSTUDIO_PERF_APP_BINARY:-}" ]; then
    reject_live_app_binary_override "$AGENTSTUDIO_PERF_APP_BINARY"
    printf '%s\n' "$AGENTSTUDIO_PERF_APP_BINARY"
    return 0
  fi
  if [ -n "${AGENTSTUDIO_PERF_APP_BUNDLE:-}" ]; then
    printf '%s\n' "$AGENTSTUDIO_PERF_APP_BUNDLE/Contents/MacOS/AgentStudio"
    return 0
  fi
  if [ "${AGENTSTUDIO_PERF_SKIP_BUILD:-0}" != "1" ]; then
    log_command mise run build >/dev/null
    mise run build >"$ARTIFACT/build.log" 2>&1
  fi
  find "$PROJECT_ROOT" \
    \( -path "$PROJECT_ROOT/.build-agent-*/debug/AgentStudio" \
      -o -path "$PROJECT_ROOT/.build-agent-*/*/debug/AgentStudio" \) \
    -type f -perm -111 -print0 2>/dev/null |
    while IFS= read -r -d '' binary_path; do
      printf '%s\t%s\n' "$(stat -f '%m' "$binary_path")" "$binary_path"
    done |
    sort -nr |
    sed -n $'1s/^[^\t]*\t//p'
}

materialize_app_bundle_for_ui_smoke() {
  local app_binary="$1"
  local bundle_path="$ARTIFACT/AgentStudio Performance Proof.app"
  local contents_path="$bundle_path/Contents"
  local binary_dir
  binary_dir="$(dirname "$app_binary")"

  log_command materialize temporary app bundle "$bundle_path"
  if [ -e "$bundle_path" ]; then
    echo "temporary app bundle path already exists: $bundle_path" >&2
    exit 1
  fi
  mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
  cp "$app_binary" "$contents_path/MacOS/AgentStudio"
  if [ -x "$PROJECT_ROOT/vendor/zmx/zig-out/bin/zmx" ]; then
    cp "$PROJECT_ROOT/vendor/zmx/zig-out/bin/zmx" "$contents_path/MacOS/zmx"
  fi
  cp "$PROJECT_ROOT/Sources/AgentStudio/Resources/Info.plist" "$contents_path/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.agentstudio.app.performanceproof" \
    "$contents_path/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleName AgentStudio Performance Proof" \
    "$contents_path/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName AgentStudio Performance Proof" \
    "$contents_path/Info.plist" >/dev/null 2>&1 || true
  cp "$PROJECT_ROOT/Sources/AgentStudio/Resources/AppIcon.icns" "$contents_path/Resources/" 2>/dev/null || true
  if [ -d "$PROJECT_ROOT/Sources/AgentStudio/Resources/terminfo" ]; then
    cp -R "$PROJECT_ROOT/Sources/AgentStudio/Resources/terminfo" "$contents_path/Resources/"
  fi
  if [ -d "$PROJECT_ROOT/Sources/AgentStudio/Resources/ghostty" ]; then
    mkdir -p "$contents_path/Resources/ghostty"
    cp -R "$PROJECT_ROOT/Sources/AgentStudio/Resources/ghostty/." "$contents_path/Resources/ghostty/"
  fi
  if [ -d "$binary_dir/AgentStudio_AgentStudio.bundle" ]; then
    cp -R "$binary_dir/AgentStudio_AgentStudio.bundle" "$contents_path/Resources/"
  fi
  codesign --force --deep --sign - "$bundle_path" >>"$ARTIFACT/bundle.log" 2>&1
  APP_LAUNCH_BUNDLE="$bundle_path"
  APP_BINARY="$contents_path/MacOS/AgentStudio"
}

reject_live_app_binary_override() {
  local binary_path="$1"
  local binary_parent
  binary_parent="$(dirname "$binary_path")"
  [ -d "$binary_parent" ] || return 0
  local canonical_parent
  canonical_parent="$(cd "$binary_parent" && pwd -P)"
  local canonical_binary="$canonical_parent/$(basename "$binary_path")"
  case "$canonical_binary" in
    "/Applications/AgentStudio.app/Contents/MacOS/AgentStudio"|"/Applications/AgentStudio Beta.app/Contents/MacOS/AgentStudio")
      echo "AGENTSTUDIO_PERF_APP_BINARY must not target a live /Applications AgentStudio executable: $canonical_binary" >&2
      exit 2
      ;;
  esac
}

reject_live_app_bundle_override() {
  local bundle_path="$1"
  local canonical_parent
  canonical_parent="$(cd "$(dirname "$bundle_path")" && pwd -P)"
  local canonical_bundle="$canonical_parent/$(basename "$bundle_path")"
  case "$canonical_bundle" in
    "/Applications/AgentStudio.app"|"/Applications/AgentStudio Beta.app")
      echo "AGENTSTUDIO_PERF_APP_BUNDLE must not target a live /Applications AgentStudio bundle: $canonical_bundle" >&2
      exit 2
      ;;
  esac
}

proof_app_pid_candidates() {
  [ -n "$APP_BINARY" ] || return 0
  ps -axo pid=,command= | awk -v app_binary="$APP_BINARY" '
    index($0, app_binary) > 0 {
      print $1
    }
  '
}

resolve_app_launch_target() {
  if [ -n "${AGENTSTUDIO_PERF_APP_BUNDLE:-}" ]; then
    reject_live_app_bundle_override "$AGENTSTUDIO_PERF_APP_BUNDLE"
    APP_LAUNCH_BUNDLE="$AGENTSTUDIO_PERF_APP_BUNDLE"
    APP_BINARY="$APP_LAUNCH_BUNDLE/Contents/MacOS/AgentStudio"
    return 0
  fi

  APP_BINARY="$(resolve_app_binary)"
  if [ -z "$APP_BINARY" ]; then
    echo "AgentStudio build product not found under .build-agent-*; see $ARTIFACT/build.log" >&2
    exit 1
  fi
  if [ "$DRIVE_COMMAND_BAR" = "1" ]; then
    materialize_app_bundle_for_ui_smoke "$APP_BINARY"
  fi
}

select_trace_backend() {
  if [ -n "${AGENTSTUDIO_PERF_TRACE_BACKEND:-}" ]; then
    printf '%s\n' "$AGENTSTUDIO_PERF_TRACE_BACKEND"
    return 0
  fi
  if [ -x "$STACK_HELPER" ] && curl --fail --silent --show-error --max-time 1 "$COLLECTOR_HEALTH_URL" >/dev/null 2>&1; then
    printf 'both\n'
  else
    printf 'jsonl\n'
  fi
}

launch_app() {
  local app_binary="$1"
  local trace_backend="$2"
  if [ "$trace_backend" = "otlp" ]; then
    echo "AGENTSTUDIO_PERF_TRACE_BACKEND=otlp is not accepted; use both so JSONL PID-scoped proof is preserved" >&2
    exit 2
  fi
  if [ ! -x "$app_binary" ]; then
    echo "AgentStudio executable not found or not executable: $app_binary" >&2
    exit 1
  fi

  local otlp_endpoint=""
  local otlp_protocol=""
  if [ "$trace_backend" = "both" ] || [ "$trace_backend" = "otlp" ]; then
    otlp_endpoint="${OTEL_EXPORTER_OTLP_ENDPOINT:-$("$STACK_HELPER" collector-url 2>/dev/null || true)}"
    otlp_protocol="${OTEL_EXPORTER_OTLP_PROTOCOL:-http/protobuf}"
  fi

  if [ -n "$APP_LAUNCH_BUNDLE" ]; then
    if [ ! -d "$APP_LAUNCH_BUNDLE" ]; then
      echo "AgentStudio app bundle not found: $APP_LAUNCH_BUNDLE" >&2
      exit 1
    fi
    log_command /usr/bin/open -n "$APP_LAUNCH_BUNDLE" --env AGENTSTUDIO_DATA_DIR="$APP_DATA_DIR" \
      --env AGENTSTUDIO_TRACE_NAME="$TRACE_NAME"
    local open_args=(
      -n "$APP_LAUNCH_BUNDLE"
      --stdout "$ARTIFACT/app.log"
      --stderr "$ARTIFACT/app.log"
      --env "AGENTSTUDIO_DATA_DIR=$APP_DATA_DIR"
      --env "AGENTSTUDIO_TRACE_TAGS=performance"
      --env "AGENTSTUDIO_TRACE_FLUSH=immediate"
      --env "AGENTSTUDIO_TRACE_NAME=$TRACE_NAME"
      --env "AGENTSTUDIO_TRACE_DIR=$TRACE_DIR"
      --env "AGENTSTUDIO_TRACE_BACKEND=$trace_backend"
      --env "AGENTSTUDIO_RESTORE_TRACE=1"
      --env "HOME=${HOME:-}"
      --env "PATH=${PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
      --env "SHELL=${SHELL:-/bin/zsh}"
      --env "USER=${USER:-}"
      --env "LOGNAME=${LOGNAME:-}"
    )
    if [ "$DRIVE_COMMAND_BAR" = "1" ]; then
      open_args+=(--env "AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=command-bar-repo-filter")
    fi
    if [ -n "$otlp_endpoint" ]; then
      open_args+=(--env "OTEL_EXPORTER_OTLP_ENDPOINT=$otlp_endpoint")
      open_args+=(--env "OTEL_EXPORTER_OTLP_PROTOCOL=$otlp_protocol")
    fi
    /usr/bin/open "${open_args[@]}"
    local deadline=$((SECONDS + 30))
    local trace_pid_confirmed=false
    while [ "$SECONDS" -lt "$deadline" ]; do
      local candidate_pid
      candidate_pid="$(proof_app_pid_candidates | head -n 1)"
      if [ -n "$candidate_pid" ] && kill -0 "$candidate_pid" >/dev/null 2>&1; then
        APP_PID="$candidate_pid"
      fi
      local trace_file
      trace_file="$(find "$TRACE_DIR" -name "agentstudio-$TRACE_NAME-*.jsonl" -type f -print | head -n 1)"
      if [ -n "$trace_file" ]; then
        local trace_pid
        trace_pid="$(printf '%s\n' "$trace_file" | sed -E 's/.*-([0-9]+)\.jsonl$/\1/')"
        if kill -0 "$trace_pid" >/dev/null 2>&1; then
          APP_PID="$trace_pid"
          trace_pid_confirmed=true
          break
        fi
      fi
      sleep 1
    done
    if [ "$trace_pid_confirmed" != "true" ]; then
      echo "Unable to determine launched AgentStudio PID for bundle: $APP_LAUNCH_BUNDLE" >&2
      exit 1
    fi
  else
    export AGENTSTUDIO_DATA_DIR="$APP_DATA_DIR"
    export AGENTSTUDIO_TRACE_TAGS=performance
    export AGENTSTUDIO_TRACE_FLUSH=immediate
    export AGENTSTUDIO_TRACE_NAME="$TRACE_NAME"
    export AGENTSTUDIO_TRACE_DIR="$TRACE_DIR"
    export AGENTSTUDIO_TRACE_BACKEND="$trace_backend"
    export AGENTSTUDIO_RESTORE_TRACE=1
    if [ "$DRIVE_COMMAND_BAR" = "1" ]; then
      export AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=command-bar-repo-filter
    else
      unset AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION
    fi
    if [ -n "$otlp_endpoint" ]; then
      export OTEL_EXPORTER_OTLP_ENDPOINT="$otlp_endpoint"
      export OTEL_EXPORTER_OTLP_PROTOCOL="$otlp_protocol"
    else
      unset OTEL_EXPORTER_OTLP_ENDPOINT
      unset OTEL_EXPORTER_OTLP_PROTOCOL
    fi

    log_command AGENTSTUDIO_DATA_DIR="$APP_DATA_DIR" AGENTSTUDIO_TRACE_NAME="$TRACE_NAME" "$app_binary"
    "$app_binary" >"$ARTIFACT/app.log" 2>&1 &
    APP_PID=$!
  fi
  printf '%s\n' "$APP_PID" >"$PID_DIR/app.pid"
}

wait_for_trace_event() {
  local event_name="$1"
  local timeout_seconds="$2"
  local deadline=$((SECONDS + timeout_seconds))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if grep -R "\"body\":\"$event_name\"" "$TRACE_DIR" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_command_bar_repo_filter_event() {
  local timeout_seconds="$1"
  local deadline=$((SECONDS + timeout_seconds))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if grep -R "\"body\":\"performance.commandbar.filter\"" "$TRACE_DIR" 2>/dev/null \
      | grep "\"agentstudio.performance.commandbar.query_character.count\":[1-9][0-9]*" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

writer_loop() {
  local writer_index="$1"
  local worktree_path="$2"
  local end_at=$((SECONDS + DURATION_SECONDS))
  local iteration=0
  while [ "$SECONDS" -lt "$end_at" ]; do
    local file_path="$worktree_path/perf-writer-$writer_index.txt"
    printf 'writer=%s iteration=%s marker=%s\n' "$writer_index" "$iteration" "$TRACE_NAME" >>"$file_path"
    git -C "$worktree_path" add "$file_path" >/dev/null 2>&1
    git -C "$worktree_path" \
      -c user.email=agentstudio-perf@example.invalid \
      -c user.name='AgentStudio Perf Fixture' \
      -c commit.gpgsign=false \
      -c tag.gpgsign=false \
      commit -m "perf writer $writer_index iteration $iteration" >/dev/null 2>&1 || true
    iteration=$((iteration + 1))
    sleep 1
  done
}

start_writers() {
  local writer_index
  for writer_index in $(seq 0 $((WRITER_COUNT - 1))); do
    local worktree_slot=$((writer_index % WORKTREE_COUNT))
    local writer_log="$ARTIFACT/writer-$writer_index.log"
    writer_loop "$writer_index" "${WORKTREE_PATHS[$worktree_slot]}" >"$writer_log" 2>&1 &
    local writer_pid=$!
    WRITER_PIDS+=("$writer_pid")
    printf '%s\n' "$writer_pid" >"$PID_DIR/writer-$writer_index.pid"
  done
}

drive_command_bar_smoke() {
  if [ "$DRIVE_COMMAND_BAR" != "1" ]; then
    echo "command-bar smoke skipped by AGENTSTUDIO_PERF_DRIVE_COMMAND_BAR=0" >"$ARTIFACT/commandbar-smoke.log"
    return 0
  fi
  if [ -z "$APP_PID" ]; then
    echo "command-bar smoke skipped: no app PID" >"$ARTIFACT/commandbar-smoke.log"
    return 1
  fi
  log_command startup diagnostic command-bar repo filter smoke for PID "$APP_PID"
  {
    echo "driver=startup-diagnostic"
    echo "action=command-bar-repo-filter"
    echo "app_pid=$APP_PID"
  } >"$ARTIFACT/commandbar-smoke.log"
}

sample_app() {
  if [ -z "$APP_PID" ]; then
    return 0
  fi
  if [ -x /usr/bin/sample ]; then
    log_command /usr/bin/sample "$APP_PID" 5 1 -file "$ARTIFACT/main-sample.txt"
    /usr/bin/sample "$APP_PID" 5 1 -file "$ARTIFACT/main-sample.txt" >>"$ARTIFACT/sample.log" 2>&1 || true
  fi
}

capture_restore_trace() {
  local restore_trace_source="/tmp/agentstudio_debug.log"
  local restore_trace_target="$ARTIFACT/restore-trace.log"
  [ -n "$APP_PID" ] || return 0
  [ -f "$restore_trace_source" ] || return 0
  grep "pid=$APP_PID " "$restore_trace_source" >"$restore_trace_target" 2>/dev/null || true
}

summarize_traces() {
  capture_restore_trace
  local jsonl_file
  jsonl_file="$(find "$TRACE_DIR" -name "agentstudio-$TRACE_NAME-*.jsonl" -type f -print | head -n 1)"
  {
    echo "artifact=$ARTIFACT"
    echo "trace_name=$TRACE_NAME"
    echo "workspace_file=$WORKSPACE_FILE"
    echo "app_data_dir=$APP_DATA_DIR"
    echo "fixture_root=$FIXTURE_ROOT"
    echo "repo_count=$REPO_COUNT"
    echo "worktree_count=$WORKTREE_COUNT"
    echo "active_pane_count=$ACTIVE_PANE_COUNT"
    echo "writer_count=$WRITER_COUNT"
    echo "duration_seconds=$DURATION_SECONDS"
    echo "drive_command_bar=$DRIVE_COMMAND_BAR"
    echo "app_pid=$APP_PID"
    echo "jsonl_file=$jsonl_file"
    [ -f "$ARTIFACT/restore-trace.log" ] && echo "restore_trace_file=$ARTIFACT/restore-trace.log"
    if [ -n "$jsonl_file" ] && [ -f "$jsonl_file" ]; then
      for event_name in \
        performance.git.tick \
        performance.git.admission \
        performance.git.status \
        performance.git.snapshot_dedup \
        performance.git.event_posted \
        performance.coordinator.write \
        performance.topology.repo_and_worktree \
        performance.tabbar.refresh \
        performance.commandbar.items \
        performance.commandbar.filter
      do
        local count
        count="$(grep -c "\"body\":\"$event_name\"" "$jsonl_file" || true)"
        echo "$event_name count=$count"
      done
    fi
  } | tee "$SUMMARY_FILE"
}

prepare_fixture

{
  echo "trace_name=$TRACE_NAME"
  echo "artifact=$ARTIFACT"
  echo "workspace_file=$WORKSPACE_FILE"
  echo "app_data_dir=$APP_DATA_DIR"
  echo "fixture_root=$FIXTURE_ROOT"
  echo "repo_count=$REPO_COUNT"
  echo "worktree_count=$WORKTREE_COUNT"
  echo "active_pane_count=$ACTIVE_PANE_COUNT"
} >"$ARTIFACT/observability-state.env"

if [ "$prepare_only" = true ]; then
  summarize_traces
  echo "prepared fixture only: $ARTIFACT"
  exit 0
fi

resolve_app_launch_target
TRACE_BACKEND="$(select_trace_backend)"
launch_app "$APP_BINARY" "$TRACE_BACKEND"

if ! wait_for_trace_event performance.coordinator.write 45; then
  echo "did not observe performance.coordinator.write within startup timeout" >&2
  sample_app
  summarize_traces
  exit 1
fi

if ! drive_command_bar_smoke; then
  echo "command-bar smoke did not run; see $ARTIFACT/commandbar-smoke.log" >&2
fi

start_writers
sample_app

for writer_pid in "${WRITER_PIDS[@]}"; do
  wait "$writer_pid" >/dev/null 2>&1 || true
done

if ! wait_for_trace_event performance.git.status 30; then
  echo "did not observe performance.git.status after busy workload" >&2
  summarize_traces
  exit 1
fi

if [ "$DRIVE_COMMAND_BAR" = "1" ] && ! wait_for_command_bar_repo_filter_event 10; then
  echo "did not observe non-empty performance.commandbar.filter after startup command-bar repo filter smoke" >&2
  summarize_traces
  exit 1
fi

summarize_traces
echo "git refresh performance workload proof: $ARTIFACT"
