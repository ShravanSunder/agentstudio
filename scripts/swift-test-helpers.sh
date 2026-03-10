#!/usr/bin/env bash
# Shared test helper functions for mise tasks.
#
# Required variables (set by caller before sourcing):
#   LOG_PREFIX         - Log prefix, e.g. "test" or "test-coverage"
#   TIMEOUT_SECONDS    - Timeout in seconds for swift commands
#   BUILD_PATH         - Swift build path
#
# Optional variables:
#   EXTRA_SWIFT_TEST_ARGS - Additional swift test flags (e.g. "--enable-code-coverage")

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

  "$@" &
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
    kill -TERM "$command_pid" 2>/dev/null || true
    sleep 2
    kill -KILL "$command_pid" 2>/dev/null || true
    pkill -9 -f "swiftpm-testing-helper|swift test|swift-build|AgentStudioPackageTests" || true
    wait "$command_pid" 2>/dev/null || true
    return 124
  fi

  set +e
  wait "$command_pid"
  local command_status=$?
  set -e

  return "$command_status"
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
    # shellcheck disable=SC2086
    output=$(run_swift_with_timeout "$filter" "$TIMEOUT_SECONDS" \
      env AGENT_STUDIO_BENCHMARK_MODE=off swift test ${EXTRA_SWIFT_TEST_ARGS:-} \
      --filter "$filter" --build-path "$BUILD_PATH" 2>&1)
    local command_status=$?
    set -e
    echo "$output"

    if [ "$command_status" -eq 0 ]; then
      return 0
    fi
    if [ "$command_status" -eq 124 ]; then
      return 124
    fi

    if [ "$command_status" -ne 124 ] && echo "$output" | grep -Eq "unexpected signal code [0-9]+"; then
      local signal_code
      signal_code=$(echo "$output" | grep -Eo "unexpected signal code [0-9]+" | grep -Eo "[0-9]+" | tail -n 1)
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
