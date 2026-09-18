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

# Maximum test cases Swift Testing may run concurrently inside one test process.
# OPT-IN, WITH NO DEFAULT, ON PURPOSE.
#
# Swift Testing's cap is experimental and off unless
# SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH is set. On this suite, setting a
# width made the fast lane hang intermittently at EVERY width tried — 15 of 28
# local runs on Swift 6.3.3 blocked (widths 3, 8, 16, 17, 64 and 256 all blocked;
# evidence in the CI reliability work). Until that is understood the width stays
# opt-in for experiments only and MUST NOT be given a default.
#
# Prints the width when SWIFT_TEST_PARALLELIZATION_WIDTH is set and non-empty,
# and nothing otherwise.
swift_test_parallelization_width() {
  echo "${SWIFT_TEST_PARALLELIZATION_WIDTH:-}"
}

# The `NAME=value` env word for a test invocation, or NOTHING when no width is
# set. Every invocation uses this one helper, unquoted, so an unset width leaves
# the variable ABSENT from the child environment rather than set to an empty
# string — Swift Testing treats absence as unlimited, and we do not rely on how
# it would parse "" or 0.
swift_test_parallelization_env_word() {
  local width
  width="$(swift_test_parallelization_width)"

  [ -n "$width" ] || return 0
  echo "SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=$width"
}

# What the lane report prints for the width: the number, or `unlimited` when no
# width is set, because an absent cap is the state a log reader needs to see.
swift_test_parallelization_width_label() {
  local width
  width="$(swift_test_parallelization_width)"

  if [ -n "$width" ]; then
    echo "$width"
  else
    echo unlimited
  fi
}

# How many isolated suite PROCESSES the aggregate phase runs at once. Process
# fan-out follows the machine: never more than one per core, and never more
# than 4 (the fan-out that developer machines already used).
swift_test_isolated_process_concurrency() {
  local cpu_count
  cpu_count="$(sysctl -n hw.ncpu)"
  if [ "$cpu_count" -lt 4 ]; then
    echo "$cpu_count"
  else
    echo 4
  fi
}

# Largest number of tests whose START EVENT had been posted but whose result had
# not, as an ordinal count over one captured console stream.
#
# This does NOT reflect the parallelization cap. Swift Testing posts .testStarted
# in _runStep BEFORE the test acquires the parallelization serializer, so a test
# counted here may be suspended in a continuation rather than running, and this
# number stays near the total test count even when the cap is working. It is kept
# because it is cheap and shows admission backlog; peak_running_parameterized_cases is the
# number that reflects the cap.
swift_test_peak_started_from_output() {
  local output_file="$1"

  /usr/bin/iconv -f UTF-8 -t UTF-8 -c <"$output_file" | /usr/bin/awk '
    { line = $0; sub(/^\[[^]]*\] /, "", line) }
    line ~ /^◇ Test / && line ~ /started\.$/ && line !~ /^◇ Test (run|case) / {
      in_flight++
      if (in_flight > peak) { peak = in_flight }
      next
    }
    line ~ /^[✔✘] Test / && line !~ /^[✔✘] Test (run|case) / &&
      (line ~ / passed after / || line ~ / failed after /) {
      if (in_flight > 0) { in_flight-- }
      next
    }
    END { print peak + 0 }
  '
}

# Largest number of test cases RUNNING at once, from Swift Testing's JSON event
# stream. The parallelization serializer gates _runTestCase and testCaseStarted /
# testCaseEnded fire inside it, so unlike peak_started_tests this observes the cap.
#
# Coverage caveat for this toolchain (Swift 6.3.3): the event stream serializes
# testCase events only for PARAMETERIZED cases — measured 54 testCaseStarted
# records against 880 testStarted records on one lane sample. So this is a lower
# bound taken over the parameterized subset, and reads 0 for a lane that has none.
swift_test_peak_running_cases_from_events() {
  local event_stream_file="${1:-}"

  # -r, not -s: a pipe (process substitution in tests) always reports size 0, and
  # an empty regular stream already yields 0 from the END rule below.
  if [ -z "$event_stream_file" ] || [ ! -r "$event_stream_file" ]; then
    echo 0
    return 0
  fi
  /usr/bin/awk '
    /"kind":"testCaseStarted"/ {
      running++
      if (running > peak) { peak = running }
      next
    }
    /"kind":"testCaseEnded"/ { if (running > 0) { running-- }; next }
    END { print peak + 0 }
  ' "$event_stream_file"
}

# Identifiers of the test cases that had a testCaseStarted with no matching
# testCaseEnded when the stream was read — i.e. what the timed-out command was
# still executing. First-seen order, capped at maximum_ids so one wedged lane
# cannot bury its own log. Returns 1 (and prints nothing) when there is no
# readable stream; the caller turns that into the `unavailable` label.
#
# Same parameterized-case caveat as swift_test_peak_running_cases_from_events:
# this names the stuck PARAMETERIZED cases and stays silent about others.
swift_test_running_case_ids_from_events() {
  local event_stream_file="${1:-}"
  local maximum_ids="${2:-40}"

  if [ -z "$event_stream_file" ] || [ ! -r "$event_stream_file" ]; then
    return 1
  fi
  # A timed-out writer leaves a half-flushed final line; awk just fails to match
  # it. Nothing in here may fail the lane, so stderr is dropped and the caller
  # tolerates a non-zero status.
  /usr/bin/awk -v maximum_ids="$maximum_ids" '
    function case_key(record,   test_id, display_name, case_field) {
      test_id = ""
      display_name = ""
      if (match(record, /"testID":"[^"]*"/)) {
        test_id = substr(record, RSTART + 10, RLENGTH - 11)
      }
      case_field = record
      if (match(case_field, /"_testCase":\{/)) {
        case_field = substr(case_field, RSTART)
        if (match(case_field, /"displayName":"[^"]*"/)) {
          display_name = substr(case_field, RSTART + 15, RLENGTH - 16)
        }
      }
      if (display_name == "") { return test_id }
      return test_id " [" display_name "]"
    }
    /"kind":"testCaseStarted"/ {
      started_key = case_key($0)
      if (!(started_key in seen)) {
        seen[started_key] = 1
        order[++order_count] = started_key
      }
      running[started_key]++
      next
    }
    /"kind":"testCaseEnded"/ {
      ended_key = case_key($0)
      if (running[ended_key] > 0) { running[ended_key]-- }
      next
    }
    END {
      for (position = 1; position <= order_count && printed < maximum_ids; position++) {
        if (running[order[position]] > 0) {
          print order[position]
          printed++
        }
      }
    }
  ' "$event_stream_file" 2>/dev/null
}

# Names what was still executing when the inactivity bound fired, under the same
# greppable lane-report prefix as the rest of the lane load numbers.
# Where a wedged run's event stream is kept, and how many per label survive.
#
# The event stream is the only authoritative record of which test cases started
# and which ended. Deleting it on the timeout path forced regex archaeology over
# console output, which produced two contradictory unfinished-suite counts (3 and
# 21) for the same runs; the preserved ledger named the one parked function
# instead.
LANE_EVENT_STREAM_DIR="${LANE_EVENT_STREAM_DIR:-tmp/plan-workflows/ci-runs}"
LANE_EVENT_STREAM_KEEP_PER_LABEL="${LANE_EVENT_STREAM_KEEP_PER_LABEL:-5}"

# Lane labels are prose ("native-concurrent fast non-WebKit suites"), so they are
# slugged before reaching a filename.
lane_event_stream_label_slug() {
  printf '%s' "${1:-lane}" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9' '-' \
    | sed -E 's/^-+//; s/-+$//'
}

# Copies the event stream somewhere durable and prints where. Called on the paths
# where the run ended without Swift Testing recording a failure — a timeout, or a
# child that died without an ✘ — because those are exactly the runs whose console
# output cannot say what was still executing. A clean run keeps nothing.
#
# A COPY, not a move, and on the timeout path it is taken before anything is
# signalled: the child still holds the stream open, so the original must stay
# where its fd points. The caller deletes that original as usual once the run is
# over.
preserve_lane_event_stream() {
  local label="$1"
  local event_stream_file="${2:-}"

  if [ -z "$event_stream_file" ] || [ ! -r "$event_stream_file" ]; then
    echo "[$LOG_PREFIX] lane-report event_stream=unavailable"
    return 0
  fi

  local label_slug
  label_slug="$(lane_event_stream_label_slug "$label")"
  mkdir -p "$LANE_EVENT_STREAM_DIR"
  local preserved_path
  preserved_path="$LANE_EVENT_STREAM_DIR/lane-$label_slug-$(date +%Y%m%dT%H%M%S)-$$.events.jsonl"
  if cp "$event_stream_file" "$preserved_path" 2>/dev/null; then
    echo "[$LOG_PREFIX] lane-report event_stream=$preserved_path"
    prune_lane_event_streams "$label_slug"
  else
    echo "[$LOG_PREFIX] lane-report event_stream=unavailable"
  fi
}

# Keeps the newest `LANE_EVENT_STREAM_KEEP_PER_LABEL` ledgers for one label.
prune_lane_event_streams() {
  local label_slug="$1"
  local surplus_file

  # shellcheck disable=SC2012
  ls -1t "$LANE_EVENT_STREAM_DIR"/lane-"$label_slug"-*.events.jsonl 2>/dev/null \
    | tail -n +$((LANE_EVENT_STREAM_KEEP_PER_LABEL + 1)) \
    | while IFS= read -r surplus_file; do
      rm -f "$surplus_file"
    done
}

print_running_parameterized_cases_at_timeout() {
  local event_stream_file="${1:-}"
  local running_case_ids=""
  local running_case_id

  if [ -z "$event_stream_file" ] || [ ! -r "$event_stream_file" ]; then
    echo "[$LOG_PREFIX] lane-report running_parameterized_cases_at_timeout=unavailable"
    return 0
  fi
  running_case_ids="$(swift_test_running_case_ids_from_events "$event_stream_file" || true)"
  if [ -z "$running_case_ids" ]; then
    echo "[$LOG_PREFIX] lane-report running_parameterized_cases_at_timeout=none"
    return 0
  fi
  while IFS= read -r running_case_id; do
    [ -n "$running_case_id" ] || continue
    echo "[$LOG_PREFIX] lane-report running_parameterized_cases_at_timeout=$running_case_id"
  done <<<"$running_case_ids"
}

# Each run_swift_with_timeout invocation appends its own peaks here; the lane
# reports the maximum. Appending (rather than read-modify-write) keeps the
# isolated phase's concurrent subshells from racing each other.
swift_test_record_lane_peaks() {
  local output_file="$1"
  local event_stream_file="${2:-}"

  if [ -n "${SWIFT_TEST_PEAK_STARTED_FILE:-}" ]; then
    swift_test_peak_started_from_output "$output_file" \
      >>"$SWIFT_TEST_PEAK_STARTED_FILE" 2>/dev/null || true
  fi
  if [ -n "${SWIFT_TEST_PEAK_RUNNING_FILE:-}" ] && [ -n "$event_stream_file" ]; then
    swift_test_peak_running_cases_from_events "$event_stream_file" \
      >>"$SWIFT_TEST_PEAK_RUNNING_FILE" 2>/dev/null || true
  fi
}

swift_test_peak_total_from_file() {
  local peak_file="${1:-}"

  if [ -z "$peak_file" ] || [ ! -s "$peak_file" ]; then
    echo 0
    return 0
  fi
  /usr/bin/awk 'BEGIN { peak = 0 } $1 + 0 > peak { peak = $1 + 0 } END { print peak }' "$peak_file"
}

# swift build (the prebuild) rejects the Swift Testing event-stream flags; every
# other run_swift_with_timeout caller is a test invocation that accepts them.
swift_test_command_accepts_event_stream() {
  local argument

  for argument in "$@"; do
    if [ "$argument" = "build" ]; then
      return 1
    fi
  done
  return 0
}

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
    GitRefreshPerformanceWorkloadScriptTests
    SidebarPerformanceWorkloadScriptTests
    SidebarPerformanceWorkloadSettlementScriptTests
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
  local excluded_suite_pattern="GlobalPreferencesBootstrapBenchmarkTests|RepoExplorerNativeTablePilotBenchmarkTests|E2E|Zmx|$webkit_leaf_suite_pattern|$(large_non_webkit_filter_pattern)|$(large_serial_non_webkit_filter_pattern)"

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
      'Tests/AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift' \
      'BridgeDevelopmentSeededWorktreeObservationTests'
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
    printf '%s:%s\n' \
      'Tests/AgentStudioAppIPCTests/AppIPCDynamicCommandClientTests.swift' \
      'AppIPCDynamicCommandClientTests'
    printf '%s:%s\n' \
      'Tests/AgentStudioAppIPCTests/AppIPCErrorCorrectionTests.swift' \
      'AppIPCErrorCorrectionTests'
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

# Anchors a suite TYPE name so `--filter`/`--skip` selects that type and nothing
# that merely lives in a file named after it.
#
# Swift Testing matches these as regexes with `contains` over the test's id, and a
# FUNCTION's id ends with its source location. Captured from a real event stream
# on this branch:
#   suite:    AgentStudioInfrastructureTests.RepoScannerTests
#   function: AgentStudioInfrastructureTests.RepoScannerTests/cloneRootGitdirIndirectionsOutsideScannedPathAreFilteredOut()/RepoScannerTests.swift:234:6
#   sibling:  AgentStudioInfrastructureTests.RepoScannerClassificationTests/gitDirectoryIsCloneRoot()/RepoScannerTests.swift:430:6
# The third id belongs to a DIFFERENT suite that happens to live in
# RepoScannerTests.swift, so the bare name `RepoScannerTests` selected it too:
# `--filter RepoScannerTests` admits 2 suites and 29 ids on this bundle. That is
# how two process-global suites ended up sharing one process and the process
# SIGSEGVed at exit (CI 35276671883).
#
# `\.<name>(/|$)` matches only the type component: the module separator `.` before
# it, and either the function separator `/` or end-of-id after it. A file
# component is always preceded by `/`, never `.`, so it can never match — and the
# leading `.` also stops a name matching a longer type it is a prefix of.
swift_test_isolated_suite_filter_pattern() {
  local suite_type_name="$1"
  local escaped_type_name

  # Escape every non-identifier character. Suite names are Swift identifiers
  # today; the anchor must not silently depend on that staying true.
  escaped_type_name="$(printf '%s' "$suite_type_name" | /usr/bin/sed 's/[^A-Za-z0-9_]/\\&/g')"
  printf '\\.%s(/|$)' "$escaped_type_name"
}

# The same anchor across a `|`-joined list of EXACT suite type names.
#
# Only for lists of exact names. `large_non_webkit_filter_pattern` deliberately
# carries substring families (`Script`, `Smoke`, `Integration`, `SourceScan`) that
# are meant to match many suites by prefix, and anchoring those would silently
# drop whole suites out of their lane — the same class of bug in the opposite
# direction.
swift_test_isolated_suite_skip_pattern() {
  local joined_type_names="${1:-}"
  local anchored_patterns=()
  local type_name
  local IFS='|'

  [ -n "$joined_type_names" ] || return 0
  for type_name in $joined_type_names; do
    [ -n "$type_name" ] || continue
    anchored_patterns+=("$(swift_test_isolated_suite_filter_pattern "$type_name")")
  done
  printf '%s' "${anchored_patterns[*]}"
}

run_fast_serial_process_swift_tests() {
  run_swift_with_timeout \
    "serial fast process suites" \
    "$TIMEOUT_SECONDS" \
    env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
    --filter "$(swift_test_isolated_suite_filter_pattern "$(fast_serial_process_filter_pattern)")" \
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
  local process_global_concurrency
  process_global_concurrency="$(swift_test_isolated_process_concurrency)"
  echo "[$LOG_PREFIX] isolated process-global concurrency: $process_global_concurrency"
  local swift_test_bundle
  swift_test_bundle="$(swift_testing_bundle_path)"
  local swift_testing_helper
  swift_testing_helper="$(swift_testing_helper_path)"
  local testing_framework_path
  testing_framework_path="$(swift_testing_framework_path)"
  local aggregate_serial_suite_filter
  local -a process_global_batch_pids=()
  local inventory_status=0
  while IFS= read -r aggregate_serial_suite_filter; do
    [ -n "$aggregate_serial_suite_filter" ] || continue
    (
      run_swift_with_timeout \
        "isolated process-global non-WebKit suite: $aggregate_serial_suite_filter" \
        "$TIMEOUT_SECONDS" \
        env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) \
        DYLD_FRAMEWORK_PATH="$testing_framework_path" \
        "$swift_testing_helper" --test-bundle-path "$swift_test_bundle" \
        --filter "$(swift_test_isolated_suite_filter_pattern "$aggregate_serial_suite_filter")" \
        "$swift_test_bundle" --testing-library swift-testing
    ) &
    process_global_batch_pids+=("$!" "$aggregate_serial_suite_filter")

    if [ "${#process_global_batch_pids[@]}" -eq $((process_global_concurrency * 2)) ]; then
      # Record the failure and keep going: stopping here is what hid 324 of 336
      # suites behind one crashed process.
      wait_for_process_global_suite_batch "${process_global_batch_pids[@]}" || inventory_status=1
      process_global_batch_pids=()
    fi
  done < <(aggregate_serial_non_webkit_suite_filters)

  if [ "${#process_global_batch_pids[@]}" -gt 0 ]; then
    wait_for_process_global_suite_batch "${process_global_batch_pids[@]}" || inventory_status=1
  fi
  return "$inventory_status"
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
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) \
      DYLD_FRAMEWORK_PATH="$testing_framework_path" \
      "$swift_testing_helper" --test-bundle-path "$swift_test_bundle" \
      --filter "$(swift_test_isolated_suite_filter_pattern "$large_process_global_suite_filter")" \
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

# Appends one failing isolated suite to the lane's tally. The lane reports every
# failure at the end rather than stopping at the first, so one crashed process
# cannot hide whether the suites after it would also have failed.
swift_test_record_failed_isolated_suite() {
  local suite_filter="$1"
  local status="$2"

  [ -n "${SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE:-}" ] || return 0
  printf '%s\t%s\t%s\n' \
    "$suite_filter" "$status" "$(swift_test_signal_name "$status")" \
    >>"$SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE" 2>/dev/null || true
}

swift_test_failed_isolated_suite_count() {
  local tally_file="${SWIFT_TEST_FAILED_ISOLATED_SUITES_FILE:-}"

  if [ -z "$tally_file" ] || [ ! -s "$tally_file" ]; then
    echo 0
    return 0
  fi
  /usr/bin/awk 'END { print NR + 0 }' "$tally_file"
}

# Takes interleaved `pid filter` pairs rather than bare pids, so a failing child
# can be named. Pairs, not a delimiter, because suite filters are regexes.
wait_for_process_global_suite_batch() {
  local suite_process_pid
  local suite_filter
  local suite_status
  local batch_status=0

  while [ "$#" -gt 0 ]; do
    suite_process_pid="$1"
    suite_filter="$2"
    shift 2
    # `|| suite_status=$?` rather than toggling `set -e`: toggling it here would
    # silently re-enable it for a caller that had turned it off.
    suite_status=0
    wait "$suite_process_pid" || suite_status=$?
    if [ "$suite_status" -ne 0 ]; then
      batch_status=1
      echo "[$LOG_PREFIX] isolated suite failed: $suite_filter" \
        "status=$suite_status signal=$(swift_test_signal_name "$suite_status")" >&2
      swift_test_record_failed_isolated_suite "$suite_filter" "$suite_status"
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
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --parallel \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests \
      --skip "$(aggregate_serial_non_webkit_filter_pattern)" --build-path "$BUILD_PATH"

    run_aggregate_serial_non_webkit_swift_tests
  else
    run_swift_with_timeout \
      "serial $label" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  fi
}

# What the fast inventory skips because another phase owns it.
#
# The exact suite names are ANCHORED for the same reason the isolated `--filter`
# is: an unanchored name also skips anything living in a file named after it, so
# a fast-lane suite sharing a file with an isolated suite was silently dropped
# from the lane and run nowhere. `large_non_webkit_filter_pattern` stays
# unanchored on purpose — it carries substring families (`Script`, `Smoke`,
# `Integration`, `SourceScan`) meant to match many suites by prefix, and
# anchoring those would drop whole suites instead.
fast_non_webkit_skip_pattern() {
  local exact_suite_names
  exact_suite_names="GlobalPreferencesBootstrapBenchmarkTests|RepoExplorerNativeTablePilotBenchmarkTests"
  exact_suite_names="$exact_suite_names|$(large_serial_non_webkit_filter_pattern)"
  exact_suite_names="$exact_suite_names|$(aggregate_serial_non_webkit_filter_pattern)"
  exact_suite_names="$exact_suite_names|$(fast_serial_process_filter_pattern)"

  printf '%s|%s' \
    "$(swift_test_isolated_suite_skip_pattern "$exact_suite_names")" \
    "$(large_non_webkit_filter_pattern)"
}

run_fast_non_webkit_swift_tests() {
  # Swift Testing provides in-process case concurrency, bounded by the explicit
  # SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH exported below. SwiftPM's
  # --parallel harness is not used for the fast inventory; suites that need a
  # process of their own get one from the isolated phases that follow.
  run_swift_with_timeout \
    "native-concurrent fast non-WebKit suites" \
    "$TIMEOUT_SECONDS" \
    env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
    --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests \
    --skip "$(fast_non_webkit_skip_pattern)" --build-path "$BUILD_PATH"

  run_aggregate_serial_non_webkit_swift_tests
  run_fast_serial_process_swift_tests
}

run_large_non_webkit_swift_tests() {
  if [ "${SWIFT_TEST_PARALLEL:-1}" = "1" ]; then
    local parallel_args=(--parallel)
    run_swift_with_timeout \
      "parallel large non-WebKit suites" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      "${parallel_args[@]}" \
      --filter "$(large_non_webkit_filter_pattern)" \
      --skip "$(large_serial_non_webkit_filter_pattern)|$(large_process_global_filter_pattern)" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"

    run_swift_with_timeout \
      "serial large process suites" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
      --filter "$(large_serial_non_webkit_filter_pattern)" \
      --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
  else
    run_swift_with_timeout \
      "serial large non-WebKit suites" \
      "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) swift test ${EXTRA_SWIFT_TEST_ARGS:-} --skip-build \
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
WebKitSerializedTests/RepositoryBridgeObservationLifetimeTests
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

  # Both `swift test` and swiftpm-testing-helper accept these trailing flags on
  # Swift 6.3.3 (neither advertises them in --help).
  local event_stream_file=""
  if swift_test_command_accepts_event_stream "$@"; then
    event_stream_file="$(mktemp "${TMPDIR:-/tmp}/agentstudio-swift-test-events.XXXXXX")"
    set -- "$@" --event-stream-version 0 --event-stream-output-path "$event_stream_file"
  fi

  # Run command piped through xcbeautify in a subshell so we track one PID.
  # Subshell inherits pipefail from parent — swift exit code propagates.
  #
  # `set -m` puts that subshell in its OWN process group, whose id is its pid.
  # The timeout path needs that: it used to signal by walking live parent links,
  # so a descendant that re-parented when its parent died was missed and outlived
  # the lane. That is how wedged `swiftpm-testing-helper` processes kept holding
  # build slots and made the NEXT run fail with "all 2 slots are busy". A process
  # group is stable across re-parenting, and this one contains only the lane's
  # own child.
  set -m
  # shellcheck disable=SC2086
  ( "$@" 2>&1 | tee "$output_file" | $xcb_pipe ) &
  local command_pid=$!
  set +m

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
    # Read the stream before terminating anything: this names what was still
    # executing at the timeout, not what survived the kill.
    print_running_parameterized_cases_at_timeout "$event_stream_file"
    print_timeout_process_diagnostics "$label" "$command_pid"
    echo "[$LOG_PREFIX] raw output tail for '$label':"
    tail -n 120 "$output_file" || true
    # Copy the ledger BEFORE anything is signalled, while the writer is still
    # alive: the child holds the stream open and a copy taken after termination
    # can miss records it had not flushed. Copying rather than moving also keeps
    # the writer's fd pointing at a file that still exists, which a
    # cross-filesystem move would not — it would leave the child appending to an
    # unlinked inode.
    preserve_lane_event_stream "$label" "$event_stream_file"
    terminate_lane_process_group TERM "$command_pid"
    # Writing the report IS the grace period. It is work the lane must do anyway,
    # so a child that honours TERM exits while it happens and no `sleep` has to
    # guess how long that takes.
    swift_test_record_lane_peaks "$output_file" "$event_stream_file"

    if lane_process_group_is_gone "$command_pid"; then
      echo "[$LOG_PREFIX] lane-report timeout_reap=terminated"
      wait "$command_pid" 2>/dev/null || true
    else
      terminate_lane_process_group KILL "$command_pid"
      # SIGKILL can be neither caught nor ignored, so this returns as soon as the
      # kernel has finished tearing the group down — however long that takes on
      # this machine. The only thing that could hold it is a process wedged in an
      # uninterruptible kernel wait, which is a kernel fault outside this
      # runner's remit and is already covered by the job-level timeout.
      wait "$command_pid" 2>/dev/null || true
      echo "[$LOG_PREFIX] lane-report timeout_reap=killed"
    fi
    rm -f "$output_file" ${event_stream_file:+"$event_stream_file"}
    return 124
  fi

  set +e
  wait "$command_pid"
  local command_status=$?
  set -e
  local should_preserve_event_stream=0

  if [ "$command_status" -eq 0 ] && swift_test_output_has_failures "$output_file"; then
    echo "[$LOG_PREFIX] ERROR: '$label' emitted Swift Testing failure output despite exit 0" >&2
    command_status=1
  elif [ "$command_status" -ne 0 ] && ! swift_test_output_has_failures "$output_file"; then
    # A child that died without recording a Swift Testing failure — a signal, or a
    # runtime abort after its tests passed. Without this the lane printed only
    # "ERROR task failed" and bash's job-table line, and the reason was gone with
    # the output file.
    print_failed_child_diagnostics "$label" "$command_status" "$output_file"
    # Same reason as the timeout path: a child that died without recording a
    # Swift Testing failure leaves the event stream as the only record of what
    # had actually started, and console output cannot reconstruct it.
    should_preserve_event_stream=1
  fi

  swift_test_record_lane_peaks "$output_file" "$event_stream_file"
  if [ "$should_preserve_event_stream" -eq 1 ]; then
    preserve_lane_event_stream "$label" "$event_stream_file"
  fi
  rm -f "$output_file" ${event_stream_file:+"$event_stream_file"}
  return "$command_status"
}

# The signal that killed a child, or `none` when the status is an ordinary exit
# code. Shells report a signalled child as 128 + signal number.
swift_test_signal_name() {
  local status="${1:-0}"

  if [ "$status" -gt 128 ]; then
    kill -l $((status - 128)) 2>/dev/null || echo "unknown"
  else
    echo none
  fi
}

# Mirrors the timeout branch's diagnostics for a child that exited non-zero
# without an ✘ marker, and must run BEFORE the captured output is deleted.
print_failed_child_diagnostics() {
  local label="$1"
  local status="$2"
  local output_file="$3"
  local signal_name
  signal_name="$(swift_test_signal_name "$status")"

  echo "[$LOG_PREFIX] ERROR: '$label' exited $status with no recorded test failure" >&2
  echo "[$LOG_PREFIX] exit_status=$status signal=$signal_name" >&2
  echo "[$LOG_PREFIX] raw output tail for '$label':" >&2
  tail -n 120 "$output_file" >&2 || true
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

# Signals the process GROUP the lane created for its own child, never the lane's
# own group: `run_swift_with_timeout` launches under `set -m`, so the group id is
# the child subshell's pid and the negative pid below can only reach that group.
#
# This replaces walking live parent links on the timeout path. That walk read
# `pgrep -P` before signalling, so a `swiftpm-testing-helper` that re-parented
# when `swift test` died was never in the second pass and survived the lane still
# holding a build slot.
terminate_lane_process_group() {
  local signal="$1"
  local group_pid="$2"

  kill -"$signal" -"$group_pid" 2>/dev/null || true
}

# True when nothing in the lane's child group is alive.
#
# ONE check, deliberately. Retrying a fixed number of times would be a wall clock
# in disguise, and a machine-speed-dependent one: a few hundred builtin
# invocations are milliseconds on a fast laptop and longer on a loaded runner, so
# a group that was merely slow to tear down would be reported as unreapable. The
# caller needs no retry — after SIGKILL it simply waits, because SIGKILL can be
# neither caught nor ignored.
lane_process_group_is_gone() {
  local group_pid="$1"

  ! kill -0 -"$group_pid" 2>/dev/null
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
      env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) swift test ${EXTRA_SWIFT_TEST_ARGS:-} \
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
