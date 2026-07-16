import Foundation

enum WorkspaceWindowMemorySnapshotKey: Hashable, Sendable {
    case windowMemory
}

struct WorkspaceWindowMemorySnapshotPreparationError: Error, Equatable {
    let rejection: WorkspaceSnapshotPreparationRejection
}

@MainActor
final class WorkspaceWindowMemoryPersistenceAdapter {
    private static let snapshotMembershipLimits = WorkspaceStateSnapshotMembershipLimits(
        maximumKeyCount: 1,
        maximumRawKeyBytes: 1
    )

    private let atom: WorkspaceWindowMemoryAtom
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let snapshotParticipant = WorkspaceStateSnapshotKeyedParticipant<
        WorkspaceWindowMemorySnapshotKey,
        WorkspacePersistenceSnapshotWindowMemory
    >()

    init(atom: WorkspaceWindowMemoryAtom, revisionOwner: WorkspacePersistenceRevisionOwner) {
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
            participantID: .workspaceWindowMemory,
            keyedParticipant: snapshotParticipant,
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
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        try prepareWindowMemoryReplacement(
            .init(sidebarWidth: sidebarWidth, windowFrame: windowFrame),
            for: preparation
        )
    }

    func prepareSetSidebarWidth(
        _ sidebarWidth: CGFloat,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        try prepareWindowMemoryReplacement(
            .init(sidebarWidth: sidebarWidth, windowFrame: atom.windowFrame),
            for: preparation
        )
    }

    func prepareSetWindowFrame(
        _ windowFrame: CGRect?,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        try prepareWindowMemoryReplacement(
            .init(sidebarWidth: atom.sidebarWidth, windowFrame: windowFrame),
            for: preparation
        )
    }

    func registerInitialWindowMemoryReplacement(
        token _: borrowing WorkspaceCompositionPreinstallToken,
        sidebarWidth: CGFloat,
        windowFrame: CGRect?,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) -> WorkspaceParticipantRegistration {
        revisionOwner.registerPreparedParticipantMutation(
            participant: self,
            preparation: preparation,
            apply: { [atom, revisionOwner = self.revisionOwner] in
                precondition(
                    revisionOwner.validateActiveCommit(preparation.transaction) == .active,
                    "workspace window-memory replacement requires its exact active transaction"
                )
                atom.replaceWindowMemory(sidebarWidth: sidebarWidth, windowFrame: windowFrame)
            },
            cancel: {}
        )
    }

    func persistenceSnapshotValue(
        for key: WorkspaceWindowMemorySnapshotKey
    ) -> WorkspaceStateSnapshotStoredValue<WorkspacePersistenceSnapshotWindowMemory> {
        switch key {
        case .windowMemory:
            .value(currentPersistenceWindowMemory)
        }
    }

    func capturePersistencePreimage(
        _ capture: WorkspaceWindowMemoryPersistenceCapture,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        switch capture {
        case .currentWindowMemory:
            break
        }
        switch snapshotParticipant.prepare(
            [.replaceValue(key: .windowMemory, currentValue: .value(currentPersistenceWindowMemory))],
            for: preparation,
            revisionOwner: revisionOwner
        ) {
        case .prepared:
            break
        case .rejected(let rejection):
            throw WorkspaceWindowMemorySnapshotPreparationError(rejection: rejection)
        }
    }

    private var currentPersistenceWindowMemory: WorkspacePersistenceSnapshotWindowMemory {
        .init(sidebarWidth: atom.sidebarWidth, windowFrame: atom.windowFrame)
    }

    private static func estimatedSnapshotByteCount(
        _ windowMemory: WorkspacePersistenceSnapshotWindowMemory
    ) -> Int {
        MemoryLayout<CGFloat>.size + 1
            + (windowMemory.windowFrame == nil ? 0 : MemoryLayout<CGRect>.size)
    }

    private func prepareWindowMemoryReplacement(
        _ replacement: WorkspacePersistenceSnapshotWindowMemory,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws -> WorkspacePersistenceTransactionDecision<WorkspacePersistenceRevision> {
        let currentWindowMemory = currentPersistenceWindowMemory
        guard replacement != currentWindowMemory else {
            return .unchanged(revisionOwner.committedRevision)
        }
        switch snapshotParticipant.prepare(
            [.replaceValue(key: .windowMemory, currentValue: .value(currentWindowMemory))],
            for: preparation,
            revisionOwner: revisionOwner
        ) {
        case .prepared:
            return .commit(
                preparation.commit { [atom] in
                    atom.replaceWindowMemory(
                        sidebarWidth: replacement.sidebarWidth,
                        windowFrame: replacement.windowFrame
                    )
                    return preparation.transaction.proposedRevision
                }
            )
        case .rejected(let rejection):
            throw WorkspaceWindowMemorySnapshotPreparationError(rejection: rejection)
        }
    }
}
