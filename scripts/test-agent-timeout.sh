#!/usr/bin/env bash

set -euo pipefail

TIMEOUT_SECONDS="${SWIFT_TEST_TIMEOUT_SECONDS:-60}"
BUILD_DIR="${SWIFT_BUILD_DIR:-.build-agent-${RANDOM}}"
FILTER="${1:-}"
LOG_FILE="${2:-/tmp/test-output.txt}"

run_with_timeout() {
  local timeout_seconds=$1
  shift
  local logfile=$1
  shift
  local -a cmd=("$@")
  local status=0

  local swift_pid
  "${cmd[@]}" >"${logfile}" 2>&1 &
  swift_pid=$!

  local killer_pid
  (
    sleep "${timeout_seconds}"
    if kill -0 "${swift_pid}" 2>/dev/null; then
      kill -TERM "${swift_pid}" 2>/dev/null || true
      sleep 10
      kill -0 "${swift_pid}" 2>/dev/null && kill -KILL "${swift_pid}" 2>/dev/null || true
    fi
  ) &
  killer_pid=$!

  if ! wait "${swift_pid}"; then
    status=$?
  fi

  kill "${killer_pid}" 2>/dev/null || true

  if [ "${status}" -ne 0 ]; then
    if [ "${status}" -eq 143 ] || [ "${status}" -eq 137 ]; then
      echo "ERROR: swift test timed out after ${timeout_seconds}s" >&2
      echo "Build directory: ${BUILD_DIR}" >&2
      echo "Log file: ${logfile}" >&2
      return 124
    fi
    return "${status}"
  fi
}

if [ -n "${FILTER}" ]; then
  echo "Running swift test with build path: ${BUILD_DIR}, timeout: ${TIMEOUT_SECONDS}s, filter: ${FILTER}"
  CMD=(swift test --build-path "${BUILD_DIR}" --filter "${FILTER}")
else
  echo "Running swift test with build path: ${BUILD_DIR}, timeout: ${TIMEOUT_SECONDS}s"
  CMD=(swift test --build-path "${BUILD_DIR}")
fi

if run_with_timeout "${TIMEOUT_SECONDS}" "${LOG_FILE}" "${CMD[@]}"; then
  echo "PASS"
else
  echo "FAIL: $(tail -20 "${LOG_FILE}")"
  exit 1
fi
