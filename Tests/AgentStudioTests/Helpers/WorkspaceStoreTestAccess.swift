import Foundation

@testable import AgentStudio

@MainActor
extension WorkspaceStore {
    /// Test-target-only convenience seam for constructing a workspace store
    /// around explicitly supplied atom owners.
    convenience init(
        identityAtom: WorkspaceIdentityAtom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate()),
        windowMemoryAtom: WorkspaceWindowMemoryAtom = WorkspaceWindowMemoryAtom(),
        repositoryTopologyAtom: RepositoryTopologyAtom = RepositoryTopologyAtom(),
        paneGraphAtom: WorkspacePaneGraphAtom = WorkspacePaneGraphAtom(),
        drawerCursorAtom: WorkspaceDrawerCursorAtom = WorkspaceDrawerCursorAtom(),
        paneAtom: WorkspacePaneAtom? = nil,
        tabShellAtom: WorkspaceTabShellAtom = WorkspaceTabShellAtom(),
        tabArrangementAtom: WorkspaceTabArrangementAtom = WorkspaceTabArrangementAtom(),
        tabLayoutAtom: WorkspaceTabLayoutAtom? = nil,
        mutationCoordinator: WorkspaceMutationCoordinator? = nil,
        sqliteDatastore: WorkspaceSQLiteDatastore? = nil,
        sqliteSaveCoordinator: WorkspaceSQLiteSaveCoordinator? = nil,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: (any Clock<Duration> & Sendable)? = nil,
        recoveryReporter: PersistenceRecoveryReporter? = nil,
        startsObserving: Bool = true
    ) {
        let resolvedTabShellAtom = tabLayoutAtom?.shellAtom ?? tabShellAtom
        let resolvedTabArrangementAtom = tabLayoutAtom?.arrangementAtom ?? tabArrangementAtom
        let resolvedTabLayoutAtom =
            tabLayoutAtom
            ?? WorkspaceTabLayoutAtom(
                shellAtom: resolvedTabShellAtom,
                arrangementAtom: resolvedTabArrangementAtom
            )
        let resolvedPaneAtom =
            paneAtom
            ?? WorkspacePaneAtom(
                graphAtom: paneGraphAtom,
                drawerCursorAtom: drawerCursorAtom,
                repositoryTopologyAtom: repositoryTopologyAtom
            )
        let resolvedMutationCoordinator =
            mutationCoordinator
            ?? WorkspaceMutationCoordinator(
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: resolvedPaneAtom,
                workspaceTabShellAtom: resolvedTabShellAtom,
                workspaceTabArrangementAtom: resolvedTabArrangementAtom
            )
        let testSQLiteRoot = FileManager.default.temporaryDirectory.appending(
            path: "workspace-store-test-\(UUIDv7.generate().uuidString)"
        )
        let resolvedSQLiteDatastore =
            sqliteDatastore
            ?? WorkspaceSQLiteDatastoreFactory(
                coreDatabaseURL: testSQLiteRoot.appending(path: "core.sqlite"),
                localDatabaseURL: { workspaceId in
                    testSQLiteRoot.appending(path: "\(workspaceId.uuidString).local.sqlite")
                }
            ).makeDatastore()
        self.init(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            paneAtom: resolvedPaneAtom,
            tabLayoutAtom: resolvedTabLayoutAtom,
            mutationCoordinator: resolvedMutationCoordinator,
            sqliteDatastore: resolvedSQLiteDatastore,
            sqliteSaveCoordinator: sqliteSaveCoordinator,
            persistDebounceDuration: persistDebounceDuration,
            clock: clock,
            recoveryReporter: recoveryReporter
        )
        if startsObserving {
            startObserving()
        }
    }

    convenience init(
        catalogAtom: RepositoryTopologyAtom,
        graphAtom: WorkspacePaneAtom,
        interactionAtom: WorkspaceTabLayoutAtom,
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> & Sendable = ContinuousClock()
    ) {
        self.init(
            identityAtom: WorkspaceIdentityAtom(workspaceId: UUIDv7.generate()),
            windowMemoryAtom: WorkspaceWindowMemoryAtom(),
            repositoryTopologyAtom: catalogAtom,
            paneAtom: graphAtom,
            tabShellAtom: interactionAtom.shellAtom,
            tabArrangementAtom: interactionAtom.arrangementAtom,
            tabLayoutAtom: interactionAtom,
            mutationCoordinator: WorkspaceMutationCoordinator(
                repositoryTopologyAtom: catalogAtom,
                workspacePaneAtom: graphAtom,
                workspaceTabShellAtom: interactionAtom.shellAtom,
                workspaceTabArrangementAtom: interactionAtom.arrangementAtom
            ),
            persistDebounceDuration: persistDebounceDuration,
            clock: clock
        )
    }

    var workspaceId: UUID { identityAtom.workspaceId }
    var workspaceName: String { identityAtom.workspaceName }
    var sidebarWidth: CGFloat { windowMemoryAtom.sidebarWidth }
    var windowFrame: CGRect? { windowMemoryAtom.windowFrame }
    var repos: [Repo] { repositoryTopologyAtom.repos }
    var watchedPaths: [WatchedPath] { repositoryTopologyAtom.watchedPaths }
    var panes: [UUID: Pane] { paneAtom.panes }
    var tabs: [Tab] { tabLayoutAtom.tabs }
    var activeTabId: UUID? { tabLayoutAtom.activeTabId }
    var activeTab: Tab? { tabLayoutAtom.activeTab }
    var orphanedPanes: [Pane] { paneAtom.orphanedPanes(excluding: tabLayoutAtom.allPaneIds) }

    var graphAtom: WorkspacePaneAtom { paneAtom }
    var catalogAtom: RepositoryTopologyAtom { repositoryTopologyAtom }
    var interactionAtom: WorkspaceTabLayoutAtom { tabLayoutAtom }
    var tabShellStateAtom: WorkspaceTabShellAtom { tabShellAtom }
    var tabArrangementStateAtom: WorkspaceTabArrangementAtom { tabArrangementAtom }

    func pane(_ id: UUID) -> Pane? { paneAtom.pane(id) }
    func tab(_ id: UUID) -> Tab? { tabLayoutAtom.tab(id) }
    func drawerView(forParent parentPaneId: UUID) -> DrawerView? {
        guard let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId,
            let tab = tabLayoutAtom.tab(tabId)
        else { return nil }
        return tab.activeArrangement.drawerViews[drawerId]
    }
    func repo(_ id: UUID) -> Repo? { repositoryTopologyAtom.repo(id) }
    func worktree(_ id: UUID) -> Worktree? { repositoryTopologyAtom.worktree(id) }
    func repo(containing worktreeId: UUID) -> Repo? { repositoryTopologyAtom.repo(containing: worktreeId) }
    func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? {
        repositoryTopologyAtom.repoAndWorktree(containing: cwd)
    }
    func tabContaining(paneId: UUID) -> Tab? { tabLayoutAtom.tabContaining(paneId: paneId) }
    func panes(for worktreeId: UUID) -> [Pane] { paneAtom.panes(for: worktreeId) }
    func paneCount(for worktreeId: UUID) -> Int { paneAtom.paneCount(for: worktreeId) }
    func isWorktreeActive(_ worktreeId: UUID) -> Bool { paneAtom.isWorktreeActive(worktreeId) }
    func isRepoUnavailable(_ repoId: UUID) -> Bool { repositoryTopologyAtom.isRepoUnavailable(repoId) }

    @discardableResult
    func createPane(
        launchDirectory: URL? = nil,
        title: String = "Terminal",
        provider: SessionProvider = .zmx,
        lifetime: SessionLifetime = .persistent,
        zmxSessionID: ZmxSessionID = .generateUUIDv7(),
        residency: SessionResidency = .active,
        facets: PaneContextFacets = .empty
    ) -> Pane {
        paneAtom.createPane(
            launchDirectory: launchDirectory,
            title: title,
            provider: provider,
            lifetime: lifetime,
            zmxSessionID: zmxSessionID,
            residency: residency,
            facets: facets
        )
    }

    @discardableResult
    func createPane(
        content: PaneContent,
        metadata: PaneMetadata,
        residency: SessionResidency = .active
    ) -> Pane {
        paneAtom.createPane(content: content, metadata: metadata, residency: residency)
    }

    func removePane(_ paneId: UUID) { mutationCoordinator.removePane(paneId) }
    func updatePaneTitle(_ paneId: UUID, title: String) { paneAtom.updatePaneTitle(paneId, title: title) }
    func updatePaneCWD(_ paneId: UUID, cwd: URL?) { paneAtom.updatePaneCWD(paneId, cwd: cwd) }
    func updatePaneWebviewState(_ paneId: UUID, state: WebviewState) {
        paneAtom.updatePaneWebviewState(paneId, state: state)
    }
    func syncPaneWebviewState(_ paneId: UUID, state: WebviewState) {
        paneAtom.syncPaneWebviewState(paneId, state: state)
    }
    func setResidency(_ residency: SessionResidency, for paneId: UUID) { paneAtom.setResidency(residency, for: paneId) }
    func backgroundPane(_ paneId: UUID) { mutationCoordinator.backgroundPane(paneId) }
    func reactivatePane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position,
        sizingMode: DropSizingMode
    ) {
        mutationCoordinator.reactivatePane(
            paneId,
            inTab: tabId,
            at: targetPaneId,
            direction: direction,
            position: position,
            sizingMode: sizingMode
        )
    }
    func purgeOrphanedPane(_ paneId: UUID) { paneAtom.purgeOrphanedPane(paneId) }
    func appendTab(_ tab: Tab) { tabLayoutAtom.appendTab(tab) }
    func removeTab(_ tabId: UUID) { tabLayoutAtom.removeTab(tabId) }
    func insertTab(_ tab: Tab, at index: Int) { tabLayoutAtom.insertTab(tab, at: index) }
    func moveTab(fromId: UUID, toIndex: Int) { tabLayoutAtom.moveTab(fromId: fromId, toIndex: toIndex) }
    func moveTabByDelta(tabId: UUID, delta: Int) { tabLayoutAtom.moveTabByDelta(tabId: tabId, delta: delta) }
    func setActiveTab(_ tabId: UUID?) { tabLayoutAtom.setActiveTab(tabId) }
    func renameTab(_ tabId: UUID, name: String) { tabLayoutAtom.renameTab(tabId, name: name) }
    @discardableResult
    func insertPane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position,
        sizingMode: DropSizingMode
    ) -> Bool {
        tabLayoutAtom.insertPane(
            paneId,
            inTab: tabId,
            at: targetPaneId,
            direction: direction,
            position: position,
            sizingMode: sizingMode
        )
    }
    func removePaneFromLayout(_ paneId: UUID, inTab tabId: UUID) {
        tabLayoutAtom.removePaneFromLayout(paneId, inTab: tabId)
    }
    func resizePane(tabId: UUID, splitId: UUID, ratio: Double) {
        tabLayoutAtom.resizePane(tabId: tabId, splitId: splitId, ratio: ratio)
    }
    func resizeVisiblePanePair(tabId: UUID, leftPaneId: UUID, rightPaneId: UUID, ratio: Double) {
        tabLayoutAtom.resizeVisiblePanePair(
            tabId: tabId, leftPaneId: leftPaneId, rightPaneId: rightPaneId, ratio: ratio)
    }
    func equalizePanes(tabId: UUID) { tabLayoutAtom.equalizePanes(tabId: tabId) }
    func setActivePane(_ paneId: UUID?, inTab tabId: UUID) { tabLayoutAtom.setActivePane(paneId, inTab: tabId) }
    @discardableResult
    func createArrangement(name: String, inTab tabId: UUID) -> UUID? {
        tabLayoutAtom.createArrangement(name: name, inTab: tabId)
    }
    func removeArrangement(_ arrangementId: UUID, inTab tabId: UUID) {
        tabLayoutAtom.removeArrangement(arrangementId, inTab: tabId)
    }
    func switchArrangement(to arrangementId: UUID, inTab tabId: UUID) {
        tabLayoutAtom.switchArrangement(to: arrangementId, inTab: tabId)
    }
    func renameArrangement(_ arrangementId: UUID, name: String, inTab tabId: UUID) {
        tabLayoutAtom.renameArrangement(arrangementId, name: name, inTab: tabId)
    }
    @discardableResult
    func addDrawerPane(
        to parentPaneId: UUID,
        parentFallbackCWD: URL? = nil,
        zmxSessionID: ZmxSessionID = .generateUUIDv7()
    ) -> Pane? {
        let fallbackCWD =
            parentFallbackCWD
            ?? paneAtom.pane(parentPaneId)?.worktreeId.flatMap(repositoryTopologyAtom.worktree)?.path
        guard
            let drawerPane = paneAtom.addDrawerPane(
                to: parentPaneId,
                parentFallbackCWD: fallbackCWD,
                zmxSessionID: zmxSessionID
            )
        else {
            return nil
        }
        if let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
        {
            tabArrangementAtom.addDrawerPaneView(
                drawerId: drawerId,
                parentPaneId: parentPaneId,
                drawerPaneId: drawerPane.id,
                inTab: tabId
            )
        }
        return drawerPane
    }
    @discardableResult
    func insertDrawerPane(
        in parentPaneId: UUID,
        at targetDrawerPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position,
        sizingMode: DropSizingMode
    ) -> Pane? {
        let splitDirection: SplitNewDirection =
            switch (direction, position) {
            case (.horizontal, .before): .left
            case (.horizontal, .after): .right
            case (.vertical, .before): .up
            case (.vertical, .after): .down
            }
        let fallbackCWD = paneAtom.pane(parentPaneId)?.worktreeId.flatMap(repositoryTopologyAtom.worktree)?.path
        guard
            let drawerPane = paneAtom.insertDrawerPane(
                in: parentPaneId,
                at: targetDrawerPaneId,
                direction: splitDirection,
                sizingMode: sizingMode,
                parentFallbackCWD: fallbackCWD,
                zmxSessionID: .generateUUIDv7()
            )
        else { return nil }
        if let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
        {
            tabArrangementAtom.addDrawerPaneView(
                drawerId: drawerId,
                parentPaneId: parentPaneId,
                drawerPaneId: drawerPane.id,
                inTab: tabId,
                targetDrawerPaneId: targetDrawerPaneId,
                direction: splitDirection,
                sizingMode: sizingMode
            )
        }
        return drawerPane
    }
    func moveDrawerPane(
        _ drawerPaneId: UUID,
        in parentPaneId: UUID,
        target: DrawerRearrangeTarget,
        sizingMode: DropSizingMode
    ) {
        guard let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
        else { return }
        tabArrangementAtom.moveDrawerPane(
            drawerPaneId,
            drawerId: drawerId,
            tabId: tabId,
            target: target,
            sizingMode: sizingMode
        )
    }
    func removeDrawerPane(_ drawerPaneId: UUID, from parentPaneId: UUID) {
        let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
        let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id
        paneAtom.removeDrawerPane(drawerPaneId, from: parentPaneId)
        if let drawerId, let tabId {
            tabArrangementAtom.removeDrawerPaneView(drawerId: drawerId, drawerPaneId: drawerPaneId, inTab: tabId)
        }
    }
    func toggleDrawer(for paneId: UUID) { paneAtom.toggleDrawer(for: paneId) }
    func collapseAllDrawers() { paneAtom.collapseAllDrawers() }
    func setActiveDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) {
        guard let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
        else { return }
        tabArrangementAtom.setActiveDrawerPane(drawerPaneId, drawerId: drawerId, inTab: tabId)
    }
    func resizeDrawerPane(parentPaneId: UUID, splitId: UUID, ratio: Double) {
        guard let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
        else { return }
        tabArrangementAtom.resizeDrawerPane(drawerId: drawerId, tabId: tabId, splitId: splitId, ratio: ratio)
    }

    func resizeDrawerVisiblePanePair(parentPaneId: UUID, leftPaneId: UUID, rightPaneId: UUID, ratio: Double) {
        guard let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
        else { return }
        tabArrangementAtom.resizeDrawerVisiblePanePair(
            drawerId: drawerId,
            tabId: tabId,
            leftPaneId: leftPaneId,
            rightPaneId: rightPaneId,
            ratio: ratio
        )
    }

    func equalizeDrawerPanes(parentPaneId: UUID) {
        guard let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
        else { return }
        tabArrangementAtom.equalizeDrawerPanes(drawerId: drawerId, tabId: tabId)
    }
    @discardableResult
    func minimizeDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) -> Bool {
        guard let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
        else { return false }
        return tabArrangementAtom.minimizeDrawerPane(drawerPaneId, drawerId: drawerId, tabId: tabId)
    }
    func expandDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) {
        guard let tabId = tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
            let drawerId = paneAtom.pane(parentPaneId)?.drawer?.drawerId
        else { return }
        tabArrangementAtom.expandDrawerPane(drawerPaneId, drawerId: drawerId, tabId: tabId)
    }
    func toggleZoom(paneId: UUID, inTab tabId: UUID) { tabLayoutAtom.toggleZoom(paneId: paneId, inTab: tabId) }
    @discardableResult
    func minimizePane(_ paneId: UUID, inTab tabId: UUID) -> Bool { tabLayoutAtom.minimizePane(paneId, inTab: tabId) }
    func expandPane(_ paneId: UUID, inTab tabId: UUID) { tabLayoutAtom.expandPane(paneId, inTab: tabId) }
    func resizePaneByDelta(tabId: UUID, paneId: UUID, direction: SplitResizeDirection, amount: UInt16) {
        tabLayoutAtom.resizePaneByDelta(tabId: tabId, paneId: paneId, direction: direction, amount: amount)
    }
    func breakUpTab(_ tabId: UUID) -> [Tab] {
        tabLayoutAtom.breakUpTab(tabId, drawerPayloadsByParentPaneId: drawerMovePayloadsByParentPaneId(inTab: tabId))
    }
    func extractPane(_ paneId: UUID, fromTab tabId: UUID) -> Tab? {
        tabLayoutAtom.extractPane(
            paneId, fromTab: tabId, drawerPayload: drawerMovePayload(forParentPaneId: paneId, inTab: tabId))
    }
    func mergeTab(
        sourceId: UUID,
        intoTarget targetId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        tabLayoutAtom.mergeTab(
            sourceId: sourceId,
            intoTarget: targetId,
            at: targetPaneId,
            direction: direction,
            position: position,
            drawerPayloadsByParentPaneId: drawerMovePayloadsByParentPaneId(inTab: sourceId)
        )
    }
    @discardableResult
    func addRepo(at path: URL) -> Repo { repositoryTopologyAtom.addRepo(at: path) }
    func removeRepo(_ repoId: UUID) { repositoryTopologyAtom.removeRepo(repoId) }
    func markRepoUnavailable(_ repoId: UUID) { repositoryTopologyAtom.markRepoUnavailable(repoId) }
    func markRepoAvailable(_ repoId: UUID) { repositoryTopologyAtom.markRepoAvailable(repoId) }
    @discardableResult
    func addWatchedPath(_ path: URL) -> WatchedPath? { repositoryTopologyAtom.addWatchedPath(path) }
    func removeWatchedPath(_ id: UUID) { repositoryTopologyAtom.removeWatchedPath(id) }
    @discardableResult
    func orphanPanesForRepo(_ repoId: UUID) -> [UUID] {
        guard let repo = repositoryTopologyAtom.repo(repoId) else { return [] }
        let unavailablePathByWorktreeId = Dictionary(
            uniqueKeysWithValues: repo.worktrees.map { ($0.id, $0.path.path) }
        )
        return paneAtom.orphanPanes(forUnavailableWorktreePathsById: unavailablePathByWorktreeId)
    }
    @discardableResult
    func orphanPanesForWorktree(_ worktreeId: UUID, path: String) -> [UUID] {
        paneAtom.orphanPanesForWorktree(worktreeId, path: path)
    }
    @discardableResult
    func reassociateRepo(
        _ repoId: UUID,
        to newPath: URL,
        discoveredWorktrees: [Worktree]
    ) -> RepositoryReassociationResult {
        mutationCoordinator.reassociateRepo(repoId, to: newPath, discoveredWorktrees: discoveredWorktrees)
    }
    func reconcileDiscoveredWorktrees(_ repoId: UUID, worktrees: [Worktree]) {
        repositoryTopologyAtom.reconcileDiscoveredWorktrees(repoId, worktrees: worktrees)
    }
    func setSidebarWidth(_ sidebarWidth: CGFloat) { windowMemoryAtom.setSidebarWidth(sidebarWidth) }
    func setWindowFrame(_ windowFrame: CGRect?) { windowMemoryAtom.setWindowFrame(windowFrame) }
    func snapshotForClose(tabId: UUID) -> WorkspaceMutationCoordinator.TabCloseSnapshot? {
        mutationCoordinator.snapshotForClose(tabId: tabId)
    }
    func snapshotForPaneClose(paneId: UUID, inTab tabId: UUID) -> WorkspaceMutationCoordinator.PaneCloseSnapshot? {
        mutationCoordinator.snapshotForPaneClose(paneId: paneId, inTab: tabId)
    }
    func restoreFromSnapshot(_ snapshot: WorkspaceMutationCoordinator.TabCloseSnapshot) {
        mutationCoordinator.restoreFromSnapshot(snapshot)
    }
    func restoreFromPaneSnapshot(_ snapshot: WorkspaceMutationCoordinator.PaneCloseSnapshot) {
        mutationCoordinator.restoreFromPaneSnapshot(snapshot)
    }

    private func drawerMovePayloadsByParentPaneId(inTab tabId: UUID) -> [UUID: PaneDrawerMovePayload] {
        guard let tab = tabLayoutAtom.tab(tabId) else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: tab.allPaneIds.compactMap { paneId in
                guard let payload = drawerMovePayload(forParentPaneId: paneId, inTab: tabId) else { return nil }
                return (paneId, payload)
            }
        )
    }

    private func drawerMovePayload(forParentPaneId parentPaneId: UUID, inTab tabId: UUID) -> PaneDrawerMovePayload? {
        guard let drawer = paneAtom.pane(parentPaneId)?.drawer else { return nil }
        guard !drawer.paneIds.isEmpty else { return nil }
        let drawerView = tabLayoutAtom.tab(tabId)?.arrangements
            .compactMap { $0.drawerViews[drawer.drawerId] }
            .first
        return PaneDrawerMovePayload(
            drawerId: drawer.drawerId,
            drawerPaneIds: drawer.paneIds,
            drawerView: drawerView
        )
    }
}
