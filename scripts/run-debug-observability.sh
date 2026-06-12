#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_HELPER="${SHRAVAN_OBSERVABILITY_STACK_HELPER:-$HOME/dev/devfiles/shared/observability/observability-stack}"
COLLECTOR_HEALTH_URL="${SHRAVAN_OBSERVABILITY_COLLECTOR_HEALTH_URL:-http://127.0.0.1:13133/}"
OPEN_BIN="${AGENTSTUDIO_OPEN_BIN:-/usr/bin/open}"
PGREP_BIN="${AGENTSTUDIO_PGREP_BIN:-/usr/bin/pgrep}"
LSOF_BIN="${AGENTSTUDIO_LSOF_BIN:-/usr/sbin/lsof}"
CURL_BIN="${AGENTSTUDIO_CURL_BIN:-/usr/bin/curl}"
DITTO_BIN="${AGENTSTUDIO_DITTO_BIN:-/usr/bin/ditto}"
CODESIGN_BIN="${AGENTSTUDIO_CODESIGN_BIN:-/usr/bin/codesign}"
CC_BIN="${AGENTSTUDIO_CC_BIN:-/usr/bin/cc}"

usage() {
  cat <<'USAGE'
Usage: run-debug-observability.sh [--build-path <dir>] [--skip-build] [--detach]

Builds the debug AgentStudio binary, wraps it in a per-worktree Debug .app, and
launches that app with full trace tags exported to the already-running shared
Victoria/OTel stack. This helper does not start observability services; run
`mise run observability:up` first.
USAGE
}

set_plist_string() {
  local plist_path="${1:?missing plist path}"
  local key="${2:?missing plist key}"
  local value="${3:?missing plist value}"

  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key \"$value\"" "$plist_path"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string \"$value\"" "$plist_path"
  fi
}

write_state_value() {
  local key="${1:?missing state key}"
  local value="${2:-}"
  printf '%s=%q\n' "$key" "$value"
}

agentstudio_pids_for_binary() {
  local binary_path="${1:?missing binary path}"
  local executable_path
  local pids
  executable_path="$(/usr/bin/python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$binary_path")"
  pids="$("$PGREP_BIN" -x AgentStudio 2>/dev/null || true)"
  [ -n "$pids" ] || return 0

  printf '%s\n' "$pids" |
    while IFS= read -r pid; do
      local txt_output
      if ! txt_output="$("$LSOF_BIN" -a -p "$pid" -d txt -Fn 2>/dev/null)"; then
        echo "unable to inspect running AgentStudio PID $pid with $LSOF_BIN" >&2
        return 2
      fi
      txt_path="$(printf '%s\n' "$txt_output" | sed -n 's/^n//p' | head -1)"
      if [ -z "$txt_path" ]; then
        echo "unable to resolve executable for running AgentStudio PID $pid" >&2
        return 2
      fi
      if [ "$txt_path" = "$executable_path" ]; then
        printf '%s\n' "$pid"
      fi
    done
}

bundle_path_for_executable() {
  local executable_path="${1:?missing executable path}"
  case "$executable_path" in
    *.app/Contents/MacOS/AgentStudio)
      printf '%s\n' "${executable_path%/Contents/MacOS/AgentStudio}"
      ;;
    *.app/Contents/MacOS/AgentStudio.bin)
      printf '%s\n' "${executable_path%/Contents/MacOS/AgentStudio.bin}"
      ;;
  esac
}

bundle_identifier_for_executable() {
  local executable_path="${1:?missing executable path}"
  local bundle_path
  bundle_path="$(bundle_path_for_executable "$executable_path")"
  [ -n "$bundle_path" ] || return 0
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_path/Contents/Info.plist" 2>/dev/null || true
}

app_pid_for_binary() {
  local binary_path="${1:?missing binary path}"
  agentstudio_pids_for_binary "$binary_path" | tail -1
}

running_debug_app_pids() {
  local code="${1:?missing debug code}"
  local expected_bundle_identifier="com.agentstudio.app.debug.d$code"
  local pids
  pids="$("$PGREP_BIN" -x AgentStudio 2>/dev/null || true)"
  [ -n "$pids" ] || return 0

  printf '%s\n' "$pids" |
    while IFS= read -r pid; do
      local txt_output
      if ! txt_output="$("$LSOF_BIN" -a -p "$pid" -d txt -Fn 2>/dev/null)"; then
        echo "unable to inspect running AgentStudio PID $pid with $LSOF_BIN" >&2
        return 2
      fi
      txt_path="$(printf '%s\n' "$txt_output" | sed -n 's/^n//p' | head -1)"
      if [ -z "$txt_path" ]; then
        echo "unable to resolve executable for running AgentStudio PID $pid" >&2
        return 2
      fi
      if [ "$(bundle_identifier_for_executable "$txt_path")" = "$expected_bundle_identifier" ]; then
        printf '%s\n' "$pid"
      fi
    done
}

wait_for_app_pid() {
  local binary_path="${1:?missing binary path}"
  local attempts="${2:-${AGENTSTUDIO_PID_WAIT_ATTEMPTS:-200}}"
  local pid=""

  for _ in $(seq 1 "$attempts"); do
    pid="$(app_pid_for_binary "$binary_path" || true)"
    if [ -n "$pid" ]; then
      printf '%s\n' "$pid"
      return 0
    fi
    sleep 0.1
  done

  return 1
}

open_app() {
  local app_path="${1:?missing app path}"
  local launch_log="${2:?missing launch log}"
  local wait_flag="${3:-}"
  shift 3
  local open_args=("$@")

  for attempt in 1 2 3 4 5; do
    if "$OPEN_BIN" ${wait_flag:+"$wait_flag"} -n "$app_path" "${open_args[@]}"
    then
      return 0
    fi
    sleep "$attempt"
  done

  return 1
}

write_launch_failed_state() {
  local reason="${1:?missing launch failure reason}"
  {
    write_state_value AGENTSTUDIO_OBSERVABILITY_STATUS launch_failed
    write_state_value AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR debug
    write_state_value AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE "$debug_code"
    write_state_value AGENTSTUDIO_OBSERVABILITY_REASON "$reason"
    write_state_value AGENTSTUDIO_OBSERVABILITY_APP "$app_path"
    write_state_value AGENTSTUDIO_OBSERVABILITY_DATA_DIR "$debug_root"
    write_state_value AGENTSTUDIO_OBSERVABILITY_ZMX_DIR "$debug_zmx_dir"
    write_state_value AGENTSTUDIO_OBSERVABILITY_LOG "$launch_log"
    write_state_value AGENTSTUDIO_OBSERVABILITY_BUILD_PATH "$build_path"
  } >"$state_file"
}

worktree_debug_code() {
  local canonical_root
  canonical_root="$(cd "$PROJECT_ROOT" && pwd -P)"
  /usr/bin/python3 - "$canonical_root" <<'PY'
import hashlib
import sys

alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
space = 36 ** 4
digest = hashlib.sha256(sys.argv[1].encode("utf-8")).digest()
value = int.from_bytes(digest[:8], "big") % space
chars = []
for _ in range(4):
    value, digit = divmod(value, 36)
    chars.append(alphabet[digit])
print("".join(reversed(chars)))
PY
}

copy_debug_bundle() {
  local source_binary="${1:?missing source binary}"
  local build_root="${2:?missing build root}"
  local code="${3:?missing debug code}"
  local artifact_root="${4:?missing artifact root}"
  local app_path="$artifact_root/AgentStudio Debug $code.app"
  local app_dir="$app_path/Contents"
  local plist_path="$app_dir/Info.plist"
  local marketing_version="${APP_MARKETING_VERSION:-0.0.1-debug+$code}"
  local build_version="${APP_BUILD_VERSION:-$(git rev-list --count HEAD)}"

  mkdir -p "$app_dir/MacOS" "$app_dir/Resources"
  "$DITTO_BIN" "$source_binary" "$app_dir/MacOS/AgentStudio.bin"

  if [ -f "vendor/zmx/zig-out/bin/zmx" ]; then
    "$DITTO_BIN" "vendor/zmx/zig-out/bin/zmx" "$app_dir/MacOS/zmx"
  fi

  "$DITTO_BIN" "Sources/AgentStudio/Resources/Info.plist" "$plist_path"
  set_plist_string "$plist_path" CFBundleShortVersionString "$marketing_version"
  set_plist_string "$plist_path" CFBundleVersion "$build_version"
  set_plist_string "$plist_path" AgentStudioReleaseChannel stable
  set_plist_string "$plist_path" CFBundleIdentifier "com.agentstudio.app.debug.d$code"
  set_plist_string "$plist_path" CFBundleName "AgentStudio Debug $code"
  set_plist_string "$plist_path" CFBundleDisplayName "Agent Studio Debug $code"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$plist_path" >/dev/null 2>&1 || true
  set_plist_string "$plist_path" UTExportedTypeDeclarations:0:UTTypeIdentifier "com.agentstudio.debug.d$code.tab"
  set_plist_string "$plist_path" UTExportedTypeDeclarations:1:UTTypeIdentifier "com.agentstudio.debug.d$code.newtab"
  set_plist_string "$plist_path" UTExportedTypeDeclarations:2:UTTypeIdentifier "com.agentstudio.debug.d$code.pane"

  "$DITTO_BIN" "Sources/AgentStudio/Resources/AppIcon.icns" "$app_dir/Resources/AppIcon.icns"
  [ -d "Sources/AgentStudio/Resources/terminfo" ] &&
    "$DITTO_BIN" "Sources/AgentStudio/Resources/terminfo" "$app_dir/Resources/terminfo"
  [ -d "Sources/AgentStudio/Resources/ghostty" ] &&
    "$DITTO_BIN" "Sources/AgentStudio/Resources/ghostty" "$app_dir/Resources/ghostty"

  local resource_bundle
  resource_bundle="$(find "$build_root" -path '*/debug/AgentStudio_AgentStudio.bundle' -type d | head -1)"
  [ -n "$resource_bundle" ] && "$DITTO_BIN" "$resource_bundle" "$app_dir/Resources/AgentStudio_AgentStudio.bundle"

  printf '%s\n' "$app_path"
}

write_debug_launcher() {
  local app_path="${1:?missing app path}"
  local debug_root="${2:?missing debug root}"
  local trace_tags="${3:?missing trace tags}"
  local trace_flush="${4:?missing trace flush}"
  local trace_backend="${5:?missing trace backend}"
  local trace_name="${6:?missing trace name}"
  local trace_dir="${7:?missing trace dir}"
  local otlp_endpoint="${8:?missing otlp endpoint}"
  local otlp_protocol="${9:?missing otlp protocol}"
  local app_dir="$app_path/Contents"
  local launcher_path="$app_dir/MacOS/AgentStudio"
  local launcher_source="$app_dir/MacOS/AgentStudioLauncher.c"

  c_string_literal() {
    /usr/bin/python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
  }

  {
    printf '#include <libgen.h>\n'
    printf '#include <limits.h>\n'
    printf '#include <mach-o/dyld.h>\n'
    printf '#include <stdio.h>\n'
    printf '#include <stdlib.h>\n'
    printf '#include <string.h>\n'
    printf '#include <unistd.h>\n\n'
    printf 'int main(int argc, char *argv[]) {\n'
    printf '  (void)argc;\n'
    printf '  setenv("AGENTSTUDIO_DATA_DIR", %s, 1);\n' "$(c_string_literal "$debug_root")"
    printf '  setenv("AGENTSTUDIO_TRACE_TAGS", %s, 1);\n' "$(c_string_literal "$trace_tags")"
    printf '  setenv("AGENTSTUDIO_TRACE_FLUSH", %s, 1);\n' "$(c_string_literal "$trace_flush")"
    printf '  setenv("AGENTSTUDIO_TRACE_BACKEND", %s, 1);\n' "$(c_string_literal "$trace_backend")"
    printf '  setenv("AGENTSTUDIO_TRACE_NAME", %s, 1);\n' "$(c_string_literal "$trace_name")"
    printf '  setenv("AGENTSTUDIO_TRACE_DIR", %s, 1);\n' "$(c_string_literal "$trace_dir")"
    printf '  setenv("OTEL_EXPORTER_OTLP_ENDPOINT", %s, 1);\n' "$(c_string_literal "$otlp_endpoint")"
    printf '  setenv("OTEL_EXPORTER_OTLP_PROTOCOL", %s, 1);\n' "$(c_string_literal "$otlp_protocol")"
    printf '  char executable_path[PATH_MAX];\n'
    printf '  uint32_t executable_path_size = sizeof(executable_path);\n'
    printf '  if (_NSGetExecutablePath(executable_path, &executable_path_size) != 0) {\n'
    printf '    fprintf(stderr, "AgentStudio launcher path exceeded PATH_MAX\\n");\n'
    printf '    return 126;\n'
    printf '  }\n'
    printf '  char resolved_path[PATH_MAX];\n'
    printf '  if (realpath(executable_path, resolved_path) == NULL) {\n'
    printf '    perror("realpath");\n'
    printf '    return 126;\n'
    printf '  }\n'
    printf '  char directory_buffer[PATH_MAX];\n'
    printf '  strlcpy(directory_buffer, resolved_path, sizeof(directory_buffer));\n'
    printf '  char target_path[PATH_MAX];\n'
    printf '  snprintf(target_path, sizeof(target_path), "%%s/AgentStudio.bin", dirname(directory_buffer));\n'
    printf '  execv(target_path, argv);\n'
    printf '  perror("execv AgentStudio.bin");\n'
    printf '  return 127;\n'
    printf '}\n'
  } >"$launcher_source"

  "$CC_BIN" "$launcher_source" -o "$launcher_path"
  rm -f "$launcher_source"
}

sign_debug_bundle() {
  local app_path="${1:?missing app path}"
  local app_dir="$app_path/Contents"
  local entitlements="Sources/AgentStudio/Resources/AgentStudio.entitlements"

  "$CODESIGN_BIN" --force --sign - --entitlements "$entitlements" "$app_dir/MacOS/AgentStudio" >/dev/null
  "$CODESIGN_BIN" --force --sign - --entitlements "$entitlements" "$app_dir/MacOS/AgentStudio.bin" >/dev/null
  if [ -f "$app_dir/MacOS/zmx" ]; then
    "$CODESIGN_BIN" --force --sign - --entitlements "$entitlements" "$app_dir/MacOS/zmx" >/dev/null
  fi
  "$CODESIGN_BIN" --force --deep --sign - "$app_path" >/dev/null
  "$CODESIGN_BIN" --verify --deep --strict "$app_path"
}

build_path="${AGENTSTUDIO_DEBUG_BUILD_PATH:-.build-agent-review}"
skip_build=false
detach=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --build-path)
      build_path="${2:?missing value for --build-path}"
      shift 2
      ;;
    --skip-build)
      skip_build=true
      shift
      ;;
    --detach)
      detach=true
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

cd "$PROJECT_ROOT"

if [ ! -x "$STACK_HELPER" ]; then
  echo "observability stack helper not executable: $STACK_HELPER" >&2
  exit 1
fi

if ! "$CURL_BIN" --fail --silent --show-error --max-time 2 "$COLLECTOR_HEALTH_URL" >/dev/null; then
  echo "OTLP collector is not healthy at $COLLECTOR_HEALTH_URL" >&2
  echo "Run: mise run observability:up" >&2
  exit 1
fi

debug_code="$(worktree_debug_code)"
debug_root="$HOME/.agentstudio-db/$debug_code"
debug_zmx_dir="$debug_root/z"
state_file="${AGENTSTUDIO_OBSERVABILITY_STATE_FILE:-$PROJECT_ROOT/tmp/debug-observability/latest-observability.env}"
if ! existing_pids="$(running_debug_app_pids "$debug_code" | paste -sd ' ' -)"; then
  mkdir -p "$(dirname "$state_file")"
  {
    write_state_value AGENTSTUDIO_OBSERVABILITY_STATUS launch_failed
    write_state_value AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR debug
    write_state_value AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE "$debug_code"
    write_state_value AGENTSTUDIO_OBSERVABILITY_REASON duplicate_attribution_failed
    write_state_value AGENTSTUDIO_OBSERVABILITY_DATA_DIR "$debug_root"
    write_state_value AGENTSTUDIO_OBSERVABILITY_ZMX_DIR "$debug_zmx_dir"
  } >"$state_file"
  echo "Unable to verify whether Agent Studio Debug $debug_code is already running." >&2
  echo "Refusing to launch because duplicate debug apps would share data and zmx roots." >&2
  echo "observability state: $state_file" >&2
  exit 1
fi
if [ -n "$existing_pids" ]; then
  mkdir -p "$(dirname "$state_file")"
  {
    write_state_value AGENTSTUDIO_OBSERVABILITY_STATUS already_running
    write_state_value AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR debug
    write_state_value AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE "$debug_code"
    write_state_value AGENTSTUDIO_OBSERVABILITY_PID "$existing_pids"
    write_state_value AGENTSTUDIO_OBSERVABILITY_DATA_DIR "$debug_root"
    write_state_value AGENTSTUDIO_OBSERVABILITY_ZMX_DIR "$debug_zmx_dir"
  } >"$state_file"
  echo "Agent Studio Debug $debug_code is already running: PID(s) $existing_pids" >&2
  echo "Quit that debug app before launching another observability run for this worktree." >&2
  echo "observability state: $state_file" >&2
  exit 1
fi

if [ "$skip_build" = false ]; then
  swift build --build-path "$build_path"
fi

binary_path="$build_path/debug/AgentStudio"
if [ ! -x "$binary_path" ]; then
  echo "debug AgentStudio executable not found: $binary_path" >&2
  exit 1
fi

artifact_parent="${AGENTSTUDIO_DEBUG_ARTIFACT_DIR:-$PROJECT_ROOT/tmp/debug-observability/$debug_code/app-$(date +%Y%m%d%H%M%S)-$$}"
app_path="$(copy_debug_bundle "$binary_path" "$build_path" "$debug_code" "$artifact_parent")"
app_binary_path="$app_path/Contents/MacOS/AgentStudio.bin"

trace_tags="${AGENTSTUDIO_TRACE_TAGS:-*}"
trace_flush="${AGENTSTUDIO_TRACE_FLUSH:-immediate}"
trace_backend=otlp
trace_name="${AGENTSTUDIO_TRACE_NAME:-debug-observability-$debug_code-$(date +%s)-$$}"
trace_dir="${AGENTSTUDIO_TRACE_DIR:-$PROJECT_ROOT/tmp/debug-observability/$debug_code/traces}"
otlp_endpoint="$("$STACK_HELPER" collector-url)"
otlp_protocol=http/protobuf

launch_log="${AGENTSTUDIO_OBSERVABILITY_LAUNCH_LOG:-$PROJECT_ROOT/tmp/debug-observability/$debug_code/$trace_name.log}"
mkdir -p "$(dirname "$launch_log")" "$(dirname "$state_file")" "$trace_dir" "$debug_root"
: >"$launch_log"
query_start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "launching debug with OTLP collector: $otlp_endpoint"
echo "debug code: $debug_code"
echo "app: $app_path"
echo "data root: $debug_root"
echo "zmx dir: $debug_zmx_dir"
echo "marker: $trace_name"

write_debug_launcher "$app_path" "$debug_root" "$trace_tags" "$trace_flush" "$trace_backend" "$trace_name" "$trace_dir" "$otlp_endpoint" "$otlp_protocol"
sign_debug_bundle "$app_path"

if [ "$detach" = true ]; then
  if ! open_app "$app_path" "$launch_log" ""; then
    write_launch_failed_state launchservices_open_failed
    echo "LaunchServices open failed for debug app; GUI observability proof was not started." >&2
    echo "Use an accepted app bundle or run beta proof against an installed notarized beta." >&2
    echo "observability state: $state_file" >&2
    exit 1
  fi
  if ! pid="$(wait_for_app_pid "$app_binary_path")"; then
    write_launch_failed_state launchservices_pid_not_found
    echo "LaunchServices started but Agent Studio Debug PID was not found." >&2
    echo "observability state: $state_file" >&2
    exit 1
  fi
else
  open_app "$app_path" "$launch_log" "-W" &
  open_pid=$!
  if ! pid="$(wait_for_app_pid "$app_binary_path")"; then
    if kill -0 "$open_pid" >/dev/null 2>&1; then
      failure_reason=launchservices_pid_not_found
      kill "$open_pid" >/dev/null 2>&1 || true
      wait "$open_pid" >/dev/null 2>&1 || true
    elif wait "$open_pid" >/dev/null 2>&1; then
      failure_reason=launchservices_pid_not_found
    else
      failure_reason=launchservices_open_failed
    fi
    write_launch_failed_state "$failure_reason"
    echo "LaunchServices started but Agent Studio Debug PID was not found." >&2
    echo "observability state: $state_file" >&2
    exit 1
  fi
fi

{
  write_state_value AGENTSTUDIO_OBSERVABILITY_MARKER "$trace_name"
  write_state_value AGENTSTUDIO_OBSERVABILITY_RUNTIME_FLAVOR debug
  write_state_value AGENTSTUDIO_OBSERVABILITY_DEBUG_CODE "$debug_code"
  write_state_value AGENTSTUDIO_OBSERVABILITY_QUERY_START "$query_start"
  write_state_value AGENTSTUDIO_OBSERVABILITY_PID "$pid"
  write_state_value AGENTSTUDIO_OBSERVABILITY_APP "$app_path"
  write_state_value AGENTSTUDIO_OBSERVABILITY_DATA_DIR "$debug_root"
  write_state_value AGENTSTUDIO_OBSERVABILITY_ZMX_DIR "$debug_zmx_dir"
  write_state_value AGENTSTUDIO_OBSERVABILITY_LOG "$launch_log"
  write_state_value AGENTSTUDIO_OBSERVABILITY_BUILD_PATH "$build_path"
} >"$state_file"

echo "pid: $pid"
echo "log: $launch_log"
echo "observability state: $state_file"

if [ "$detach" = false ]; then
  terminate_child() {
    kill "$pid" >/dev/null 2>&1 || true
    wait "$open_pid" >/dev/null 2>&1 || true
    exit 0
  }
  trap terminate_child INT TERM
  set +e
  wait "$open_pid"
  child_status=$?
  set -e
  case "$child_status" in
    0|130|143)
      exit 0
      ;;
    *)
      exit "$child_status"
      ;;
  esac
fi
