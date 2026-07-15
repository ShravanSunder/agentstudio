import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabPersistenceOwnerTransactionTests {
    @Test("later graph preparation failure cancels earlier shell preparation without mutation")
    func laterPreparationFailureCancelsEarlierOwner() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let shellAtom = WorkspaceTabShellAtom()
        let graphAtom = WorkspaceTabGraphAtom()
        let shell = TabShell(id: UUIDv7.generate(), name: "Original")
        let graph = makeTransactionGraphState(tabID: shell.id)
        shellAtom.appendTabShell(shell)
        graphAtom.replaceStates([graph])
        _ = try requireConstructedShellParticipant(
            shellAtom.makePersistenceSnapshotParticipant(
                limits: .init(maximumKeyCount: 2, maximumRawKeyBytes: 32)
            )
        )
        _ = try requireConstructedGraphParticipantForTransaction(
            graphAtom.makePersistenceSnapshotParticipant(
                limits: .init(maximumKeyCount: 1, maximumRawKeyBytes: 16)
            )
        )
        let replacement = TabShell(id: shell.id, name: "Replacement")

        // Act
        #expect(throws: WorkspaceTabGraphPersistencePreparationError.self) {
            try revisionOwner.performSynchronousTransaction { preparation in
                _ = try shellAtom.preparePersistenceMutation(
                    [.update(replacement)],
                    for: preparation,
                    revisionOwner: revisionOwner
                )
                _ = try graphAtom.preparePersistenceMutation(
                    [.insert(makeTransactionGraphState(), at: 1)],
                    for: preparation,
                    revisionOwner: revisionOwner
                )
                return preparation.commit {}
            }
        }

        // Assert
        #expect(shellAtom.tabShell(shell.id) == shell)
        #expect(graphAtom.tabStates == [graph])
        #expect(revisionOwner.committedRevision == .zero)

        try revisionOwner.performSynchronousTransaction { preparation in
            try shellAtom.preparePersistenceMutation(
                [.update(replacement)],
                for: preparation,
                revisionOwner: revisionOwner
            )
            return preparation.commit {}
        }
        #expect(shellAtom.tabShell(shell.id) == replacement)
        #expect(revisionOwner.committedRevision.rawValue == 1)
    }
}

@MainActor
private func requireConstructedShellParticipant(
    _ result: SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >
) throws -> WorkspaceStateSnapshotPagerParticipant<
    WorkspacePersistenceSnapshotParticipantID,
    WorkspacePersistenceSnapshotItem
> {
    switch result {
    case .constructed(let participant): participant
    case .rejected(let rejection):
        throw WorkspaceTabShellPersistencePreparationError.snapshotParticipant(rejection)
    }
}

@MainActor
private func requireConstructedGraphParticipantForTransaction(
    _ result: SnapshotPagerParticipantConstructionResult<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >
) throws -> WorkspaceStateSnapshotPagerParticipant<
    WorkspacePersistenceSnapshotParticipantID,
    WorkspacePersistenceSnapshotItem
> {
    switch result {
    case .constructed(let participant): participant
    case .rejected(let rejection):
        throw WorkspaceTabGraphPersistencePreparationError.snapshotParticipant(rejection)
    }
}

private func makeTransactionGraphState(tabID: UUID = UUIDv7.generate()) -> TabGraphState {
    let paneID = UUIDv7.generate()
    return TabGraphState(
        tabId: tabID,
        allPaneIds: [paneID],
        arrangements: [
            PaneArrangementGraphState(
                id: UUIDv7.generate(),
                name: "Default",
                isDefault: true,
                layout: Layout(paneId: paneID),
                minimizedPaneIds: [],
                showsMinimizedPanes: false,
                drawerViews: [:]
            )
        ]
    )
}
