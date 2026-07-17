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

struct WorkspaceLiveSQLiteSnapshotResult: Equatable {
    let snapshot: WorkspaceSQLiteSnapshot
    let repairReport: WorkspaceTabMembershipRepairReport
}

struct WorkspaceLiveSQLiteSaveBundleResult: Equatable {
    let bundle: WorkspaceSQLiteSaveBundle
    let repairReport: WorkspaceTabMembershipRepairReport
}

@MainActor
enum WorkspacePersistenceTransformer {
    @discardableResult
    static func hydrate(
        _ state: WorkspacePersistor.PersistableState,
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom
    ) -> WorkspaceTabMembershipRepairReport {
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

        return hydrateWorkspaceOnly(
            state,
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: workspacePaneAtom,
            workspaceTabLayoutAtom: workspaceTabLayoutAtom
        )
    }

    static func hydrateRepositoryTopology(
        _ snapshot: RepositoryTopologySQLiteSnapshot,
        repositoryTopologyAtom: RepositoryTopologyAtom
    ) {
        let runtimeRepos = runtimeRepos(
            canonicalRepos: snapshot.repos,
            canonicalWorktrees: snapshot.worktrees
        )
        repositoryTopologyAtom.hydrate(
            runtimeRepos: runtimeRepos,
            watchedPaths: snapshot.watchedPaths,
            unavailableRepoIds: snapshot.unavailableRepoIds
        )
    }

    @discardableResult
    static func hydrateWorkspaceOnly(
        _ state: WorkspacePersistor.PersistableState,
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom
    ) -> WorkspaceTabMembershipRepairReport {
        identityAtom.hydrate(
            workspaceId: state.id,
            workspaceName: state.name,
            createdAt: state.createdAt
        )
        windowMemoryAtom.hydrate(
            sidebarWidth: state.sidebarWidth,
            windowFrame: state.windowFrame
        )

        workspacePaneAtom.hydrate(
            persistedPanes: state.panes,
            validWorktreeIds: repositoryTopologyAtom.allWorktreeIds
        )
        let validPaneIds = workspacePaneAtom.graphAtom.paneIds
        let drawerParentPaneIdByDrawerId = drawerParentPaneIdsByDrawerId(from: workspacePaneAtom.liveSQLitePanes.values)
        let normalizedTabs = normalizeLiveSQLiteTabs(
            tabs: state.tabs,
            validPaneIds: validPaneIds,
            activeTabId: state.activeTabId,
            drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId
        )
        workspaceTabLayoutAtom.hydrate(
            persistedTabs: normalizedTabs.tabs,
            activeTabId: normalizedTabs.activeTabId,
            validPaneIds: validPaneIds,
            drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId
        )
        return normalizedTabs.repairReport
    }

    static func makePersistableState(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
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
        let drawerParentPaneIdByDrawerId = drawerParentPaneIdsByDrawerId(from: persistablePanes)
        var prunedTabs = workspaceTabLayoutAtom.tabs
        var prunedActiveTabId = workspaceTabLayoutAtom.activeTabId
        pruneInvalidPanes(
            from: &prunedTabs,
            validPaneIds: validPaneIds,
            drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId,
            activeTabId: &prunedActiveTabId
        )

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
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        persistedAt: Date
    ) -> WorkspacePersistor.PersistableState {
        persistableState(
            from: makeLiveSQLiteSaveBundle(
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
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        persistedAt: Date
    ) -> WorkspaceSQLiteSnapshot {
        makeLiveSQLiteSnapshotResult(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: workspacePaneAtom,
            workspaceTabLayoutAtom: workspaceTabLayoutAtom,
            persistedAt: persistedAt
        ).snapshot
    }

    static func makeLiveSQLiteSaveBundle(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        persistedAt: Date
    ) -> WorkspaceSQLiteSaveBundle {
        makeLiveSQLiteSaveBundleResult(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: workspacePaneAtom,
            workspaceTabLayoutAtom: workspaceTabLayoutAtom,
            persistedAt: persistedAt
        ).bundle
    }

    static func makeLiveSQLiteSaveBundleResult(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        persistedAt: Date
    ) -> WorkspaceLiveSQLiteSaveBundleResult {
        let workspaceSnapshotResult = makeLiveSQLiteSnapshotResult(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: workspacePaneAtom,
            workspaceTabLayoutAtom: workspaceTabLayoutAtom,
            persistedAt: persistedAt
        )
        return WorkspaceLiveSQLiteSaveBundleResult(
            bundle: .init(
                workspace: workspaceSnapshotResult.snapshot,
                repositoryTopology: makeRepositoryTopologySQLiteSnapshot(
                    identityAtom: identityAtom,
                    repositoryTopologyAtom: repositoryTopologyAtom,
                    persistedAt: persistedAt
                )
            ),
            repairReport: workspaceSnapshotResult.repairReport
        )
    }

    static func makeLiveSQLiteSnapshotResult(
        identityAtom: WorkspaceIdentityAtom,
        windowMemoryAtom: WorkspaceWindowMemoryAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        workspacePaneAtom: WorkspacePaneAtom,
        workspaceTabLayoutAtom: WorkspaceTabLayoutAtom,
        persistedAt: Date
    ) -> WorkspaceLiveSQLiteSnapshotResult {
        let livePanes = Array(workspacePaneAtom.liveSQLitePanes.values)
        let drawerParentPaneIdByDrawerId = drawerParentPaneIdsByDrawerId(from: livePanes)
        let normalizedTabs = normalizeLiveSQLiteTabs(
            tabs: workspaceTabLayoutAtom.tabs,
            validPaneIds: Set(livePanes.map(\.id)),
            activeTabId: workspaceTabLayoutAtom.activeTabId,
            drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId
        )
        if normalizedTabs.repairReport.hasRepairs {
            let repairedTabIds = normalizedTabs.repairReport.repairedTabIds
                .map(\.uuidString)
                .joined(separator: ",")
            workspacePersistenceTransformerLogger.warning(
                "Repaired live SQLite tab membership for \(normalizedTabs.repairReport.repairedTabIds.count) tab(s); activeTabIdChanged=\(normalizedTabs.repairReport.activeTabIdChanged); tabIds=\(repairedTabIds)"
            )
        }

        return WorkspaceLiveSQLiteSnapshotResult(
            snapshot: WorkspaceSQLiteSnapshot(
                id: identityAtom.workspaceId,
                name: identityAtom.workspaceName,
                panes: livePanes,
                tabs: normalizedTabs.tabs,
                activeTabId: normalizedTabs.activeTabId,
                sidebarWidth: windowMemoryAtom.sidebarWidth,
                windowFrame: windowMemoryAtom.windowFrame,
                createdAt: identityAtom.createdAt,
                updatedAt: persistedAt
            ),
            repairReport: normalizedTabs.repairReport
        )
    }

    static func makeRepositoryTopologySQLiteSnapshot(
        identityAtom: WorkspaceIdentityAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom,
        persistedAt: Date
    ) -> RepositoryTopologySQLiteSnapshot {
        RepositoryTopologySQLiteSnapshot(
            id: identityAtom.workspaceId,
            repos: canonicalRepos(from: repositoryTopologyAtom.repos),
            worktrees: canonicalWorktrees(from: repositoryTopologyAtom.repos),
            unavailableRepoIds: repositoryTopologyAtom.unavailableRepoIds,
            watchedPaths: repositoryTopologyAtom.watchedPaths,
            updatedAt: persistedAt
        )
    }

    static func normalizeLiveSQLiteTabs(
        tabs: [Tab],
        validPaneIds: Set<UUID>,
        activeTabId: UUID?,
        drawerParentPaneIdByDrawerId: [UUID: UUID]? = nil
    ) -> WorkspaceTabMembershipNormalizationResult {
        var normalizedTabs = tabs
        var repairedTabIds: [UUID] = []

        for tabIndex in normalizedTabs.indices {
            let originalTab = normalizedTabs[tabIndex]
            normalizedTabs[tabIndex].arrangements = TabArrangementRepairRules.pruningInvalidPaneIds(
                validPaneIds: validPaneIds,
                from: normalizedTabs[tabIndex].arrangements
            )
            normalizedTabs[tabIndex].arrangements = TabArrangementRepairRules.pruningDrawerViewsMissingParentPane(
                drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId,
                from: normalizedTabs[tabIndex].arrangements
            )
            normalizedTabs[tabIndex].arrangements = TabArrangementRepairRules.promotingLiveArrangementToDefault(
                in: normalizedTabs[tabIndex].arrangements
            )

            if normalizedTabs[tabIndex].activeArrangement.layout.isEmpty {
                if let liveArrangement = normalizedTabs[tabIndex].arrangements.first(where: { !$0.layout.isEmpty }) {
                    normalizedTabs[tabIndex].activeArrangementId = liveArrangement.id
                }
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
                validPaneIds: validPaneIds,
                drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId
            )

            if normalizedTabs[tabIndex] != originalTab {
                repairedTabIds.append(originalTab.id)
            }
        }

        let tabIdsBeforeDroppingEmptyTabs = Set(normalizedTabs.map(\.id))
        normalizedTabs.removeAll { tab in
            !TabArrangementRepairRules.hasLivePaneReferences(in: tab.arrangements)
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

    private static func normalizedMembershipPaneIds(
        for tab: Tab,
        validPaneIds: Set<UUID>,
        drawerParentPaneIdByDrawerId: [UUID: UUID]?
    ) -> [UUID] {
        let referencedPaneIds = orderedReferencedPaneIds(
            in: tab,
            validPaneIds: validPaneIds,
            drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId
        )
        let referencedPaneIdSet = Set(referencedPaneIds)
        var normalizedPaneIds: [UUID] = []
        var seenPaneIds = Set<UUID>()

        for paneId in referencedPaneIds {
            guard seenPaneIds.insert(paneId).inserted else { continue }
            normalizedPaneIds.append(paneId)
        }
        for paneId in tab.allPaneIds where validPaneIds.contains(paneId) && referencedPaneIdSet.contains(paneId) {
            guard seenPaneIds.insert(paneId).inserted else { continue }
            normalizedPaneIds.append(paneId)
        }

        return normalizedPaneIds
    }

    private static func orderedReferencedPaneIds(
        in tab: Tab,
        validPaneIds: Set<UUID>,
        drawerParentPaneIdByDrawerId: [UUID: UUID]?
    ) -> [UUID] {
        var paneIds: [UUID] = []
        var seenPaneIds = Set<UUID>()
        for arrangement in tab.arrangements {
            for paneId in arrangement.layout.paneIds where validPaneIds.contains(paneId) {
                guard seenPaneIds.insert(paneId).inserted else { continue }
                paneIds.append(paneId)
            }
            for drawerId in arrangement.drawerViews.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let drawerView = arrangement.drawerViews[drawerId] else { continue }
                if let drawerParentPaneIdByDrawerId {
                    guard let parentPaneId = drawerParentPaneIdByDrawerId[drawerId],
                        arrangement.layout.contains(parentPaneId)
                    else { continue }
                }
                for paneId in drawerView.layout.paneIds where validPaneIds.contains(paneId) {
                    guard seenPaneIds.insert(paneId).inserted else { continue }
                    paneIds.append(paneId)
                }
            }
        }
        return paneIds
    }

    nonisolated static func sqliteSnapshot(
        from state: WorkspacePersistor.PersistableState
    ) -> WorkspaceSQLiteSnapshot {
        WorkspaceSQLiteSnapshot(
            id: state.id,
            name: state.name,
            panes: state.panes,
            tabs: state.tabs,
            activeTabId: state.activeTabId,
            sidebarWidth: state.sidebarWidth,
            windowFrame: state.windowFrame,
            createdAt: state.createdAt,
            updatedAt: state.updatedAt
        )
    }

    nonisolated static func repositoryTopologySQLiteSnapshot(
        from state: WorkspacePersistor.PersistableState
    ) -> RepositoryTopologySQLiteSnapshot {
        RepositoryTopologySQLiteSnapshot(
            id: state.id,
            repos: state.repos,
            worktrees: state.worktrees,
            unavailableRepoIds: state.unavailableRepoIds,
            watchedPaths: state.watchedPaths,
            updatedAt: state.updatedAt
        )
    }

    nonisolated static func sqliteSaveBundle(
        from state: WorkspacePersistor.PersistableState
    ) -> WorkspaceSQLiteSaveBundle {
        WorkspaceSQLiteSaveBundle(
            workspace: sqliteSnapshot(from: state),
            repositoryTopology: repositoryTopologySQLiteSnapshot(from: state)
        )
    }

    nonisolated static func persistableState(from snapshot: WorkspaceSQLiteSnapshot)
        -> WorkspacePersistor.PersistableState
    {
        WorkspacePersistor.PersistableState(
            id: snapshot.id,
            name: snapshot.name,
            repos: [],
            worktrees: [],
            unavailableRepoIds: [],
            panes: snapshot.panes,
            tabs: snapshot.tabs,
            activeTabId: snapshot.activeTabId,
            sidebarWidth: snapshot.sidebarWidth,
            windowFrame: snapshot.windowFrame,
            watchedPaths: [],
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt
        )
    }

    nonisolated static func persistableState(from bundle: WorkspaceSQLiteSaveBundle)
        -> WorkspacePersistor.PersistableState
    {
        let snapshot = bundle.workspace
        let topology = bundle.repositoryTopology
        return WorkspacePersistor.PersistableState(
            id: snapshot.id,
            name: snapshot.name,
            repos: topology.repos,
            worktrees: topology.worktrees,
            unavailableRepoIds: topology.unavailableRepoIds,
            panes: snapshot.panes,
            tabs: snapshot.tabs,
            activeTabId: snapshot.activeTabId,
            sidebarWidth: snapshot.sidebarWidth,
            windowFrame: snapshot.windowFrame,
            watchedPaths: topology.watchedPaths,
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
                createdAt: repo.createdAt,
                isFavorite: repo.isFavorite,
                note: repo.note,
                tags: repo.tags
            )
        }
    }

    static func drawerParentPaneIdsByDrawerId<Panes: Collection>(from panes: Panes) -> [UUID: UUID]
    where Panes.Element == Pane {
        Dictionary(
            panes.compactMap { pane in
                pane.drawer.map { drawer in (drawer.drawerId, pane.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func canonicalWorktrees(from repos: [Repo]) -> [CanonicalWorktree] {
        repos.flatMap { repo in
            repo.worktrees.map { worktree in
                CanonicalWorktree(
                    id: worktree.id,
                    repoId: repo.id,
                    name: worktree.name,
                    path: worktree.path,
                    isMainWorktree: worktree.isMainWorktree,
                    note: worktree.note
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
                    isMainWorktree: canonicalWorktree.isMainWorktree,
                    note: canonicalWorktree.note
                )
            }
            return Repo(
                id: canonicalRepo.id,
                name: canonicalRepo.name,
                repoPath: canonicalRepo.repoPath,
                worktrees: worktrees,
                createdAt: canonicalRepo.createdAt,
                isFavorite: canonicalRepo.isFavorite,
                note: canonicalRepo.note,
                tags: canonicalRepo.tags
            )
        }
    }

    private static func pruneInvalidPanes(
        from tabs: inout [Tab],
        validPaneIds: Set<UUID>,
        drawerParentPaneIdByDrawerId: [UUID: UUID]?,
        activeTabId: inout UUID?
    ) {
        for tabIndex in tabs.indices {
            tabs[tabIndex].panes.removeAll { !validPaneIds.contains($0) }

            tabs[tabIndex].arrangements = TabArrangementRepairRules.pruningInvalidPaneIds(
                validPaneIds: validPaneIds,
                from: tabs[tabIndex].arrangements
            )
            tabs[tabIndex].arrangements = TabArrangementRepairRules.pruningDrawerViewsMissingParentPane(
                drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId,
                from: tabs[tabIndex].arrangements
            )
            tabs[tabIndex].arrangements = TabArrangementRepairRules.promotingLiveArrangementToDefault(
                in: tabs[tabIndex].arrangements
            )

            if tabs[tabIndex].activeArrangement.layout.isEmpty {
                if let liveArrangement = tabs[tabIndex].arrangements.first(where: { !$0.layout.isEmpty }) {
                    tabs[tabIndex].activeArrangementId = liveArrangement.id
                }
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
            !TabArrangementRepairRules.hasLivePaneReferences(in: tab.arrangements)
        }
        if let currentActiveTabId = activeTabId, !tabs.contains(where: { $0.id == currentActiveTabId }) {
            activeTabId = tabs.last?.id
        }
    }
}
