#!/usr/bin/env bash
set -euo pipefail

readonly PROOF_PREFIX="filesystem-observation-proof"
readonly ZERO_TESTS_STATUS=65
readonly SCRIPT_DIRECTORY="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd -P
)"
readonly PROJECT_ROOT="$(
  cd -- "$SCRIPT_DIRECTORY/.." >/dev/null 2>&1
  pwd -P
)"
readonly MANIFEST_PATH="$PROJECT_ROOT/Tests/ProofManifests/FilesystemObservationSuites/manifest.txt"
readonly NEGATIVE_SELF_TEST_SELECTOR="FilesystemObservationProofVerifierDeliberatelyMissingSelector"

selector_invocation_count=0
temporary_files=()

cleanup_temporary_files() {
  if [[ "${#temporary_files[@]}" -gt 0 ]]; then
    rm -f -- "${temporary_files[@]}"
  fi
}

print_usage() {
  echo "usage: $0 --gate pre-w2b|w2b" >&2
}

parse_gate() {
  if [[ $# -ne 2 || "$1" != "--gate" ]]; then
    print_usage
    return 2
  fi

  case "$2" in
    pre-w2b | w2b)
      printf '%s\n' "$2"
      ;;
    *)
      print_usage
      return 2
      ;;
  esac
}

parse_test_summary() {
  local output_path="$1"
  local summary
  summary="$({
    grep -Eo 'Test run with [0-9]+ tests? in [0-9]+ suites? passed' "$output_path" || true
  } | tail -n 1)"

  if [[ -z "$summary" ]]; then
    return "$ZERO_TESTS_STATUS"
  fi

  local test_count
  local suite_count
  test_count="$(printf '%s\n' "$summary" | sed -E 's/^Test run with ([0-9]+) tests?.*/\1/')"
  suite_count="$(printf '%s\n' "$summary" | sed -E 's/.* in ([0-9]+) suites? passed$/\1/')"
  if [[ "$test_count" -eq 0 || "$suite_count" -eq 0 ]]; then
    return "$ZERO_TESTS_STATUS"
  fi

  printf '%s %s\n' "$test_count" "$suite_count"
}

run_selector() {
  local task="$1"
  local selector="$2"
  local output_path="$3"
  local skip_prebuild=1
  if [[ "$selector_invocation_count" -eq 0 ]]; then
    skip_prebuild=0
  fi
  selector_invocation_count=$((selector_invocation_count + 1))

  local task_status
  if (
    cd -- "$PROJECT_ROOT"
    SWIFT_TEST_SKIP_PREBUILD="$skip_prebuild" mise run "$task" -- --filter "$selector"
  ) >"$output_path" 2>&1; then
    task_status=0
  else
    task_status=$?
  fi

  cat -- "$output_path"
  if [[ "$task_status" -ne 0 ]]; then
    echo "[$PROOF_PREFIX] FAIL task=$task selector=$selector exit=$task_status" >&2
    return "$task_status"
  fi

  local parsed_summary
  local summary_status
  if parsed_summary="$(parse_test_summary "$output_path")"; then
    summary_status=0
  else
    summary_status=$?
  fi
  if [[ "$summary_status" -ne 0 ]]; then
    echo "[$PROOF_PREFIX] REJECTED-ZERO task=$task selector=$selector" >&2
    return "$summary_status"
  fi

  local test_count
  local suite_count
  read -r test_count suite_count <<<"$parsed_summary"
  echo "[$PROOF_PREFIX] PASS task=$task selector=$selector tests=$test_count suites=$suite_count"
}

run_negative_self_test() {
  local output_path="$1"
  local self_test_status

  if run_selector "test" "$NEGATIVE_SELF_TEST_SELECTOR" "$output_path"; then
    self_test_status=0
  else
    self_test_status=$?
  fi

  if [[ "$self_test_status" -ne "$ZERO_TESTS_STATUS" ]]; then
    echo "[$PROOF_PREFIX] FAIL negative-self-test expected=$ZERO_TESTS_STATUS actual=$self_test_status" >&2
    return 1
  fi

  echo "[$PROOF_PREFIX] PASS negative-self-test rejected-selector=$NEGATIVE_SELF_TEST_SELECTOR status=$self_test_status"
}

validate_manifest_row() {
  local row_number="$1"
  local row_gate="$2"
  local task="$3"
  local selector="$4"
  local extra_field="$5"

  if [[ -n "$extra_field" ]]; then
    echo "[$PROOF_PREFIX] FAIL manifest row $row_number has more than three fields" >&2
    return 1
  fi
  case "$row_gate" in
    all | pre-w2b | w2b) ;;
    *)
      echo "[$PROOF_PREFIX] FAIL manifest row $row_number has invalid gate '$row_gate'" >&2
      return 1
      ;;
  esac
  case "$task" in
    test | test-large) ;;
    *)
      echo "[$PROOF_PREFIX] FAIL manifest row $row_number has invalid task '$task'" >&2
      return 1
      ;;
  esac
  if [[ ! "$selector" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo "[$PROOF_PREFIX] FAIL manifest row $row_number has unsafe selector '$selector'" >&2
    return 1
  fi
}

run_manifest_gate() {
  local selected_gate="$1"
  local selected_row_count=0
  local row_number=0
  local row_gate
  local task
  local selector
  local extra_field

  while IFS='|' read -r row_gate task selector extra_field || [[ -n "${row_gate:-}" ]]; do
    row_number=$((row_number + 1))
    if [[ -z "${row_gate:-}" || "${row_gate:0:1}" == "#" ]]; then
      continue
    fi
    validate_manifest_row "$row_number" "$row_gate" "$task" "$selector" "${extra_field:-}"
    if [[ "$row_gate" != "all" && "$row_gate" != "$selected_gate" ]]; then
      continue
    fi

    selected_row_count=$((selected_row_count + 1))
    local output_path
    output_path="$(mktemp "${TMPDIR:-/tmp}/agentstudio-filesystem-proof-selector.XXXXXX")"
    temporary_files+=("$output_path")
    run_selector \
      "$task" \
      "$selector" \
      "$output_path"
  done <"$MANIFEST_PATH"

  if [[ "$selected_row_count" -eq 0 ]]; then
    echo "[$PROOF_PREFIX] FAIL manifest selected no rows for gate=$selected_gate" >&2
    return 1
  fi
  echo "[$PROOF_PREFIX] PASS gate=$selected_gate selectors=$selected_row_count"
}

main() {
  local selected_gate
  selected_gate="$(parse_gate "$@")"
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "[$PROOF_PREFIX] FAIL missing manifest: $MANIFEST_PATH" >&2
    return 1
  fi

  trap cleanup_temporary_files EXIT

  local negative_self_test_output
  negative_self_test_output="$(mktemp "${TMPDIR:-/tmp}/agentstudio-filesystem-proof-negative.XXXXXX")"
  temporary_files+=("$negative_self_test_output")
  run_negative_self_test "$negative_self_test_output"
  run_manifest_gate "$selected_gate"
}

main "$@"
