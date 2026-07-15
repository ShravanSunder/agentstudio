import Foundation
import Observation

struct WorkspaceDrawerCursorSnapshotPreparationError: Error, Equatable {
    let rejection: WorkspaceSnapshotPreparationRejection
}

@MainActor
@Observable
final class WorkspaceDrawerCursorAtom {
    private enum ExpandedDrawerMembershipChange {
        case unchanged
        case insert(UUID)
        case remove(UUID)
        case replace(removing: UUID, inserting: UUID)
    }

    private static let snapshotMembershipLimits = WorkspaceStateSnapshotMembershipLimits(
        maximumKeyCount: 1,
        maximumRawKeyBytes: 16
    )

    private let persistenceSnapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, UUID>()

    var expandedDrawerId: UUID? { storedExpandedDrawerId }

    private var storedExpandedDrawerId: UUID?

    init(expandedDrawerId: UUID? = nil) {
        storedExpandedDrawerId = expandedDrawerId
    }

    func isExpanded(drawerId: UUID) -> Bool {
        storedExpandedDrawerId == drawerId
    }

    func toggleDrawer(drawerId: UUID) {
        storedExpandedDrawerId = storedExpandedDrawerId == drawerId ? nil : drawerId
    }

    func expandDrawer(drawerId: UUID) {
        storedExpandedDrawerId = drawerId
    }

    func collapseAllDrawers() {
        storedExpandedDrawerId = nil
    }

    func hydrate(persistedPanes: [Pane], validDrawerIds: Set<UUID>) {
        let expandedDrawerIds: [UUID] = persistedPanes.compactMap { pane in
            guard let drawer = pane.drawer, drawer.isExpanded, validDrawerIds.contains(drawer.drawerId) else {
                return nil
            }
            return drawer.drawerId
        }
        storedExpandedDrawerId = expandedDrawerIds.last
    }

    func prune(validDrawerIds: Set<UUID>) {
        guard let storedExpandedDrawerId, !validDrawerIds.contains(storedExpandedDrawerId) else { return }
        self.storedExpandedDrawerId = nil
    }

    func persistenceSnapshotValue(for drawerID: UUID) -> WorkspaceStateSnapshotStoredValue<UUID> {
        storedExpandedDrawerId == drawerID ? .value(drawerID) : .absent
    }

    func makePersistenceSnapshotParticipant() -> SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    > {
        WorkspaceStateSnapshotPagerParticipant<
            WorkspacePersistenceSnapshotParticipantID,
            WorkspacePersistenceSnapshotItem
        >.typed(
            participantID: .expandedDrawer,
            keyedParticipant: persistenceSnapshotParticipant,
            membershipLimits: Self.snapshotMembershipLimits,
            orderedBaseKeys: { [self] in storedExpandedDrawerId.map { [$0] } ?? [] },
            currentValue: { [self] drawerID in persistenceSnapshotValue(for: drawerID) },
            projection: .init(
                itemIDForKey: { .expandedDrawer($0) },
                projectItem: { _, drawerID in
                    .init(item: .expandedDrawer(drawerID), estimatedByteCount: 16)
                }
            ),
            rawKeyByteCount: { _ in 16 }
        )
    }

    func prepareToggleDrawer(
        drawerId: UUID,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        try prepareExpandedDrawerReplacement(
            storedExpandedDrawerId == drawerId ? nil : drawerId,
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    func prepareExpandDrawer(
        drawerId: UUID,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        try prepareExpandedDrawerReplacement(
            drawerId,
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    func prepareCollapseAllDrawers(
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        try prepareExpandedDrawerReplacement(
            nil,
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    func prepareHydrate(
        persistedPanes: [Pane],
        validDrawerIds: Set<UUID>,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        let replacement = persistedPanes.compactMap { pane -> UUID? in
            guard let drawer = pane.drawer, drawer.isExpanded, validDrawerIds.contains(drawer.drawerId) else {
                return nil
            }
            return drawer.drawerId
        }.last
        return try prepareExpandedDrawerReplacement(
            replacement,
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    func preparePrune(
        validDrawerIds: Set<UUID>,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        let replacement = storedExpandedDrawerId.flatMap { validDrawerIds.contains($0) ? $0 : nil }
        return try prepareExpandedDrawerReplacement(
            replacement,
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    private func prepareExpandedDrawerReplacement(
        _ replacement: UUID?,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        let membershipChange = expandedDrawerMembershipChange(replacement: replacement)
        let mutations: [WorkspaceStateSnapshotParticipantMutation<UUID, UUID>]
        switch membershipChange {
        case .unchanged:
            mutations = []
        case .insert(let drawerID):
            mutations = [.insert(.init(key: drawerID, rawKeyByteCount: 16))]
        case .remove(let drawerID):
            mutations = [.remove(.init(key: drawerID, currentValue: .value(drawerID)))]
        case .replace(let removedDrawerID, let insertedDrawerID):
            mutations = [
                .replaceMembership(
                    removing: .init(key: removedDrawerID, currentValue: .value(removedDrawerID)),
                    inserting: .init(key: insertedDrawerID, rawKeyByteCount: 16)
                )
            ]
        }
        switch persistenceSnapshotParticipant.prepare(
            mutations,
            for: preparation,
            revisionOwner: revisionOwner
        ) {
        case .prepared:
            return preparation.commit { [self] in
                storedExpandedDrawerId = replacement
                return preparation.transaction.proposedRevision
            }
        case .rejected(let rejection):
            throw WorkspaceDrawerCursorSnapshotPreparationError(rejection: rejection)
        }
    }

    private func expandedDrawerMembershipChange(replacement: UUID?) -> ExpandedDrawerMembershipChange {
        if let currentDrawerID = storedExpandedDrawerId {
            if let replacement {
                return currentDrawerID == replacement
                    ? .unchanged
                    : .replace(removing: currentDrawerID, inserting: replacement)
            }
            return .remove(currentDrawerID)
        }
        if let replacement { return .insert(replacement) }
        return .unchanged
    }
}
