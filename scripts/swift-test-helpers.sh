#!/usr/bin/env bash
# Shared test helper functions for mise tasks.
#
# Required variables (set by caller before sourcing):
#   LOG_PREFIX         - Log prefix, e.g. "test" or "test-coverage"
#   TIMEOUT_SECONDS    - Maximum seconds without Swift command output progress
#   PREBUILD_TIMEOUT_SECONDS - Maximum seconds without one-time test bundle build output progress
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
    SourceScan
    Smoke
    Integration
    ZmxStartupTraceAnalyzerTests
    WorkspaceSurfaceCoordinatorFilesystemSourceTests
    TerminalActivityAgentSettledHeuristicTests
    MainWindowControllerInboxToolbarButtonTests
    ProcessExecutorTests
    DarwinCompositeFSEventContinuityTests
    DarwinFSEventStreamClientTests
    DarwinSharedLocalFSEventObserverFailureTests
    DarwinSharedLocalFSEventObserverTests
    DarwinSharedExactItemObserverTests
    FilesystemActorActivityTests
    WorkspaceStrictStartupSubprocessTests
  )
  local IFS="|"
  echo "${patterns[*]}"
}

large_serial_non_webkit_filter_pattern() {
  local patterns=(
    BridgePackagedProductJourneyScriptTests
    PaneAgentLaunchOwnerTests
  )
  local IFS="|"
  echo "${patterns[*]}"
}

large_process_global_suite_filters() {
  local large_suite_pattern
  large_suite_pattern="$(large_non_webkit_filter_pattern)"
  local webkit_leaf_suite_pattern
  webkit_leaf_suite_pattern="$(webkit_leaf_suite_filters | /usr/bin/paste -sd'|' -)"
  local excluded_suite_pattern="E2E|Zmx|$webkit_leaf_suite_pattern"

  {
    serialized_main_actor_suite_matches main-actor-first
    serialized_main_actor_suite_matches suite-first
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPBootstrapSmokeTests.swift' \
      'AgentStudioOTLPBootstrapSmokeTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedExactItemRealStreamIntegrationTests.swift' \
      'DarwinSharedExactItemRealStreamIntegrationTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinCompositeFSEventContinuityTests.swift' \
      'DarwinCompositeFSEventContinuityTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinFSEventStreamClientTests.swift' \
      'DarwinFSEventStreamClientTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedLocalFSEventObserverFailureTests.swift' \
      'DarwinSharedLocalFSEventObserverFailureTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedLocalFSEventObserverTests.swift' \
      'DarwinSharedLocalFSEventObserverTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedExactItemObserverTests.swift' \
      'DarwinSharedExactItemObserverTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorActivityTests.swift' \
      'FilesystemActorActivityTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/App/WorkspaceStrictStartupSubprocessTests.swift' \
      'WorkspaceStrictStartupSubprocessTests'
  } | while IFS=: read -r source_file suite_name; do
    case "$source_file" in
      *"/App/WebKit/"*) continue ;;
    esac
    if printf '%s\n' "$suite_name" | grep -Eq "$excluded_suite_pattern"; then
      continue
    fi
    if printf '%s\n' "$suite_name" | grep -Eq "$large_suite_pattern"; then
      printf '%s\n' "$suite_name"
    fi
  done | sort -u
}

large_process_global_filter_pattern() {
  large_process_global_suite_filters | /usr/bin/paste -sd'|' -
}

serialized_main_actor_suite_pattern() {
  local annotation_order="$1"
  local declaration_modifiers='(?:(?:public|package|internal|fileprivate|private|open|final|indirect|nonisolated(?:\(unsafe\))?)\s+)*'
  local type_declaration_keywords='(?:class|struct|actor|enum|protocol|extension|typealias)'
  local declaration_boundary="${declaration_modifiers}${type_declaration_keywords}\\s"
  local suite_type_declaration="${declaration_modifiers}(?:class|struct)\\s+"
  local suite_arguments="(?:(?!\\n\\s*(?:@[A-Za-z]|${declaration_boundary}))[\\s\\S])*?"
  local suite_annotation="@Suite\\(${suite_arguments}\\.serialized\\b${suite_arguments}\\)"

  case "$annotation_order" in
    main-actor-first)
      printf '%s\n' "@MainActor\\s*\\n\\s*${suite_annotation}\\s*\\n\\s*${suite_type_declaration}([A-Za-z0-9_]+)"
      ;;
    suite-first)
      printf '%s\n' "${suite_annotation}\\s*\\n\\s*@MainActor\\s*\\n\\s*${suite_type_declaration}([A-Za-z0-9_]+)"
      ;;
    *)
      echo "Unknown serialized suite annotation order: $annotation_order" >&2
      return 2
      ;;
  esac
}

serialized_main_actor_suite_matches() {
  local annotation_order="$1"
  local pattern
  pattern="$(serialized_main_actor_suite_pattern "$annotation_order")"

  SERIALIZED_SUITE_PATTERN="$pattern" find Tests/AgentStudioTests -type f -name '*.swift' \
    -exec /usr/bin/perl -0777 -ne '
      BEGIN { $pattern = qr/$ENV{"SERIALIZED_SUITE_PATTERN"}/; }
      while ($_ =~ /$pattern/g) { print "$ARGV:$1\n"; }
    ' {} +
}

serialized_main_actor_suite_names_from_stdin() {
  local annotation_order="$1"
  local pattern
  pattern="$(serialized_main_actor_suite_pattern "$annotation_order")"

  SERIALIZED_SUITE_PATTERN="$pattern" /usr/bin/perl -0777 -ne '
    BEGIN { $pattern = qr/$ENV{"SERIALIZED_SUITE_PATTERN"}/; }
    while ($_ =~ /$pattern/g) { print "$1\n"; }
  '
}

aggregate_serial_non_webkit_suite_filters() {
  # Permit formatted multiline Suite arguments, but never cross into the next
  # attribute or type declaration while searching for the serialized trait.
  local webkit_leaf_suite_pattern
  webkit_leaf_suite_pattern="$(webkit_leaf_suite_filters | /usr/bin/paste -sd'|' -)"
  local excluded_suite_pattern="GlobalPreferencesBootstrapBenchmarkTests|E2E|Zmx|$webkit_leaf_suite_pattern|$(large_non_webkit_filter_pattern)|$(large_serial_non_webkit_filter_pattern)"

  {
    serialized_main_actor_suite_matches main-actor-first
    serialized_main_actor_suite_matches suite-first
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/Features/Terminal/State/TerminalActivityProjectorTests.swift' \
      'TerminalActivityProjectorTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift' \
      'GitWorkingDirectoryProjectorTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceTests.swift' \
      'AgentStudioAppIPCServiceTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceAuthModeTests.swift' \
      'AgentStudioAppIPCServiceAuthModeTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceCommandTests.swift' \
      'AgentStudioAppIPCServiceCommandTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceContributionTests.swift' \
      'AgentStudioAppIPCServiceContributionTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioAppIPCTests/AgentStudioIPCBridgeServiceTests.swift' \
      'AgentStudioIPCBridgeServiceTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioAppIPCTests/AgentStudioAppIPCCommandExecuteContractTests.swift' \
      'AgentStudioAppIPCCommandExecuteContractTests'
  } | while IFS=: read -r source_file suite_name; do
    case "$source_file" in
      *"/App/WebKit/"*) continue ;;
    esac
    if printf '%s\n' "$suite_name" | grep -Eq "$excluded_suite_pattern"; then
      continue
    fi
    printf '%s\n' "$suite_name"
  done | sort -u
}

aggregate_serial_non_webkit_filter_pattern() {
  aggregate_serial_non_webkit_suite_filters | /usr/bin/paste -sd'|' -
}

fast_serial_process_filter_pattern() {
  echo "SQLiteDatabaseFactoryProcessTests"
}

run_fast_serial_process_swift_tests() {
  run_swift_with_timeout \
    "serial fast process suites" \
    "$TIMEOUT_SECONDS" \
    env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
    --filter "$(fast_serial_process_filter_pattern)" \
    --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
}

prebuild_swift_tests() {
  # shellcheck disable=SC2086
  run_swift_with_timeout \
    "prebuild test bundles" \
    "$PREBUILD_TIMEOUT_SECONDS" \
    swift build --build-tests ${EXTRA_SWIFT_TEST_ARGS:-} --build-path "$BUILD_PATH"
}

run_aggregate_serial_non_webkit_swift_tests() {
  local process_global_concurrency=4
  local swift_test_bundle
  swift_test_bundle="$(swift_testing_bundle_path)"
  local swift_testing_helper
  swift_testing_helper="$(swift_testing_helper_path)"
  local testing_framework_path
  testing_framework_path="$(swift_testing_framework_path)"
  local aggregate_serial_suite_filter
  local -a process_global_batch_pids=()
  while IFS= read -r aggregate_serial_suite_filter; do
    [ -n "$aggregate_serial_suite_filter" ] || continue
    (
      run_swift_with_timeout \
        "isolated process-global non-WebKit suite: $aggregate_serial_suite_filter" \
        "$TIMEOUT_SECONDS" \
        env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" \
        DYLD_FRAMEWORK_PATH="$testing_framework_path" \
        "$swift_testing_helper" --test-bundle-path "$swift_test_bundle" \
        --filter "$aggregate_serial_suite_filter" \
        "$swift_test_bundle" --testing-library swift-testing
    ) &
    process_global_batch_pids+=("$!")

    if [ "${#process_global_batch_pids[@]}" -eq "$process_global_concurrency" ]; then
      wait_for_process_global_suite_batch "${process_global_batch_pids[@]}" || return $?
      process_global_batch_pids=()
    fi
  done < <(aggregate_serial_non_webkit_suite_filters)

  if [ "${#process_global_batch_pids[@]}" -gt 0 ]; then
    wait_for_process_global_suite_batch "${process_global_batch_pids[@]}"
  fi
}

run_large_process_global_swift_tests() {
  local swift_test_bundle
  swift_test_bundle="$(swift_testing_bundle_path)"
  local swift_testing_helper
  swift_testing_helper="$(swift_testing_helper_path)"
  local testing_framework_path
  testing_framework_path="$(swift_testing_framework_path)"
  local large_process_global_suite_filter
  while IFS= read -r large_process_global_suite_filter; do
    [ -n "$large_process_global_suite_filter" ] || continue
    run_swift_with_timeout \
      "isolated large process-global suite: $large_process_global_suite_filter" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" \
      DYLD_FRAMEWORK_PATH="$testing_framework_path" \
      "$swift_testing_helper" --test-bundle-path "$swift_test_bundle" \
      --filter "$large_process_global_suite_filter" \
      "$swift_test_bundle" --testing-library swift-testing
  done < <(large_process_global_suite_filters)
}

swift_testing_bundle_path() {
  local test_bundle
  test_bundle="$(find "$BUILD_PATH" -type f -path '*/debug/AgentStudioPackageTests.xctest/Contents/MacOS/AgentStudioPackageTests' -print -quit)"
  if [ -z "$test_bundle" ]; then
    echo "Swift Testing bundle not found under $BUILD_PATH" >&2
    return 1
  fi
  printf '%s\n' "$test_bundle"
}

swift_testing_helper_path() {
  local swift_executable
  swift_executable="$(xcrun --find swift)"
  printf '%s/libexec/swift/pm/swiftpm-testing-helper\n' "$(dirname "$(dirname "$swift_executable")")"
}

swift_testing_framework_path() {
  local platform_path
  platform_path="$(xcrun --sdk macosx --show-sdk-platform-path)"
  printf '%s/Developer/Library/Frameworks\n' "$platform_path"
}

wait_for_process_global_suite_batch() {
  local suite_process_pid
  local batch_status=0
  for suite_process_pid in "$@"; do
    if ! wait "$suite_process_pid"; then
      batch_status=1
    fi
  done
  return "$batch_status"
}

run_non_serialized_swift_tests() {
  local label="$1"

  if [ "${SWIFT_TEST_PARALLEL:-1}" = "1" ]; then
    run_swift_with_timeout \
      "parallel $label" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --parallel \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests \
      --skip "$(aggregate_serial_non_webkit_filter_pattern)" --build-path "$BUILD_PATH"

    run_aggregate_serial_non_webkit_swift_tests
  else
    run_swift_with_timeout \
      "serial $label" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  fi
}

run_fast_non_webkit_swift_tests() {
  # Swift Testing provides in-process case concurrency. SwiftPM's --parallel
  # harness wraps the entire Testing library in one helper process on Xcode
  # 26.3 and can deadlock its event stream under the fast inventory's volume.
  run_swift_with_timeout \
    "native-concurrent fast non-WebKit suites" \
    "$TIMEOUT_SECONDS" \
    env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
    --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests \
    --skip "GlobalPreferencesBootstrapBenchmarkTests|$(large_non_webkit_filter_pattern)|$(large_serial_non_webkit_filter_pattern)|$(aggregate_serial_non_webkit_filter_pattern)|$(fast_serial_process_filter_pattern)" --build-path "$BUILD_PATH"

  run_aggregate_serial_non_webkit_swift_tests
  run_fast_serial_process_swift_tests
}

run_large_non_webkit_swift_tests() {
  if [ "${SWIFT_TEST_PARALLEL:-1}" = "1" ]; then
    local parallel_args=(--parallel)
    if [ -n "${SWIFT_TEST_NUM_WORKERS:-}" ]; then
      parallel_args+=(--num-workers "$SWIFT_TEST_NUM_WORKERS")
    fi
    run_swift_with_timeout \
      "parallel large non-WebKit suites" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      "${parallel_args[@]}" \
      --filter "$(large_non_webkit_filter_pattern)" \
      --skip "$(large_serial_non_webkit_filter_pattern)|$(large_process_global_filter_pattern)" \
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
      --skip "$(large_process_global_filter_pattern)" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  fi

  run_large_process_global_swift_tests
}

webkit_suite_filters() {
  cat <<'EOF'
WebKitSerializedTests/BridgePaneControllerTests
WebKitSerializedTests/BridgePaneControllerContentAuthorityTests
WebKitSerializedTests/BridgePaneControllerInitialLoadTests
WebKitSerializedTests/BridgeSchemeHandlerSpikeTests
WebKitSerializedTests/BridgeContentWorldIsolationTests
WebKitSerializedTests/BridgePaneControllerIPCProjectionTests
WebKitSerializedTests/BridgePaneControllerRealGitReviewLoadTests
WebKitSerializedTests/BridgePaneControllerTelemetryTests
WebKitSerializedTests/BridgePaneProductActiveViewerModeTests
WebKitSerializedTests/BridgeProductRealGitFileAndReviewWebKitTests
WebKitSerializedTests/BridgeReviewComparisonPresentationTests
WebKitSerializedTests/BridgeReviewContentStreamTransportTests
WebKitSerializedTests/WorkspaceSurfaceCoordinatorViewFactoryTests
WebKitSerializedTests/WorkspaceBridgeGitReadActivityOrderingTests
WebKitSerializedTests/WorkspaceBridgePaneRefreshIntegrationTests
WebKitSerializedTests/WorkspaceBridgeConstructionIntegrationTests
WebKitSerializedTests/WorkspaceBridgePaneActivityIntegrationTests
WebKitSerializedTests/WorkspaceBridgePaneActivityRemediationTests
WebKitSerializedTests/WorkspaceSurfaceCoordinatorZoomCompanionTests
WebKitSerializedTests/WorkspaceSurfaceCoordinatorZoomLifecycleTests
WebKitSerializedTests/WorkspaceSurfaceCoordinatorZoomRecoveryTests
WebKitSerializedTests/PaneTabViewControllerBridgeCommandTests
WebKitSerializedTests/WorkspaceActionExecutorWebKitTests
WebKitSerializedTests/BridgePaneControllerProductBootstrapDeliveryTests
WebKitSerializedTests/BridgeTelemetryBootstrapDeliveryTests
WebKitSerializedTests/BridgeProductReviewIntakeLockOrderTests
WebKitSerializedTests/BridgeTransportIntegrationTests/test_bridgeReady_gatesAndIsIdempotent
WebKitSerializedTests/BridgeTransportIntegrationTests/test_teardown_resetsBridgeReady
WebKitSerializedTests/BridgeTransportIntegrationTests/test_schemeHandler_servesPackagedReactApp
WebKitSerializedTests/BridgeTransportIntegrationTests/test_handleDiffCommandWithSmokeProvider_rendersReviewViewerShell
WebKitSerializedTests/BridgeTransportIntegrationTests/test_sourceBackedInitialReviewLoad_rendersReviewViewerShell
WebKitSerializedTests/BridgeWebKitSpikeTests
WebKitSerializedTests/WebviewPaneControllerTests
WebKitSerializedTests/PreparedNonterminalContentMountTests
EOF
}

webkit_leaf_suite_filters() {
  webkit_suite_filters | awk -F/ 'NF >= 2 { print $2 }' | sort -u
}

run_webkit_suites() {
  echo "--- WebKit serialized tests (serial) ---"
  while IFS= read -r filter; do
    [ -n "$filter" ] || continue
    run_webkit_suite_with_retry "$filter" || return $?
  done < <(webkit_suite_filters)
}

swift_test_watchdog_state() {
  local previous_output_size="$1"
  local current_output_size="$2"
  local previous_progress_epoch="$3"
  local current_epoch="$4"

  if [ "$current_output_size" -gt "$previous_output_size" ]; then
    printf '%s %s\n' "$current_output_size" "$current_epoch"
  else
    printf '%s %s\n' "$previous_output_size" "$previous_progress_epoch"
  fi
}

swift_test_watchdog_timeout_status() {
  local last_progress_epoch="$1"
  local current_epoch="$2"
  local timeout_seconds="$3"
  local inactive_seconds=$((current_epoch - last_progress_epoch))

  if [ "$inactive_seconds" -ge "$timeout_seconds" ]; then
    return 124
  fi
  return 0
}

run_swift_with_timeout() {
  local label="$1"
  shift
  local timeout_seconds="$1"
  shift

  echo "[$LOG_PREFIX] >>> $label (inactivity-timeout=${timeout_seconds}s)"
  local start_epoch
  start_epoch=$(date +%s)
  local last_heartbeat="$start_epoch"
  local last_progress_epoch="$start_epoch"
  local last_output_size=0
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
    local output_size
    output_size=$(wc -c <"$output_file" | tr -d '[:space:]')
    read -r last_output_size last_progress_epoch < <(
      swift_test_watchdog_state \
        "$last_output_size" \
        "$output_size" \
        "$last_progress_epoch" \
        "$now_epoch"
    )
    local inactive_seconds=$((now_epoch - last_progress_epoch))

    if ! swift_test_watchdog_timeout_status \
      "$last_progress_epoch" \
      "$now_epoch" \
      "$timeout_seconds"
    then
      timed_out=1
      break
    fi

    if [ $((now_epoch - last_heartbeat)) -ge 20 ]; then
      # A heartbeat write can fail with EINTR when the child exits mid-write; that is not a
      # test failure and must not abort the watchdog under `set -e`.
      echo "[$LOG_PREFIX] ... $label still running (${elapsed_seconds}s elapsed, ${inactive_seconds}s without output)" || true
      last_heartbeat="$now_epoch"
    fi
  done

  if [ "$timed_out" -eq 1 ]; then
    echo "[$LOG_PREFIX] ERROR: no output progress from '$label' for ${timeout_seconds}s"
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

  (
    set -o pipefail
    /usr/bin/iconv -f UTF-8 -t UTF-8 -c <"$output_file" |
      grep -Eq \
        '(^|[[:space:]])(✘|✖)[[:space:]]|recorded an issue|failed after [0-9.]+ seconds with [0-9]+ issue\(s\)|Test run with .* failed after|No matching test cases were run'
  )
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
