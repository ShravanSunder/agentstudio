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
TIMEOUT_SECONDS="${SWIFT_TEST_TIMEOUT_SECONDS:-60}"
PREBUILD_TIMEOUT_SECONDS="${SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS:-$TIMEOUT_SECONDS}"

LOG_PREFIX="$mode"
EXTRA_SWIFT_TEST_ARGS=""
source scripts/swift-test-helpers.sh

echo "[$LOG_PREFIX] BUILD_PATH=$BUILD_PATH"
echo "[$LOG_PREFIX] TIMEOUT_SECONDS=$TIMEOUT_SECONDS"
echo "[$LOG_PREFIX] PREBUILD_TIMEOUT_SECONDS=$PREBUILD_TIMEOUT_SECONDS"

if [ "$mode" = "test-prebuild" ]; then
  prebuild_swift_tests
  exit $?
fi

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
    env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test --skip-build "${swift_test_args[@]}" \
    --build-path "$BUILD_PATH"
  exit $?
fi

case "$mode" in
  test)
    run_non_serialized_swift_tests "non-serialized suites"
    run_webkit_suites

    echo "--- E2E serialized tests (serial) ---"
    if [ "${SWIFT_TEST_INCLUDE_E2E:-0}" = "1" ]; then
      run_swift_with_timeout \
        "E2ESerializedTests" \
        "$TIMEOUT_SECONDS" \
        env AGENT_STUDIO_BENCHMARK_MODE=off AGENTSTUDIO_TRACE_BACKEND="${SWIFT_TEST_TRACE_BACKEND:-jsonl}" swift test --skip-build --filter E2ESerializedTests --skip ZmxE2ETests --build-path "$BUILD_PATH"
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
