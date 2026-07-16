import Foundation

extension WorkspacePersistenceSnapshotAssembler {
    static func finalize(
        assembly: WorkspacePersistenceSnapshotAssembly,
        input: WorkspacePersistenceSnapshotFinalizationInput
    ) throws -> WorkspaceSQLiteSaveBundle {
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

        return WorkspaceSQLiteSaveBundle(
            workspace: WorkspaceSQLiteSnapshot(
                id: assembly.identity.workspaceID,
                name: assembly.identity.workspaceName,
                panes: panes,
                tabs: tabs,
                activeTabId: assembly.activeTabID,
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
    }
}
