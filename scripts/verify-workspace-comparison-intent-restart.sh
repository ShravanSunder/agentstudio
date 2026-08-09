#!/bin/bash

set -euo pipefail

project_root=$(git rev-parse --show-toplevel)
restart_root=$(mktemp -d "${TMPDIR:-/tmp}/agentstudio-comparison-intent-restart.XXXXXX")
pane_id="019c0000-0000-7000-8000-0000000000a2"
process_a_log="$restart_root/process-a.log"
process_b_log="$restart_root/process-b.log"

export AGENTSTUDIO_COMPARISON_INTENT_RESTART_ROOT="$restart_root"
export AGENTSTUDIO_COMPARISON_INTENT_RESTART_PANE_ID="$pane_id"

run_filtered_process() {
  local test_filter=$1
  local output_path=$2
  (
    cd "$project_root"
    mise run test:swift -- --filter "$test_filter"
  ) >"$output_path" 2>&1 &
  launched_process_id=$!
}

run_filtered_process \
  workspaceComparisonIntentRestartProcessACommits \
  "$process_a_log"
process_a_invocation_pid=$launched_process_id
if wait "$process_a_invocation_pid"; then
  process_a_exit_code=0
else
  process_a_exit_code=$?
fi
sed -n '1,240p' "$process_a_log"
if [[ "$process_a_exit_code" -ne 0 ]]; then
  echo "comparison-intent restart: process A exited abnormally with $process_a_exit_code" >&2
  exit "$process_a_exit_code"
fi

process_a_test_pid=$(rg -o 'COMPARISON_INTENT_PROCESS_A_TEST_PID=[0-9]+' "$process_a_log" | tail -n 1 | cut -d= -f2)
if [[ -z "$process_a_test_pid" ]]; then
  echo "comparison-intent restart: process A did not report its Swift test PID" >&2
  exit 1
fi
if ! rg -q 'COMPARISON_INTENT_PROCESS_A_FLUSH=persisted' "$process_a_log"; then
  echo "comparison-intent restart: process A did not report a persisted flush" >&2
  exit 1
fi
if ! rg -q 'COMPARISON_INTENT_PROCESS_A_TRANSITION=contribution>stagedOnly>contribution' "$process_a_log"; then
  echo "comparison-intent restart: process A did not report the retained-target transition" >&2
  exit 1
fi

run_filtered_process \
  workspaceComparisonIntentRestartProcessBRestores \
  "$process_b_log"
process_b_invocation_pid=$launched_process_id
if wait "$process_b_invocation_pid"; then
  process_b_exit_code=0
else
  process_b_exit_code=$?
fi
sed -n '1,240p' "$process_b_log"
if [[ "$process_b_exit_code" -ne 0 ]]; then
  echo "comparison-intent restart: process B exited abnormally with $process_b_exit_code" >&2
  exit "$process_b_exit_code"
fi

process_b_test_pid=$(rg -o 'COMPARISON_INTENT_PROCESS_B_TEST_PID=[0-9]+' "$process_b_log" | tail -n 1 | cut -d= -f2)
if [[ -z "$process_b_test_pid" ]]; then
  echo "comparison-intent restart: process B did not report its Swift test PID" >&2
  exit 1
fi
if [[ "$process_a_test_pid" == "$process_b_test_pid" ]]; then
  echo "comparison-intent restart: expected distinct Swift test process IDs" >&2
  exit 1
fi
if ! rg -q 'COMPARISON_INTENT_PROCESS_B_CALCULATED_ORIGIN_PERSISTED=false' "$process_b_log"; then
  echo "comparison-intent restart: process B did not prove calculated origin absence" >&2
  exit 1
fi
if ! rg -q 'COMPARISON_INTENT_PROCESS_B_EXACT_PAYLOAD_SHAPE=true' "$process_b_log"; then
  echo "comparison-intent restart: process B did not prove the exact persisted payload shape" >&2
  exit 1
fi

echo "comparison-intent restart receipt"
echo "  isolated root: $restart_root"
echo "  pane UUID: $pane_id"
echo "  process A invocation PID: $process_a_invocation_pid"
echo "  process A Swift test PID: $process_a_test_pid"
echo "  process A exit: normal ($process_a_exit_code)"
echo "  process A transition: contribution > stagedOnly > contribution (target retained)"
echo "  process A flush: persisted"
echo "  process B invocation PID: $process_b_invocation_pid"
echo "  process B Swift test PID: $process_b_test_pid"
echo "  process B exit: normal ($process_b_exit_code)"
echo "  process B restore: exact pane UUID and symbolic contribution intent"
echo "  persisted payload: exact intent-only shape"
echo "  calculated target/HEAD/base/snapshot origin persisted: false"
