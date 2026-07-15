import Foundation

struct WorkspacePersistenceSnapshotValidatedInventory: Sendable {
    let identity: WorkspacePersistenceSnapshotWorkspaceIdentity
    let windowMemory: WorkspacePersistenceSnapshotWindowMemory
    let repositories: [CanonicalRepo]
    let worktrees: [CanonicalWorktree]
    let watchedPaths: [WatchedPath]
    let unavailableRepositoryIDs: Set<UUID>
    let paneGraphs: [PaneGraphState]
    let expandedDrawerID: UUID?
    let tabShells: [WorkspacePersistenceSnapshotTabShell]
    let activeTabID: UUID?
    let tabGraphs: [TabGraphState]
    let activeArrangementIDsByTabID: [UUID: UUID]
    let activePaneIDsByArrangementID: [UUID: UUID]
    let activeDrawerChildIDsByKey: [ArrangementDrawerCursorKey: UUID]
}

extension WorkspacePersistenceSnapshotAssembler {
    static func validatedInventory(
        from participants: [WorkspacePersistenceSnapshotParticipantItems]
    ) -> Result<WorkspacePersistenceSnapshotValidatedInventory, WorkspacePersistenceSnapshotAssemblyRejection> {
        if let rejection = validateParticipantEnvelope(participants) {
            return .failure(rejection)
        }
        guard case .workspaceIdentity(let identity) = participants[0].items[0] else {
            return .failure(.missingSingleton(.workspaceIdentity))
        }
        guard case .windowMemory(let windowMemory) = participants[1].items[0] else {
            return .failure(.missingSingleton(.workspaceWindowMemory))
        }
        let repositories = participants[2].items.compactMap { item -> CanonicalRepo? in
            guard case .repository(let repository) = item else { return nil }
            return repository
        }
        let worktrees = participants[3].items.compactMap { item -> CanonicalWorktree? in
            guard case .worktree(let worktree) = item else { return nil }
            return worktree
        }
        let watchedPaths = participants[4].items.compactMap { item -> WatchedPath? in
            guard case .watchedPath(let watchedPath) = item else { return nil }
            return watchedPath
        }
        let unavailableRepositoryIDs = Set(
            participants[5].items.compactMap { item -> UUID? in
                guard case .unavailableRepository(let repositoryID) = item else { return nil }
                return repositoryID
            })
        let paneGraphs = participants[6].items.compactMap { item -> PaneGraphState? in
            guard case .paneGraph(let graph) = item else { return nil }
            return graph
        }
        let expandedDrawerID = participants[7].items.first.flatMap { item -> UUID? in
            guard case .expandedDrawer(let drawerID) = item else { return nil }
            return drawerID
        }
        let tabShells = participants[8].items.compactMap { item -> WorkspacePersistenceSnapshotTabShell? in
            guard case .tabShell(let shell) = item else { return nil }
            return shell
        }
        let activeTabID = participants[9].items.first.flatMap { item -> UUID? in
            guard case .activeTab(let tabID) = item else { return nil }
            return tabID
        }
        let tabGraphs = participants[10].items.compactMap { item -> TabGraphState? in
            guard case .tabGraph(let graph) = item else { return nil }
            return graph
        }
        let activeArrangementIDsByTabID = Dictionary(
            uniqueKeysWithValues: participants[11].items.compactMap { item -> (UUID, UUID)? in
                guard case .activeArrangement(let tabID, let arrangementID) = item else { return nil }
                return (tabID, arrangementID)
            }
        )
        let activePaneIDsByArrangementID = Dictionary(
            uniqueKeysWithValues: participants[12].items.compactMap { item -> (UUID, UUID)? in
                guard case .activePane(let arrangementID, let paneID) = item else { return nil }
                return (arrangementID, paneID)
            }
        )
        typealias ActiveDrawerChildEntry = (ArrangementDrawerCursorKey, UUID)
        let activeDrawerChildIDsByKey = Dictionary(
            uniqueKeysWithValues: participants[13].items.compactMap { item -> ActiveDrawerChildEntry? in
                guard case .activeDrawerChild(let key, let childPaneID) = item else { return nil }
                return (key, childPaneID)
            }
        )
        return .success(
            WorkspacePersistenceSnapshotValidatedInventory(
                identity: identity,
                windowMemory: windowMemory,
                repositories: repositories,
                worktrees: worktrees,
                watchedPaths: watchedPaths,
                unavailableRepositoryIDs: unavailableRepositoryIDs,
                paneGraphs: paneGraphs,
                expandedDrawerID: expandedDrawerID,
                tabShells: tabShells,
                activeTabID: activeTabID,
                tabGraphs: tabGraphs,
                activeArrangementIDsByTabID: activeArrangementIDsByTabID,
                activePaneIDsByArrangementID: activePaneIDsByArrangementID,
                activeDrawerChildIDsByKey: activeDrawerChildIDsByKey
            ))
    }

    static func validateParticipantEnvelope(
        _ participants: [WorkspacePersistenceSnapshotParticipantItems]
    ) -> WorkspacePersistenceSnapshotAssemblyRejection? {
        var seenParticipants: Set<WorkspacePersistenceSnapshotParticipantID> = []
        var seenItemIDs: Set<WorkspacePersistenceSnapshotItemID> = []
        for participant in participants {
            guard seenParticipants.insert(participant.participantID).inserted else {
                return .duplicateParticipant(participant.participantID)
            }
            for item in participant.items {
                guard item.participantID == participant.participantID else {
                    return .foreignItem(
                        declaredParticipant: participant.participantID,
                        actualParticipant: item.participantID,
                        itemID: item.itemID
                    )
                }
                guard seenItemIDs.insert(item.itemID).inserted else {
                    return .duplicateItemID(item.itemID)
                }
            }
        }
        for participantID in WorkspacePersistenceSnapshotParticipantID.allCases
        where !seenParticipants.contains(participantID) {
            return .missingParticipant(participantID)
        }
        for (index, expectedParticipantID) in WorkspacePersistenceSnapshotParticipantID.allCases.enumerated() {
            let actualParticipantID = participants[index].participantID
            guard actualParticipantID == expectedParticipantID else {
                return .participantOutOfOrder(
                    index: index,
                    expected: expectedParticipantID,
                    actual: actualParticipantID
                )
            }
        }
        for index in [0, 1] {
            let participant = participants[index]
            guard participant.items.count == 1 else {
                return participant.items.isEmpty
                    ? .missingSingleton(participant.participantID)
                    : .invalidSingletonCardinality(
                        participant: participant.participantID,
                        count: participant.items.count
                    )
            }
        }
        for index in [7, 9] where participants[index].items.count > 1 {
            return .invalidSingletonCardinality(
                participant: participants[index].participantID,
                count: participants[index].items.count
            )
        }
        return nil
    }

    static func validateReferences(
        _ inventory: WorkspacePersistenceSnapshotValidatedInventory
    ) -> WorkspacePersistenceSnapshotAssemblyRejection? {
        if let rejection = validateTopologyAndPaneReferences(inventory) {
            return rejection
        }
        return validateTabAndCursorReferences(inventory)
    }

    private static func validateTopologyAndPaneReferences(
        _ inventory: WorkspacePersistenceSnapshotValidatedInventory
    ) -> WorkspacePersistenceSnapshotAssemblyRejection? {
        let repositoryIDs = Set(inventory.repositories.map(\.id))
        let worktreeByID = Dictionary(uniqueKeysWithValues: inventory.worktrees.map { ($0.id, $0) })
        for worktree in inventory.worktrees where !repositoryIDs.contains(worktree.repoId) {
            return .missingRepositoryForWorktree(worktreeID: worktree.id, repositoryID: worktree.repoId)
        }
        if let repositoryID = inventory.unavailableRepositoryIDs.first(where: { !repositoryIDs.contains($0) }) {
            return .unavailableRepositoryNotFound(repositoryID)
        }
        let paneByID = Dictionary(uniqueKeysWithValues: inventory.paneGraphs.map { ($0.id, $0) })
        var drawerParentByID: [UUID: UUID] = [:]
        for pane in inventory.paneGraphs {
            if let repositoryID = pane.metadata.facets.repoId, !repositoryIDs.contains(repositoryID) {
                return .paneRepositoryNotFound(paneID: pane.id, repositoryID: repositoryID)
            }
            if let worktreeID = pane.metadata.facets.worktreeId {
                guard let worktree = worktreeByID[worktreeID] else {
                    return .paneWorktreeNotFound(paneID: pane.id, worktreeID: worktreeID)
                }
                if let repositoryID = pane.metadata.facets.repoId, repositoryID != worktree.repoId {
                    return .paneRepositoryWorktreeMismatch(
                        paneID: pane.id,
                        repositoryID: repositoryID,
                        worktreeID: worktreeID,
                        worktreeRepositoryID: worktree.repoId
                    )
                }
            }
            guard let drawer = pane.drawer else { continue }
            guard drawerParentByID.updateValue(pane.id, forKey: drawer.drawerId) == nil else {
                return .duplicateDrawerID(drawer.drawerId)
            }
            guard drawer.parentPaneId == pane.id else {
                return .drawerParentPaneNotFound(drawerID: drawer.drawerId, parentPaneID: drawer.parentPaneId)
            }
            for childPaneID in drawer.paneIds {
                guard let child = paneByID[childPaneID] else {
                    return .drawerChildPaneNotFound(drawerID: drawer.drawerId, childPaneID: childPaneID)
                }
                guard child.parentPaneId == pane.id else {
                    return .invalidDrawerChildParent(childPaneID: childPaneID, expectedParentPaneID: pane.id)
                }
            }
        }
        for pane in inventory.paneGraphs {
            guard let parentPaneID = pane.parentPaneId else { continue }
            guard let parent = paneByID[parentPaneID], parent.drawer?.paneIds.contains(pane.id) == true else {
                return .orphanedDrawerChild(childPaneID: pane.id, parentPaneID: parentPaneID)
            }
        }
        if let expandedDrawerID = inventory.expandedDrawerID, drawerParentByID[expandedDrawerID] == nil {
            return .expandedDrawerNotFound(expandedDrawerID)
        }
        return nil
    }

    private static func validateTabAndCursorReferences(
        _ inventory: WorkspacePersistenceSnapshotValidatedInventory
    ) -> WorkspacePersistenceSnapshotAssemblyRejection? {
        for (index, shell) in inventory.tabShells.enumerated() where shell.sortIndex != index {
            return .invalidTabSortIndex(tabID: shell.shell.id, expected: index, actual: shell.sortIndex)
        }
        let shellIDs = Set(inventory.tabShells.map(\.shell.id))
        let graphIDs = Set(inventory.tabGraphs.map(\.tabId))
        if let shellID = inventory.tabShells.map(\.shell.id).first(where: { !graphIDs.contains($0) }) {
            return .missingTabGraph(tabID: shellID)
        }
        if let graphID = inventory.tabGraphs.map(\.tabId).first(where: { !shellIDs.contains($0) }) {
            return .missingTabShell(tabID: graphID)
        }
        for index in inventory.tabGraphs.indices {
            let expectedTabID = inventory.tabShells[index].shell.id
            let actualTabID = inventory.tabGraphs[index].tabId
            guard expectedTabID == actualTabID else {
                return .tabGraphOutOfOrder(index: index, expectedTabID: expectedTabID, actualTabID: actualTabID)
            }
        }
        if let activeTabID = inventory.activeTabID, !shellIDs.contains(activeTabID) {
            return .activeTabNotFound(activeTabID)
        }
        return validateGraphAndCursorReferences(inventory, graphIDs: graphIDs)
    }

    private static func validateGraphAndCursorReferences(
        _ inventory: WorkspacePersistenceSnapshotValidatedInventory,
        graphIDs: Set<UUID>
    ) -> WorkspacePersistenceSnapshotAssemblyRejection? {
        let paneIDs = Set(inventory.paneGraphs.map(\.id))
        var ownerByPaneID: [UUID: UUID] = [:]
        var arrangementByID: [UUID: PaneArrangementGraphState] = [:]
        for tabGraph in inventory.tabGraphs {
            guard !tabGraph.arrangements.isEmpty else { return .emptyTabArrangements(tabID: tabGraph.tabId) }
            let defaultCount = tabGraph.arrangements.filter(\.isDefault).count
            guard defaultCount == 1 else {
                return .invalidDefaultArrangementCount(tabID: tabGraph.tabId, count: defaultCount)
            }
            for paneID in tabGraph.allPaneIds {
                guard paneIDs.contains(paneID) else { return .tabPaneNotFound(tabID: tabGraph.tabId, paneID: paneID) }
                if let firstTabID = ownerByPaneID.updateValue(tabGraph.tabId, forKey: paneID),
                    firstTabID != tabGraph.tabId
                {
                    return .paneOwnedByMultipleTabs(
                        paneID: paneID,
                        firstTabID: firstTabID,
                        secondTabID: tabGraph.tabId
                    )
                }
            }
            let ownedPaneIDs = Set(tabGraph.allPaneIds)
            for arrangement in tabGraph.arrangements {
                guard arrangementByID.updateValue(arrangement, forKey: arrangement.id) == nil else {
                    return .duplicateArrangementID(arrangement.id)
                }
                if let paneID = arrangement.layout.paneIds.first(where: { !ownedPaneIDs.contains($0) }) {
                    return .arrangementPaneNotOwnedByTab(
                        tabID: tabGraph.tabId,
                        arrangementID: arrangement.id,
                        paneID: paneID
                    )
                }
                for (drawerID, drawerView) in arrangement.drawerViews {
                    if let paneID = drawerView.layout.paneIds.first(where: { !ownedPaneIDs.contains($0) }) {
                        return .drawerViewPaneNotOwnedByTab(
                            tabID: tabGraph.tabId,
                            arrangementID: arrangement.id,
                            drawerID: drawerID,
                            paneID: paneID
                        )
                    }
                }
            }
            guard let activeArrangementID = inventory.activeArrangementIDsByTabID[tabGraph.tabId] else {
                return .missingActiveArrangement(tabID: tabGraph.tabId)
            }
            guard tabGraph.arrangements.contains(where: { $0.id == activeArrangementID }) else {
                return .activeArrangementNotFound(tabID: tabGraph.tabId, arrangementID: activeArrangementID)
            }
        }
        for (tabID, arrangementID) in inventory.activeArrangementIDsByTabID where !graphIDs.contains(tabID) {
            return .activeArrangementNotFound(tabID: tabID, arrangementID: arrangementID)
        }
        for (arrangementID, paneID) in inventory.activePaneIDsByArrangementID {
            guard let arrangement = arrangementByID[arrangementID] else {
                return .activePaneArrangementNotFound(arrangementID: arrangementID)
            }
            guard arrangement.layout.contains(paneID) else {
                return .activePaneNotInArrangement(arrangementID: arrangementID, paneID: paneID)
            }
        }
        for (key, childPaneID) in inventory.activeDrawerChildIDsByKey {
            guard let arrangement = arrangementByID[key.arrangementId] else {
                return .activeDrawerArrangementNotFound(key)
            }
            guard let drawerView = arrangement.drawerViews[key.drawerId] else {
                return .activeDrawerNotFound(key)
            }
            guard drawerView.layout.contains(childPaneID) else {
                return .activeDrawerChildNotFound(key: key, childPaneID: childPaneID)
            }
        }
        return nil
    }
}
