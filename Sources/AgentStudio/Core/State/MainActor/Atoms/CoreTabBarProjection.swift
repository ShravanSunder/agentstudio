import Foundation

package struct CoreTabBarProjectionRequest: Sendable {
    fileprivate let tabShells: [TabShell]
    fileprivate let activeTabId: UUID?
    fileprivate let tabGraphStates: [TabGraphState]
    fileprivate let activeArrangementIdsByTabId: [UUID: UUID]
    fileprivate let paneCursorsByArrangementId: [UUID: ArrangementPaneCursorState]
    fileprivate let drawerCursorsByKey: [ArrangementDrawerCursorKey: ArrangementDrawerCursorState]
    fileprivate let paneStates: [UUID: PaneGraphState]
    fileprivate let expandedDrawerId: UUID?
    fileprivate let repositories: [Repo]
    fileprivate let unavailableRepositoryIds: Set<UUID>
    fileprivate let repoEnrichmentSnapshot: [UUID: RepoEnrichment]
    fileprivate let worktreeEnrichmentSnapshot: [UUID: WorktreeEnrichment]
    fileprivate let zoomPresentationsByTabId: [UUID: ZoomPresentation]

    @MainActor
    package static func capture(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> Self {
        Self(
            tabShells: store.tabShellAtom.tabShells,
            activeTabId: store.tabCursorAtom.activeTabId,
            tabGraphStates: store.tabGraphAtom.tabStates,
            activeArrangementIdsByTabId: store.arrangementCursorAtom.activeArrangementIdsByTabId,
            paneCursorsByArrangementId: store.arrangementCursorAtom.paneCursorsByArrangementId,
            drawerCursorsByKey: store.arrangementCursorAtom.drawerCursorsByKey,
            paneStates: store.paneGraphAtom.paneStates,
            expandedDrawerId: store.drawerCursorAtom.expandedDrawerId,
            repositories: store.repositoryTopologyAtom.repos,
            unavailableRepositoryIds: store.repositoryTopologyAtom.unavailableRepoIds,
            repoEnrichmentSnapshot: repoCache.repoEnrichmentSnapshot(),
            worktreeEnrichmentSnapshot: repoCache.worktreeEnrichmentSnapshot(),
            zoomPresentationsByTabId: store.panePresentationAtom.zoomPresentationsByTabId
        )
    }
}

package struct CoreTabBarProjectionItem: Equatable, Sendable, Identifiable {
    package let id: UUID
    package let title: String
    package let isSplit: Bool
    package let displayTitle: String
    package let activeArrangementName: String
    package let activeArrangementBadgeNumber: Int?
    package let arrangementCount: Int
    package let colorHex: String?
    package let panes: [PaneVisibilityInfo]
    package let paneIds: [UUID]
    package let zoomMode: ArrangementPanelZoomMode?
    package let zoomSourcePaneOrdinal: Int?
    package let arrangements: [ArrangementInfo]
    package let minimizedCount: Int
}

package struct CoreTabBarProjection: Equatable, Sendable {
    package let items: [CoreTabBarProjectionItem]
    package let activeTabId: UUID?
}

package enum CoreTabBarProjector {
    package static func project(
        _ request: CoreTabBarProjectionRequest,
        cancellationCheck: () throws(CancellationError) -> Void = checkCancellation
    ) throws(CancellationError) -> CoreTabBarProjection {
        let topology = try CoreTabBarTopologySnapshot(
            repositories: request.repositories,
            unavailableRepositoryIds: request.unavailableRepositoryIds,
            cancellationCheck: cancellationCheck
        )
        let panesById = try makePanesById(
            request: request,
            topology: topology,
            cancellationCheck: cancellationCheck
        )
        let graphStatesByTabId = try makeGraphStatesByTabId(
            request.tabGraphStates,
            cancellationCheck: cancellationCheck
        )

        var items: [CoreTabBarProjectionItem] = []
        items.reserveCapacity(request.tabShells.count)
        for shell in request.tabShells {
            try cancellationCheck()
            guard let graphState = graphStatesByTabId[shell.id] else { continue }
            let arrangementState = try arrangementState(
                graphState: graphState,
                request: request,
                cancellationCheck: cancellationCheck
            )
            let tab = WorkspaceTabLayoutDerived.assembleTab(
                shell: shell,
                arrangementState: arrangementState
            )
            items.append(
                try item(
                    for: tab,
                    request: request,
                    panesById: panesById,
                    topology: topology,
                    cancellationCheck: cancellationCheck
                )
            )
        }

        try cancellationCheck()
        return CoreTabBarProjection(
            items: items,
            activeTabId: request.activeTabId ?? items.last?.id
        )
    }

    private static func checkCancellation() throws(CancellationError) {
        guard Task.isCancelled else { return }
        throw CancellationError()
    }

    private static func makeGraphStatesByTabId(
        _ graphStates: [TabGraphState],
        cancellationCheck: () throws(CancellationError) -> Void
    ) throws(CancellationError) -> [UUID: TabGraphState] {
        var graphStatesByTabId: [UUID: TabGraphState] = [:]
        graphStatesByTabId.reserveCapacity(graphStates.count)
        for graphState in graphStates {
            try cancellationCheck()
            graphStatesByTabId[graphState.tabId] = graphState
        }
        return graphStatesByTabId
    }

    private static func makePanesById(
        request: CoreTabBarProjectionRequest,
        topology: CoreTabBarTopologySnapshot,
        cancellationCheck: () throws(CancellationError) -> Void
    ) throws(CancellationError) -> [UUID: Pane] {
        var panesById: [UUID: Pane] = [:]
        panesById.reserveCapacity(request.paneStates.count)
        for (paneId, paneState) in request.paneStates {
            try cancellationCheck()
            var pane = paneState.pane(
                isDrawerExpanded: paneState.drawer?.drawerId == request.expandedDrawerId
            )
            pane.metadata.updateFacets(
                topology.displayFacets(
                    for: pane.metadata.facets,
                    repoEnrichmentByRepoId: request.repoEnrichmentSnapshot
                )
            )
            panesById[paneId] = pane
        }
        return panesById
    }

    private static func arrangementState(
        graphState: TabGraphState,
        request: CoreTabBarProjectionRequest,
        cancellationCheck: () throws(CancellationError) -> Void
    ) throws(CancellationError) -> TabArrangementState {
        var arrangements: [PaneArrangement] = []
        arrangements.reserveCapacity(graphState.arrangements.count)
        for arrangementGraphState in graphState.arrangements {
            try cancellationCheck()
            var drawerViews: [UUID: DrawerView] = [:]
            drawerViews.reserveCapacity(arrangementGraphState.drawerViews.count)
            for (drawerId, drawerGraphState) in arrangementGraphState.drawerViews {
                try cancellationCheck()
                let cursorKey = ArrangementDrawerCursorKey(
                    arrangementId: arrangementGraphState.id,
                    drawerId: drawerId
                )
                var drawerView = DrawerView(
                    layout: drawerGraphState.layout,
                    activeChildId: request.drawerCursorsByKey[cursorKey]?.activeChildId,
                    minimizedPaneIds: drawerGraphState.minimizedPaneIds
                )
                drawerView.activeChildId = request.drawerCursorsByKey[cursorKey]?.activeChildId
                drawerViews[drawerId] = drawerView
            }

            var arrangement = PaneArrangement(
                id: arrangementGraphState.id,
                name: arrangementGraphState.name,
                isDefault: arrangementGraphState.isDefault,
                layout: arrangementGraphState.layout,
                minimizedPaneIds: arrangementGraphState.minimizedPaneIds,
                activePaneId: request.paneCursorsByArrangementId[arrangementGraphState.id]?.activePaneId,
                drawerViews: drawerViews
            )
            arrangement.activePaneId = request.paneCursorsByArrangementId[arrangementGraphState.id]?.activePaneId
            arrangements.append(arrangement)
        }

        let activeArrangementId =
            request.activeArrangementIdsByTabId[graphState.tabId]
            ?? arrangements.first(where: \.isDefault)?.id
            ?? arrangements.first?.id
            ?? graphState.tabId
        return TabArrangementState(
            tabId: graphState.tabId,
            allPaneIds: graphState.allPaneIds,
            arrangements: arrangements,
            activeArrangementId: activeArrangementId
        )
    }

    private static func item(
        for tab: Tab,
        request: CoreTabBarProjectionRequest,
        panesById: [UUID: Pane],
        topology: CoreTabBarTopologySnapshot,
        cancellationCheck: () throws(CancellationError) -> Void
    ) throws(CancellationError) -> CoreTabBarProjectionItem {
        let displayTitle = try TabDisplayDerived.displayTitle(
            for: tab,
            cancellationCheck: cancellationCheck
        ) { paneId in
            guard let pane = panesById[paneId] else { return nil }
            let worktree = pane.worktreeId.flatMap { topology.worktreesById[$0] }
            return TabDisplayDerived.title(
                for: pane,
                worktree: worktree,
                enrichment: worktree.flatMap { request.worktreeEnrichmentSnapshot[$0.id] }
            )
        }

        var paneInfos: [PaneVisibilityInfo] = []
        paneInfos.reserveCapacity(tab.activePaneIds.count)
        for paneId in tab.activePaneIds {
            try cancellationCheck()
            let pane = panesById[paneId]
            let workspaceContext = pane.flatMap {
                topology.displayContext(
                    for: $0,
                    worktreeEnrichmentByWorktreeId: request.worktreeEnrichmentSnapshot
                )
            }
            let title =
                pane.map {
                    PaneDisplayDerived.displayParts(for: $0, workspaceContext: workspaceContext).primaryLabel
                } ?? "Terminal"
            paneInfos.append(
                ArrangementDerived.paneVisibilityInfo(
                    paneId: paneId,
                    title: title,
                    isMinimized: tab.activeMinimizedPaneIds.contains(paneId),
                    paneContent: pane?.content
                )
            )
        }

        var arrangementInfos: [ArrangementInfo] = []
        arrangementInfos.reserveCapacity(tab.arrangements.count)
        for arrangement in tab.arrangements {
            try cancellationCheck()
            arrangementInfos.append(
                ArrangementDerived.arrangementInfo(
                    for: arrangement,
                    activeArrangementId: tab.activeArrangementId
                )
            )
        }

        let zoomPresentation = request.zoomPresentationsByTabId[tab.id]
        let zoomMode = zoomPresentation.map { presentation in
            let sourceIdentity = panesById[presentation.sourcePaneId].map { sourcePane in
                ArrangementDerived.zoomSourceIdentity(
                    for: sourcePane,
                    workspaceContext: topology.zoomSourceContext(
                        for: sourcePane,
                        worktreeEnrichmentByWorktreeId: request.worktreeEnrichmentSnapshot
                    )
                )
            }
            return ArrangementDerived.zoomMode(
                presentation: presentation,
                sourceIdentity: sourceIdentity
            )
        }
        let activeArrangement = tab.activeArrangement

        return CoreTabBarProjectionItem(
            id: tab.id,
            title: displayTitle,
            isSplit: tab.isSplit,
            displayTitle: displayTitle,
            activeArrangementName: ArrangementDerived.activeArrangementDisplayName(for: activeArrangement),
            activeArrangementBadgeNumber: zoomPresentation == nil
                ? ArrangementDerived.activeArrangementBadgeNumber(for: tab) : nil,
            arrangementCount: tab.arrangements.count,
            colorHex: tab.colorHex,
            panes: paneInfos,
            paneIds: tab.allPaneIds,
            zoomMode: zoomMode,
            zoomSourcePaneOrdinal: zoomPresentation.flatMap { presentation in
                PaneOrdinalMap(orderedPaneIds: activeArrangement.layout.paneIds)
                    .ordinal(forPaneId: presentation.sourcePaneId)
            },
            arrangements: arrangementInfos,
            minimizedCount: tab.activeMinimizedPaneIds.count
        )
    }
}

private struct CoreTabBarTopologySnapshot {
    struct PathEntry {
        let repoId: UUID
        let worktreeId: UUID
        let normalizedWorktreePath: String
        let repoWorktreeCount: Int
        let repoPathMatchesWorktree: Bool
        let isMainWorktree: Bool
        let stableTieBreaker: String
    }

    let repositoriesById: [UUID: Repo]
    let worktreesById: [UUID: Worktree]
    let pathEntries: [PathEntry]

    init(
        repositories: [Repo],
        unavailableRepositoryIds: Set<UUID>,
        cancellationCheck: () throws(CancellationError) -> Void
    ) throws(CancellationError) {
        var repositoriesById: [UUID: Repo] = [:]
        var worktreesById: [UUID: Worktree] = [:]
        var pathEntries: [PathEntry] = []
        repositoriesById.reserveCapacity(repositories.count)

        for repository in repositories {
            try cancellationCheck()
            repositoriesById[repository.id] = repository
            let normalizedRepoPath = repository.repoPath.standardizedFileURL.path
            var normalizedWorktrees: [(worktree: Worktree, path: String)] = []
            normalizedWorktrees.reserveCapacity(repository.worktrees.count)
            for worktree in repository.worktrees {
                try cancellationCheck()
                worktreesById[worktree.id] = worktree
                normalizedWorktrees.append(
                    (worktree, worktree.path.standardizedFileURL.path)
                )
            }
            guard !unavailableRepositoryIds.contains(repository.id) else { continue }
            let repoPathMatchesAnyWorktree = normalizedWorktrees.contains {
                $0.path == normalizedRepoPath
            }
            for item in normalizedWorktrees {
                try cancellationCheck()
                pathEntries.append(
                    PathEntry(
                        repoId: repository.id,
                        worktreeId: item.worktree.id,
                        normalizedWorktreePath: item.path,
                        repoWorktreeCount: repository.worktrees.count,
                        repoPathMatchesWorktree: repoPathMatchesAnyWorktree
                            && normalizedRepoPath == item.path,
                        isMainWorktree: item.worktree.isMainWorktree,
                        stableTieBreaker: "\(repository.id.uuidString)|\(item.worktree.id.uuidString)"
                    )
                )
            }
        }

        try cancellationCheck()
        pathEntries.sort(by: Self.pathEntryPrecedes)
        try cancellationCheck()
        self.repositoriesById = repositoriesById
        self.worktreesById = worktreesById
        self.pathEntries = pathEntries
    }

    func displayFacets(
        for durableFacets: PaneContextFacets,
        repoEnrichmentByRepoId: [UUID: RepoEnrichment]
    ) -> PaneContextFacets {
        var facets = PaneContextFacets(cwd: durableFacets.cwd)
        guard let resolvedContext = repoAndWorktree(containing: facets.cwd) else {
            return facets
        }

        facets.repoId = resolvedContext.repo.id
        facets.worktreeId = resolvedContext.worktree.id
        facets.repoName = resolvedContext.repo.name
        facets.worktreeName = resolvedContext.worktree.name
        let parentName = resolvedContext.repo.repoPath.deletingLastPathComponent().lastPathComponent
        facets.parentFolder = parentName.isEmpty ? nil : parentName
        if let enrichment = repoEnrichmentByRepoId[resolvedContext.repo.id] {
            facets.organizationName = enrichment.organizationName
            facets.origin = enrichment.origin
            facets.upstream = enrichment.upstream
        }
        return facets
    }

    func displayContext(
        for pane: Pane,
        worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
    ) -> PaneDisplayWorkspaceContext? {
        let explicitRepoId = pane.repoId ?? pane.metadata.repoId
        let explicitWorktreeId = pane.worktreeId ?? pane.metadata.worktreeId
        let resolvedContext: (repo: Repo, worktree: Worktree)? = {
            if let explicitRepoId,
                let explicitWorktreeId,
                let repository = repositoriesById[explicitRepoId],
                let worktree = worktreesById[explicitWorktreeId]
            {
                return (repository, worktree)
            }
            return repoAndWorktree(containing: pane.metadata.cwd)
        }()

        if let resolvedContext {
            return PaneDisplayWorkspaceContext(
                repoName: pane.metadata.repoName ?? resolvedContext.repo.name,
                worktreeName: pane.metadata.worktreeName ?? resolvedContext.worktree.path.lastPathComponent,
                worktreeIconName: resolvedContext.worktree.isMainWorktree
                    ? "octicon-star-fill" : "octicon-git-worktree",
                branchName: PaneDisplayDerived.resolvedBranchName(
                    worktree: resolvedContext.worktree,
                    enrichment: worktreeEnrichmentByWorktreeId[resolvedContext.worktree.id]
                )
            )
        }

        if let repoName = pane.metadata.repoName, let worktreeName = pane.metadata.worktreeName {
            let branchName = explicitWorktreeId.flatMap { worktreeId in
                let branch = worktreeEnrichmentByWorktreeId[worktreeId]?.branch ?? ""
                return branch.isEmpty ? nil : branch
            }
            return PaneDisplayWorkspaceContext(
                repoName: repoName,
                worktreeName: worktreeName,
                worktreeIconName: "octicon-git-worktree",
                branchName: branchName
            )
        }
        return nil
    }

    func zoomSourceContext(
        for pane: Pane,
        worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
    ) -> PaneDisplayWorkspaceContext? {
        let resolvedContext =
            pane.worktreeId.flatMap { worktreeId in
                pane.repoId.flatMap { repoId in
                    repositoriesById[repoId].flatMap { repo in
                        worktreesById[worktreeId].map { (repo, $0) }
                    }
                }
            } ?? repoAndWorktree(containing: pane.metadata.cwd)
        guard let resolvedContext else { return nil }
        return PaneDisplayWorkspaceContext(
            repoName: resolvedContext.repo.name,
            worktreeName: resolvedContext.worktree.path.lastPathComponent,
            worktreeIconName: resolvedContext.worktree.isMainWorktree
                ? "octicon-star-fill" : "octicon-git-worktree",
            branchName: PaneDisplayDerived.resolvedBranchName(
                worktree: resolvedContext.worktree,
                enrichment: worktreeEnrichmentByWorktreeId[resolvedContext.worktree.id]
            )
        )
    }

    private func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? {
        guard let cwd else { return nil }
        let normalizedCWD = cwd.standardizedFileURL.path
        guard
            let match = pathEntries.first(where: {
                normalizedCWD == $0.normalizedWorktreePath
                    || normalizedCWD.hasPrefix($0.normalizedWorktreePath + "/")
            }),
            let repository = repositoriesById[match.repoId],
            let worktree = worktreesById[match.worktreeId]
        else {
            return nil
        }
        return (repository, worktree)
    }

    private static func pathEntryPrecedes(lhs: PathEntry, rhs: PathEntry) -> Bool {
        if lhs.normalizedWorktreePath.count != rhs.normalizedWorktreePath.count {
            return lhs.normalizedWorktreePath.count > rhs.normalizedWorktreePath.count
        }
        if lhs.repoWorktreeCount != rhs.repoWorktreeCount {
            return lhs.repoWorktreeCount < rhs.repoWorktreeCount
        }
        if lhs.repoPathMatchesWorktree != rhs.repoPathMatchesWorktree {
            return lhs.repoPathMatchesWorktree && !rhs.repoPathMatchesWorktree
        }
        if lhs.isMainWorktree != rhs.isMainWorktree {
            return !lhs.isMainWorktree && rhs.isMainWorktree
        }
        return lhs.stableTieBreaker < rhs.stableTieBreaker
    }
}
