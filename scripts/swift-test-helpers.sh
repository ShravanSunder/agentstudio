#!/usr/bin/env bash
# Shared test helper functions for mise tasks.
#
# Required variables (set by caller before sourcing):
#   LOG_PREFIX         - Log prefix, e.g. "test" or "test-coverage"
#   TIMEOUT_SECONDS    - Timeout in seconds for swift commands
#   PREBUILD_TIMEOUT_SECONDS - Timeout in seconds for the one-time test bundle build
#   RUNNER_WARMUP_TIMEOUT_SECONDS - Optional timeout for a no-test runner launch warmup
#   BUILD_PATH         - Swift build path
#
# Optional variables:
#   EXTRA_SWIFT_TEST_ARGS - Additional swift test flags (e.g. "--enable-code-coverage")
#   XCB_EXTRA_ARGS        - Extra xcbeautify flags (e.g. "--renderer github-actions")
#   SWIFT_TEST_SHARD_BY_CLASS - Set to 1 to run non-WebKit tests in class chunks
#   SWIFT_TEST_SHARD_CLASS_COUNT - Number of test classes per shard (default: 40)
#   SWIFT_TEST_FIRST_SHARD_TIMEOUT_SECONDS - Optional timeout for the first cold class shard
#   SWIFT_TEST_SKIP_BUILD - Set to 0 to let filtered swift test invocations plan/build

# shellcheck source=scripts/xcb-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/xcb-helpers.sh"

prebuild_swift_tests() {
  # shellcheck disable=SC2086
  run_swift_with_timeout \
    "prebuild test bundles" \
    "$PREBUILD_TIMEOUT_SECONDS" \
    swift build --build-tests ${EXTRA_SWIFT_TEST_ARGS:-} --build-path "$BUILD_PATH"
}

warm_swift_test_runner() {
  if [ "${RUNNER_WARMUP_TIMEOUT_SECONDS:-0}" = "0" ]; then
    return 0
  fi

  run_swift_with_timeout \
    "warm swift test runner" \
    "$RUNNER_WARMUP_TIMEOUT_SECONDS" \
    env AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build \
    --filter AgentStudioNoMatchingWarmupSentinel --build-path "$BUILD_PATH"
}

run_non_serialized_swift_tests() {
  local label="$1"

  if [ "${SWIFT_TEST_SHARD_BY_CLASS:-0}" = "1" ]; then
    run_swift_class_shards "$label"
    return $?
  fi

  if [ "${SWIFT_TEST_PARALLEL:-1}" = "1" ]; then
    SWIFT_TEST_WORKERS="${SWIFT_TEST_WORKERS:-$(( $(sysctl -n hw.ncpu) / 2 ))}"
    if [ "$SWIFT_TEST_WORKERS" -lt 2 ]; then SWIFT_TEST_WORKERS=2; fi
    if [ "$SWIFT_TEST_WORKERS" -gt 4 ]; then SWIFT_TEST_WORKERS=4; fi
    run_swift_with_timeout \
      "parallel $label" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --parallel --num-workers "$SWIFT_TEST_WORKERS" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  else
    run_swift_with_timeout \
      "serial $label" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  fi
}

run_swift_class_shards() {
  local label="$1"
  local shard_class_count="${SWIFT_TEST_SHARD_CLASS_COUNT:-40}"
  local class_file
  class_file="$(mktemp "${TMPDIR:-/tmp}/agentstudio-swift-test-classes.XXXXXX")"

  # shellcheck disable=SC2086
  swift test list ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
    --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH" \
    | awk '/^AgentStudio/ { split($0, pathParts, "/"); split(pathParts[1], classParts, "."); print classParts[1] "." classParts[2] }' \
    | LC_ALL=C sort -u >"$class_file"

  local total_classes
  total_classes="$(wc -l <"$class_file" | tr -d '[:space:]')"
  if [ "${total_classes:-0}" -eq 0 ]; then
    echo "[$LOG_PREFIX] ERROR: no Swift test classes found for sharded $label" >&2
    rm -f "$class_file"
    return 1
  fi

  echo "[$LOG_PREFIX] sharding $label into class chunks (${total_classes} classes, ${shard_class_count} per shard)"

  local shard_index=1
  local class_count=0
  local shard_classes=()
  local test_class
  while IFS= read -r test_class; do
    shard_classes+=("$test_class")
    class_count=$((class_count + 1))
    if [ "$class_count" -ge "$shard_class_count" ]; then
      run_swift_class_shard "$shard_index" "${shard_classes[@]}" || {
        local status=$?
        rm -f "$class_file"
        return "$status"
      }
      shard_index=$((shard_index + 1))
      class_count=0
      shard_classes=()
    fi
  done <"$class_file"

  if [ "${#shard_classes[@]}" -gt 0 ]; then
    run_swift_class_shard "$shard_index" "${shard_classes[@]}" || {
      local status=$?
      rm -f "$class_file"
      return "$status"
    }
  fi

  rm -f "$class_file"
}

run_swift_class_shard() {
  local shard_index="$1"
  shift
  local shard_classes=("$@")
  local report_slug
  report_slug="$(printf "class-%02d" "$shard_index")"
  local filter
  filter="$(swift_test_class_filter "${shard_classes[@]}")"
  local label="class shard ${shard_index} (${#shard_classes[@]} classes)"
  local shard_timeout="$TIMEOUT_SECONDS"
  if [ "$shard_index" = "1" ]; then
    shard_timeout="${SWIFT_TEST_FIRST_SHARD_TIMEOUT_SECONDS:-$TIMEOUT_SECONDS}"
  fi

  echo "[$LOG_PREFIX] class shard ${shard_index} classes:"
  printf '  %s\n' "${shard_classes[@]}"

  local shard_xcb_extra_args="${XCB_EXTRA_ARGS:-}"
  if [[ "$shard_xcb_extra_args" == *"--report-path test-results-fast.xml"* ]]; then
    shard_xcb_extra_args="${shard_xcb_extra_args/--report-path test-results-fast.xml/--report-path test-results-fast-${report_slug}.xml}"
  fi

  local skip_build_arg="--skip-build"
  if [ "${SWIFT_TEST_SKIP_BUILD:-1}" = "1" ]; then
    skip_build_arg="--skip-build"
  else
    skip_build_arg=""
  fi

  if [ "${SWIFT_TEST_PARALLEL:-1}" = "1" ]; then
    SWIFT_TEST_WORKERS="${SWIFT_TEST_WORKERS:-$(( $(sysctl -n hw.ncpu) / 2 ))}"
    if [ "$SWIFT_TEST_WORKERS" -lt 2 ]; then SWIFT_TEST_WORKERS=2; fi
    if [ "$SWIFT_TEST_WORKERS" -gt 4 ]; then SWIFT_TEST_WORKERS=4; fi
    XCB_EXTRA_ARGS="$shard_xcb_extra_args" run_swift_with_timeout \
      "$label" \
      "$shard_timeout" \
      env AGENT_STUDIO_BENCHMARK_MODE=off swift test ${EXTRA_SWIFT_TEST_ARGS:-} ${skip_build_arg:+"$skip_build_arg"} \
      --parallel --num-workers "$SWIFT_TEST_WORKERS" \
      --filter "$filter" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  else
    XCB_EXTRA_ARGS="$shard_xcb_extra_args" run_swift_with_timeout \
      "$label" \
      "$shard_timeout" \
      env AGENT_STUDIO_BENCHMARK_MODE=off swift test ${EXTRA_SWIFT_TEST_ARGS:-} ${skip_build_arg:+"$skip_build_arg"} \
      --filter "$filter" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  fi
}

swift_test_class_filter() {
  local separator=""
  local filter="^("
  local test_class
  local escaped_class
  for test_class in "$@"; do
    escaped_class="${test_class//./\\.}"
    filter="${filter}${separator}${escaped_class}"
    separator="|"
  done
  filter="${filter})(/|$)"
  printf "%s" "$filter"
}

webkit_suite_filters() {
  cat <<'EOF'
WebKitSerializedTests/BridgePaneControllerTests
WebKitSerializedTests/BridgeSchemeHandlerSpikeTests
WebKitSerializedTests/BridgeContentWorldIsolationTests
WebKitSerializedTests/BridgeTransportIntegrationTests
WebKitSerializedTests/BridgeWebKitSpikeTests
WebKitSerializedTests/InboxPostHandlerTests
WebKitSerializedTests/InboxNotificationBridgeWebKitIntegrationTests
WebKitSerializedTests/WorkspaceSurfaceBridgeFilesystemRefreshTests
WebKitSerializedTests/WebviewPaneControllerTests
EOF
}

run_webkit_suites() {
  echo "--- WebKit serialized tests (serial) ---"
  while IFS= read -r filter; do
    [ -n "$filter" ] || continue
    run_webkit_suite_with_retry "$filter" || return $?
  done < <(webkit_suite_filters)
}

run_swift_with_timeout() {
  local label="$1"
  shift
  local timeout_seconds="$1"
  shift

  echo "[$LOG_PREFIX] >>> $label (timeout=${timeout_seconds}s)"
  local start_epoch
  start_epoch=$(date +%s)
  local last_heartbeat="$start_epoch"
  local timed_out=0

  local xcb_pipe
  xcb_pipe=$(_xcb_pipe_cmd)
  local output_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/agentstudio-swift-test-output.XXXXXX")"

  # Run command piped through xcbeautify in a subshell so we track one PID.
  # Subshell inherits pipefail from parent — swift exit code propagates.
  # shellcheck disable=SC2086
  ( "$@" 2>&1 | tee "$output_file" | $xcb_pipe ) &
  local command_pid=$!

  while kill -0 "$command_pid" 2>/dev/null; do
    sleep 1
    local now_epoch
    now_epoch=$(date +%s)
    local elapsed_seconds=$((now_epoch - start_epoch))

    if [ "$elapsed_seconds" -ge "$timeout_seconds" ]; then
      timed_out=1
      break
    fi

    if [ $((now_epoch - last_heartbeat)) -ge 20 ]; then
      echo "[$LOG_PREFIX] ... $label still running (${elapsed_seconds}s)"
      last_heartbeat="$now_epoch"
    fi
  done

  if [ "$timed_out" -eq 1 ]; then
    echo "[$LOG_PREFIX] ERROR: timeout while running '$label' after ${timeout_seconds}s"
    echo "[$LOG_PREFIX] raw output tail for '$label':"
    tail -n 120 "$output_file" || true
    terminate_process_tree TERM "$command_pid"
    sleep 2
    terminate_process_tree KILL "$command_pid"
    wait "$command_pid" 2>/dev/null || true
    rm -f "$output_file"
    return 124
  fi

  set +e
  wait "$command_pid"
  local command_status=$?
  set -e

  if [ "$command_status" -eq 0 ] && swift_test_output_has_failures "$output_file"; then
    echo "[$LOG_PREFIX] ERROR: '$label' emitted Swift Testing failure output despite exit 0" >&2
    command_status=1
  fi

  rm -f "$output_file"
  return "$command_status"
}

swift_test_output_has_failures() {
  local output_file="$1"

  grep -Eq \
    '(^|[[:space:]])(✘|✖)[[:space:]]|recorded an issue|failed after [0-9.]+ seconds with [0-9]+ issue\(s\)|Test run with .* failed after' \
    "$output_file"
}

terminate_process_tree() {
  local signal="$1"
  local root_pid="$2"
  local child_pid

  for child_pid in $(pgrep -P "$root_pid" 2>/dev/null || true); do
    terminate_process_tree "$signal" "$child_pid"
  done
  kill -"$signal" "$root_pid" 2>/dev/null || true
}

run_webkit_suite_with_retry() {
  local filter="$1"
  local attempt=1
  local max_attempts=3
  local backoff_seconds=1

  while [ "$attempt" -le "$max_attempts" ]; do
    echo "[webkit] running $filter (attempt $attempt/$max_attempts)"
    set +e
    local output
    # Bypass xcbeautify — we need raw output to detect "unexpected signal code" for retries.
    # Set _XCB_BYPASS on its own line: bash evaluates $() before assignments on the same line.
    _XCB_BYPASS=1
    # shellcheck disable=SC2086
    output=$(run_swift_with_timeout "$filter" "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off swift test ${EXTRA_SWIFT_TEST_ARGS:-} \
      --skip-build --filter "$filter" --build-path "$BUILD_PATH" 2>&1)
    local command_status=$?
    unset _XCB_BYPASS
    set -e
    echo "$output"

    if [ "$command_status" -eq 0 ]; then
      return 0
    fi
    if [ "$command_status" -eq 124 ]; then
      return 124
    fi

    if [ "$command_status" -ne 124 ] && grep -Eq "unexpected signal code [0-9]+" <<<"$output"; then
      local signal_code
      signal_code=$(grep -Eo "unexpected signal code [0-9]+" <<<"$output" | grep -Eo "[0-9]+" | tail -n 1)
      if [ -z "$signal_code" ]; then
        signal_code="unknown"
      fi
      if [ "$attempt" -lt "$max_attempts" ]; then
        echo "[webkit] signal $signal_code in $filter; retrying after ${backoff_seconds}s"
        sleep "$backoff_seconds"
        backoff_seconds=$((backoff_seconds * 2))
        attempt=$((attempt + 1))
        continue
      fi
    fi

    return "$command_status"
  done
}
