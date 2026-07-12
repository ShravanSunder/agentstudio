#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

fixture_root="Tests/CompilerFixtures/AdmissionTypeState"
manifest_path="$fixture_root/Manifest.txt"
admission_sources=(Sources/AgentStudio/Core/RuntimeEventSystem/Admission/*.swift)
compiler_arguments=(
  xcrun swiftc
  -typecheck
  -parse-as-library
  -strict-concurrency=complete
  -swift-version 6
  "${admission_sources[@]}"
)

expected_case_ids=(
  "latest-rejected-offer-with-wake"
  "gather-rejected-offer-with-wake"
  "cleanup-quantum-nil-bytes"
  "cleanup-release-nil-bytes"
  "gather-contracted-without-revision"
  "gather-empty-ordinary-lease"
  "immediate-replay-completion-with-wake"
  "immediate-replay-with-registered-result"
  "registered-replay-with-immediate-result"
  "immediate-replay-capture-with-reader"
  "registered-replay-capture-without-reader"
  "latest-empty-drain"
  "latest-missing-age-drain"
  "latest-conservative-age-drain"
  "ordered-empty-fact-drain"
  "ordered-missing-age-drain"
  "ordered-conservative-age-drain"
  "split-journal-initial-snapshot"
  "ordered-current-lifecycle-boolean"
  "diagnostic-current-with-gap"
  "diagnostic-noncurrent-without-gap"
  "diagnostic-invalidated-without-case"
  "doorbell-pending-and-waiting"
  "doorbell-finished-and-pending"
  "doorbell-finished-and-waiting"
  "latest-unavailable-cleanup-with-authority"
  "latest-unavailable-cleanup-with-custody"
  "gather-unavailable-cleanup-with-authority"
  "gather-unavailable-cleanup-with-custody"
  "ordered-unavailable-cleanup-with-authority"
  "ordered-unavailable-cleanup-with-custody"
  "latest-detached-empty-cleanup"
  "gather-detached-empty-cleanup"
  "ordered-detached-empty-cleanup"
  "latest-rejected-capture-without-incoming-value"
  "latest-accepted-capture-with-release-value"
  "gather-recovery-stamp-without-custody"
  "gather-recovery-custody-without-stamp"
  "latest-no-drain-awaiting-initial"
  "latest-no-drain-awaiting-rebind"
  "latest-presentation-without-active-drain"
  "doorbell-wait-optional-result"
  "gather-acknowledgement-optional-released-lease"
  "gather-offer-optional-retry-result"
  "ordered-offer-optional-preflight-result"
  "gather-resolved-admission-correlated-booleans"
  "gather-recovery-advance-stamp-escalation-boolean"
  "gather-no-lease-awaiting-presentation"
  "gather-no-lease-presented"
  "gather-presentation-without-active-lease"
  "ordered-product-gap-transfer-state"
  "ordered-drain-presentation-state"
  "latest-nonempty-cleanup-age"
  "ordered-nonempty-cleanup-age"
)

declare -A expected_case_id_set=()
declare -A manifest_case_id_set=()
for expected_case_id in "${expected_case_ids[@]}"; do
  if [[ -n "${expected_case_id_set[$expected_case_id]:-}" ]]; then
    echo "[admission-type-state] FAIL duplicate canonical case id: $expected_case_id" >&2
    exit 2
  fi
  expected_case_id_set["$expected_case_id"]=1
done
while IFS='|' read -r manifest_case_id _; do
  [[ -z "$manifest_case_id" || "$manifest_case_id" == \#* ]] && continue
  if [[ -n "${manifest_case_id_set[$manifest_case_id]:-}" ]]; then
    echo "[admission-type-state] FAIL duplicate manifest case id: $manifest_case_id" >&2
    exit 2
  fi
  manifest_case_id_set["$manifest_case_id"]=1
done <"$manifest_path"
for expected_case_id in "${expected_case_ids[@]}"; do
  if [[ -z "${manifest_case_id_set[$expected_case_id]:-}" ]]; then
    echo "[admission-type-state] FAIL manifest missing canonical case: $expected_case_id" >&2
    exit 2
  fi
done
for manifest_case_id in "${!manifest_case_id_set[@]}"; do
  if [[ -z "${expected_case_id_set[$manifest_case_id]:-}" ]]; then
    echo "[admission-type-state] FAIL unexpected noncanonical manifest case: $manifest_case_id" >&2
    exit 2
  fi
done
echo "[admission-type-state] PASS canonical case inventory ${#expected_case_ids[@]}"

declare -a unexpected_legacy_successes=()
declare -a post_cut_failures=()
declare -a mutation_owned_rows=()
declare -A seen_ids=()
declare -A referenced_fixtures=()
new_api_available=0

if rg -q 'struct NonEmptyAdmissionBatch' \
  Sources/AgentStudio/Core/RuntimeEventSystem/Admission/*.swift
then
  new_api_available=1
fi

typecheck_fixture() {
  local fixture_path="$1"
  local output_path="$2"
  set +e
  "${compiler_arguments[@]}" "$fixture_path" >"$output_path" 2>&1
  local exit_code=$?
  set -e
  return "$exit_code"
}

verify_manifest_fixture_path() {
  local relative_path="$1"
  local expected_directory="$2"
  [[ "$relative_path" =~ ^${expected_directory}/[A-Za-z0-9]+\.swift$ ]]
  [[ -f "$fixture_root/$relative_path" ]]
  referenced_fixtures["$fixture_root/$relative_path"]=1
}

while IFS='|' read -r case_id oracle legacy_fixture current_negative \
  current_positive diagnostic_category diagnostic_pattern mutation_id
do
  [[ -z "$case_id" || "$case_id" == \#* ]] && continue
  if [[ -n "${seen_ids[$case_id]:-}" ]]; then
    echo "[admission-type-state] FAIL duplicate manifest id: $case_id"
    exit 2
  fi
  seen_ids["$case_id"]=1

  case "$oracle" in
    fixture)
      verify_manifest_fixture_path "$legacy_fixture" Legacy
      verify_manifest_fixture_path "$current_negative" CurrentNegative
      verify_manifest_fixture_path "$current_positive" CurrentPositive
      [[ "$mutation_id" == "-" ]]
      ;;
    legacy-fixture-current-mutation)
      verify_manifest_fixture_path "$legacy_fixture" Legacy
      [[ "$current_negative" == "-" && "$current_positive" == "-" ]]
      [[ "$mutation_id" != "-" ]]
      mutation_owned_rows+=("$case_id:$mutation_id")
      ;;
    mutation-owned)
      [[ "$legacy_fixture" == "-" && "$current_negative" == "-" ]]
      [[ "$current_positive" == "-" && "$mutation_id" != "-" ]]
      mutation_owned_rows+=("$case_id:$mutation_id")
      continue
      ;;
    *)
      echo "[admission-type-state] FAIL invalid oracle for $case_id: $oracle"
      exit 2
      ;;
  esac

  legacy_output="$(mktemp -t agentstudio-type-state-legacy.XXXXXX)"
  if typecheck_fixture "$fixture_root/$legacy_fixture" "$legacy_output"; then
    unexpected_legacy_successes+=("$case_id")
  else
    echo "[admission-type-state] PASS legacy rejected $case_id"
  fi
  rm -f "$legacy_output"

  [[ "$oracle" == "fixture" ]] || continue
  if [[ $new_api_available -eq 0 ]]; then
    echo "[admission-type-state] PENDING $case_id post-cut diagnostic validation; new API absent"
    continue
  fi

  positive_output="$(mktemp -t agentstudio-type-state-positive.XXXXXX)"
  if typecheck_fixture "$fixture_root/$current_positive" "$positive_output"; then
    echo "[admission-type-state] PASS current positive $case_id"
  else
    post_cut_failures+=("$case_id:positive-control")
    sed -n '1,80p' "$positive_output"
  fi
  rm -f "$positive_output"

  negative_output="$(mktemp -t agentstudio-type-state-negative.XXXXXX)"
  if typecheck_fixture "$fixture_root/$current_negative" "$negative_output"; then
    post_cut_failures+=("$case_id:negative-unexpected-success")
  elif rg -q -- "$diagnostic_pattern" "$negative_output"; then
    echo "[admission-type-state] PASS current negative $case_id category=$diagnostic_category"
  else
    post_cut_failures+=("$case_id:diagnostic-$diagnostic_category")
    sed -n '1,80p' "$negative_output"
  fi
  rm -f "$negative_output"
done <"$manifest_path"

while IFS= read -r fixture_path; do
  if [[ -z "${referenced_fixtures[$fixture_path]:-}" ]]; then
    echo "[admission-type-state] FAIL unmanifested fixture: $fixture_path"
    exit 2
  fi
done < <(find "$fixture_root" -mindepth 2 -type f -name '*.swift' | LC_ALL=C sort)

for mutation_row in "${mutation_owned_rows[@]}"; do
  echo "[admission-type-state] MUTATION-OWNED $mutation_row"
done

if ((${#unexpected_legacy_successes[@]} > 0)); then
  echo "[admission-type-state] RED unexpected legacy successes (${#unexpected_legacy_successes[@]}):"
  printf '  %s\n' "${unexpected_legacy_successes[@]}"
fi
if ((${#post_cut_failures[@]} > 0)); then
  echo "[admission-type-state] FAIL post-cut controls (${#post_cut_failures[@]}):"
  printf '  %s\n' "${post_cut_failures[@]}"
fi

if ((${#unexpected_legacy_successes[@]} > 0 || ${#post_cut_failures[@]} > 0)); then
  exit 1
fi

"$repository_root/scripts/verify-admission-type-state-mutations.sh"

echo "[admission-type-state] PASS paired fixture and mutation-owned rows"
