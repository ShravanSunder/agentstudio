#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
DITTO_BIN="${AGENTSTUDIO_DITTO_BIN:-/usr/bin/ditto}"
STAT_BIN="${AGENTSTUDIO_STAT_BIN:-/usr/bin/stat}"
replacement_executable=""
dry_run=true
acknowledged=false

usage() {
  cat <<'USAGE'
Usage: replace-running-debug-app-for-tcc-probe.sh [--state-file <path>] [--replacement-executable <path>] [--dry-run]
       AGENTSTUDIO_TCC_REPLACEMENT_EXPERIMENT=1 replace-running-debug-app-for-tcc-probe.sh --acknowledge-mutates-generated-debug-app

Replaces only the executable inside the generated per-worktree AgentStudio
Debug .app recorded in a debug observability state file. This is intentionally
not a Homebrew, beta, stable, or /Applications updater. It exists only to
simulate a running app's on-disk executable identity changing while the
tcc-upgrade-probe monitor is active.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --state-file)
      STATE_FILE="${2:?missing value for --state-file}"
      shift 2
      ;;
    --replacement-executable)
      replacement_executable="${2:?missing value for --replacement-executable}"
      shift 2
      ;;
    --acknowledge-mutates-generated-debug-app)
      acknowledged=true
      dry_run=false
      shift
      ;;
    --dry-run)
      dry_run=true
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

decode_state_value() {
  local raw_value="${1:-}"
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

realpath_value() {
  /usr/bin/python3 - "$1" <<'PY'
import os
import sys

print(os.path.realpath(sys.argv[1]) if sys.argv[1] else "")
PY
}

file_identity() {
  local file_path="${1:?missing file path}"
  if [ ! -e "$file_path" ]; then
    printf 'missing\n'
    return 0
  fi
  "$STAT_BIN" -f 'dev=%d inode=%i size=%z mtime=%m path=%N' "$file_path"
}

state_status=""
state_runtime_flavor=""
state_debug_code=""
state_app=""
state_executable=""
state_build_path=""
state_startup_diagnostic_action=""
if [ -f "$STATE_FILE" ]; then
  while IFS='=' read -r key value || [ -n "$key" ]; do
    decoded_value="$(decode_state_value "$value")"
    case "$key" in
      AGENTSTUDIO_OBSERVABILITY_STATUS)
        state_status="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR)
        state_runtime_flavor="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE)
        state_debug_code="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_APP)
        state_app="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_EXECUTABLE)
        state_executable="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_BUILD_PATH)
        state_build_path="$decoded_value"
        ;;
      AGENTSTUDIO_OBSERVABILITY_STARTUP_DIAGNOSTIC_ACTION)
        state_startup_diagnostic_action="$decoded_value"
        ;;
    esac
  done <"$STATE_FILE"
fi

if [ "$state_status" != "running" ]; then
  echo "debug observability state is not running: ${state_status:-<missing>}" >&2
  echo "state file: $STATE_FILE" >&2
  exit 1
fi
if [ "$state_runtime_flavor" != "debug" ]; then
  echo "refusing to mutate non-debug observability runtime: ${state_runtime_flavor:-<missing>}" >&2
  exit 1
fi
if [ "$state_startup_diagnostic_action" != "tcc-upgrade-probe" ]; then
  echo "refusing state that is not running tcc-upgrade-probe: ${state_startup_diagnostic_action:-<missing>}" >&2
  exit 1
fi
if [ -z "$state_debug_code" ] || [ -z "$state_app" ] || [ -z "$state_executable" ]; then
  echo "debug observability state is missing debug code, app path, or executable path" >&2
  exit 1
fi

app_realpath="$(realpath_value "$state_app")"
executable_realpath="$(realpath_value "$state_executable")"
expected_debug_root="$(realpath_value "$HOME/.agentstudio-db/$state_debug_code")"
expected_apps_root="$expected_debug_root/apps"
expected_app_suffix="/AgentStudio Debug $state_debug_code.app"

case "$app_realpath" in
  "$expected_apps_root"/*"$expected_app_suffix")
    ;;
  *)
    echo "refusing to mutate app outside generated debug app root" >&2
    echo "expected root: $expected_apps_root" >&2
    echo "actual app: $app_realpath" >&2
    exit 1
    ;;
esac

case "$executable_realpath" in
  "$app_realpath/Contents/MacOS/AgentStudio")
    ;;
  *)
    echo "refusing state executable outside generated debug app bundle" >&2
    echo "app: $app_realpath" >&2
    echo "executable: $executable_realpath" >&2
    exit 1
    ;;
esac

if [ -z "$replacement_executable" ]; then
  replacement_executable="$state_build_path/debug/AgentStudio"
fi
replacement_realpath="$(realpath_value "$replacement_executable")"
if [ ! -x "$replacement_realpath" ]; then
  echo "replacement executable is not executable: $replacement_realpath" >&2
  exit 1
fi

if [ "$dry_run" = false ]; then
  if [ "$acknowledged" != true ] || [ "${AGENTSTUDIO_TCC_REPLACEMENT_EXPERIMENT:-0}" != "1" ]; then
    echo "refusing mutation without --acknowledge-mutates-generated-debug-app and AGENTSTUDIO_TCC_REPLACEMENT_EXPERIMENT=1" >&2
    exit 2
  fi
fi

echo "tcc replacement experiment target:"
echo "state file: $STATE_FILE"
echo "debug code: $state_debug_code"
echo "app: $app_realpath"
echo "target executable: $executable_realpath"
echo "replacement executable: $replacement_realpath"
echo "target identity before: $(file_identity "$executable_realpath")"
echo "replacement identity: $(file_identity "$replacement_realpath")"

if [ "$dry_run" = true ]; then
  echo "dry run: no files mutated"
  exit 0
fi

"$DITTO_BIN" "$replacement_realpath" "$executable_realpath"
chmod 755 "$executable_realpath"
echo "target identity after: $(file_identity "$executable_realpath")"
echo "mutation complete: generated debug app executable replaced"
