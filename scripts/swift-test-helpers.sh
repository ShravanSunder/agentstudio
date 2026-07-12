#!/usr/bin/env bash
# Shared test helper functions for mise tasks.
#
# Required variables (set by caller before sourcing):
#   LOG_PREFIX         - Log prefix, e.g. "test" or "test-coverage"
#   TIMEOUT_SECONDS    - Timeout in seconds for swift commands
#   PREBUILD_TIMEOUT_SECONDS - Timeout in seconds for the one-time test bundle build
#   BUILD_PATH         - Swift build path
#
# Optional variables:
#   EXTRA_SWIFT_TEST_ARGS - Additional swift test flags (e.g. "--enable-code-coverage")
#   XCB_EXTRA_ARGS        - Extra xcbeautify flags (e.g. "--renderer github-actions")

# shellcheck source=scripts/xcb-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/xcb-helpers.sh"

large_non_webkit_filter_pattern() {
  local patterns=(
    Script
    Smoke
    Integration
    ZmxStartupTraceAnalyzerTests
    WorkspaceSurfaceCoordinatorFilesystemSourceTests
    TerminalActivityAgentSettledHeuristicTests
    MainWindowControllerInboxToolbarButtonTests
    ProcessExecutorTests
    AgentStudioAppIPCServiceAuthModeTests
    AgentStudioAppIPCServiceContributionTests
    AgentStudioIPCBridgeServiceTests
    AgentStudioAppIPCCommandExecuteContractTests
  )
  local IFS="|"
  echo "${patterns[*]}"
}

large_serial_non_webkit_filter_pattern() {
  local patterns=(
    AgentStudioAppIPCServiceCommandTests
    PaneAgentLaunchOwnerTests
  )
  local IFS="|"
  echo "${patterns[*]}"
}

prebuild_swift_tests() {
  # shellcheck disable=SC2086
  run_swift_with_timeout \
    "prebuild test bundles" \
    "$PREBUILD_TIMEOUT_SECONDS" \
    swift build --build-tests ${EXTRA_SWIFT_TEST_ARGS:-} --build-path "$BUILD_PATH"
}

run_non_serialized_swift_tests() {
  local label="$1"

  if [ "${SWIFT_TEST_PARALLEL:-1}" = "1" ]; then
    SWIFT_TEST_WORKERS="${SWIFT_TEST_WORKERS:-$(( $(sysctl -n hw.ncpu) / 2 ))}"
    if [ "$SWIFT_TEST_WORKERS" -lt 2 ]; then SWIFT_TEST_WORKERS=2; fi
    if [ "$SWIFT_TEST_WORKERS" -gt 4 ]; then SWIFT_TEST_WORKERS=4; fi
    run_swift_with_timeout \
      "parallel $label" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --parallel --num-workers "$SWIFT_TEST_WORKERS" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  else
    run_swift_with_timeout \
      "serial $label" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  fi
}

run_fast_non_webkit_swift_tests() {
  if [ "${SWIFT_TEST_PARALLEL:-1}" = "1" ]; then
    SWIFT_TEST_WORKERS="${SWIFT_TEST_WORKERS:-$(( $(sysctl -n hw.ncpu) / 2 ))}"
    if [ "$SWIFT_TEST_WORKERS" -lt 2 ]; then SWIFT_TEST_WORKERS=2; fi
    if [ "$SWIFT_TEST_WORKERS" -gt 4 ]; then SWIFT_TEST_WORKERS=4; fi
    run_swift_with_timeout \
      "parallel fast non-WebKit suites" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --parallel --num-workers "$SWIFT_TEST_WORKERS" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests \
      --skip "Benchmark|AgentStudioAppIPCServiceTests|$(large_non_webkit_filter_pattern)|$(large_serial_non_webkit_filter_pattern)" --build-path "$BUILD_PATH"
  else
    run_swift_with_timeout \
      "serial fast non-WebKit suites" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests \
      --skip "Benchmark|AgentStudioAppIPCServiceTests|$(large_non_webkit_filter_pattern)|$(large_serial_non_webkit_filter_pattern)" --build-path "$BUILD_PATH"
  fi

  run_swift_with_timeout \
    "serial App IPC service live socket suite" \
    "$TIMEOUT_SECONDS" \
    env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
    --filter AgentStudioAppIPCServiceTests --build-path "$BUILD_PATH"
}

run_large_non_webkit_swift_tests() {
  if [ "${SWIFT_TEST_PARALLEL:-1}" = "1" ]; then
    SWIFT_TEST_WORKERS="${SWIFT_TEST_WORKERS:-$(( $(sysctl -n hw.ncpu) / 2 ))}"
    if [ "$SWIFT_TEST_WORKERS" -lt 2 ]; then SWIFT_TEST_WORKERS=2; fi
    if [ "$SWIFT_TEST_WORKERS" -gt 4 ]; then SWIFT_TEST_WORKERS=4; fi
    run_swift_with_timeout \
      "parallel large non-WebKit suites" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --parallel --num-workers "$SWIFT_TEST_WORKERS" \
      --filter "$(large_non_webkit_filter_pattern)" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"

    run_swift_with_timeout \
      "serial large process suites" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --filter "$(large_serial_non_webkit_filter_pattern)" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  else
    run_swift_with_timeout \
      "serial large non-WebKit suites" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --filter "$(large_non_webkit_filter_pattern)|$(large_serial_non_webkit_filter_pattern)" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  fi
}

webkit_suite_filters() {
  cat <<'EOF'
WebKitSerializedTests/BridgePaneControllerTests
WebKitSerializedTests/BridgePaneControllerContentAuthorityTests
WebKitSerializedTests/BridgeSchemeHandlerSpikeTests
WebKitSerializedTests/BridgeContentWorldIsolationTests
WebKitSerializedTests/BridgePaneControllerIPCProjectionTests
WebKitSerializedTests/BridgeTransportIntegrationTests/test_bridgeReady_gatesAndIsIdempotent
WebKitSerializedTests/BridgeTransportIntegrationTests/test_teardown_resetsBridgeReady
WebKitSerializedTests/BridgeTransportIntegrationTests/test_pushJSON_transportFailure_setsConnectionHealthError
WebKitSerializedTests/BridgeTransportIntegrationTests/test_requestWithId_emitsBridgeResponseEvent
WebKitSerializedTests/BridgeTransportIntegrationTests/test_schemeHandler_servesAppHtml
WebKitSerializedTests/BridgeTransportIntegrationTests/test_intakeSnapshotFrame_rendersReviewViewerShell
WebKitSerializedTests/BridgeTransportIntegrationTests/test_pushJSON_concurrentBurstDeliversOrderedPageEvents
WebKitSerializedTests/BridgeIntakeCarrierWebKitTests
WebKitSerializedTests/BridgeTransportIntegrationTests/test_contentFetch_traceparentHeaderReachesCustomSchemeHandler
WebKitSerializedTests/BridgeTransportIntegrationTests/test_contentFetch_realDiffHandlesResolveAndDoNotRejectThroughReviewViewer
WebKitSerializedTests/BridgeWebKitSpikeTests
WebKitSerializedTests/InboxPostHandlerTests
WebKitSerializedTests/InboxNotificationBridgeWebKitIntegrationTests
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
    print_timeout_process_diagnostics "$label" "$command_pid"
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

print_timeout_process_diagnostics() {
  local label="$1"
  local root_pid="$2"

  echo "[$LOG_PREFIX] process tree for timed out '$label' (root pid=$root_pid):"
  print_timeout_process_tree "$root_pid" 0
  print_timeout_process_snapshot "$label" "$root_pid"
  sample_stuck_swift_test_processes "$label" "$root_pid"
}

print_timeout_process_tree() {
  local root_pid="$1"
  local indent_columns="$2"
  local process_command

  process_command="$(ps -p "$root_pid" -o command= 2>/dev/null || true)"
  [ -n "$process_command" ] || return 0
  printf '[%s] %*s%s %s\n' "$LOG_PREFIX" "$indent_columns" "" "$root_pid" "$process_command"

  local child_pid
  for child_pid in $(pgrep -P "$root_pid" 2>/dev/null || true); do
    print_timeout_process_tree "$child_pid" $((indent_columns + 2))
  done
}

print_timeout_process_snapshot() {
  local label="$1"
  local root_pid="$2"

  echo "[$LOG_PREFIX] ps snapshot for timed out '$label':"
  echo "[$LOG_PREFIX]   PID  PPID  PGID STAT ELAPSED COMMAND"

  local process_pid
  for process_pid in "$root_pid" $(descendant_process_pids "$root_pid"); do
    ps -o pid=,ppid=,pgid=,stat=,etime=,command= -p "$process_pid" 2>/dev/null |
      sed "s/^/[$LOG_PREFIX] /" || true
  done
}

descendant_process_pids() {
  local root_pid="$1"
  local child_pid

  for child_pid in $(pgrep -P "$root_pid" 2>/dev/null || true); do
    echo "$child_pid"
    descendant_process_pids "$child_pid"
  done
}

sample_stuck_swift_test_processes() {
  local label="$1"
  local root_pid="$2"
  local sampled_count=0

  if [ ! -x /usr/bin/sample ]; then
    echo "[$LOG_PREFIX] sample unavailable; skipping stuck Swift test stack capture"
    return 0
  fi

  local process_pid
  for process_pid in $(descendant_process_pids "$root_pid"); do
    local process_command
    process_command="$(ps -p "$process_pid" -o command= 2>/dev/null || true)"
    case "$process_command" in
      *AgentStudioPackageTests* | *.xctest* | *"swift test"*)
        sample_stuck_swift_test_process "$label" "$process_pid"
        sampled_count=$((sampled_count + 1))
        if [ "$sampled_count" -ge 3 ]; then
          break
        fi
        ;;
    esac
  done

  if [ "$sampled_count" -eq 0 ]; then
    echo "[$LOG_PREFIX] no Swift test process matched for stack capture"
  fi
}

sample_stuck_swift_test_process() {
  local label="$1"
  local process_pid="$2"
  local sample_file

  sample_file="$(mktemp "${TMPDIR:-/tmp}/agentstudio-swift-test-sample.XXXXXX")"
  echo "[$LOG_PREFIX] sampling stuck Swift test process pid=$process_pid for '$label'"
  if /usr/bin/sample "$process_pid" 3 1 -file "$sample_file" >/dev/null 2>&1; then
    echo "[$LOG_PREFIX] sampled stuck Swift test process pid=$process_pid:"
    sed -n '1,220p' "$sample_file" | sed "s/^/[$LOG_PREFIX] /" || true
  else
    echo "[$LOG_PREFIX] sample failed for Swift test process pid=$process_pid"
  fi
  rm -f "$sample_file"
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
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} \
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
