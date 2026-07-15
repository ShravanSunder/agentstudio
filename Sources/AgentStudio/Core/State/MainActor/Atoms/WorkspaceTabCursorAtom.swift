import Foundation
import Observation

enum WorkspaceTabCursorSnapshotKey: Hashable, Sendable {
    case activeTab
}

struct WorkspaceTabCursorSnapshotPreparationError: Error, Equatable {
    let rejection: WorkspaceSnapshotPreparationRejection
}

@MainActor
@Observable
final class WorkspaceTabCursorAtom {
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

    private let persistenceSnapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<
        WorkspaceTabCursorSnapshotKey,
        UUID
    >()

    var activeTabId: UUID? { storedActiveTabId }

    private var storedActiveTabId: UUID?

    init(activeTabId: UUID? = nil) {
        storedActiveTabId = activeTabId
    }

    func hydrate(activeTabId: UUID?, availableTabIds: [UUID]) {
        if let activeTabId, availableTabIds.contains(activeTabId) {
            storedActiveTabId = activeTabId
        } else {
            storedActiveTabId = availableTabIds.first
        }
    }

    func selectTab(_ tabId: UUID?, availableTabIds: [UUID]) {
        guard let tabId else {
            storedActiveTabId = nil
            return
        }
        guard availableTabIds.contains(tabId) else { return }
        storedActiveTabId = tabId
    }

    func removeTab(_ tabId: UUID, remainingTabIds: [UUID]) {
        guard storedActiveTabId == tabId else { return }
        storedActiveTabId = remainingTabIds.last
    }

    func persistenceSnapshotValue(
        for key: WorkspaceTabCursorSnapshotKey
    ) -> WorkspaceStateSnapshotStoredValue<UUID> {
        switch key {
        case .activeTab:
            storedActiveTabId.map(WorkspaceStateSnapshotStoredValue.value) ?? .absent
        }
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
            keyedParticipant: persistenceSnapshotParticipant,
            membershipLimits: Self.snapshotMembershipLimits,
            orderedBaseKeys: { [self] in storedActiveTabId == nil ? [] : [.activeTab] },
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
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        let replacement = activeTabId.flatMap { availableTabIds.contains($0) ? $0 : nil } ?? availableTabIds.first
        return try prepareActiveTabReplacement(
            replacement,
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    func prepareSelectTab(
        _ tabId: UUID?,
        availableTabIds: [UUID],
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        let replacement: UUID?
        if let tabId {
            replacement = availableTabIds.contains(tabId) ? tabId : storedActiveTabId
        } else {
            replacement = nil
        }
        return try prepareActiveTabReplacement(
            replacement,
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    func prepareRemoveTab(
        _ tabId: UUID,
        remainingTabIds: [UUID],
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        try prepareActiveTabReplacement(
            storedActiveTabId == tabId ? remainingTabIds.last : storedActiveTabId,
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    private func prepareActiveTabReplacement(
        _ replacement: UUID?,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        let membershipChange = activeTabMembershipChange(replacement: replacement)
        let mutations: [WorkspaceStateSnapshotParticipantMutation<WorkspaceTabCursorSnapshotKey, UUID>]
        switch membershipChange {
        case .unchanged:
            mutations = []
        case .insert:
            mutations = [.insert(.init(key: .activeTab, rawKeyByteCount: 1))]
        case .remove(let currentTabID):
            mutations = [.remove(.init(key: .activeTab, currentValue: .value(currentTabID)))]
        case .replace(let currentTabID):
            mutations = [.replaceValue(key: .activeTab, currentValue: .value(currentTabID))]
        }
        switch persistenceSnapshotParticipant.prepare(
            mutations,
            for: preparation,
            revisionOwner: revisionOwner
        ) {
        case .prepared:
            return preparation.commit { [self] in
                storedActiveTabId = replacement
                return preparation.transaction.proposedRevision
            }
        case .rejected(let rejection):
            throw WorkspaceTabCursorSnapshotPreparationError(rejection: rejection)
        }
    }

    private func activeTabMembershipChange(replacement: UUID?) -> ActiveTabMembershipChange {
        if let currentTabID = storedActiveTabId {
            if let replacement {
                return currentTabID == replacement ? .unchanged : .replace(currentTabID)
            }
            return .remove(currentTabID)
        }
        return replacement == nil ? .unchanged : .insert
    }
}
