#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

admission_sources=(Sources/AgentStudio/Core/RuntimeEventSystem/Admission/*.swift)
fixture_root="Tests/CompilerFixtures/AdmissionProtectedRegion"
compiler_arguments=(
  xcrun swiftc
  -typecheck
  -parse-as-library
  -strict-concurrency=complete
  -swift-version 6
  "${admission_sources[@]}"
)

verification_failed=0

verify_compiler_case() {
  local case_name="$1"
  local expected_status="$2"
  local fixture_path="$3"
  local diagnostic_category="$4"
  local diagnostic_pattern="$5"
  local output_path
  output_path="$(mktemp -t agentstudio-admission-compiler.XXXXXX)"

  set +e
  "${compiler_arguments[@]}" "$fixture_path" >"$output_path" 2>&1
  local exit_code=$?
  set -e

  if [[ "$expected_status" == "success" ]]; then
    if [[ $exit_code -ne 0 ]]; then
      echo "[admission-compiler] FAIL $case_name expected success (exit=$exit_code)"
      sed -n '1,120p' "$output_path"
      verification_failed=1
    else
      echo "[admission-compiler] PASS $case_name success"
    fi
  elif [[ $exit_code -eq 0 ]]; then
    echo "[admission-compiler] FAIL $case_name expected diagnostic category $diagnostic_category"
    verification_failed=1
  elif ! rg -q -- "$diagnostic_pattern" "$output_path"; then
    echo "[admission-compiler] FAIL $case_name missing diagnostic category $diagnostic_category"
    sed -n '1,120p' "$output_path"
    verification_failed=1
  else
    echo "[admission-compiler] PASS $case_name category=$diagnostic_category exit=$exit_code"
  fi

  rm -f "$output_path"
}

verify_compiler_case \
  "copyable-result" \
  "success" \
  "$fixture_root/GoodCopyableResult.swift" \
  "none" \
  "unused"
verify_compiler_case \
  "direct-construction" \
  "failure" \
  "$fixture_root/BadDirectConstruction.swift" \
  "inaccessible-construction" \
  "fileprivate|inaccessible"
verify_compiler_case \
  "direct-return" \
  "failure" \
  "$fixture_root/BadDirectReturn.swift" \
  "noncopyable-result" \
  "Copyable|noncopyable|noncopyable type"
verify_compiler_case \
  "token-storage" \
  "failure" \
  "$fixture_root/BadTokenStorage.swift" \
  "noncopyable-storage" \
  "Copyable|noncopyable|must be declared '~Copyable'"
verify_compiler_case \
  "escaping-capture-gap" \
  "success" \
  "$fixture_root/EscapingCaptureCompilerGap.swift" \
  "deferred-to-s1h" \
  "unused"
verify_compiler_case \
  "journal-raw-state-access" \
  "failure" \
  "$fixture_root/BadJournalRawStateAccess.swift" \
  "private-journal-state" \
  "private protection level|inaccessible"
verify_compiler_case \
  "journal-raw-lock-access" \
  "failure" \
  "$fixture_root/BadJournalRawLockAccess.swift" \
  "private-journal-lock" \
  "private protection level|inaccessible"

forbidden_lifetimes_flag="-enable-experimental-feature"' Lifetimes'
forbidden_manifest_api='.enableExperimentalFeature(''"Lifetimes"'')'
forbidden_non_escaping="~"'Escapable'
forbidden_lifetime_attribute="@_"'lifetime'
configuration_scan_roots=(
  Sources/AgentStudio/Core/RuntimeEventSystem/Admission
  Package.swift
  Tools/AgentStudioArchitectureLint/Package.swift
  .mise.toml
  .github/workflows
  scripts
)

for forbidden_pattern in \
  "$forbidden_lifetimes_flag" \
  "$forbidden_manifest_api" \
  "$forbidden_non_escaping" \
  "$forbidden_lifetime_attribute"
do
  if rg -n -F -- "$forbidden_pattern" "${configuration_scan_roots[@]}"; then
    echo "[admission-compiler] FAIL forbidden experimental lifetime configuration"
    verification_failed=1
  fi
done

if ! scripts/verify-admission-type-state-compiler.sh; then
  echo "[admission-compiler] FAIL strict type-state verifier"
  verification_failed=1
fi

if [[ $verification_failed -ne 0 ]]; then
  exit 1
fi

echo "[admission-compiler] PASS stable ownership and no-experimental guard"
