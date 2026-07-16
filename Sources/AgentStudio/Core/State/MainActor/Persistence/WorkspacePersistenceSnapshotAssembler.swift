import Foundation

struct WorkspacePersistenceSnapshotParticipantItems: Equatable, Sendable {
    let participantID: WorkspacePersistenceSnapshotParticipantID
    let items: [WorkspacePersistenceSnapshotItem]
}

enum WorkspacePersistenceSnapshotAssemblyRejection: Error, Equatable, Sendable {
    case duplicateParticipant(WorkspacePersistenceSnapshotParticipantID)
    case missingParticipant(WorkspacePersistenceSnapshotParticipantID)
    case participantOutOfOrder(
        index: Int,
        expected: WorkspacePersistenceSnapshotParticipantID,
        actual: WorkspacePersistenceSnapshotParticipantID
    )
    case foreignItem(
        declaredParticipant: WorkspacePersistenceSnapshotParticipantID,
        actualParticipant: WorkspacePersistenceSnapshotParticipantID,
        itemID: WorkspacePersistenceSnapshotItemID
    )
    case duplicateItemID(WorkspacePersistenceSnapshotItemID)
    case missingSingleton(WorkspacePersistenceSnapshotParticipantID)
    case invalidSingletonCardinality(participant: WorkspacePersistenceSnapshotParticipantID, count: Int)
    case invalidTabSortIndex(tabID: UUID, expected: Int, actual: Int)
    case missingRepositoryForWorktree(worktreeID: UUID, repositoryID: UUID)
    case unavailableRepositoryNotFound(UUID)
    case paneRepositoryNotFound(paneID: UUID, repositoryID: UUID)
    case paneWorktreeNotFound(paneID: UUID, worktreeID: UUID)
    case paneRepositoryWorktreeMismatch(
        paneID: UUID,
        repositoryID: UUID,
        worktreeID: UUID,
        worktreeRepositoryID: UUID
    )
    case duplicateDrawerID(UUID)
    case drawerParentPaneNotFound(drawerID: UUID, parentPaneID: UUID)
    case drawerChildPaneNotFound(drawerID: UUID, childPaneID: UUID)
    case invalidDrawerChildParent(childPaneID: UUID, expectedParentPaneID: UUID)
    case orphanedDrawerChild(childPaneID: UUID, parentPaneID: UUID)
    case expandedDrawerNotFound(UUID)
    case missingTabGraph(tabID: UUID)
    case missingTabShell(tabID: UUID)
    case tabGraphOutOfOrder(index: Int, expectedTabID: UUID, actualTabID: UUID)
    case emptyTabArrangements(tabID: UUID)
    case invalidDefaultArrangementCount(tabID: UUID, count: Int)
    case duplicateArrangementID(UUID)
    case tabPaneNotFound(tabID: UUID, paneID: UUID)
    case duplicateTabPaneMembership(tabID: UUID, paneID: UUID)
    case paneOwnedByMultipleTabs(paneID: UUID, firstTabID: UUID, secondTabID: UUID)
    case arrangementPaneNotOwnedByTab(tabID: UUID, arrangementID: UUID, paneID: UUID)
    case drawerViewPaneNotOwnedByTab(tabID: UUID, arrangementID: UUID, drawerID: UUID, paneID: UUID)
    case drawerViewNotFound(tabID: UUID, arrangementID: UUID, drawerID: UUID)
    case drawerViewParentPaneNotInArrangement(
        tabID: UUID,
        arrangementID: UUID,
        drawerID: UUID,
        parentPaneID: UUID
    )
    case tabPaneNotReferenced(tabID: UUID, paneID: UUID)
    case activeTabNotFound(UUID)
    case missingActiveArrangement(tabID: UUID)
    case activeArrangementNotFound(tabID: UUID, arrangementID: UUID)
    case activeArrangementHasNoLivePane(tabID: UUID, arrangementID: UUID)
    case activePaneArrangementNotFound(arrangementID: UUID)
    case activePaneNotInArrangement(arrangementID: UUID, paneID: UUID)
    case activePaneIsMinimized(arrangementID: UUID, paneID: UUID)
    case activeDrawerArrangementNotFound(ArrangementDrawerCursorKey)
    case activeDrawerNotFound(ArrangementDrawerCursorKey)
    case activeDrawerChildNotFound(key: ArrangementDrawerCursorKey, childPaneID: UUID)
}

enum WorkspacePersistenceSnapshotAssemblyResult: Equatable, Sendable {
    case assembled(WorkspacePersistenceSnapshotAssembly)
    case rejected(WorkspacePersistenceSnapshotAssemblyRejection)
}

struct WorkspacePersistenceSnapshotFinalizationInput: Equatable, Sendable {
    let persistedAt: Date
}

struct WorkspacePersistenceSnapshotAssembly: Equatable, Sendable {
    let identity: WorkspacePersistenceSnapshotWorkspaceIdentity
    let windowMemory: WorkspacePersistenceSnapshotWindowMemory
    let repositories: [CanonicalRepo]
    let worktrees: [CanonicalWorktree]
    let watchedPaths: [WatchedPath]
    let unavailableRepositoryIDs: Set<UUID>
    let paneGraphs: [PaneGraphState]
    let expandedDrawerID: UUID?
    let tabShells: [TabShell]
    let activeTabID: UUID?
    let tabGraphs: [TabGraphState]
    let activeArrangementIDsByTabID: [UUID: UUID]
    let activePaneIDsByArrangementID: [UUID: UUID]
    let activeDrawerChildIDsByKey: [ArrangementDrawerCursorKey: UUID]

    func finalize(
        input: WorkspacePersistenceSnapshotFinalizationInput
    ) throws -> WorkspaceSQLiteSaveBundle {
        try WorkspacePersistenceSnapshotAssembler.finalize(assembly: self, input: input)
    }
}

enum WorkspacePersistenceSnapshotAssembler {
    static func assemble(
        participants: [WorkspacePersistenceSnapshotParticipantItems]
    ) -> WorkspacePersistenceSnapshotAssemblyResult {
        let inventory: WorkspacePersistenceSnapshotValidatedInventory
        switch validatedInventory(from: participants) {
        case .success(let validatedInventory):
            inventory = validatedInventory
        case .failure(let rejection):
            return .rejected(rejection)
        }
        if let rejection = validateReferences(inventory) {
            return .rejected(rejection)
        }
        return .assembled(
            WorkspacePersistenceSnapshotAssembly(
                identity: inventory.identity,
                windowMemory: inventory.windowMemory,
                repositories: inventory.repositories,
                worktrees: inventory.worktrees,
                watchedPaths: inventory.watchedPaths,
                unavailableRepositoryIDs: inventory.unavailableRepositoryIDs,
                paneGraphs: inventory.paneGraphs,
                expandedDrawerID: inventory.expandedDrawerID,
                tabShells: inventory.tabShells.map(\.shell),
                activeTabID: inventory.activeTabID,
                tabGraphs: inventory.tabGraphs,
                activeArrangementIDsByTabID: inventory.activeArrangementIDsByTabID,
                activePaneIDsByArrangementID: inventory.activePaneIDsByArrangementID,
                activeDrawerChildIDsByKey: inventory.activeDrawerChildIDsByKey
            )
        )
    }
}
