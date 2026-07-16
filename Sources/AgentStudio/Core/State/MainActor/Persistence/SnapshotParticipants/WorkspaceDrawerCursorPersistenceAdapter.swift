import Foundation

struct WorkspaceDrawerCursorSnapshotPreparationError: Error, Equatable {
    let rejection: WorkspaceSnapshotPreparationRejection
}

@MainActor
final class WorkspaceDrawerCursorPersistenceAdapter {
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

    private let atom: WorkspaceDrawerCursorAtom
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let snapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<UUID, UUID>()

    init(atom: WorkspaceDrawerCursorAtom, revisionOwner: WorkspacePersistenceRevisionOwner) {
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
            participantID: .expandedDrawer,
            keyedParticipant: snapshotParticipant,
            membershipLimits: Self.snapshotMembershipLimits,
            orderedBaseKeys: { [atom] in atom.expandedDrawerId.map { [$0] } ?? [] },
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
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        try prepareExpandedDrawerReplacement(
            atom.expandedDrawerId == drawerId ? nil : drawerId,
            for: preparation
        )
    }

    func prepareExpandDrawer(
        drawerId: UUID,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        try prepareExpandedDrawerReplacement(
            drawerId,
            for: preparation
        )
    }

    func prepareCollapseAllDrawers(
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        try prepareExpandedDrawerReplacement(
            nil,
            for: preparation
        )
    }

    func prepareHydrate(
        persistedPanes: [Pane],
        validDrawerIds: Set<UUID>,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        let replacement = persistedPanes.compactMap { pane -> UUID? in
            guard let drawer = pane.drawer, drawer.isExpanded, validDrawerIds.contains(drawer.drawerId) else {
                return nil
            }
            return drawer.drawerId
        }.last
        return try prepareExpandedDrawerReplacement(
            replacement,
            for: preparation
        )
    }

    func preparePrune(
        validDrawerIds: Set<UUID>,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        let replacement = atom.expandedDrawerId.flatMap { validDrawerIds.contains($0) ? $0 : nil }
        return try prepareExpandedDrawerReplacement(
            replacement,
            for: preparation
        )
    }

    func registerInitialExpandedDrawerReplacement(
        token _: borrowing WorkspaceCompositionPreinstallToken,
        _ expandedDrawerId: UUID?,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) -> WorkspaceParticipantRegistration {
        revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [atom, revisionOwner = self.revisionOwner] in
                precondition(
                    revisionOwner.validateActiveCommit(preparation.transaction) == .active,
                    "workspace drawer-cursor replacement requires its exact active transaction"
                )
                atom.replaceExpandedDrawer(expandedDrawerId)
            },
            cancel: {}
        )
    }

    func persistenceSnapshotValue(for drawerID: UUID) -> WorkspaceStateSnapshotStoredValue<UUID> {
        atom.expandedDrawerId == drawerID ? .value(drawerID) : .absent
    }

    private func prepareExpandedDrawerReplacement(
        _ replacement: UUID?,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        guard replacement != atom.expandedDrawerId else {
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
                    atom.replaceExpandedDrawer(replacement)
                    return preparation.transaction.proposedRevision
                }
            )
        case .rejected(let rejection):
            throw WorkspaceDrawerCursorSnapshotPreparationError(rejection: rejection)
        }
    }

    private func persistenceMutations(
        replacement: UUID?
    ) -> [WorkspaceStateSnapshotParticipantMutation<UUID, UUID>] {
        switch expandedDrawerMembershipChange(replacement: replacement) {
        case .unchanged:
            []
        case .insert(let drawerID):
            [.insert(.init(key: drawerID, rawKeyByteCount: 16))]
        case .remove(let drawerID):
            [.remove(.init(key: drawerID, currentValue: .value(drawerID)))]
        case .replace(let removedDrawerID, let insertedDrawerID):
            [
                .replaceMembership(
                    removing: .init(key: removedDrawerID, currentValue: .value(removedDrawerID)),
                    inserting: .init(key: insertedDrawerID, rawKeyByteCount: 16)
                )
            ]
        }
    }

    private func expandedDrawerMembershipChange(replacement: UUID?) -> ExpandedDrawerMembershipChange {
        if let currentDrawerID = atom.expandedDrawerId {
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
