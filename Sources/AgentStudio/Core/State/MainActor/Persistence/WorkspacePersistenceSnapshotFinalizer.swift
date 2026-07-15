import Foundation

extension WorkspacePersistenceSnapshotAssembler {
    static func finalize(
        assembly: WorkspacePersistenceSnapshotAssembly,
        input: WorkspacePersistenceSnapshotFinalizationInput
    ) throws -> WorkspacePersistenceSnapshotFinalization {
        let panes = assembly.paneGraphs.map { paneGraph in
            paneGraph.pane(isDrawerExpanded: paneGraph.drawer?.drawerId == assembly.expandedDrawerID)
        }
        var tabs: [Tab] = []
        tabs.reserveCapacity(assembly.tabShells.count)
        for (shell, graph) in zip(assembly.tabShells, assembly.tabGraphs) {
            guard let activeArrangementID = assembly.activeArrangementIDsByTabID[shell.id] else {
                throw WorkspacePersistenceSnapshotAssemblyRejection.missingActiveArrangement(tabID: shell.id)
            }
            let arrangements = graph.arrangements.map { graphArrangement in
                var arrangement = PaneArrangement(
                    id: graphArrangement.id,
                    name: graphArrangement.name,
                    isDefault: graphArrangement.isDefault,
                    layout: graphArrangement.layout,
                    minimizedPaneIds: graphArrangement.minimizedPaneIds,
                    showsMinimizedPanes: graphArrangement.showsMinimizedPanes,
                    activePaneId: assembly.activePaneIDsByArrangementID[graphArrangement.id],
                    drawerViews: graphArrangement.drawerViews.mapValues { drawerGraph in
                        DrawerView(
                            layout: drawerGraph.layout,
                            activeChildId: nil,
                            minimizedPaneIds: drawerGraph.minimizedPaneIds
                        )
                    }
                )
                arrangement.activePaneId = assembly.activePaneIDsByArrangementID[graphArrangement.id]
                for drawerID in graphArrangement.drawerViews.keys {
                    let key = ArrangementDrawerCursorKey(
                        arrangementId: graphArrangement.id,
                        drawerId: drawerID
                    )
                    arrangement.drawerViews[drawerID]?.activeChildId = assembly.activeDrawerChildIDsByKey[key]
                }
                return arrangement
            }
            tabs.append(
                Tab(
                    id: shell.id,
                    name: shell.name,
                    allPaneIds: graph.allPaneIds,
                    arrangements: arrangements,
                    activeArrangementId: activeArrangementID,
                    colorHex: shell.colorHex,
                    zoomedPaneId: nil
                )
            )
        }

        let drawerParentPaneIDByDrawerID = Dictionary(
            uniqueKeysWithValues: assembly.paneGraphs.compactMap { graph in
                graph.drawer.map { ($0.drawerId, $0.parentPaneId) }
            }
        )
        let normalizedTabs = normalizeTabs(
            tabs: tabs,
            validPaneIds: Set(assembly.paneGraphs.map(\.id)),
            activeTabId: assembly.activeTabID,
            drawerParentPaneIDByDrawerID: drawerParentPaneIDByDrawerID,
            paneGraphs: assembly.paneGraphs
        )
        let bundle = WorkspaceSQLiteSaveBundle(
            workspace: WorkspaceSQLiteSnapshot(
                id: assembly.identity.workspaceID,
                name: assembly.identity.workspaceName,
                panes: panes,
                tabs: normalizedTabs.tabs,
                activeTabId: normalizedTabs.activeTabId,
                sidebarWidth: assembly.windowMemory.sidebarWidth,
                windowFrame: assembly.windowMemory.windowFrame,
                createdAt: assembly.identity.createdAt,
                updatedAt: input.persistedAt
            ),
            repositoryTopology: RepositoryTopologySQLiteSnapshot(
                id: assembly.identity.workspaceID,
                repos: assembly.repositories,
                worktrees: assembly.worktrees,
                unavailableRepoIds: assembly.unavailableRepositoryIDs,
                watchedPaths: assembly.watchedPaths,
                updatedAt: input.persistedAt
            )
        )
        return WorkspacePersistenceSnapshotFinalization(
            bundle: bundle,
            repairReport: WorkspacePersistenceSnapshotRepairReport(
                repairedTabIDs: normalizedTabs.repairReport.repairedTabIds,
                activeTabIDChanged: normalizedTabs.repairReport.activeTabIdChanged
            )
        )
    }

    private static func normalizeTabs(
        tabs: [Tab],
        validPaneIds: Set<UUID>,
        activeTabId: UUID?,
        drawerParentPaneIDByDrawerID: [UUID: UUID],
        paneGraphs: [PaneGraphState]
    ) -> WorkspaceTabMembershipNormalizationResult {
        var normalizedTabs = tabs
        var repairedTabIDs: [UUID] = []
        let drawerIDByParentPaneID = Dictionary(
            uniqueKeysWithValues: paneGraphs.compactMap { graph in
                graph.drawer.map { (graph.id, $0.drawerId) }
            }
        )
        for tabIndex in normalizedTabs.indices {
            let originalTab = normalizedTabs[tabIndex]
            normalizedTabs[tabIndex].arrangements = TabArrangementRepairRules.pruningInvalidPaneIds(
                validPaneIds: validPaneIds,
                from: normalizedTabs[tabIndex].arrangements
            )
            normalizedTabs[tabIndex].arrangements =
                TabArrangementRepairRules.pruningDrawerViewsMissingParentPane(
                    drawerParentPaneIdByDrawerId: drawerParentPaneIDByDrawerID,
                    from: normalizedTabs[tabIndex].arrangements
                )
            normalizedTabs[tabIndex].arrangements = TabArrangementRepairRules.promotingLiveArrangementToDefault(
                in: normalizedTabs[tabIndex].arrangements
            )
            if normalizedTabs[tabIndex].activeArrangement.layout.isEmpty,
                let liveArrangement = normalizedTabs[tabIndex].arrangements.first(where: { !$0.layout.isEmpty })
            {
                normalizedTabs[tabIndex].activeArrangementId = liveArrangement.id
            }
            let activeArrangementIndex = normalizedTabs[tabIndex].activeArrangementIndex
            if let activePaneID = normalizedTabs[tabIndex].arrangements[activeArrangementIndex].activePaneId,
                !validPaneIds.contains(activePaneID)
                    || !normalizedTabs[tabIndex].arrangements[activeArrangementIndex].layout.contains(activePaneID)
                    || normalizedTabs[tabIndex].arrangements[activeArrangementIndex].minimizedPaneIds.contains(
                        activePaneID)
            {
                normalizedTabs[tabIndex].arrangements[activeArrangementIndex].activePaneId =
                    TabArrangementSelectionRules.firstUnminimizedPaneId(
                        in: normalizedTabs[tabIndex].arrangements[activeArrangementIndex]
                    )
            }
            normalizedTabs[tabIndex].allPaneIds = normalizedMembershipPaneIDs(
                for: normalizedTabs[tabIndex],
                validPaneIDs: validPaneIds,
                drawerIDByParentPaneID: drawerIDByParentPaneID
            )
            if normalizedTabs[tabIndex] != originalTab {
                repairedTabIDs.append(originalTab.id)
            }
        }
        let tabIDsBeforeDroppingEmptyTabs = Set(normalizedTabs.map(\.id))
        normalizedTabs.removeAll { tab in
            !TabArrangementRepairRules.hasLivePaneReferences(in: tab.arrangements)
        }
        let droppedTabIDs = tabIDsBeforeDroppingEmptyTabs.subtracting(normalizedTabs.map(\.id))
        for tabID in droppedTabIDs where !repairedTabIDs.contains(tabID) {
            repairedTabIDs.append(tabID)
        }
        var normalizedActiveTabID = activeTabId
        if let activeTabId, !normalizedTabs.contains(where: { $0.id == activeTabId }) {
            normalizedActiveTabID = normalizedTabs.last?.id
        }
        return WorkspaceTabMembershipNormalizationResult(
            tabs: normalizedTabs,
            activeTabId: normalizedActiveTabID,
            repairReport: WorkspaceTabMembershipRepairReport(
                repairedTabIds: repairedTabIDs,
                activeTabIdChanged: normalizedActiveTabID != activeTabId
            )
        )
    }

    private static func normalizedMembershipPaneIDs(
        for tab: Tab,
        validPaneIDs: Set<UUID>,
        drawerIDByParentPaneID: [UUID: UUID]
    ) -> [UUID] {
        var referencedPaneIDs: Set<UUID> = []
        for arrangement in tab.arrangements {
            referencedPaneIDs.formUnion(arrangement.layout.paneIds.filter(validPaneIDs.contains))
            for drawerView in arrangement.drawerViews.values {
                referencedPaneIDs.formUnion(drawerView.layout.paneIds.filter(validPaneIDs.contains))
            }
        }
        var normalizedPaneIDs: [UUID] = []
        var seenPaneIDs: Set<UUID> = []
        for arrangement in tab.arrangements {
            for paneID in arrangement.layout.paneIds where referencedPaneIDs.contains(paneID) {
                if seenPaneIDs.insert(paneID).inserted {
                    normalizedPaneIDs.append(paneID)
                }
                guard let drawerID = drawerIDByParentPaneID[paneID],
                    let drawerView = arrangement.drawerViews[drawerID]
                else { continue }
                for childPaneID in tab.allPaneIds
                where drawerView.layout.contains(childPaneID) && referencedPaneIDs.contains(childPaneID) {
                    guard seenPaneIDs.insert(childPaneID).inserted else { continue }
                    normalizedPaneIDs.append(childPaneID)
                }
            }
        }
        for paneID in tab.allPaneIds where referencedPaneIDs.contains(paneID) {
            guard seenPaneIDs.insert(paneID).inserted else { continue }
            normalizedPaneIDs.append(paneID)
        }
        return normalizedPaneIDs
    }
}
