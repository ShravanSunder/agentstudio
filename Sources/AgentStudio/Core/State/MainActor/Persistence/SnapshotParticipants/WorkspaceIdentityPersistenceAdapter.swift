import Foundation

enum WorkspaceIdentitySnapshotKey: Hashable, Sendable {
    case identity
}

struct WorkspaceIdentitySnapshotPreparationError: Error, Equatable {
    let rejection: WorkspaceSnapshotPreparationRejection
}

@MainActor
final class WorkspaceIdentityPersistenceAdapter {
    private static let snapshotMembershipLimits = WorkspaceStateSnapshotMembershipLimits(
        maximumKeyCount: 1,
        maximumRawKeyBytes: 1
    )

    private let atom: WorkspaceIdentityAtom
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let snapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<
        WorkspaceIdentitySnapshotKey,
        WorkspacePersistenceSnapshotWorkspaceIdentity
    >()

    init(atom: WorkspaceIdentityAtom, revisionOwner: WorkspacePersistenceRevisionOwner) {
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
            participantID: .workspaceIdentity,
            keyedParticipant: snapshotParticipant,
            membershipLimits: Self.snapshotMembershipLimits,
            orderedBaseKeys: { [.identity] },
            currentValue: { [self] key in persistenceSnapshotValue(for: key) },
            projection: .init(
                itemIDForKey: { _ in .workspaceIdentity },
                projectItem: { _, value in
                    .init(
                        item: .workspaceIdentity(value),
                        estimatedByteCount: Self.estimatedSnapshotByteCount(value)
                    )
                }
            )
        )
    }

    func prepareHydrate(
        workspaceId: UUID,
        workspaceName: String,
        createdAt: Date,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        try prepareIdentityReplacement(
            .init(
                workspaceID: workspaceId,
                workspaceName: workspaceName,
                createdAt: createdAt
            ),
            for: preparation
        )
    }

    func prepareSetWorkspaceName(
        _ workspaceName: String,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        try prepareIdentityReplacement(
            .init(
                workspaceID: atom.workspaceId,
                workspaceName: workspaceName,
                createdAt: atom.createdAt
            ),
            for: preparation
        )
    }

    func registerInitialIdentityReplacement(
        token _: borrowing WorkspaceCompositionPreinstallToken,
        workspaceId: UUID,
        workspaceName: String,
        createdAt: Date,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) -> WorkspaceParticipantRegistration {
        revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [atom, revisionOwner = self.revisionOwner] in
                precondition(
                    revisionOwner.validateActiveCommit(preparation.transaction) == .active,
                    "workspace identity replacement requires its exact active transaction"
                )
                atom.replaceIdentity(
                    workspaceId: workspaceId,
                    workspaceName: workspaceName,
                    createdAt: createdAt
                )
            },
            cancel: {}
        )
    }

    func persistenceSnapshotValue(
        for key: WorkspaceIdentitySnapshotKey
    ) -> WorkspaceStateSnapshotStoredValue<WorkspacePersistenceSnapshotWorkspaceIdentity> {
        switch key {
        case .identity:
            .value(currentPersistenceIdentity)
        }
    }

    private var currentPersistenceIdentity: WorkspacePersistenceSnapshotWorkspaceIdentity {
        .init(
            workspaceID: atom.workspaceId,
            workspaceName: atom.workspaceName,
            createdAt: atom.createdAt
        )
    }

    private static func estimatedSnapshotByteCount(
        _ identity: WorkspacePersistenceSnapshotWorkspaceIdentity
    ) -> Int {
        16 + MemoryLayout<Date>.size + identity.workspaceName.utf8.count
    }

    private func prepareIdentityReplacement(
        _ replacement: WorkspacePersistenceSnapshotWorkspaceIdentity,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        let currentIdentity = currentPersistenceIdentity
        guard replacement != currentIdentity else {
            return .unchanged(revisionOwner.committedRevision)
        }
        switch snapshotParticipant.prepare(
            [.replaceValue(key: .identity, currentValue: .value(currentIdentity))],
            for: preparation,
            revisionOwner: revisionOwner
        ) {
        case .prepared:
            return .commit(
                preparation.commit { [atom] in
                    atom.replaceIdentity(
                        workspaceId: replacement.workspaceID,
                        workspaceName: replacement.workspaceName,
                        createdAt: replacement.createdAt
                    )
                    return preparation.transaction.proposedRevision
                }
            )
        case .rejected(let rejection):
            throw WorkspaceIdentitySnapshotPreparationError(rejection: rejection)
        }
    }
}
