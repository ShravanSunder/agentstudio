#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

manifest_path="Tests/CompilerFixtures/AdmissionTypeState/Manifest.txt"
admission_sources=(Sources/AgentStudio/Core/RuntimeEventSystem/Admission/*.swift)
compiler_arguments=(
  xcrun swiftc
  -typecheck
  -parse-as-library
  -strict-concurrency=complete
  -swift-version 6
  "${admission_sources[@]}"
)

latest_target="Sources/AgentStudio/Core/RuntimeEventSystem/Admission/LatestValueMailbox.swift"
gather_target="Sources/AgentStudio/Core/RuntimeEventSystem/Admission/BoundedGatherMailbox.swift"
ordered_target="Sources/AgentStudio/Core/RuntimeEventSystem/Admission/OrderedFactJournal.swift"
ordered_replay_target="Sources/AgentStudio/Core/RuntimeEventSystem/Admission/OrderedFactJournalReplayMaterialization.swift"
ordered_preflight_target="Sources/AgentStudio/Core/RuntimeEventSystem/Admission/OrderedFactJournalStateQueries.swift"
doorbell_target="Sources/AgentStudio/Core/RuntimeEventSystem/Admission/AdmissionDoorbell.swift"

latest_anchor='final class LatestValueMailbox<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {'
gather_anchor=$'final class BoundedGatherMailbox<Key, Payload>: @unchecked Sendable\nwhere Key: Hashable & Sendable, Payload: Sendable {'
ordered_anchor='final class OrderedFactJournal<Fact: Sendable, Snapshot: Sendable>: @unchecked Sendable {'
ordered_replay_anchor='enum OrderedFactReplayCapture<Fact: Sendable, Snapshot: Sendable>: Sendable {'
ordered_preflight_anchor='enum OrderedFactOfferPreflight: Sendable {'
doorbell_anchor='final class AdmissionDoorbell: @unchecked Sendable {'

expected_mutation_ids=(
  "ordered-replay-immediate-reader-authority"
  "ordered-replay-registered-missing-reader-authority"
  "latest-cleanup-unavailable-authority"
  "latest-cleanup-unavailable-custody"
  "gather-cleanup-unavailable-authority"
  "gather-cleanup-unavailable-custody"
  "ordered-cleanup-unavailable-authority"
  "ordered-cleanup-unavailable-custody"
  "latest-cleanup-detached-empty"
  "gather-cleanup-detached-empty"
  "ordered-cleanup-detached-empty"
  "latest-offer-rejected-missing-release-value"
  "latest-offer-accepted-carrying-release-value"
  "gather-recovery-stamp-without-custody"
  "gather-recovery-custody-without-stamp"
  "latest-no-drain-awaiting-initial-presentation"
  "latest-no-drain-awaiting-rebind-presentation"
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

active_target=""
active_backup=""
active_preimage_hash=""

hash_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

restore_active_mutation() {
  if [[ -n "$active_target" && -n "$active_backup" && -f "$active_backup" ]]; then
    cp "$active_backup" "$active_target"
    local restored_hash
    restored_hash="$(hash_file "$active_target")"
    if [[ "$restored_hash" != "$active_preimage_hash" ]]; then
      echo "[admission-type-state-mutation] FATAL restore hash mismatch: $active_target" >&2
      exit 3
    fi
    rm -f "$active_backup"
  fi
  active_target=""
  active_backup=""
  active_preimage_hash=""
}

trap 'restore_active_mutation' EXIT
trap 'restore_active_mutation; exit 130' INT
trap 'restore_active_mutation; exit 143' TERM HUP

apply_checked_insertion() {
  local target_file="$1"
  local exact_anchor="$2"
  local insertion="$3"
  MUTATION_ANCHOR="$exact_anchor" MUTATION_INSERTION="$insertion" \
    /usr/bin/python3 - "$target_file" <<'PY'
import os
import pathlib
import sys

target = pathlib.Path(sys.argv[1])
source = target.read_text()
anchor = os.environ["MUTATION_ANCHOR"]
insertion = os.environ["MUTATION_INSERTION"]
count = source.count(anchor)
if count != 1:
    raise SystemExit(f"expected one exact anchor in {target}, found {count}")
target.write_text(source.replace(anchor, anchor + "\n" + insertion, 1))
PY
}

typecheck_admission() {
  local output_path="$1"
  set +e
  "${compiler_arguments[@]}" >"$output_path" 2>&1
  local exit_code=$?
  set -e
  return "$exit_code"
}

diagnostic_matches_injected_mutation() {
  local output_path="$1"
  local target_file="$2"
  local mutation_symbol="$3"
  local diagnostic_pattern="$4"
  MUTATION_TARGET="$target_file" MUTATION_SYMBOL="$mutation_symbol" \
    MUTATION_DIAGNOSTIC_PATTERN="$diagnostic_pattern" \
    /usr/bin/python3 - "$output_path" <<'PY'
import os
import pathlib
import re
import sys

output = pathlib.Path(sys.argv[1]).read_text()
target = re.escape(os.environ["MUTATION_TARGET"])
symbol = os.environ["MUTATION_SYMBOL"]
diagnostic = re.compile(os.environ["MUTATION_DIAGNOSTIC_PATTERN"])
start = re.compile(rf"^{target}:\d+:\d+: error: .+$", re.MULTILINE)
matches = list(start.finditer(output))
for index, match in enumerate(matches):
    end = matches[index + 1].start() if index + 1 < len(matches) else len(output)
    block = output[match.start():end]
    if symbol in block and diagnostic.search(block):
        raise SystemExit(0)
raise SystemExit(1)
PY
}

configure_latest_mutation() {
  target_file="$latest_target"
  exact_anchor="$latest_anchor"
  positive_selector="AdmissionLatestValueMailboxTests"
  diagnostic_pattern='extra argument|argument passed to call that takes no arguments|has no associated values|missing argument|not compatible with expected argument type|cannot convert value of type'
}

configure_gather_mutation() {
  target_file="$gather_target"
  exact_anchor="$gather_anchor"
  positive_selector="AdmissionBoundedGatherMailboxTests"
  diagnostic_pattern='extra argument|argument passed to call that takes no arguments|has no associated values|missing argument|not compatible with expected argument type|cannot convert value of type'
}

configure_ordered_mutation() {
  target_file="$ordered_target"
  exact_anchor="$ordered_anchor"
  positive_selector="AdmissionOrderedFactJournalTests"
  diagnostic_pattern='extra argument|argument passed to call that takes no arguments|has no associated values|missing argument|not compatible with expected argument type|cannot convert value of type'
}

configure_mutation() {
  local mutation_id="$1"
  target_file=""
  exact_anchor=""
  insertion=""
  positive_selector=""
  diagnostic_pattern=""

  case "$mutation_id" in
    latest-cleanup-unavailable-authority)
      configure_latest_mutation
      insertion='    private func __mutationLatestUnavailableAuthority() { let _: CleanupDetachTransition = .unavailable(.empty, authority: AdmissionOpaqueIdentity()) }'
      positive_selector="AdmissionLatestCleanupFinalizationTests"
      ;;
    latest-cleanup-unavailable-custody)
      configure_latest_mutation
      insertion='    private func __mutationLatestUnavailableCustody() { let _: CleanupDetachTransition = .unavailable(.empty, custody: fatalError()) }'
      positive_selector="AdmissionLatestCleanupFinalizationTests"
      ;;
    latest-cleanup-detached-empty)
      configure_latest_mutation
      insertion='    private func __mutationLatestDetachedEmpty() { let _: CleanupDetachTransition = .detached(authority: AdmissionOpaqueIdentity(), custody: [], retiredBatches: []) }'
      positive_selector="AdmissionLatestCleanupFinalizationTests"
      ;;
    latest-offer-rejected-missing-release-value)
      configure_latest_mutation
      insertion='    private func __mutationLatestRejectedMissingRelease() { let _: OfferTransition = .rejected(result: .closed) }'
      positive_selector="AdmissionLatestValueMailboxCapacityTests"
      ;;
    latest-offer-accepted-carrying-release-value)
      configure_latest_mutation
      insertion='    private func __mutationLatestAcceptedWithRelease() { let _: OfferTransition = .accepted(.closed, incomingValue: fatalError()) }'
      positive_selector="AdmissionLatestValueMailboxCapacityTests"
      ;;
    latest-no-drain-awaiting-initial-presentation)
      configure_latest_mutation
      insertion='    private func __mutationLatestNoDrainAwaitingInitial() { let _: ActiveDrainState = .awaitingInitialPresentation(nil) }'
      positive_selector="AdmissionLatestValueMailboxTests"
      ;;
    latest-no-drain-awaiting-rebind-presentation)
      configure_latest_mutation
      insertion='    private func __mutationLatestNoDrainAwaitingRebind() { let _: ActiveDrainState = .awaitingRebindPresentation(nil) }'
      positive_selector="AdmissionRebindDoorbellCompositionTests"
      ;;
    latest-presentation-without-active-drain)
      configure_latest_mutation
      insertion='    private func __mutationLatestPresentationWithoutDrain() { let _: ActiveDrainState = .presented(nil) }'
      positive_selector="AdmissionLatestValueMailboxTests"
      ;;
    latest-nonempty-cleanup-age)
      configure_latest_mutation
      insertion='    private func __mutationLatestMissingCleanupAge() { _ = InFlightCleanup(authority: AdmissionOpaqueIdentity(), retainedValueCount: 1, oldestRetainedTimestamp: nil) }'
      positive_selector="AdmissionAgeMeasurementTests"
      ;;
    gather-cleanup-unavailable-authority)
      configure_gather_mutation
      insertion='    private func __mutationGatherUnavailableAuthority() { let _: CleanupTurnOutcome = .empty(authority: AdmissionOpaqueIdentity()) }'
      positive_selector="AdmissionBoundedGatherMailboxMetadataCustodyTests"
      ;;
    gather-cleanup-unavailable-custody)
      configure_gather_mutation
      insertion='    private func __mutationGatherUnavailableCustody() { let _: CleanupTurnOutcome = .empty(custody: fatalError()) }'
      positive_selector="AdmissionBoundedGatherMailboxMetadataCustodyTests"
      ;;
    gather-cleanup-detached-empty)
      configure_gather_mutation
      insertion='    private func __mutationGatherDetachedEmpty() { _ = CleanupDetachment(entries: [], accounting: fatalError()) }'
      positive_selector="AdmissionBoundedGatherMailboxMetadataCustodyTests"
      ;;
    gather-recovery-stamp-without-custody)
      configure_gather_mutation
      insertion='    private func __mutationGatherStampWithoutCustody() { _ = RecoveryCustodyReference(stamp: .sequenced(1)) }'
      positive_selector="AdmissionBoundedGatherMailboxTests"
      ;;
    gather-recovery-custody-without-stamp)
      configure_gather_mutation
      insertion='    private func __mutationGatherCustodyWithoutStamp() { _ = RecoveryCustodyReference(identity: fatalError()) }'
      positive_selector="AdmissionBoundedGatherMailboxTests"
      ;;
    gather-acknowledgement-optional-released-lease)
      configure_gather_mutation
      insertion='    private func __mutationGatherAcceptedWithoutLease() { let _: AcknowledgementOutcome = .accepted(.accepted(wake: .noWake), releasedLease: nil) }'
      positive_selector="AdmissionBoundedGatherMailboxTests"
      ;;
    gather-offer-optional-retry-result)
      configure_gather_mutation
      insertion='    private func __mutationGatherRetryWithResult() { let _: OfferAttemptResult = .prepareRecoveryCustodyEpoch(result: .closed) }'
      positive_selector="AdmissionBoundedGatherMailboxTests"
      ;;
    gather-resolved-admission-correlated-booleans)
      configure_gather_mutation
      insertion='    private func __mutationGatherResolvedBooleans() { let _: ResolvedOfferAttempt = .retain(fatalError(), requiresRecovery: true) }'
      positive_selector="AdmissionBoundedGatherMailboxTests"
      ;;
    gather-recovery-advance-stamp-escalation-boolean)
      configure_gather_mutation
      insertion='    private func __mutationGatherRecoveryEscalationBoolean() { let _: RecoveryAdvance = .escalated(.sequenced(1), didEscalate: false) }'
      positive_selector="AdmissionBoundedGatherMailboxTests"
      ;;
    gather-no-lease-awaiting-presentation)
      configure_gather_mutation
      insertion='    private func __mutationGatherNoLeaseAwaiting() { let _: ActiveLeaseState = .awaitingPresentation(nil) }'
      positive_selector="AdmissionRebindDoorbellCompositionTests"
      ;;
    gather-no-lease-presented)
      configure_gather_mutation
      insertion='    private func __mutationGatherNoLeasePresented() { let _: ActiveLeaseState = .presented(nil) }'
      positive_selector="AdmissionRebindDoorbellCompositionTests"
      ;;
    gather-presentation-without-active-lease)
      configure_gather_mutation
      insertion='    private func __mutationGatherPresentationWithoutLease() { let _: ActiveLeaseState = .noActiveLease(presentation: true) }'
      positive_selector="AdmissionRebindDoorbellCompositionTests"
      ;;
    doorbell-wait-optional-result)
      target_file="$doorbell_target"
      exact_anchor="$doorbell_anchor"
      insertion='    private func __mutationDoorbellSuspendedWithResult() { let _: WaitRegistrationTransition = .suspended(result: .finished) }'
      positive_selector="AdmissionDoorbellTests"
      diagnostic_pattern='extra argument|argument passed to call that takes no arguments|has no associated values'
      ;;
    ordered-replay-immediate-reader-authority)
      target_file="$ordered_replay_target"
      exact_anchor="$ordered_replay_anchor"
      insertion='    private static func __mutationImmediateReplayWithReader() -> Self { .immediate(.invalidated, readerIdentity: AdmissionOpaqueIdentity()) }'
      positive_selector="AdmissionOrderedFactJournalTests"
      diagnostic_pattern='extra argument|argument passed to call that takes no arguments'
      ;;
    ordered-replay-registered-missing-reader-authority)
      target_file="$ordered_replay_target"
      exact_anchor="$ordered_replay_anchor"
      insertion='    private static func __mutationRegisteredReplayWithoutReader() -> Self { .registered(history: fatalError()) }'
      positive_selector="AdmissionOrderedFactJournalTests"
      diagnostic_pattern='missing argument|incorrect argument label|expects argument'
      ;;
    ordered-cleanup-unavailable-authority)
      configure_ordered_mutation
      insertion='    private func __mutationOrderedUnavailableAuthority() { let _: CleanupDetachTransition = .unavailable(.empty, authority: AdmissionOpaqueIdentity()) }'
      positive_selector="AdmissionOrderedFactJournalPhysicalCustodyTests"
      ;;
    ordered-cleanup-unavailable-custody)
      configure_ordered_mutation
      insertion='    private func __mutationOrderedUnavailableCustody() { let _: CleanupDetachTransition = .unavailable(.empty, custody: fatalError()) }'
      positive_selector="AdmissionOrderedFactJournalPhysicalCustodyTests"
      ;;
    ordered-cleanup-detached-empty)
      configure_ordered_mutation
      insertion='    private func __mutationOrderedDetachedEmpty() { let _: CleanupCustody = .snapshots([]) }'
      positive_selector="AdmissionOrderedFactJournalPhysicalCustodyTests"
      ;;
    ordered-offer-optional-preflight-result)
      target_file="$ordered_preflight_target"
      exact_anchor="$ordered_preflight_anchor"
      insertion='    private static let __mutationOrderedAdmitWithRejection: Self = .admit(rejection: .closed)'
      positive_selector="AdmissionOrderedFactJournalPhysicalCustodyTests"
      diagnostic_pattern='extra argument|argument passed to call that takes no arguments|has no associated values'
      ;;
    ordered-product-gap-transfer-state)
      configure_ordered_mutation
      insertion='    private func __mutationOrderedProductGapWithoutGap() { let _: ProductGapState = .pendingTransfer(nil, firstRetainedAt: .zero) }'
      positive_selector="AdmissionOrderedFactJournalCorrectionTests"
      ;;
    ordered-drain-presentation-state)
      configure_ordered_mutation
      insertion='    private func __mutationOrderedDrainWithoutToken() { let _: DrainLease = .awaitingPresentation(nil, fatalError()) }'
      positive_selector="AdmissionOrderedFactJournalTests"
      ;;
    ordered-nonempty-cleanup-age)
      configure_ordered_mutation
      insertion='    private func __mutationOrderedMissingCleanupAge() { _ = InFlightCleanup(authority: AdmissionOpaqueIdentity(), release: fatalError(), oldestRetainedAt: nil) }'
      positive_selector="AdmissionAgeMeasurementTests"
      ;;
    *)
      return 1
      ;;
  esac
}

declare -A expected_mutation_id_set=()
declare -A runner_mutation_id_set=()
for expected_mutation_id in "${expected_mutation_ids[@]}"; do
  if [[ -n "${expected_mutation_id_set[$expected_mutation_id]:-}" ]]; then
    echo "[admission-type-state-mutation] FAIL duplicate canonical mutation id: $expected_mutation_id" >&2
    exit 2
  fi
  expected_mutation_id_set["$expected_mutation_id"]=1
done
while IFS= read -r runner_mutation_id; do
  if [[ -n "${runner_mutation_id_set[$runner_mutation_id]:-}" ]]; then
    echo "[admission-type-state-mutation] FAIL duplicate runner mutation case: $runner_mutation_id" >&2
    exit 2
  fi
  runner_mutation_id_set["$runner_mutation_id"]=1
done < <(
  awk '
    /^configure_mutation\(\)/ { in_function = 1 }
    in_function && /case "\$mutation_id" in/ { in_case = 1; next }
    in_case && /^    \*\)/ { exit }
    in_case && /^    [a-z0-9-]+\)$/ {
      value = $0
      sub(/^    /, "", value)
      sub(/\)$/, "", value)
      print value
    }
  ' "$0"
)
for expected_mutation_id in "${expected_mutation_ids[@]}"; do
  if [[ -z "${runner_mutation_id_set[$expected_mutation_id]:-}" ]]; then
    echo "[admission-type-state-mutation] FAIL runner missing canonical mutation: $expected_mutation_id" >&2
    exit 2
  fi
done
for runner_mutation_id in "${!runner_mutation_id_set[@]}"; do
  if [[ -z "${expected_mutation_id_set[$runner_mutation_id]:-}" ]]; then
    echo "[admission-type-state-mutation] FAIL unreachable noncanonical runner case: $runner_mutation_id" >&2
    exit 2
  fi
done

declare -a mutation_ids=()
declare -A seen_mutation_ids=()
while IFS='|' read -r case_id oracle _ _ _ _ _ mutation_id; do
  [[ -z "$case_id" || "$case_id" == \#* ]] && continue
  [[ "$oracle" == "mutation-owned" || "$oracle" == "legacy-fixture-current-mutation" ]] || continue
  if [[ -z "$mutation_id" || "$mutation_id" == "-" || -n "${seen_mutation_ids[$mutation_id]:-}" ]]; then
    echo "[admission-type-state-mutation] FAIL invalid or duplicate mutation id: $mutation_id" >&2
    exit 2
  fi
  seen_mutation_ids["$mutation_id"]=1
  mutation_ids+=("$mutation_id")
done <"$manifest_path"
for expected_mutation_id in "${expected_mutation_ids[@]}"; do
  if [[ -z "${seen_mutation_ids[$expected_mutation_id]:-}" ]]; then
    echo "[admission-type-state-mutation] FAIL manifest missing canonical mutation: $expected_mutation_id" >&2
    exit 2
  fi
done
for manifest_mutation_id in "${!seen_mutation_ids[@]}"; do
  if [[ -z "${expected_mutation_id_set[$manifest_mutation_id]:-}" ]]; then
    echo "[admission-type-state-mutation] FAIL unexpected noncanonical manifest mutation: $manifest_mutation_id" >&2
    exit 2
  fi
done
echo "[admission-type-state-mutation] PASS canonical mutation inventory ${#expected_mutation_ids[@]}"

declare -A positive_selector_rows=()
declare -a positive_selector_order=()
for mutation_id in "${mutation_ids[@]}"; do
  if ! configure_mutation "$mutation_id"; then
    echo "[admission-type-state-mutation] FAIL unmapped manifest row: $mutation_id" >&2
    exit 1
  fi
  if [[ ! -f "$target_file" || -z "$positive_selector" || -z "$diagnostic_pattern" ]]; then
    echo "[admission-type-state-mutation] FAIL incomplete runner case: $mutation_id" >&2
    exit 1
  fi
  mutation_symbol="$(printf '%s\n' "$insertion" | rg -o '__mutation[A-Za-z0-9]+' | head -1)"
  if [[ -z "$mutation_symbol" ]]; then
    echo "[admission-type-state-mutation] FAIL missing injected symbol: $mutation_id" >&2
    exit 1
  fi
  if ! rg -q -F -- "$positive_selector" Tests/AgentStudioTests/Core/PaneRuntime/Admission; then
    echo "[admission-type-state-mutation] FAIL missing positive selector: $mutation_id -> $positive_selector" >&2
    exit 1
  fi
  if [[ -z "${positive_selector_rows[$positive_selector]:-}" ]]; then
    positive_selector_order+=("$positive_selector")
  fi
  positive_selector_rows["$positive_selector"]+="$mutation_id "
  echo "[admission-type-state-mutation] CONTROL-MAP row=$mutation_id selector=$positive_selector"

  preimage_output="$(mktemp -t agentstudio-type-state-preimage.XXXXXX)"
  if ! typecheck_admission "$preimage_output"; then
    echo "[admission-type-state-mutation] FAIL preimage does not typecheck: $mutation_id" >&2
    sed -n '1,100p' "$preimage_output"
    rm -f "$preimage_output"
    exit 1
  fi
  rm -f "$preimage_output"

  active_target="$target_file"
  active_backup="$(mktemp -t agentstudio-type-state-source.XXXXXX)"
  cp "$active_target" "$active_backup"
  active_preimage_hash="$(hash_file "$active_target")"

  if ! apply_checked_insertion "$active_target" "$exact_anchor" "$insertion"; then
    echo "[admission-type-state-mutation] FAIL unique anchor/preimage: $mutation_id" >&2
    restore_active_mutation
    exit 1
  fi

  mutation_output="$(mktemp -t agentstudio-type-state-mutation.XXXXXX)"
  row_failed=0
  if typecheck_admission "$mutation_output"; then
    echo "[admission-type-state-mutation] FAIL mutation unexpectedly compiled: $mutation_id" >&2
    row_failed=1
  elif ! diagnostic_matches_injected_mutation \
    "$mutation_output" "$active_target" "$mutation_symbol" "$diagnostic_pattern"
  then
    echo "[admission-type-state-mutation] FAIL diagnostic mismatch: $mutation_id" >&2
    sed -n '1,100p' "$mutation_output"
    row_failed=1
  else
    echo "[admission-type-state-mutation] PASS $mutation_id selector=$positive_selector preimage=$active_preimage_hash"
  fi
  rm -f "$mutation_output"
  restore_active_mutation
  if [[ $row_failed -ne 0 ]]; then
    exit 1
  fi
done

runtime_control_index=0
for positive_selector in "${positive_selector_order[@]}"; do
  runtime_output="$(mktemp -t agentstudio-type-state-runtime.XXXXXX)"
  if [[ $runtime_control_index -eq 0 ]]; then
    runtime_skip_prebuild=0
    runtime_prebuild_label="fresh"
  else
    runtime_skip_prebuild=1
    runtime_prebuild_label="reused"
  fi
  set +e
  SWIFT_TEST_SKIP_PREBUILD="$runtime_skip_prebuild" \
    SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS="${SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS:-180}" \
    mise run test -- --filter "$positive_selector" \
    >"$runtime_output" 2>&1
  runtime_exit_code=$?
  set -e
  if [[ $runtime_exit_code -ne 0 ]]; then
    echo "[admission-type-state-mutation] FAIL runtime control selector=$positive_selector exit=$runtime_exit_code" >&2
    sed -n '1,160p' "$runtime_output"
    rm -f "$runtime_output"
    exit 1
  fi
  runtime_test_count="$(
    rg -o 'Test run with [0-9]+ tests? .*passed' "$runtime_output" \
      | tail -1 \
      | rg -o '[0-9]+' \
      | head -1 \
      || true
  )"
  if [[ -z "$runtime_test_count" || "$runtime_test_count" -eq 0 ]]; then
    echo "[admission-type-state-mutation] FAIL runtime control reported no tests: $positive_selector" >&2
    sed -n '1,160p' "$runtime_output"
    rm -f "$runtime_output"
    exit 1
  fi
  echo "[admission-type-state-mutation] RUNTIME-CONTROL selector=$positive_selector tests=$runtime_test_count prebuild=$runtime_prebuild_label rows=${positive_selector_rows[$positive_selector]}"
  rm -f "$runtime_output"
  runtime_control_index=$((runtime_control_index + 1))
done

echo "[admission-type-state-mutation] PASS ${#mutation_ids[@]} mutation rows with exact restoration"
