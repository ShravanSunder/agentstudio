#!/usr/bin/env bash
set -euo pipefail

mode="${1:-test}"
shift || true

bash "${PROJECT_ROOT}/scripts/vendor-worktree.sh" verify

case "$mode" in
  test|test-fast|test-large|test-prebuild|test-webkit)
    ;;
  *)
    echo "run-swift-test-task: unknown mode '$mode'" >&2
    exit 2
    ;;
esac

source "${PROJECT_ROOT}/scripts/swift-build-slot.sh"
BUILD_PATH="$SWIFT_BUILD_DIR"
# Defaults match what every gated path already sets (CI lane env and the
# aggregate `mise run test` task). A bare focused run used to inherit 60/90,
# which kills a correct cold compile rather than a hung one.
TIMEOUT_SECONDS="${SWIFT_TEST_TIMEOUT_SECONDS:-600}"
PREBUILD_TIMEOUT_SECONDS="${SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS:-1200}"

LOG_PREFIX="$mode"
EXTRA_SWIFT_TEST_ARGS=""
source scripts/swift-test-helpers.sh

echo "[$LOG_PREFIX] BUILD_PATH=$BUILD_PATH"
echo "[$LOG_PREFIX] TIMEOUT_SECONDS=$TIMEOUT_SECONDS"
echo "[$LOG_PREFIX] PREBUILD_TIMEOUT_SECONDS=$PREBUILD_TIMEOUT_SECONDS"

LANE_CPU_COUNT="$(sysctl -n hw.ncpu)"
echo "[$LOG_PREFIX] lane-report cpu_count=$LANE_CPU_COUNT"
echo "[$LOG_PREFIX] lane-report memory_bytes=$(sysctl -n hw.memsize)"
echo "[$LOG_PREFIX] lane-report parallelization_width=$(swift_test_parallelization_width_label)"
echo "[$LOG_PREFIX] lane-report isolated_process_concurrency=$(swift_test_isolated_process_concurrency)"
echo "[$LOG_PREFIX] lane-report xcode=$(xcodebuild -version | tr '\n' ' ')"
echo "[$LOG_PREFIX] lane-report swift=$(swift --version | head -1)"

if [ "$mode" = "test-prebuild" ]; then
  prebuild_swift_tests
  exit $?
fi

# Children CPU seconds (user+sys) from the second line of bash `times`, which
# reads "<minutes>m<seconds>s <minutes>m<seconds>s".
lane_children_cpu_seconds() {
  local times_file="$1"

  [ -s "$times_file" ] || { echo "0.00"; return 0; }
  /usr/bin/awk 'NR == 2 {
      total = 0
      for (field = 1; field <= NF; field++) {
        split($field, parts, "m")
        seconds = parts[2]
        sub(/s$/, "", seconds)
        total += parts[1] * 60 + seconds
      }
      printf "%.2f\n", total
      found = 1
    }
    END { if (!found) { print "0.00" } }' "$times_file"
}

# Printed on every exit, including a failing one: a failing lane is the one we
# most need to read load numbers from.
print_closing_lane_report() {
  local exit_status=$?
  local wall_seconds=$((SECONDS - LANE_START_SECONDS))
  local cpu_seconds

  times >"$LANE_TIMES_FILE" 2>/dev/null || true
  cpu_seconds="$(lane_children_cpu_seconds "$LANE_TIMES_FILE")"

  echo "[$LOG_PREFIX] lane-report exit_status=$exit_status"
  echo "[$LOG_PREFIX] lane-report wall_seconds=$wall_seconds"
  echo "[$LOG_PREFIX] lane-report cpu_seconds=$cpu_seconds"
  echo "[$LOG_PREFIX] lane-report cpu_utilization=$(
    /usr/bin/awk -v cpu="$cpu_seconds" -v wall="$wall_seconds" -v cores="$LANE_CPU_COUNT" \
      'BEGIN { if (wall <= 0 || cores <= 0) { print "0.00" } else { printf "%.2f\n", cpu / (wall * cores) } }'
  )"
  # peak_started_tests counts tests whose start event was posted and does NOT
  # reflect the parallelization cap; peak_running_parameterized_cases does.
  # Both labels say "parameterized" because Swift Testing's v0 event stream emits
  # test-case records only for parameterized cases, so that number is a floor over
  # that subset and reads 0 for a lane with no parameterized tests.
  echo "[$LOG_PREFIX] lane-report peak_started_tests=$(
    swift_test_peak_total_from_file "${SWIFT_TEST_PEAK_STARTED_FILE:-}"
  )"
  echo "[$LOG_PREFIX] lane-report peak_running_parameterized_cases=$(
    swift_test_peak_total_from_file "${SWIFT_TEST_PEAK_RUNNING_FILE:-}"
  )"

  rm -f "$LANE_TIMES_FILE" "${SWIFT_TEST_PEAK_STARTED_FILE:-}" "${SWIFT_TEST_PEAK_RUNNING_FILE:-}"
}

LANE_START_SECONDS="$SECONDS"
LANE_TIMES_FILE="$(mktemp "${TMPDIR:-/tmp}/agentstudio-lane-times.XXXXXX")"
SWIFT_TEST_PEAK_STARTED_FILE="$(mktemp "${TMPDIR:-/tmp}/agentstudio-lane-peak-started.XXXXXX")"
SWIFT_TEST_PEAK_RUNNING_FILE="$(mktemp "${TMPDIR:-/tmp}/agentstudio-lane-peak-running.XXXXXX")"
export SWIFT_TEST_PEAK_STARTED_FILE SWIFT_TEST_PEAK_RUNNING_FILE
trap print_closing_lane_report EXIT

if [ "${SWIFT_TEST_SKIP_PREBUILD:-0}" = "1" ]; then
  echo "[$LOG_PREFIX] skipping prebuild test bundles (SWIFT_TEST_SKIP_PREBUILD=1)"
else
  prebuild_swift_tests
fi

if [ "$#" -gt 0 ]; then
  requested_filter_mentions_suite() {
    local requested_suite="$1"
    shift

    local argument
    local filter_pattern
    local expects_filter_pattern=0
    for argument in "$@"; do
      filter_pattern=""
      if [ "$expects_filter_pattern" = "1" ]; then
        filter_pattern="$argument"
        expects_filter_pattern=0
      else
        case "$argument" in
          --filter)
            expects_filter_pattern=1
            continue
            ;;
          --filter=*)
            filter_pattern="${argument#--filter=}"
            ;;
          *)
            continue
            ;;
        esac
      fi

      case "$filter_pattern" in
        *"$requested_suite"*)
          return 0
          ;;
      esac
    done
    return 1
  }

  swift_test_args=("$@")
  if ! requested_filter_mentions_suite WebKitSerializedTests "$@"; then
    swift_test_args+=(--skip WebKitSerializedTests)
  fi
  if ! requested_filter_mentions_suite E2ESerializedTests "$@" &&
    ! requested_filter_mentions_suite ZmxE2ETests "$@"
  then
    swift_test_args+=(--skip E2ESerializedTests)
  fi
  if ! requested_filter_mentions_suite ZmxE2ETests "$@"; then
    swift_test_args+=(--skip ZmxE2ETests)
  fi

  run_swift_with_timeout \
    "requested swift test args: $*" \
    "$TIMEOUT_SECONDS" \
    env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) swift test --skip-build "${swift_test_args[@]}" \
    --build-path "$BUILD_PATH"
  exit $?
fi

case "$mode" in
  test)
    run_fast_non_webkit_swift_tests
    run_large_non_webkit_swift_tests
    run_webkit_suites

    echo "--- E2E serialized tests (serial) ---"
    if [ "${SWIFT_TEST_INCLUDE_E2E:-0}" = "1" ]; then
      run_swift_with_timeout \
        "E2ESerializedTests" \
        "$TIMEOUT_SECONDS" \
        env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" $(swift_test_parallelization_env_word) swift test --skip-build --filter E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
    else
      echo "[test] skipping E2ESerializedTests (SWIFT_TEST_INCLUDE_E2E=${SWIFT_TEST_INCLUDE_E2E:-0})"
    fi
    ;;
  test-fast)
    run_fast_non_webkit_swift_tests
    ;;
  test-large)
    run_large_non_webkit_swift_tests
    ;;
  test-webkit)
    run_webkit_suites
    ;;
esac
