#!/usr/bin/env bash
set -euo pipefail

mode="${1:-test}"
shift || true

case "$mode" in
  test|test-fast|test-webkit|test-otlp-smoke)
    ;;
  *)
    echo "run-swift-test-task: unknown mode '$mode'" >&2
    exit 2
    ;;
esac

source "${PROJECT_ROOT}/scripts/swift-build-slot.sh" debug
BUILD_PATH="$SWIFT_BUILD_DIR"
TIMEOUT_SECONDS="${SWIFT_TEST_TIMEOUT_SECONDS:-60}"

LOG_PREFIX="$mode"
EXTRA_SWIFT_TEST_ARGS=""
source scripts/swift-test-helpers.sh

echo "[$LOG_PREFIX] BUILD_PATH=$BUILD_PATH"
echo "[$LOG_PREFIX] TIMEOUT_SECONDS=$TIMEOUT_SECONDS"

prebuild_swift_tests

if [ "$#" -gt 0 ]; then
  run_swift_with_timeout \
    "requested swift test args: $*" \
    "$TIMEOUT_SECONDS" \
    env AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build "$@" --build-path "$BUILD_PATH"
  exit $?
fi

case "$mode" in
  test)
    run_non_serialized_swift_tests "non-serialized suites"
    run_webkit_suites
    run_otlp_bootstrap_smoke

    echo "--- E2E serialized tests (serial) ---"
    if [ "${SWIFT_TEST_INCLUDE_E2E:-0}" = "1" ]; then
      run_swift_with_timeout \
        "E2ESerializedTests" \
        "$TIMEOUT_SECONDS" \
        env AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --filter E2ESerializedTests --build-path "$BUILD_PATH"
    else
      echo "[test] skipping E2ESerializedTests (SWIFT_TEST_INCLUDE_E2E=${SWIFT_TEST_INCLUDE_E2E:-0})"
    fi

    echo "--- Zmx E2E tests (serial) ---"
    if [ "${SWIFT_TEST_INCLUDE_ZMX_E2E:-0}" = "1" ]; then
      run_swift_with_timeout \
        "ZmxE2ETests" \
        "$TIMEOUT_SECONDS" \
        env AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --filter ZmxE2ETests --build-path "$BUILD_PATH"
    else
      echo "[test] skipping ZmxE2ETests (SWIFT_TEST_INCLUDE_ZMX_E2E=${SWIFT_TEST_INCLUDE_ZMX_E2E:-0})"
    fi
    ;;
  test-fast)
    run_non_serialized_swift_tests "fast non-WebKit suites"
    ;;
  test-webkit)
    run_webkit_suites
    ;;
  test-otlp-smoke)
    run_otlp_bootstrap_smoke
    ;;
esac
