import Foundation

@MainActor
enum WorkspacePersistenceTransformer {
    static func hydrate(
        _ state: WorkspacePersistor.PersistableState,
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom
    ) {
        identityAtom.hydrate(
            workspaceId: state.id,
            workspaceName: state.name,
            createdAt: state.createdAt
        )
        windowMemoryAtom.hydrate(
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
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
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
            id: identityAtom.workspaceId,
            name: identityAtom.workspaceName,
            repos: canonicalRepos(from: repositoryTopologyAtom.repos),
            worktrees: canonicalWorktrees(from: repositoryTopologyAtom.repos),
            unavailableRepoIds: repositoryTopologyAtom.unavailableRepoIds,
            panes: persistablePanes,
            tabs: prunedTabs,
            activeTabId: prunedActiveTabId,
            sidebarWidth: windowMemoryAtom.sidebarWidth,
            windowFrame: windowMemoryAtom.windowFrame,
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            createdAt: identityAtom.createdAt,
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

            tabs[tabIndex].arrangements = TabArrangementRepairRules.pruningInvalidPaneIds(
                validPaneIds: validPaneIds,
                from: tabs[tabIndex].arrangements
            )

            if tabs[tabIndex].activeArrangement.layout.isEmpty && !tabs[tabIndex].defaultArrangement.layout.isEmpty {
                tabs[tabIndex].activeArrangementId = tabs[tabIndex].defaultArrangement.id
            }

            let activeArrangementIndex = tabs[tabIndex].activeArrangementIndex
            if let activePaneId = tabs[tabIndex].arrangements[activeArrangementIndex].activePaneId,
                !validPaneIds.contains(activePaneId)
                    || !tabs[tabIndex].arrangements[activeArrangementIndex].layout.contains(activePaneId)
                    || tabs[tabIndex].arrangements[activeArrangementIndex].minimizedPaneIds.contains(activePaneId)
            {
                tabs[tabIndex].arrangements[activeArrangementIndex].activePaneId =
                    TabArrangementSelectionRules.firstUnminimizedPaneId(
                        in: tabs[tabIndex].arrangements[activeArrangementIndex]
                    )
            }
        }

        tabs.removeAll { tab in
            tab.allPaneIds.isEmpty && tab.arrangements.allSatisfy { $0.layout.isEmpty }
        }
        if let currentActiveTabId = activeTabId, !tabs.contains(where: { $0.id == currentActiveTabId }) {
            activeTabId = tabs.last?.id
        }
    }
}
