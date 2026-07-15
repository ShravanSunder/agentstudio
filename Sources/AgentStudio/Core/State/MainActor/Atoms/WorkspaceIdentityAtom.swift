import Foundation
import Observation

enum WorkspaceIdentitySnapshotKey: Hashable, Sendable {
    case identity
}

struct WorkspaceIdentitySnapshotPreparationError: Error, Equatable {
    let rejection: WorkspaceSnapshotPreparationRejection
}

@MainActor
@Observable
final class WorkspaceIdentityAtom {
    private static let snapshotMembershipLimits = WorkspaceStateSnapshotMembershipLimits(
        maximumKeyCount: 1,
        maximumRawKeyBytes: 1
    )

    private let persistenceSnapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<
        WorkspaceIdentitySnapshotKey,
        WorkspacePersistenceSnapshotWorkspaceIdentity
    >()

    var workspaceId: UUID { storedWorkspaceId }
    var workspaceName: String { storedWorkspaceName }
    var createdAt: Date { storedCreatedAt }

    private var storedWorkspaceId: UUID
    private var storedWorkspaceName: String
    private var storedCreatedAt: Date

    init(
        workspaceId: UUID = UUIDv7.generate(),
        workspaceName: String = "Default Workspace",
        createdAt: Date = Date()
    ) {
        storedWorkspaceId = workspaceId
        storedWorkspaceName = workspaceName
        storedCreatedAt = createdAt
    }

    func hydrate(
        workspaceId: UUID,
        workspaceName: String,
        createdAt: Date
    ) {
        storedWorkspaceId = workspaceId
        storedWorkspaceName = workspaceName
        storedCreatedAt = createdAt
    }

    func setWorkspaceName(_ workspaceName: String) {
        guard storedWorkspaceName != workspaceName else { return }
        storedWorkspaceName = workspaceName
    }

    func persistenceSnapshotValue(
        for key: WorkspaceIdentitySnapshotKey
    ) -> WorkspaceStateSnapshotStoredValue<WorkspacePersistenceSnapshotWorkspaceIdentity> {
        switch key {
        case .identity:
            .value(currentPersistenceIdentity)
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
            participantID: .workspaceIdentity,
            keyedParticipant: persistenceSnapshotParticipant,
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
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        try prepareIdentityReplacement(
            .init(
                workspaceID: workspaceId,
                workspaceName: workspaceName,
                createdAt: createdAt
            ),
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    func prepareSetWorkspaceName(
        _ workspaceName: String,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        try prepareIdentityReplacement(
            .init(
                workspaceID: storedWorkspaceId,
                workspaceName: workspaceName,
                createdAt: storedCreatedAt
            ),
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    private var currentPersistenceIdentity: WorkspacePersistenceSnapshotWorkspaceIdentity {
        .init(
            workspaceID: storedWorkspaceId,
            workspaceName: storedWorkspaceName,
            createdAt: storedCreatedAt
        )
    }

    private static func estimatedSnapshotByteCount(
        _ identity: WorkspacePersistenceSnapshotWorkspaceIdentity
    ) -> Int {
        16 + MemoryLayout<Date>.size + identity.workspaceName.utf8.count
    }

    private func prepareIdentityReplacement(
        _ replacement: WorkspacePersistenceSnapshotWorkspaceIdentity,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        let currentIdentity = currentPersistenceIdentity
        switch persistenceSnapshotParticipant.prepare(
            [.replaceValue(key: .identity, currentValue: .value(currentIdentity))],
            for: preparation,
            revisionOwner: revisionOwner
        ) {
        case .prepared:
            return preparation.commit { [self] in
                storedWorkspaceId = replacement.workspaceID
                storedWorkspaceName = replacement.workspaceName
                storedCreatedAt = replacement.createdAt
                return preparation.transaction.proposedRevision
            }
        case .rejected(let rejection):
            throw WorkspaceIdentitySnapshotPreparationError(rejection: rejection)
        }
    }
}
