#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_HELPER="${SHRAVAN_OBSERVABILITY_STACK_HELPER:-$HOME/dev/devfiles/shared/observability/observability-stack}"
COLLECTOR_HEALTH_URL="${SHRAVAN_OBSERVABILITY_COLLECTOR_HEALTH_URL:-http://127.0.0.1:13133/}"
LOGS_QUERY_URL="${SHRAVAN_OBSERVABILITY_LOGS_QUERY_URL:-http://127.0.0.1:9428/select/logsql/query}"

DEFAULT_PROOF_ROOT="$PROJECT_ROOT/tmp/debug-workflows/2026-06-11-agent-studio-performance-issues-cmdp-slowdown/proofs"
DEFAULT_UI_PROOF_ROOT="/tmp/asperf"

usage() {
  cat <<'USAGE'
Usage: verify-git-refresh-performance-workload.sh [--prepare-only]

Creates a disposable 118-repo / 163-worktree / 14-pane AgentStudio workspace,
launches AgentStudio through the standard per-worktree debug observability
runner, runs five fixture git writers, and captures marker-scoped VictoriaLogs
performance evidence.

Environment overrides:
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
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE
                                      State file passed through to the standard debug runner.

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
DEBUG_OBSERVABILITY_STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
DEBUG_IDENTITY_FILE="$ARTIFACT/debug-identity.env"
DEBUG_STATE_COPY="$ARTIFACT/debug-observability.env"

APP_PID=""
APP_BINARY=""
APP_LAUNCH_BUNDLE=""
QUERY_START=""
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

decode_env_file_value() {
  local env_file="$1"
  local lookup_key="$2"
  [ -f "$env_file" ] || return 1
  local raw_value
  raw_value="$(sed -n "s/^$lookup_key=//p" "$env_file" | tail -1)"
  [ -n "$raw_value" ] || return 1
  /usr/bin/python3 - "$raw_value" <<'PY'
import shlex
import sys

try:
    parsed = shlex.split(sys.argv[1])
except ValueError:
    parsed = []
print(parsed[0] if parsed else "")
PY
}

load_debug_identity_for_workload() {
  mkdir -p "$ARTIFACT"
  log_command "$PROJECT_ROOT/scripts/run-debug-observability.sh" --print-identity
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$DEBUG_OBSERVABILITY_STATE_FILE" \
    "$PROJECT_ROOT/scripts/run-debug-observability.sh" --print-identity >"$DEBUG_IDENTITY_FILE"
  APP_DATA_DIR="$(decode_env_file_value "$DEBUG_IDENTITY_FILE" AGENTSTUDIO_OBSERVABILITY_DATA_DIR)"
  TRACE_DIR="$APP_DATA_DIR/traces"
  if [ -z "$APP_DATA_DIR" ] || [ -z "$TRACE_DIR" ]; then
    echo "debug identity did not provide data/trace directories: $DEBUG_IDENTITY_FILE" >&2
    exit 1
  fi
}

preflight_debug_observability_idle() {
  log_command "$PROJECT_ROOT/scripts/run-debug-observability.sh" --preflight-idle
  AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$DEBUG_OBSERVABILITY_STATE_FILE" \
    "$PROJECT_ROOT/scripts/run-debug-observability.sh" --preflight-idle
}

fail_if_trace_marker_would_reuse_jsonl() {
  if find "$TRACE_DIR" -maxdepth 1 -name "agentstudio-$TRACE_NAME-*.jsonl" -type f -print -quit 2>/dev/null |
    grep -q .
  then
    echo "trace marker already has JSONL files in $TRACE_DIR: $TRACE_NAME" >&2
    echo "Choose a fresh AGENTSTUDIO_TRACE_NAME before running workload proof." >&2
    exit 1
  fi
}

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

launch_debug_observability_app() {
  if [ ! -x "$STACK_HELPER" ]; then
    echo "observability stack helper not executable: $STACK_HELPER" >&2
    exit 1
  fi
  if ! curl --fail --silent --show-error --max-time 2 "$COLLECTOR_HEALTH_URL" >/dev/null; then
    echo "OTLP collector is not healthy at $COLLECTOR_HEALTH_URL" >&2
    echo "Run: mise run observability:up" >&2
    exit 1
  fi

  local launcher_env=(
    "AGENTSTUDIO_OBSERVABILITY_STATE_FILE=$DEBUG_OBSERVABILITY_STATE_FILE"
    "AGENTSTUDIO_TRACE_TAGS=${AGENTSTUDIO_TRACE_TAGS:-*}"
    "AGENTSTUDIO_TRACE_FLUSH=immediate"
    "AGENTSTUDIO_TRACE_NAME=$TRACE_NAME"
    "AGENTSTUDIO_TRACE_DIR=$TRACE_DIR"
  )
  if [ "$DRIVE_COMMAND_BAR" = "1" ]; then
    launcher_env+=("AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=command-bar-repo-filter")
  fi

  log_command env "${launcher_env[@]}" "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach
  env "${launcher_env[@]}" "$PROJECT_ROOT/scripts/run-debug-observability.sh" --detach \
    >"$ARTIFACT/run-debug-observability.log" 2>&1

  cp "$DEBUG_OBSERVABILITY_STATE_FILE" "$DEBUG_STATE_COPY"
  APP_PID="$(decode_env_file_value "$DEBUG_OBSERVABILITY_STATE_FILE" AGENTSTUDIO_OBSERVABILITY_PID)"
  APP_BINARY="$(decode_env_file_value "$DEBUG_OBSERVABILITY_STATE_FILE" AGENTSTUDIO_OBSERVABILITY_EXECUTABLE)"
  APP_LAUNCH_BUNDLE="$(decode_env_file_value "$DEBUG_OBSERVABILITY_STATE_FILE" AGENTSTUDIO_OBSERVABILITY_APP)"
  QUERY_START="$(decode_env_file_value "$DEBUG_OBSERVABILITY_STATE_FILE" AGENTSTUDIO_OBSERVABILITY_QUERY_START)"
  if [ -z "$APP_PID" ] || [ -z "$APP_BINARY" ]; then
    echo "debug observability state did not include PID/executable: $DEBUG_OBSERVABILITY_STATE_FILE" >&2
    exit 1
  fi
  printf '%s\n' "$APP_PID" >"$PID_DIR/app.pid"

  log_command "$PROJECT_ROOT/scripts/verify-debug-observability.sh"
  local deadline=$((SECONDS + 60))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if AGENTSTUDIO_OBSERVABILITY_STATE_FILE="$DEBUG_OBSERVABILITY_STATE_FILE" \
      "$PROJECT_ROOT/scripts/verify-debug-observability.sh" \
      >"$ARTIFACT/verify-debug-observability.log" 2>&1
    then
      return 0
    fi
    sleep 2
  done
  cat "$ARTIFACT/verify-debug-observability.log" >&2
  return 1
}

query_victoria_logs() {
  local logsql="$1"
  local args=(
    --fail
    --silent
    --show-error
    --max-time 5
    --get
    --data-urlencode "query=$logsql"
  )
  if [ -n "$QUERY_START" ]; then
    args+=(--data-urlencode "start=$QUERY_START")
  fi
  curl "${args[@]}" "$LOGS_QUERY_URL"
}

victoria_event_query() {
  local event_name="$1"
  printf '{service.name="AgentStudio",dev.runtime.flavor="debug",agentstudio.trace.name="%s"} _msg:%s' \
    "$TRACE_NAME" "$event_name"
}

victoria_event_count() {
  local event_name="$1"
  local response
  response="$(query_victoria_logs "$(victoria_event_query "$event_name") | fields _msg | limit 10000" 2>/dev/null || true)"
  if [ -z "$response" ]; then
    printf '0\n'
  else
    printf '%s\n' "$response" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
  fi
}

jsonl_event_count() {
  local event_name="$1"
  local jsonl_file="$2"
  [ -n "$jsonl_file" ] && [ -f "$jsonl_file" ] || {
    printf '0\n'
    return 0
  }
  grep -c "\"body\":\"$event_name\"" "$jsonl_file" || true
}

current_trace_jsonl_files() {
  find "$TRACE_DIR" -maxdepth 1 -name "agentstudio-$TRACE_NAME-*.jsonl" -type f -print 2>/dev/null
}

current_trace_jsonl_has_event() {
  local event_name="$1"
  local jsonl_file
  while IFS= read -r jsonl_file; do
    if grep "\"body\":\"$event_name\"" "$jsonl_file" >/dev/null 2>&1; then
      return 0
    fi
  done < <(current_trace_jsonl_files)
  return 1
}

current_trace_jsonl_has_command_bar_filter() {
  local jsonl_file
  while IFS= read -r jsonl_file; do
    if grep "\"body\":\"performance.commandbar.filter\"" "$jsonl_file" 2>/dev/null \
      | grep -E "\"agentstudio.performance.commandbar.query_character.count\":\"?[1-9][0-9]*\"?" >/dev/null 2>&1
    then
      return 0
    fi
  done < <(current_trace_jsonl_files)
  return 1
}

wait_for_trace_event() {
  local event_name="$1"
  local timeout_seconds="$2"
  local deadline=$((SECONDS + timeout_seconds))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if current_trace_jsonl_has_event "$event_name"; then
      return 0
    fi
    if [ "$(victoria_event_count "$event_name")" -gt 0 ]; then
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
    if current_trace_jsonl_has_command_bar_filter; then
      return 0
    fi
    local victoria_response
    victoria_response="$(
      query_victoria_logs \
        "$(victoria_event_query performance.commandbar.filter) | fields _msg,agentstudio.performance.commandbar.query_character.count | limit 20" \
        2>/dev/null || true
    )"
    if printf '%s\n' "$victoria_response" |
      grep -E "\"agentstudio.performance.commandbar.query_character.count\":\"?[1-9][0-9]*\"?" >/dev/null 2>&1
    then
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
  jsonl_file="$(current_trace_jsonl_files | head -n 1)"
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
    echo "debug_observability_state_file=$DEBUG_OBSERVABILITY_STATE_FILE"
    [ -f "$DEBUG_STATE_COPY" ] && echo "debug_observability_state_copy=$DEBUG_STATE_COPY"
    echo "jsonl_file=$jsonl_file"
    [ -f "$ARTIFACT/restore-trace.log" ] && echo "restore_trace_file=$ARTIFACT/restore-trace.log"
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
      local victoria_count jsonl_count
      victoria_count="$(victoria_event_count "$event_name")"
      jsonl_count="$(jsonl_event_count "$event_name" "$jsonl_file")"
      echo "$event_name victoria_count=$victoria_count jsonl_count=$jsonl_count"
    done
  } | tee "$SUMMARY_FILE"
}

mkdir -p "$ARTIFACT" "$FIXTURE_ROOT" "$PID_DIR"
: >"$COMMAND_LOG"
if [ "$prepare_only" != true ]; then
  load_debug_identity_for_workload
  preflight_debug_observability_idle
  fail_if_trace_marker_would_reuse_jsonl
fi
mkdir -p "$APP_DATA_DIR/workspaces" "$TRACE_DIR"

prepare_fixture

{
  echo "trace_name=$TRACE_NAME"
  echo "artifact=$ARTIFACT"
  echo "workspace_file=$WORKSPACE_FILE"
  echo "app_data_dir=$APP_DATA_DIR"
  echo "debug_observability_state_file=$DEBUG_OBSERVABILITY_STATE_FILE"
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

launch_debug_observability_app

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
