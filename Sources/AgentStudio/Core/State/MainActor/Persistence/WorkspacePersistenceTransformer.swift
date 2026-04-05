import Foundation

@MainActor
enum WorkspacePersistenceTransformer {
    static func hydrate(
        _ state: WorkspacePersistor.PersistableState,
        metadataAtom: WorkspaceMetadataAtom,
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom
    ) {
        metadataAtom.hydrate(
            workspaceId: state.id,
            workspaceName: state.name,
            createdAt: state.createdAt,
            sidebarWidth: state.sidebarWidth,
            windowFrame: state.windowFrame
        )

        let runtimeRepos = runtimeRepos(
            canonicalRepos: state.repos,
            canonicalWorktrees: state.worktrees
        )
        repositoryTopologyAtom.hydrate(
            runtimeRepos: runtimeRepos,
            watchedPaths: state.watchedPaths,
            unavailableRepoIds: state.unavailableRepoIds
        )

        workspacePaneAtom.hydrate(
            persistedPanes: state.panes,
            validWorktreeIds: repositoryTopologyAtom.allWorktreeIds
        )
        workspaceTabLayoutAtom.hydrate(
            persistedTabs: state.tabs,
            activeTabId: state.activeTabId,
            validPaneIds: Set(workspacePaneAtom.panes.keys)
        )
    }

    static func makePersistableState(
        metadataAtom: WorkspaceMetadataAtom,
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        persistedAt: Date
    ) -> WorkspacePersistor.PersistableState {
        let persistablePanes = Array(
            workspacePaneAtom.panes.values.filter { pane in
                if case .terminal(let terminalState) = pane.content {
                    return terminalState.lifetime != .temporary
                }
                return true
            }
        )

        let validPaneIds = Set(persistablePanes.map(\.id))
        var prunedTabs = workspaceTabLayoutAtom.tabs
        var prunedActiveTabId = workspaceTabLayoutAtom.activeTabId
        pruneInvalidPanes(from: &prunedTabs, validPaneIds: validPaneIds, activeTabId: &prunedActiveTabId)

        return WorkspacePersistor.PersistableState(
            id: metadataAtom.workspaceId,
            name: metadataAtom.workspaceName,
            repos: canonicalRepos(from: repositoryTopologyAtom.repos),
            worktrees: canonicalWorktrees(from: repositoryTopologyAtom.repos),
            unavailableRepoIds: repositoryTopologyAtom.unavailableRepoIds,
            panes: persistablePanes,
            tabs: prunedTabs,
            activeTabId: prunedActiveTabId,
            sidebarWidth: metadataAtom.sidebarWidth,
            windowFrame: metadataAtom.windowFrame,
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            createdAt: metadataAtom.createdAt,
            updatedAt: persistedAt
        )
    }

    private static func canonicalRepos(from repos: [Repo]) -> [CanonicalRepo] {
        repos.map { repo in
            CanonicalRepo(
                id: repo.id,
                name: repo.name,
                repoPath: repo.repoPath,
                createdAt: repo.createdAt
            )
        }
    }

    private static func canonicalWorktrees(from repos: [Repo]) -> [CanonicalWorktree] {
        repos.flatMap { repo in
            repo.worktrees.map { worktree in
                CanonicalWorktree(
                    id: worktree.id,
                    repoId: repo.id,
                    name: worktree.name,
                    path: worktree.path,
                    isMainWorktree: worktree.isMainWorktree
                )
            }
        }
    }

    private static func runtimeRepos(
        canonicalRepos: [CanonicalRepo],
        canonicalWorktrees: [CanonicalWorktree]
    ) -> [Repo] {
        let worktreesByRepoId = Dictionary(grouping: canonicalWorktrees, by: \.repoId)
        return canonicalRepos.map { canonicalRepo in
            let worktrees = (worktreesByRepoId[canonicalRepo.id] ?? []).map { canonicalWorktree in
                Worktree(
                    id: canonicalWorktree.id,
                    repoId: canonicalRepo.id,
                    name: canonicalWorktree.name,
                    path: canonicalWorktree.path,
                    isMainWorktree: canonicalWorktree.isMainWorktree
                )
            }
            return Repo(
                id: canonicalRepo.id,
                name: canonicalRepo.name,
                repoPath: canonicalRepo.repoPath,
                worktrees: worktrees,
                createdAt: canonicalRepo.createdAt
            )
        }
    }

    private static func pruneInvalidPanes(
        from tabs: inout [Tab],
        validPaneIds: Set<UUID>,
        activeTabId: inout UUID?
    ) {
        for tabIndex in tabs.indices {
            tabs[tabIndex].panes.removeAll { !validPaneIds.contains($0) }

            for arrIndex in tabs[tabIndex].arrangements.indices {
                let invalidIds = tabs[tabIndex].arrangements[arrIndex].layout.paneIds.filter {
                    !validPaneIds.contains($0)
                }
                for paneId in invalidIds {
                    if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
                        tabs[tabIndex].arrangements[arrIndex].layout = newLayout
                    } else {
                        tabs[tabIndex].arrangements[arrIndex].layout = Layout()
                    }
                    tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
                }
            }

            if let activePaneId = tabs[tabIndex].activePaneId, !validPaneIds.contains(activePaneId) {
                tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
            }
        }

        tabs.removeAll { $0.defaultArrangement.layout.isEmpty }
        if let currentActiveTabId = activeTabId, !tabs.contains(where: { $0.id == currentActiveTabId }) {
            activeTabId = tabs.last?.id
        }
    }
}
