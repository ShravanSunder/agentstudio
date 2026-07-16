import Foundation

enum WorkspaceTabCursorSnapshotKey: Hashable, Sendable {
    case activeTab
}

struct WorkspaceTabCursorSnapshotPreparationError: Error, Equatable {
    let rejection: WorkspaceSnapshotPreparationRejection
}

@MainActor
final class WorkspaceTabCursorPersistenceAdapter {
    private enum ActiveTabMembershipChange {
        case unchanged
        case insert
        case remove(UUID)
        case replace(UUID)
    }

    private static let snapshotMembershipLimits = WorkspaceStateSnapshotMembershipLimits(
        maximumKeyCount: 1,
        maximumRawKeyBytes: 1
    )

    private let atom: WorkspaceTabCursorAtom
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let snapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<
        WorkspaceTabCursorSnapshotKey,
        UUID
    >()

    init(atom: WorkspaceTabCursorAtom, revisionOwner: WorkspacePersistenceRevisionOwner) {
        self.atom = atom
        self.revisionOwner = revisionOwner
    }

    func makePersistenceSnapshotParticipant() -> SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >.typed(
            participantID: .activeTab,
            keyedParticipant: snapshotParticipant,
            membershipLimits: Self.snapshotMembershipLimits,
            orderedBaseKeys: { [atom] in atom.activeTabId == nil ? [] : [.activeTab] },
            currentValue: { [self] key in persistenceSnapshotValue(for: key) },
            projection: .init(
                itemIDForKey: { _ in .activeTab },
                projectItem: { _, tabID in
                    .init(item: .activeTab(tabID), estimatedByteCount: 16)
                }
            )
        )
    }

    func prepareHydrate(
        activeTabId: UUID?,
        availableTabIds: [UUID],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        let replacement = activeTabId.flatMap { availableTabIds.contains($0) ? $0 : nil } ?? availableTabIds.first
        return try prepareActiveTabReplacement(
            replacement,
            for: preparation
        )
    }

    func prepareSelectTab(
        _ tabId: UUID?,
        availableTabIds: [UUID],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        let replacement: UUID?
        if let tabId {
            replacement = availableTabIds.contains(tabId) ? tabId : atom.activeTabId
        } else {
            replacement = nil
        }
        return try prepareActiveTabReplacement(
            replacement,
            for: preparation
        )
    }

    func prepareRemoveTab(
        _ tabId: UUID,
        remainingTabIds: [UUID],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        try prepareActiveTabReplacement(
            atom.activeTabId == tabId ? remainingTabIds.last : atom.activeTabId,
            for: preparation
        )
    }

    func registerInitialActiveTabReplacement(
        token _: borrowing WorkspaceCompositionPreinstallToken,
        _ activeTabId: UUID?,
        availableTabIds: [UUID],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) -> WorkspaceParticipantRegistration {
        let replacement = activeTabId.flatMap { availableTabIds.contains($0) ? $0 : nil } ?? availableTabIds.first
        return revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [atom, revisionOwner = self.revisionOwner] in
                precondition(
                    revisionOwner.validateActiveCommit(preparation.transaction) == .active,
                    "workspace tab-cursor replacement requires its exact active transaction"
                )
                atom.replaceActiveTab(replacement)
            },
            cancel: {}
        )
    }

    func persistenceSnapshotValue(
        for key: WorkspaceTabCursorSnapshotKey
    ) -> WorkspaceStateSnapshotStoredValue<UUID> {
        switch key {
        case .activeTab:
            atom.activeTabId.map(WorkspaceStateSnapshotStoredValue.value) ?? .absent
        }
    }

    func capturePersistencePreimage(
        _ capture: WorkspaceTabCursorPersistenceCapture,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let mutations: [WorkspaceStateSnapshotParticipantMutation<WorkspaceTabCursorSnapshotKey, UUID>]
        switch capture {
        case .insertion:
            if let activeTabID = atom.activeTabId {
                throw WorkspaceTabCursorPersistenceCaptureError.activeTabAlreadyExists(activeTabID)
            }
            mutations = [.insert(.init(key: .activeTab, rawKeyByteCount: 1))]
        case .valueChange:
            guard let activeTabID = atom.activeTabId else {
                throw WorkspaceTabCursorPersistenceCaptureError.activeTabMissing
            }
            mutations = [.replaceValue(key: .activeTab, currentValue: .value(activeTabID))]
        case .removal:
            guard let activeTabID = atom.activeTabId else {
                throw WorkspaceTabCursorPersistenceCaptureError.activeTabMissing
            }
            mutations = [.remove(.init(key: .activeTab, currentValue: .value(activeTabID)))]
        }

        switch snapshotParticipant.prepare(mutations, for: preparation, revisionOwner: revisionOwner) {
        case .prepared:
            break
        case .rejected(let rejection):
            throw WorkspaceTabCursorPersistenceCaptureError.snapshotPreparation(rejection)
        }
    }

    private func prepareActiveTabReplacement(
        _ replacement: UUID?,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        guard replacement != atom.activeTabId else {
            return .unchanged(revisionOwner.committedRevision)
        }
        let mutations = persistenceMutations(replacement: replacement)
        switch snapshotParticipant.prepare(
            mutations,
            for: preparation,
            revisionOwner: revisionOwner
        ) {
        case .prepared:
            return .commit(
                preparation.commit { [atom] in
                    atom.replaceActiveTab(replacement)
                    return preparation.transaction.proposedRevision
                }
            )
        case .rejected(let rejection):
            throw WorkspaceTabCursorSnapshotPreparationError(rejection: rejection)
        }
    }

    private func persistenceMutations(
        replacement: UUID?
    ) -> [WorkspaceStateSnapshotParticipantMutation<WorkspaceTabCursorSnapshotKey, UUID>] {
        switch activeTabMembershipChange(replacement: replacement) {
        case .unchanged:
            []
        case .insert:
            [.insert(.init(key: .activeTab, rawKeyByteCount: 1))]
        case .remove(let currentTabID):
            [.remove(.init(key: .activeTab, currentValue: .value(currentTabID)))]
        case .replace(let currentTabID):
            [.replaceValue(key: .activeTab, currentValue: .value(currentTabID))]
        }
    }

    private func activeTabMembershipChange(replacement: UUID?) -> ActiveTabMembershipChange {
        if let currentTabID = atom.activeTabId {
            if let replacement {
                return currentTabID == replacement ? .unchanged : .replace(currentTabID)
            }
            return .remove(currentTabID)
        }
        return replacement == nil ? .unchanged : .insert
    }
}
