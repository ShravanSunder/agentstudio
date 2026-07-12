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

echo "[admission-type-state] PASS paired fixture rows; mutation-owned rows require mutation receipt"
