#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

fixture_root="Tests/CompilerFixtures/FilesystemObservationAuthority"
debug_bin_path="$(swift build --disable-sandbox --show-bin-path)"
module_directory="$debug_bin_path/Modules"
module_path="$module_directory/AgentStudio.swiftmodule"
build_description_path="$debug_bin_path/description.json"
diagnostic_output="$(mktemp -t agentstudio-filesystem-authority-compiler.XXXXXX)"
trap 'rm -f "$diagnostic_output"' EXIT

if [[ ! -e "$module_path" ]]; then
  echo "[filesystem-authority-compiler] BLOCKED built AgentStudio module not found: $module_path" >&2
  echo "[filesystem-authority-compiler] Run swift build --disable-sandbox before this verifier." >&2
  exit 2
fi

if [[ ! -f "$build_description_path" ]] || ! command -v jq >/dev/null; then
  echo "[filesystem-authority-compiler] BLOCKED SwiftPM compiler metadata unavailable" >&2
  echo "[filesystem-authority-compiler] Expected description=$build_description_path and jq on PATH." >&2
  exit 2
fi

swiftpm_compiler_arguments=()
while IFS= read -r argument; do
  case "$argument" in
    -enable-batch-mode | -incremental | -j* | -parseable-output | -serialize-diagnostics)
      continue
      ;;
  esac
  swiftpm_compiler_arguments+=("$argument")
done < <(
  jq -r \
    '.swiftCommands[] | select(.moduleName == "AgentStudio") | .otherArguments[]' \
    "$build_description_path"
)

if [[ ${#swiftpm_compiler_arguments[@]} -eq 0 ]]; then
  echo "[filesystem-authority-compiler] BLOCKED AgentStudio compiler metadata missing" >&2
  exit 2
fi

compiler_arguments=(
  xcrun swiftc
  -typecheck
  -parse-as-library
  -strict-concurrency=complete
  -swift-version 6
  -I "$module_directory"
  "${swiftpm_compiler_arguments[@]}"
)

typecheck_fixture() {
  local fixture_path="$1"
  : >"$diagnostic_output"

  set +e
  "${compiler_arguments[@]}" "$fixture_path" >"$diagnostic_output" 2>&1
  local exit_code=$?
  set -e

  return "$exit_code"
}

verify_negative_fixture() {
  local case_name="$1"
  local fixture_name="$2"
  local diagnostic_category="$3"
  local symbol_pattern="$4"
  local diagnostic_pattern="$5"
  local fixture_path="$fixture_root/$fixture_name"

  if typecheck_fixture "$fixture_path"; then
    echo "[filesystem-authority-compiler] FAIL $case_name unexpectedly compiled"
    return 1
  fi

  if ! rg -q -- "$symbol_pattern" "$diagnostic_output" \
    || ! rg -q -- "$diagnostic_pattern" "$diagnostic_output"
  then
    echo "[filesystem-authority-compiler] FAIL $case_name unrelated compiler diagnostic"
    echo "[filesystem-authority-compiler] Expected category=$diagnostic_category symbol=$symbol_pattern"
    sed -n '1,120p' "$diagnostic_output"
    return 1
  fi

  echo "[filesystem-authority-compiler] PASS $case_name category=$diagnostic_category"
}

if ! typecheck_fixture "$fixture_root/ImportAgentStudio.swift"; then
  echo "[filesystem-authority-compiler] BLOCKED AgentStudio module import control failed" >&2
  sed -n '1,120p' "$diagnostic_output" >&2
  exit 2
fi
echo "[filesystem-authority-compiler] PASS AgentStudio module import control"

verification_failed=0

verify_negative_fixture \
  "removed-callback-producer-port" \
  "RemovedCallbackProducerPort.swift" \
  "removed-type" \
  "FilesystemObservationCallbackProducerPort" \
  "cannot find (type )?'FilesystemObservationCallbackProducerPort' in scope" \
  || verification_failed=1
verify_negative_fixture \
  "removed-callback-signaler-port" \
  "RemovedCallbackSignalerPort.swift" \
  "removed-type" \
  "FilesystemObservationCallbackSignalerPort" \
  "cannot find (type )?'FilesystemObservationCallbackSignalerPort' in scope" \
  || verification_failed=1
verify_negative_fixture \
  "direct-callback-lease-construction" \
  "DirectCallbackLeaseConstruction.swift" \
  "inaccessible-construction" \
  "FSEventCallbackLease" \
  "initializer is inaccessible.*fileprivate.*protection level" \
  || verification_failed=1
verify_negative_fixture \
  "removed-raw-callback-lease-admission-signature" \
  "RemovedRawCallbackLeaseAdmissionSignature.swift" \
  "removed-method-signature" \
  "withOneShotCallbackAdmission" \
  "extra arguments at positions #[0-9]+.*in call|incorrect argument labels in call" \
  || verification_failed=1
verify_negative_fixture \
  "direct-callback-lease-admission-authority-construction" \
  "DirectCallbackLeaseAdmissionAuthorityConstruction.swift" \
  "inaccessible-construction" \
  "CallbackLeaseAdmissionAuthority" \
  "initializer is inaccessible.*fileprivate.*protection level" \
  || verification_failed=1
verify_negative_fixture \
  "direct-callback-admission-port-construction" \
  "DirectCallbackAdmissionPortConstruction.swift" \
  "inaccessible-construction" \
  "FilesystemObservationCallbackAdmissionPort" \
  "initializer is inaccessible.*fileprivate.*protection level" \
  || verification_failed=1
verify_negative_fixture \
  "direct-lease-drain-receipt-construction" \
  "DirectLeaseDrainReceiptConstruction.swift" \
  "inaccessible-construction" \
  "DarwinFSEventRegistrationLeaseDrainReceipt" \
  "initializer is inaccessible.*fileprivate.*protection level" \
  || verification_failed=1
verify_negative_fixture \
  "direct-callback-admission-operation-construction" \
  "DirectCallbackAdmissionOperationConstruction.swift" \
  "private-authority-operation" \
  "FilesystemObservationCallbackAdmissionOperation" \
  "cannot find 'FilesystemObservationCallbackAdmissionOperation' in scope" \
  || verification_failed=1
verify_negative_fixture \
  "direct-native-lifecycle-operation-construction" \
  "DirectNativeLifecycleOperationConstruction.swift" \
  "private-authority-operation" \
  "FilesystemObservationNativeLifecycleOperation" \
  "cannot find 'FilesystemObservationNativeLifecycleOperation' in scope" \
  || verification_failed=1
verify_negative_fixture \
  "removed-callback-only-port-factory" \
  "RemovedCallbackOnlyPortFactory.swift" \
  "removed-method" \
  "callbackAdmissionPort" \
  "has no member 'callbackAdmissionPort'" \
  || verification_failed=1
verify_negative_fixture \
  "removed-raw-mailbox-offer" \
  "RemovedRawMailboxOffer.swift" \
  "removed-method" \
  "offer" \
  "has no member 'offer'" \
  || verification_failed=1
verify_negative_fixture \
  "direct-contribution-identity-construction" \
  "DirectContributionIdentityConstruction.swift" \
  "inaccessible-construction" \
  "FilesystemObservationContributionIdentity" \
  "initializer is inaccessible.*fileprivate.*protection level" \
  || verification_failed=1

if [[ $verification_failed -ne 0 ]]; then
  exit 1
fi

echo "[filesystem-authority-compiler] PASS all forbidden construction probes rejected"
