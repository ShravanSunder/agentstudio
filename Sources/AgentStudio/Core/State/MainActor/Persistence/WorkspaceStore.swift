import Foundation
import Observation
import os.log

private let workspaceStoreLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceStore")

/// Main-actor persistence aggregate for the workspace atoms.
///
/// This type owns debounced persistence, restore, and flush. Workspace-domain
/// mutations live on the owning atoms or `WorkspaceMutationCoordinator`.
@MainActor
final class WorkspaceStore {
    let metadataAtom: WorkspaceMetadataAtom
    let repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom
    let paneAtom: WorkspacePaneAtom
    let tabLayoutAtom: WorkspaceTabLayoutAtom
    let mutationCoordinator: WorkspaceMutationCoordinator

    private let persistor: WorkspacePersistor
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private var debouncedSaveTask: Task<Void, Never>?
    private var isObservingPersistedState = false
    private var isRestoringState = false
    private(set) var scanningPath: URL?
    private(set) var isDirty: Bool = false

    init(
        metadataAtom: WorkspaceMetadataAtom = WorkspaceMetadataAtom(),
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom = WorkspaceRepositoryTopologyAtom(),
        paneAtom: WorkspacePaneAtom = WorkspacePaneAtom(),
        tabLayoutAtom: WorkspaceTabLayoutAtom = WorkspaceTabLayoutAtom(),
        mutationCoordinator: WorkspaceMutationCoordinator? = nil,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.metadataAtom = metadataAtom
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.paneAtom = paneAtom
        self.tabLayoutAtom = tabLayoutAtom
        self.mutationCoordinator =
            mutationCoordinator
            ?? WorkspaceMutationCoordinator(
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: paneAtom,
                workspaceTabLayoutAtom: tabLayoutAtom
            )
        self.persistor = persistor
        self.persistDebounceDuration = persistDebounceDuration
        self.clock = clock
        observePersistedState()
    }

    convenience init(
        catalogAtom: WorkspaceRepositoryTopologyAtom,
        graphAtom: WorkspacePaneAtom,
        interactionAtom: WorkspaceTabLayoutAtom,
        persistor: WorkspacePersistor = WorkspacePersistor(),
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.init(
            metadataAtom: WorkspaceMetadataAtom(),
            repositoryTopologyAtom: catalogAtom,
            paneAtom: graphAtom,
            tabLayoutAtom: interactionAtom,
            mutationCoordinator: WorkspaceMutationCoordinator(
                repositoryTopologyAtom: catalogAtom,
                workspacePaneAtom: graphAtom,
                workspaceTabLayoutAtom: interactionAtom
            ),
            persistor: persistor,
            persistDebounceDuration: persistDebounceDuration,
            clock: clock
        )
    }

    // MARK: - Read Aggregate

    var repos: [Repo] {
        repositoryTopologyAtom.repos
    }

    var watchedPaths: [WatchedPath] {
        repositoryTopologyAtom.watchedPaths
    }

    var panes: [UUID: Pane] {
        paneAtom.panes
    }

    var tabs: [Tab] {
        tabLayoutAtom.tabs
    }

    var activeTabId: UUID? {
        tabLayoutAtom.activeTabId
    }

    var workspaceId: UUID {
        metadataAtom.workspaceId
    }

    var workspaceName: String {
        metadataAtom.workspaceName
    }

    var sidebarWidth: CGFloat {
        metadataAtom.sidebarWidth
    }

    var windowFrame: CGRect? {
        metadataAtom.windowFrame
    }

    var createdAt: Date {
        metadataAtom.createdAt
    }

    var unavailableRepoIds: Set<UUID> {
        repositoryTopologyAtom.unavailableRepoIds
    }

    var activeTab: Tab? {
        tabLayoutAtom.activeTab
    }

    var activePaneIds: Set<UUID> {
        tabLayoutAtom.activePaneIds
    }

    var orphanedPanes: [Pane] {
        paneAtom.orphanedPanes(excluding: tabLayoutAtom.allPaneIds)
    }

    typealias CloseEntry = WorkspaceMutationCoordinator.CloseEntry
    typealias TabCloseSnapshot = WorkspaceMutationCoordinator.TabCloseSnapshot
    typealias PaneCloseSnapshot = WorkspaceMutationCoordinator.PaneCloseSnapshot
    typealias CloseSnapshot = TabCloseSnapshot

    // Transitional compatibility aliases for migrated call sites/tests.
    var catalogAtom: WorkspaceRepositoryTopologyAtom { repositoryTopologyAtom }
    var graphAtom: WorkspacePaneAtom { paneAtom }
    var interactionAtom: WorkspaceTabLayoutAtom { tabLayoutAtom }

    func pane(_ id: UUID) -> Pane? {
        paneAtom.pane(id)
    }

    func tab(_ id: UUID) -> Tab? {
        tabLayoutAtom.tab(id)
    }

    func tabContaining(paneId: UUID) -> Tab? {
        tabLayoutAtom.tabContaining(paneId: paneId)
    }

    func repo(_ id: UUID) -> Repo? {
        repositoryTopologyAtom.repo(id)
    }

    func worktree(_ id: UUID) -> Worktree? {
        repositoryTopologyAtom.worktree(id)
    }

    func repo(containing worktreeId: UUID) -> Repo? {
        repositoryTopologyAtom.repo(containing: worktreeId)
    }

    func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? {
        repositoryTopologyAtom.repoAndWorktree(containing: cwd)
    }

    func panes(for worktreeId: UUID) -> [Pane] {
        paneAtom.panes(for: worktreeId)
    }

    func paneCount(for worktreeId: UUID) -> Int {
        paneAtom.paneCount(for: worktreeId)
    }

    func isWorktreeActive(_ worktreeId: UUID) -> Bool {
        paneAtom.isWorktreeActive(worktreeId)
    }

    // MARK: - Forwarding Mutation Surface

    @discardableResult
    func createPane(
        source: TerminalSource,
        title: String = "Terminal",
        provider: SessionProvider = .zmx,
        lifetime: SessionLifetime = .persistent,
        residency: SessionResidency = .active,
        facets: PaneContextFacets = .empty
    ) -> Pane {
        paneAtom.createPane(
            source: source,
            title: title,
            provider: provider,
            lifetime: lifetime,
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

    func removePane(_ paneId: UUID) {
        mutationCoordinator.removePane(paneId)
    }

    func updatePaneTitle(_ paneId: UUID, title: String) {
        paneAtom.updatePaneTitle(paneId, title: title)
    }

    func updatePaneCWD(_ paneId: UUID, cwd: URL?) {
        paneAtom.updatePaneCWD(paneId, cwd: cwd)
    }

    func updatePaneWebviewState(_ paneId: UUID, state: WebviewState) {
        paneAtom.updatePaneWebviewState(paneId, state: state)
    }

    func syncPaneWebviewState(_ paneId: UUID, state: WebviewState) {
        paneAtom.syncPaneWebviewState(paneId, state: state)
    }

    func setResidency(_ residency: SessionResidency, for paneId: UUID) {
        paneAtom.setResidency(residency, for: paneId)
    }

    func backgroundPane(_ paneId: UUID) {
        mutationCoordinator.backgroundPane(paneId)
    }

    func reactivatePane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        mutationCoordinator.reactivatePane(
            paneId,
            inTab: tabId,
            at: targetPaneId,
            direction: direction,
            position: position
        )
    }

    func purgeOrphanedPane(_ paneId: UUID) {
        paneAtom.purgeOrphanedPane(paneId)
    }

    func appendTab(_ tab: Tab) {
        tabLayoutAtom.appendTab(tab)
    }

    func removeTab(_ tabId: UUID) {
        tabLayoutAtom.removeTab(tabId)
    }

    func insertTab(_ tab: Tab, at index: Int) {
        tabLayoutAtom.insertTab(tab, at: index)
    }

    func moveTab(fromId: UUID, toIndex: Int) {
        tabLayoutAtom.moveTab(fromId: fromId, toIndex: toIndex)
    }

    func moveTabByDelta(tabId: UUID, delta: Int) {
        tabLayoutAtom.moveTabByDelta(tabId: tabId, delta: delta)
    }

    func setActiveTab(_ tabId: UUID?) {
        tabLayoutAtom.setActiveTab(tabId)
    }

    @discardableResult
    func insertPane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) -> Bool {
        tabLayoutAtom.insertPane(
            paneId,
            inTab: tabId,
            at: targetPaneId,
            direction: direction,
            position: position
        )
    }

    func removePaneFromLayout(_ paneId: UUID, inTab tabId: UUID) {
        tabLayoutAtom.removePaneFromLayout(paneId, inTab: tabId)
    }

    func resizePane(tabId: UUID, splitId: UUID, ratio: Double) {
        tabLayoutAtom.resizePane(tabId: tabId, splitId: splitId, ratio: ratio)
    }

    func equalizePanes(tabId: UUID) {
        tabLayoutAtom.equalizePanes(tabId: tabId)
    }

    func setActivePane(_ paneId: UUID?, inTab tabId: UUID) {
        tabLayoutAtom.setActivePane(paneId, inTab: tabId)
    }

    @discardableResult
    func createArrangement(name: String, paneIds: Set<UUID>, inTab tabId: UUID) -> UUID? {
        tabLayoutAtom.createArrangement(name: name, paneIds: paneIds, inTab: tabId)
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
    func addDrawerPane(to parentPaneId: UUID) -> Pane? {
        let fallbackCWD = pane(parentPaneId)?.worktreeId.flatMap(worktree)?.path
        return paneAtom.addDrawerPane(to: parentPaneId, parentFallbackCWD: fallbackCWD)
    }

    @discardableResult
    func insertDrawerPane(
        in parentPaneId: UUID,
        at targetDrawerPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) -> Pane? {
        let fallbackCWD = pane(parentPaneId)?.worktreeId.flatMap(worktree)?.path
        return paneAtom.insertDrawerPane(
            in: parentPaneId,
            at: targetDrawerPaneId,
            direction: direction,
            position: position,
            parentFallbackCWD: fallbackCWD
        )
    }

    func moveDrawerPane(
        _ drawerPaneId: UUID,
        in parentPaneId: UUID,
        at targetDrawerPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        paneAtom.moveDrawerPane(
            drawerPaneId,
            in: parentPaneId,
            at: targetDrawerPaneId,
            direction: direction,
            position: position
        )
    }

    func removeDrawerPane(_ drawerPaneId: UUID, from parentPaneId: UUID) {
        paneAtom.removeDrawerPane(drawerPaneId, from: parentPaneId)
    }

    func toggleDrawer(for paneId: UUID) {
        paneAtom.toggleDrawer(for: paneId)
    }

    func collapseAllDrawers() {
        paneAtom.collapseAllDrawers()
    }

    func setActiveDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) {
        paneAtom.setActiveDrawerPane(drawerPaneId, in: parentPaneId)
    }

    func resizeDrawerPane(parentPaneId: UUID, splitId: UUID, ratio: Double) {
        paneAtom.resizeDrawerPane(parentPaneId: parentPaneId, splitId: splitId, ratio: ratio)
    }

    func equalizeDrawerPanes(parentPaneId: UUID) {
        paneAtom.equalizeDrawerPanes(parentPaneId: parentPaneId)
    }

    @discardableResult
    func minimizeDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) -> Bool {
        paneAtom.minimizeDrawerPane(drawerPaneId, in: parentPaneId)
    }

    func expandDrawerPane(_ drawerPaneId: UUID, in parentPaneId: UUID) {
        paneAtom.expandDrawerPane(drawerPaneId, in: parentPaneId)
    }

    func toggleZoom(paneId: UUID, inTab tabId: UUID) {
        tabLayoutAtom.toggleZoom(paneId: paneId, inTab: tabId)
    }

    @discardableResult
    func minimizePane(_ paneId: UUID, inTab tabId: UUID) -> Bool {
        tabLayoutAtom.minimizePane(paneId, inTab: tabId)
    }

    func expandPane(_ paneId: UUID, inTab tabId: UUID) {
        tabLayoutAtom.expandPane(paneId, inTab: tabId)
    }

    func resizePaneByDelta(tabId: UUID, paneId: UUID, direction: SplitResizeDirection, amount: UInt16) {
        tabLayoutAtom.resizePaneByDelta(tabId: tabId, paneId: paneId, direction: direction, amount: amount)
    }

    func breakUpTab(_ tabId: UUID) -> [Tab] {
        tabLayoutAtom.breakUpTab(tabId)
    }

    func extractPane(_ paneId: UUID, fromTab tabId: UUID) -> Tab? {
        tabLayoutAtom.extractPane(paneId, fromTab: tabId)
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
            position: position
        )
    }

    @discardableResult
    func addRepo(at path: URL) -> Repo {
        repositoryTopologyAtom.addRepo(at: path)
    }

    func removeRepo(_ repoId: UUID) {
        repositoryTopologyAtom.removeRepo(repoId)
    }

    func markRepoUnavailable(_ repoId: UUID) {
        repositoryTopologyAtom.markRepoUnavailable(repoId)
    }

    func markRepoAvailable(_ repoId: UUID) {
        repositoryTopologyAtom.markRepoAvailable(repoId)
    }

    func isRepoUnavailable(_ repoId: UUID) -> Bool {
        repositoryTopologyAtom.isRepoUnavailable(repoId)
    }

    @discardableResult
    func addWatchedPath(_ path: URL) -> WatchedPath? {
        repositoryTopologyAtom.addWatchedPath(path)
    }

    func removeWatchedPath(_ id: UUID) {
        repositoryTopologyAtom.removeWatchedPath(id)
    }

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
    func reassociateRepo(_ repoId: UUID, to newPath: URL, discoveredWorktrees: [Worktree]) -> Bool {
        mutationCoordinator.reassociateRepo(repoId, to: newPath, discoveredWorktrees: discoveredWorktrees)
    }

    func reconcileDiscoveredWorktrees(_ repoId: UUID, worktrees: [Worktree]) {
        repositoryTopologyAtom.reconcileDiscoveredWorktrees(repoId, worktrees: worktrees)
    }

    func setSidebarWidth(_ sidebarWidth: CGFloat) {
        metadataAtom.setSidebarWidth(sidebarWidth)
    }

    func setWindowFrame(_ windowFrame: CGRect?) {
        metadataAtom.setWindowFrame(windowFrame)
    }

    func snapshotForClose(tabId: UUID) -> TabCloseSnapshot? {
        mutationCoordinator.snapshotForClose(tabId: tabId)
    }

    func snapshotForPaneClose(paneId: UUID, inTab tabId: UUID) -> PaneCloseSnapshot? {
        mutationCoordinator.snapshotForPaneClose(paneId: paneId, inTab: tabId)
    }

    func restoreFromSnapshot(_ snapshot: TabCloseSnapshot) {
        mutationCoordinator.restoreFromSnapshot(snapshot)
    }

    func restoreFromPaneSnapshot(_ snapshot: PaneCloseSnapshot) {
        mutationCoordinator.restoreFromPaneSnapshot(snapshot)
    }

    // MARK: - Persistence

    func restore() {
        _ = persistor.ensureDirectory()
        switch persistor.load() {
        case .loaded(let state):
            isRestoringState = true
            WorkspacePersistenceTransformer.hydrate(
                state,
                metadataAtom: metadataAtom,
                repositoryTopologyAtom: repositoryTopologyAtom,
                workspacePaneAtom: paneAtom,
                workspaceTabLayoutAtom: tabLayoutAtom
            )
            isRestoringState = false
            workspaceStoreLogger.info(
                "Restored workspace '\(state.name)' with \(state.panes.count) pane(s), \(state.tabs.count) tab(s)"
            )
        case .corrupt(let error):
            workspaceStoreLogger.error(
                "Workspace file exists but failed to decode — starting with empty state: \(error)"
            )
        case .missing:
            workspaceStoreLogger.info("No workspace files found — first launch")
        }
    }

    func beginScan(_ path: URL) {
        scanningPath = path
    }

    func endScan() {
        scanningPath = nil
    }

    @discardableResult
    func flush() -> Bool {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        return persistNow()
    }

    var prePersistHook: (() -> Void)?

    private func observePersistedState() {
        guard !isObservingPersistedState else { return }
        isObservingPersistedState = true
        withObservationTracking {
            _ = metadataAtom.workspaceId
            _ = metadataAtom.workspaceName
            _ = metadataAtom.createdAt
            _ = metadataAtom.sidebarWidth
            _ = metadataAtom.windowFrame
            _ = repositoryTopologyAtom.repos
            _ = repositoryTopologyAtom.watchedPaths
            _ = repositoryTopologyAtom.unavailableRepoIds
            _ = paneAtom.panes
            _ = tabLayoutAtom.tabs
            _ = tabLayoutAtom.activeTabId
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let shouldIgnore = self.isRestoringState
                self.isObservingPersistedState = false
                self.observePersistedState()
                guard !shouldIgnore else { return }
                self.markDirtyObserved()
            }
        }
    }

    private func markDirtyObserved() {
        if !isDirty {
            isDirty = true
            ProcessInfo.processInfo.disableSuddenTermination()
        }

        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: self.persistDebounceDuration)
            guard !Task.isCancelled else { return }
            _ = self.persistNow()
        }
    }

    @discardableResult
    private func persistNow() -> Bool {
        prePersistHook?()
        guard persistor.ensureDirectory() else {
            workspaceStoreLogger.error(
                "Failed to persist workspace because the workspaces directory could not be created"
            )
            return false
        }

        let persistedAt = Date()
        let state = WorkspacePersistenceTransformer.makePersistableState(
            metadataAtom: metadataAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: paneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            persistedAt: persistedAt
        )

        do {
            try persistor.save(state)
            if isDirty {
                isDirty = false
                ProcessInfo.processInfo.enableSuddenTermination()
            }
            return true
        } catch {
            workspaceStoreLogger.error("Failed to persist workspace: \(error.localizedDescription)")
            return false
        }
    }
}
