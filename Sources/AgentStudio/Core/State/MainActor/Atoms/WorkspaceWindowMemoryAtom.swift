import Foundation
import Observation

enum WorkspaceWindowMemorySnapshotKey: Hashable, Sendable {
    case windowMemory
}

struct WorkspaceWindowMemorySnapshotPreparationError: Error, Equatable {
    let rejection: WorkspaceSnapshotPreparationRejection
}

@MainActor
@Observable
final class WorkspaceWindowMemoryAtom {
    private static let snapshotMembershipLimits = WorkspaceStateSnapshotMembershipLimits(
        maximumKeyCount: 1,
        maximumRawKeyBytes: 1
    )

    private let persistenceSnapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<
        WorkspaceWindowMemorySnapshotKey,
        WorkspacePersistenceSnapshotWindowMemory
    >()

    var sidebarWidth: CGFloat { storedSidebarWidth }
    var windowFrame: CGRect? { storedWindowFrame }

    private var storedSidebarWidth: CGFloat
    private var storedWindowFrame: CGRect?

    init(sidebarWidth: CGFloat = 250, windowFrame: CGRect? = nil) {
        storedSidebarWidth = sidebarWidth
        storedWindowFrame = windowFrame
    }

    func hydrate(
        sidebarWidth: CGFloat,
        windowFrame: CGRect?
    ) {
        storedSidebarWidth = sidebarWidth
        storedWindowFrame = windowFrame
    }

    func setSidebarWidth(_ sidebarWidth: CGFloat) {
        guard storedSidebarWidth != sidebarWidth else { return }
        storedSidebarWidth = sidebarWidth
    }

    func setWindowFrame(_ windowFrame: CGRect?) {
        guard storedWindowFrame != windowFrame else { return }
        storedWindowFrame = windowFrame
    }

    func persistenceSnapshotValue(
        for key: WorkspaceWindowMemorySnapshotKey
    ) -> WorkspaceStateSnapshotStoredValue<WorkspacePersistenceSnapshotWindowMemory> {
        switch key {
        case .windowMemory:
            .value(currentPersistenceWindowMemory)
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
            participantID: .workspaceWindowMemory,
            keyedParticipant: persistenceSnapshotParticipant,
            membershipLimits: Self.snapshotMembershipLimits,
            orderedBaseKeys: { [.windowMemory] },
            currentValue: { [self] key in persistenceSnapshotValue(for: key) },
            projection: .init(
                itemIDForKey: { _ in .windowMemory },
                projectItem: { _, value in
                    .init(
                        item: .windowMemory(value),
                        estimatedByteCount: Self.estimatedSnapshotByteCount(value)
                    )
                }
            )
        )
    }

    func prepareHydrate(
        sidebarWidth: CGFloat,
        windowFrame: CGRect?,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        try prepareWindowMemoryReplacement(
            .init(sidebarWidth: sidebarWidth, windowFrame: windowFrame),
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    func prepareSetSidebarWidth(
        _ sidebarWidth: CGFloat,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        try prepareWindowMemoryReplacement(
            .init(sidebarWidth: sidebarWidth, windowFrame: storedWindowFrame),
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    func prepareSetWindowFrame(
        _ windowFrame: CGRect?,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        try prepareWindowMemoryReplacement(
            .init(sidebarWidth: storedSidebarWidth, windowFrame: windowFrame),
            for: preparation,
            revisionOwner: revisionOwner
        )
    }

    private var currentPersistenceWindowMemory: WorkspacePersistenceSnapshotWindowMemory {
        .init(sidebarWidth: storedSidebarWidth, windowFrame: storedWindowFrame)
    }

    private static func estimatedSnapshotByteCount(
        _ windowMemory: WorkspacePersistenceSnapshotWindowMemory
    ) -> Int {
        MemoryLayout<CGFloat>.size + 1
            + (windowMemory.windowFrame == nil ? 0 : MemoryLayout<CGRect>.size)
    }

    private func prepareWindowMemoryReplacement(
        _ replacement: WorkspacePersistenceSnapshotWindowMemory,
        for preparation: WorkspacePersistenceTransactionPreparation,
        revisionOwner: WorkspacePersistenceRevisionOwner
    ) throws -> WorkspacePersistencePreparedMutation<WorkspacePersistenceRevision> {
        let currentWindowMemory = currentPersistenceWindowMemory
        switch persistenceSnapshotParticipant.prepare(
            [.replaceValue(key: .windowMemory, currentValue: .value(currentWindowMemory))],
            for: preparation,
            revisionOwner: revisionOwner
        ) {
        case .prepared:
            return preparation.commit { [self] in
                storedSidebarWidth = replacement.sidebarWidth
                storedWindowFrame = replacement.windowFrame
                return preparation.transaction.proposedRevision
            }
        case .rejected(let rejection):
            throw WorkspaceWindowMemorySnapshotPreparationError(rejection: rejection)
        }
    }
}
