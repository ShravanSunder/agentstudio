import AgentStudioInfrastructure
import Foundation
import Observation

/// One already-prepared Files input and the capture order that produced it.
/// The ticket is publication order, not a durable navigation generation.
package struct BridgePreparedFilesBinding: Sendable {
    package let ticket: Int
    package let binding: BridgeFilesSourceBinding
}

/// One keyed observation slot of a receiver's opened-document inventory.
package struct BridgeOpenedDocumentAtomKey: Hashable, Sendable {
    package let receiver: BridgeReceiver
    package let location: BridgeDocumentLocation

    package init(receiver: BridgeReceiver, location: BridgeDocumentLocation) {
        self.receiver = receiver
        self.location = location
    }
}

package enum BridgeOpenedDocumentAtomUpdate: Sendable {
    case set(BridgeDocumentLocation, BridgeOpenedDocumentEntry)
    case remove(BridgeDocumentLocation)

    /// Compute per-key observation updates off-main with the navigation rule.
    package static func difference(
        from current: BridgeNavigationRecord, to desired: BridgeNavigationRecord
    ) -> [Self] {
        var updates: [Self] = []
        for location in current.openedDocuments.keys where desired.openedDocuments[location] == nil {
            updates.append(.remove(location))
        }
        for (location, entry) in desired.openedDocuments
        where current.openedDocuments[location] != entry {
            updates.append(.set(location, entry))
        }
        return updates
    }
}

/// The receiver's observed state apart from its location-keyed inventory.
/// Copying these COW values into the observation index is constant work.
package struct BridgeNavigationObservedState: Hashable, Sendable {
    package let committedMemberLinks: [BridgeMemberLink]
    package let derivedCurrentCWDWorktreeId: WorktreeId?
    package let pullRequestLinks: [BridgePullRequestLink]
    package let filesFilter: BridgeFilesFilter
    package let selectedFilesDocument: BridgeDocumentLocation?
    package let reviewSelection: BridgeReviewSelection
    package let surface: BridgeNavigationSurface
    package let reviewComparisonsByWorktreeId: [UUID: WorkspaceBaseline]

    package init(_ record: BridgeNavigationRecord) {
        committedMemberLinks = record.committedMemberLinks
        derivedCurrentCWDWorktreeId = record.derivedCurrentCWDWorktreeId
        pullRequestLinks = record.pullRequestLinks
        filesFilter = record.filesFilter
        selectedFilesDocument = record.selectedFilesDocument
        reviewSelection = record.reviewSelection
        surface = record.surface
        reviewComparisonsByWorktreeId = record.reviewComparisonsByWorktreeId
    }
}

/// Fully prepared hydration input. Flattening the document keys runs off-main.
package struct BridgeNavigationAtomPublication: Sendable {
    package let records: [BridgeReceiver: BridgeNavigationRecord]
    package let observedStates: [BridgeReceiver: BridgeNavigationObservedState]
    package let openedEntries: [BridgeOpenedDocumentAtomKey: BridgeOpenedDocumentEntry]
    package let openedKeysByReceiver: [BridgeReceiver: Set<BridgeDocumentLocation>]

    @concurrent nonisolated package static func prepareOffMain(
        records: [BridgeReceiver: BridgeNavigationRecord]
    ) async -> Self {
        var observedStates: [BridgeReceiver: BridgeNavigationObservedState] = [:]
        var openedEntries: [BridgeOpenedDocumentAtomKey: BridgeOpenedDocumentEntry] = [:]
        var openedKeysByReceiver: [BridgeReceiver: Set<BridgeDocumentLocation>] = [:]
        for (receiver, record) in records {
            observedStates[receiver] = BridgeNavigationObservedState(record)
            for (location, entry) in record.openedDocuments {
                openedEntries[BridgeOpenedDocumentAtomKey(receiver: receiver, location: location)] = entry
                openedKeysByReceiver[receiver, default: []].insert(location)
            }
        }
        return Self(
            records: records, observedStates: observedStates,
            openedEntries: openedEntries, openedKeysByReceiver: openedKeysByReceiver)
    }
}

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
    @ObservationIgnored private let recordFamily = AtomFamily<BridgeReceiver, BridgeNavigationObservedState>(
        telemetryLabel: "bridge_navigation_record",
        isContentEqual: ==
    )
    @ObservationIgnored private let openedDocumentFamily = AtomFamily<
        BridgeOpenedDocumentAtomKey, BridgeOpenedDocumentEntry
    >(
        telemetryLabel: "bridge_opened_document",
        isContentEqual: ==
    )
    @ObservationIgnored private var rawRecordsByReceiver: [BridgeReceiver: BridgeNavigationRecord] = [:]
    @ObservationIgnored private var openedDocumentKeysByReceiver: [BridgeReceiver: Set<BridgeDocumentLocation>] = [:]
    @ObservationIgnored private let acceptedCommitRevision = AtomRevision()
    @ObservationIgnored private let preparedFilesBindingRevision = AtomRevision()
    @ObservationIgnored private let preparedFilesBindingFamily = AtomFamily<BridgeReceiver, BridgePreparedFilesBinding>(
        telemetryLabel: "bridge_prepared_files_binding",
        isContentEqual: { $0.ticket == $1.ticket }
    )

    /// Runtime only, never persisted: standalone Bridge panes whose legacy
    /// source could not be imported this launch. They present as unavailable
    /// and never mount an alternate legacy runtime.
    package private(set) var conversionUnavailablePaneIds: Set<UUID> = []

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
        guard recordFamily.value(for: receiver) != nil else { return nil }
        return rawRecordsByReceiver[receiver]
    }

    /// Observe one document without comparing or waking the receiver's whole inventory.
    package func openedDocumentEntry(
        for receiver: BridgeReceiver, at location: BridgeDocumentLocation
    ) -> BridgeOpenedDocumentEntry? {
        openedDocumentFamily.value(for: BridgeOpenedDocumentAtomKey(receiver: receiver, location: location))
    }

    package func preparedFilesBinding(for receiver: BridgeReceiver) -> BridgeFilesSourceBinding? {
        preparedFilesBindingFamily.value(for: receiver)?.binding
    }

    /// Publish only a preparation captured after the currently applied one.
    /// A new receiver's O(1) creation seed uses ticket zero.
    @discardableResult
    package func assignPreparedFilesBinding(
        _ binding: BridgeFilesSourceBinding, for receiver: BridgeReceiver, ticket: Int
    ) -> Bool {
        guard ticket > (preparedFilesBindingFamily.snapshotValue(for: receiver)?.ticket ?? -1) else { return false }
        let mutation = AtomMutationContext(aggregateRevision: preparedFilesBindingRevision)
        preparedFilesBindingFamily.setValue(
            BridgePreparedFilesBinding(ticket: ticket, binding: binding),
            for: receiver, mutation: mutation)
        mutation.commit()
        return true
    }

    /// Cold bridge for persistence capture, batch reconciliation and tests.
    package func recordsSnapshot() -> [BridgeReceiver: BridgeNavigationRecord] {
        rawRecordsByReceiver
    }

    /// Cold lookup of the receiver keyed by a pane, whichever kind it is.
    package func receiver(forPaneId paneId: UUID) -> BridgeReceiver? {
        BridgeReceiverKind.allCases
            .map { BridgeReceiver(paneId: paneId, kind: $0) }
            .first { recordFamily.snapshotValue(for: $0) != nil }
    }

    /// Publish one receiver's record. Equal records are suppressed.
    @discardableResult
    package func setRecord(
        _ record: BridgeNavigationRecord, for receiver: BridgeReceiver,
        openedDocumentUpdates: [BridgeOpenedDocumentAtomUpdate] = []
    ) -> Bool {
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        let revisionBefore = acceptedCommitRevision.value
        rawRecordsByReceiver[receiver] = record
        recordFamily.setValue(BridgeNavigationObservedState(record), for: receiver, mutation: mutation)
        for update in openedDocumentUpdates {
            switch update {
            case .set(let location, let entry):
                openedDocumentFamily.setValue(
                    entry, for: BridgeOpenedDocumentAtomKey(receiver: receiver, location: location),
                    mutation: mutation)
                openedDocumentKeysByReceiver[receiver, default: []].insert(location)
            case .remove(let location):
                openedDocumentFamily.removeValue(
                    for: BridgeOpenedDocumentAtomKey(receiver: receiver, location: location),
                    mutation: mutation)
                openedDocumentKeysByReceiver[receiver]?.remove(location)
            }
        }
        mutation.commit()
        let changed = acceptedCommitRevision.value != revisionBefore
        return changed
    }

    /// Apply one already-prepared Open files value at its canonical key.
    @discardableResult
    package func assignOpenedDocument(
        _ entry: BridgeOpenedDocumentEntry,
        at location: BridgeDocumentLocation,
        for receiver: BridgeReceiver
    ) -> Bool {
        guard var record = rawRecordsByReceiver[receiver] else { return false }
        record.openedDocuments[location] = entry
        return setRecord(record, for: receiver, openedDocumentUpdates: [.set(location, entry)])
    }

    @discardableResult
    package func removeRecord(for receiver: BridgeReceiver) -> Bool {
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        let revisionBefore = acceptedCommitRevision.value
        rawRecordsByReceiver[receiver] = nil
        recordFamily.removeValue(for: receiver, mutation: mutation)
        for location in openedDocumentKeysByReceiver.removeValue(forKey: receiver) ?? [] {
            openedDocumentFamily.removeValue(
                for: BridgeOpenedDocumentAtomKey(receiver: receiver, location: location),
                mutation: mutation)
        }
        mutation.commit()
        let preparedMutation = AtomMutationContext(aggregateRevision: preparedFilesBindingRevision)
        preparedFilesBindingFamily.removeValue(for: receiver, mutation: preparedMutation)
        preparedMutation.commit()
        let changed = acceptedCommitRevision.value != revisionBefore
        return changed
    }

    package func replaceConversionUnavailablePaneIds(_ paneIds: Set<UUID>) {
        guard conversionUnavailablePaneIds != paneIds else { return }
        conversionUnavailablePaneIds = paneIds
    }

    /// Replace every record at once (hydration). Unchanged records do not wake.
    package func replaceAllPreparedRecords(_ publication: BridgeNavigationAtomPublication) {
        let mutation = AtomMutationContext(aggregateRevision: acceptedCommitRevision)
        rawRecordsByReceiver = publication.records
        recordFamily.replaceAll(publication.observedStates, mutation: mutation)
        openedDocumentFamily.replaceAll(publication.openedEntries, mutation: mutation)
        openedDocumentKeysByReceiver = publication.openedKeysByReceiver
        mutation.commit()
    }
}
