import AgentStudioInfrastructure
import Foundation
import Observation

/// Live navigation records of every receiving Bridge in the workspace.
///
/// Lifecycle lane: local UX memory. The atom only assigns, equality-suppresses
/// and publishes; transitions come from `BridgeNavigationRules`, sequencing
/// from the App navigation handler, and SQL from the workspace local
/// repository through the store snapshot. Each receiver wakes only its own
/// keyed slot; `acceptedRevision` advances once per accepted change so the
/// workspace store can capture and acknowledge a specific revision.
@MainActor
@Observable
package final class BridgeNavigationAtom {
    @ObservationIgnored private let recordFamily = AtomFamily<BridgeReceiver, BridgeNavigationRecord>(
        telemetryLabel: "bridge_navigation_record",
        isContentEqual: ==
    )
    @ObservationIgnored private let acceptedCommitRevision = AtomRevision()

    package init() {}

    /// Advances once per accepted (unequal) change.
    package var acceptedRevision: Int {
        acceptedCommitRevision.value
    }

    package var membershipRevision: Int {
        recordFamily.membershipRevision
    }

    /// Keyed observed read for one receiver.
    package func record(for receiver: BridgeReceiver) -> BridgeNavigationRecord? {
        recordFamily.value(for: receiver)
    }

    /// Cold bridge for persistence capture, batch reconciliation and tests.
    package func recordsSnapshot() -> [BridgeReceiver: BridgeNavigationRecord] {
        recordFamily.snapshot()
    }

    /// Cold lookup of the receiver keyed by a pane, whichever kind it is.
    package func receiver(forPaneId paneId: UUID) -> BridgeReceiver? {
        BridgeReceiverKind.allCases
            .map { BridgeReceiver(paneId: paneId, kind: $0) }
            .first { recordFamily.snapshotValue(for: $0) != nil }
    }

    /// Publish one receiver's record. Equal records are suppressed.
    @discardableResult
    package func setRecord(_ record: BridgeNavigationRecord, for receiver: BridgeReceiver) -> Bool {
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        let revisionBefore = acceptedCommitRevision.value
        recordFamily.setValue(record, for: receiver, mutation: mutation)
        mutation.commit()
        return acceptedCommitRevision.value != revisionBefore
    }

    @discardableResult
    package func removeRecord(for receiver: BridgeReceiver) -> Bool {
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        let revisionBefore = acceptedCommitRevision.value
        recordFamily.removeValue(for: receiver, mutation: mutation)
        mutation.commit()
        return acceptedCommitRevision.value != revisionBefore
    }

    /// Replace every record at once (hydration). Unchanged records do not wake.
    package func replaceAllRecords(_ records: [BridgeReceiver: BridgeNavigationRecord]) {
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        recordFamily.replaceAll(records, mutation: mutation)
        mutation.commit()
    }
}
