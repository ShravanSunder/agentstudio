import Foundation
import os.log

private let workspacePersistenceTransformerLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspacePersistenceTransformer"
)

struct WorkspaceTabMembershipRepairReport: Equatable {
    let repairedTabIds: [UUID]
    let activeTabIdChanged: Bool

    var hasRepairs: Bool {
        !repairedTabIds.isEmpty || activeTabIdChanged
    }
}

struct WorkspaceTabMembershipNormalizationResult: Equatable {
    let tabs: [Tab]
    let activeTabId: UUID?
    let repairReport: WorkspaceTabMembershipRepairReport
}

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
            validPaneIds: workspacePaneAtom.graphAtom.paneIds
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
            workspacePaneAtom.legacyPersistablePanes.values.filter { pane in
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

    static func makeLiveSQLiteState(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        persistedAt: Date
    ) -> WorkspacePersistor.PersistableState {
        persistableState(
            from: makeLiveSQLiteSnapshot(
                identityAtom: identityAtom,
                windowMemoryAtom: windowMemoryAtom,
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: workspacePaneAtom,
                workspaceTabLayoutAtom: workspaceTabLayoutAtom,
                persistedAt: persistedAt
            )
        )
    }

    static func makeLiveSQLiteSnapshot(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        persistedAt: Date
    ) -> WorkspaceSQLiteSnapshot {
        let livePanes = Array(workspacePaneAtom.liveSQLitePanes.values)
        let normalizedTabs = normalizeLiveSQLiteTabs(
            tabs: workspaceTabLayoutAtom.tabs,
            validPaneIds: Set(livePanes.map(\.id)),
            activeTabId: workspaceTabLayoutAtom.activeTabId
        )
        if normalizedTabs.repairReport.hasRepairs {
            let repairedTabIds = normalizedTabs.repairReport.repairedTabIds
                .map(\.uuidString)
                .joined(separator: ",")
            workspacePersistenceTransformerLogger.warning(
                "Repaired live SQLite tab membership for \(normalizedTabs.repairReport.repairedTabIds.count) tab(s); activeTabIdChanged=\(normalizedTabs.repairReport.activeTabIdChanged); tabIds=\(repairedTabIds)"
            )
        }

        return WorkspaceSQLiteSnapshot(
            id: identityAtom.workspaceId,
            name: identityAtom.workspaceName,
            repos: canonicalRepos(from: repositoryTopologyAtom.repos),
            worktrees: canonicalWorktrees(from: repositoryTopologyAtom.repos),
            unavailableRepoIds: repositoryTopologyAtom.unavailableRepoIds,
            panes: livePanes,
            tabs: normalizedTabs.tabs,
            activeTabId: normalizedTabs.activeTabId,
            sidebarWidth: windowMemoryAtom.sidebarWidth,
            windowFrame: windowMemoryAtom.windowFrame,
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            createdAt: identityAtom.createdAt,
            updatedAt: persistedAt
        )
    }

    static func normalizeLiveSQLiteTabs(
        tabs: [Tab],
        validPaneIds: Set<UUID>,
        activeTabId: UUID?
    ) -> WorkspaceTabMembershipNormalizationResult {
        var normalizedTabs = tabs
        var repairedTabIds: [UUID] = []

        for tabIndex in normalizedTabs.indices {
            let originalTab = normalizedTabs[tabIndex]
            normalizedTabs[tabIndex].arrangements = TabArrangementRepairRules.pruningInvalidPaneIds(
                validPaneIds: validPaneIds,
                from: normalizedTabs[tabIndex].arrangements
            )

            if normalizedTabs[tabIndex].activeArrangement.layout.isEmpty
                && !normalizedTabs[tabIndex].defaultArrangement.layout.isEmpty
            {
                normalizedTabs[tabIndex].activeArrangementId = normalizedTabs[tabIndex].defaultArrangement.id
            }

            let activeArrangementIndex = normalizedTabs[tabIndex].activeArrangementIndex
            if let activePaneId = normalizedTabs[tabIndex].arrangements[activeArrangementIndex].activePaneId,
                !validPaneIds.contains(activePaneId)
                    || !normalizedTabs[tabIndex].arrangements[activeArrangementIndex].layout.contains(activePaneId)
                    || normalizedTabs[tabIndex].arrangements[activeArrangementIndex].minimizedPaneIds.contains(
                        activePaneId)
            {
                normalizedTabs[tabIndex].arrangements[activeArrangementIndex].activePaneId =
                    TabArrangementSelectionRules.firstUnminimizedPaneId(
                        in: normalizedTabs[tabIndex].arrangements[activeArrangementIndex]
                    )
            }

            normalizedTabs[tabIndex].allPaneIds = normalizedMembershipPaneIds(
                for: normalizedTabs[tabIndex],
                validPaneIds: validPaneIds
            )

            if normalizedTabs[tabIndex] != originalTab {
                repairedTabIds.append(originalTab.id)
            }
        }

        let tabIdsBeforeDroppingEmptyTabs = Set(normalizedTabs.map(\.id))
        normalizedTabs.removeAll { tab in
            tab.arrangements.first(where: \.isDefault)?.layout.isEmpty ?? true
        }
        let droppedTabIds = tabIdsBeforeDroppingEmptyTabs.subtracting(normalizedTabs.map(\.id))
        for tabId in droppedTabIds where !repairedTabIds.contains(tabId) {
            repairedTabIds.append(tabId)
        }

        var normalizedActiveTabId = activeTabId
        if let currentActiveTabId = activeTabId, !normalizedTabs.contains(where: { $0.id == currentActiveTabId }) {
            normalizedActiveTabId = normalizedTabs.last?.id
        }

        return WorkspaceTabMembershipNormalizationResult(
            tabs: normalizedTabs,
            activeTabId: normalizedActiveTabId,
            repairReport: WorkspaceTabMembershipRepairReport(
                repairedTabIds: repairedTabIds,
                activeTabIdChanged: normalizedActiveTabId != activeTabId
            )
        )
    }

    private static func normalizedMembershipPaneIds(for tab: Tab, validPaneIds: Set<UUID>) -> [UUID] {
        let referencedPaneIds = orderedReferencedPaneIds(in: tab, validPaneIds: validPaneIds)
        let referencedPaneIdSet = Set(referencedPaneIds)
        var normalizedPaneIds: [UUID] = []

        for paneId in tab.allPaneIds where validPaneIds.contains(paneId) && referencedPaneIdSet.contains(paneId) {
            appendPaneId(paneId, to: &normalizedPaneIds)
        }
        for paneId in referencedPaneIds {
            appendPaneId(paneId, to: &normalizedPaneIds)
        }

        return normalizedPaneIds
    }

    private static func orderedReferencedPaneIds(in tab: Tab, validPaneIds: Set<UUID>) -> [UUID] {
        var paneIds: [UUID] = []
        for arrangement in tab.arrangements {
            for paneId in arrangement.layout.paneIds where validPaneIds.contains(paneId) {
                appendPaneId(paneId, to: &paneIds)
            }
            for drawerId in arrangement.drawerViews.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let drawerView = arrangement.drawerViews[drawerId] else { continue }
                for paneId in drawerView.layout.paneIds where validPaneIds.contains(paneId) {
                    appendPaneId(paneId, to: &paneIds)
                }
            }
        }
        return paneIds
    }

    private static func appendPaneId(_ paneId: UUID, to paneIds: inout [UUID]) {
        guard !paneIds.contains(paneId) else { return }
        paneIds.append(paneId)
    }

    nonisolated static func sqliteSnapshot(
        from state: WorkspacePersistor.PersistableState
    ) -> WorkspaceSQLiteSnapshot {
        WorkspaceSQLiteSnapshot(
            id: state.id,
            name: state.name,
            repos: state.repos,
            worktrees: state.worktrees,
            unavailableRepoIds: state.unavailableRepoIds,
            panes: state.panes,
            tabs: state.tabs,
            activeTabId: state.activeTabId,
            sidebarWidth: state.sidebarWidth,
            windowFrame: state.windowFrame,
            watchedPaths: state.watchedPaths,
            createdAt: state.createdAt,
            updatedAt: state.updatedAt
        )
    }

    nonisolated static func persistableState(from snapshot: WorkspaceSQLiteSnapshot)
        -> WorkspacePersistor.PersistableState
    {
        WorkspacePersistor.PersistableState(
            id: snapshot.id,
            name: snapshot.name,
            repos: snapshot.repos,
            worktrees: snapshot.worktrees,
            unavailableRepoIds: snapshot.unavailableRepoIds,
            panes: snapshot.panes,
            tabs: snapshot.tabs,
            activeTabId: snapshot.activeTabId,
            sidebarWidth: snapshot.sidebarWidth,
            windowFrame: snapshot.windowFrame,
            watchedPaths: snapshot.watchedPaths,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
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
