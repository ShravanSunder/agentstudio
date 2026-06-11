import Foundation
import Observation
import os.log

private let workspacePaneLogger = Logger(subsystem: "com.agentstudio", category: "WorkspacePaneAtom")

enum PaneCWDContextUpdateResult: Equatable {
    case applied
    case unchanged
    case paneMissing
}

@MainActor
@Observable
final class WorkspacePaneAtom {
    let graphAtom: WorkspacePaneGraphAtom
    let drawerCursorAtom: WorkspaceDrawerCursorAtom
    private let repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom?
    private let repoEnrichmentCacheAtom: RepoEnrichmentCacheAtom?

    init(
        graphAtom: WorkspacePaneGraphAtom = WorkspacePaneGraphAtom(),
        drawerCursorAtom: WorkspaceDrawerCursorAtom = WorkspaceDrawerCursorAtom(),
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom? = nil,
        repoEnrichmentCacheAtom: RepoEnrichmentCacheAtom? = nil
    ) {
        self.graphAtom = graphAtom
        self.drawerCursorAtom = drawerCursorAtom
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.repoEnrichmentCacheAtom = repoEnrichmentCacheAtom
    }

    var panes: [UUID: Pane] {
        derived.panes
    }

    /// Legacy JSON persistence projection. This composes the graph owner with
    /// the drawer cursor so current workspace.state.json saves retain drawer
    /// expansion, while excluding topology/cache display facets.
    var legacyPersistablePanes: [UUID: Pane] {
        liveSQLitePanes
    }

    /// Live SQLite projection of the pane graph plus local drawer cursor facts.
    /// This keeps derived topology/cache display facets out of core rows while
    /// preserving the current atom-owned pane graph.
    var liveSQLitePanes: [UUID: Pane] {
        Dictionary(
            uniqueKeysWithValues: graphAtom.paneStates.map { paneId, state in
                let drawerId = state.drawer?.drawerId
                return (
                    paneId,
                    state.pane(
                        isDrawerExpanded: drawerId.map { drawerCursorAtom.isExpanded(drawerId: $0) } ?? false
                    )
                )
            }
        )
    }

    private var derived: WorkspacePaneDerived {
        WorkspacePaneDerived(
            graphAtom: graphAtom,
            drawerCursorAtom: drawerCursorAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            repoEnrichmentCacheAtom: repoEnrichmentCacheAtom
        )
    }

    func hydrate(persistedPanes: [Pane], validWorktreeIds: Set<UUID>) {
        graphAtom.hydrate(persistedPanes: persistedPanes, validWorktreeIds: validWorktreeIds)
        drawerCursorAtom.hydrate(persistedPanes: persistedPanes, validDrawerIds: graphAtom.drawerIds)
    }

    func pane(_ id: UUID) -> Pane? {
        guard let pane = derived.pane(id) else {
            workspacePaneLogger.warning("pane(\(id)): not found in store")
            return nil
        }
        return pane
    }

    func panes(for worktreeId: UUID) -> [Pane] {
        panes.values.filter { $0.worktreeId == worktreeId }
    }

    func addPane(_ pane: Pane) {
        graphAtom.addPane(pane)
        drawerCursorAtom.prune(validDrawerIds: graphAtom.drawerIds)
    }

    func paneCount(for worktreeId: UUID) -> Int {
        panes.values.filter { $0.worktreeId == worktreeId }.count
    }

    func isWorktreeActive(_ worktreeId: UUID) -> Bool {
        panes.values.contains { $0.worktreeId == worktreeId && $0.residency == .active }
    }

    func orphanedPanes(excluding layoutPaneIds: Set<UUID>) -> [Pane] {
        panes.values.filter {
            guard !layoutPaneIds.contains($0.id) else { return false }
            return $0.residency == .backgrounded || $0.residency.isOrphaned
        }
    }

    @discardableResult
    func createPane(
        source: TerminalSource,
        title: String = "Terminal",
        provider: SessionProvider = .zmx,
        lifetime: SessionLifetime = .persistent,
        residency: SessionResidency = .active,
        facets: PaneContextFacets = .empty
    ) -> Pane {
        let state = graphAtom.createPane(
            source: source,
            title: title,
            provider: provider,
            lifetime: lifetime,
            residency: residency,
            facets: facets
        )
        if provider == .zmx, let sessionId = zmxSessionId(for: source, paneId: state.id) {
            graphAtom.setTerminalZmxSessionId(state.id, sessionId: sessionId)
        }
        return pane(state.id)!
    }

    @discardableResult
    func createPane(
        content: PaneContent,
        metadata: PaneMetadata,
        residency: SessionResidency = .active
    ) -> Pane {
        let state = graphAtom.createPane(content: content, metadata: metadata, residency: residency)
        return pane(state.id)!
    }

    @discardableResult
    func insertRestoredPane(_ pane: Pane) -> Bool {
        let didInsert = graphAtom.insertRestoredPane(pane)
        if didInsert {
            drawerCursorAtom.prune(validDrawerIds: graphAtom.drawerIds)
        }
        return didInsert
    }

    @discardableResult
    func deletePaneAndOwnedDrawerChildren(_ paneId: UUID) -> Bool {
        let didDelete = graphAtom.deletePaneAndOwnedDrawerChildren(paneId)
        if didDelete {
            drawerCursorAtom.prune(validDrawerIds: graphAtom.drawerIds)
        }
        return didDelete
    }

    func updatePaneTitle(_ paneId: UUID, title: String) {
        graphAtom.updatePaneTitle(paneId, title: title)
    }

    func renamePane(_ paneId: UUID, title: String) {
        updatePaneTitle(paneId, title: title)
    }

    func updatePaneCWD(_ paneId: UUID, cwd: URL?) {
        graphAtom.updatePaneCWD(paneId, cwd: cwd)
    }

    func updatePaneNote(_ paneId: UUID, note: String?) {
        graphAtom.updatePaneNote(paneId, note: note)
    }

    func updatePaneCWDAndResolvedContext(
        _ paneId: UUID,
        cwd: URL?,
        resolvedContext: (repo: Repo, worktree: Worktree)?
    ) -> PaneCWDContextUpdateResult {
        graphAtom.updatePaneCWDAndResolvedContext(paneId, cwd: cwd, resolvedContext: resolvedContext)
    }

    func updatePaneWebviewState(_ paneId: UUID, state: WebviewState) {
        graphAtom.updatePaneWebviewState(paneId, state: state)
    }

    func syncPaneWebviewState(_ paneId: UUID, state: WebviewState) {
        graphAtom.syncPaneWebviewState(paneId, state: state)
    }

    func setResidency(_ residency: SessionResidency, for paneId: UUID) {
        graphAtom.setResidency(residency, for: paneId)
    }

    func purgeOrphanedPane(_ paneId: UUID) {
        graphAtom.purgeOrphanedPane(paneId)
        drawerCursorAtom.prune(validDrawerIds: graphAtom.drawerIds)
    }

    @discardableResult
    func addDrawerPane(to parentPaneId: UUID, parentFallbackCWD: URL?) -> Pane? {
        guard let metadata = inheritedDrawerMetadata(from: parentPaneId, parentFallbackCWD: parentFallbackCWD) else {
            workspacePaneLogger.warning("addDrawerPane: parent pane \(parentPaneId) not found")
            return nil
        }
        return addDrawerPane(
            to: parentPaneId,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: metadata
        )
    }

    @discardableResult
    func addDrawerPane(
        to parentPaneId: UUID,
        content: PaneContent,
        metadata: PaneMetadata
    ) -> Pane? {
        guard let drawerPane = graphAtom.addDrawerPane(to: parentPaneId, content: content, metadata: metadata) else {
            return nil
        }
        anchorDrawerZmxSessionIfNeeded(parentPaneId: parentPaneId, drawerPaneId: drawerPane.id)
        if let drawerId = graphAtom.paneState(parentPaneId)?.drawer?.drawerId {
            drawerCursorAtom.expandDrawer(drawerId: drawerId)
        }
        return pane(drawerPane.id)
    }

    @discardableResult
    func insertDrawerPane(
        in parentPaneId: UUID,
        at targetDrawerPaneId: UUID,
        direction _: SplitNewDirection,
        sizingMode _: DropSizingMode,
        parentFallbackCWD: URL?
    ) -> Pane? {
        guard let metadata = inheritedDrawerMetadata(from: parentPaneId, parentFallbackCWD: parentFallbackCWD) else {
            workspacePaneLogger.warning("insertDrawerPane: parent pane \(parentPaneId) not found")
            return nil
        }
        return insertDrawerPane(
            in: parentPaneId,
            at: targetDrawerPaneId,
            direction: .right,
            sizingMode: .halveTarget,
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
            metadata: metadata
        )
    }

    @discardableResult
    func insertDrawerPane(
        in parentPaneId: UUID,
        at targetDrawerPaneId: UUID,
        direction _: SplitNewDirection,
        sizingMode _: DropSizingMode,
        content: PaneContent,
        metadata: PaneMetadata
    ) -> Pane? {
        guard
            let drawerPane = graphAtom.insertDrawerPane(
                in: parentPaneId,
                at: targetDrawerPaneId,
                content: content,
                metadata: metadata
            )
        else { return nil }
        anchorDrawerZmxSessionIfNeeded(parentPaneId: parentPaneId, drawerPaneId: drawerPane.id)
        if let drawerId = graphAtom.paneState(parentPaneId)?.drawer?.drawerId {
            drawerCursorAtom.expandDrawer(drawerId: drawerId)
        }
        return pane(drawerPane.id)
    }

    func removeDrawerPane(_ drawerPaneId: UUID, from parentPaneId: UUID) {
        graphAtom.removeDrawerPane(drawerPaneId, from: parentPaneId)
        drawerCursorAtom.prune(validDrawerIds: graphAtom.drawerIds)
    }

    @discardableResult
    func detachDrawerPane(_ drawerPaneId: UUID, from parentPaneId: UUID) -> Pane? {
        guard let detached = graphAtom.detachDrawerPane(drawerPaneId, from: parentPaneId) else { return nil }
        drawerCursorAtom.prune(validDrawerIds: graphAtom.drawerIds)
        return pane(detached.id)
    }

    func toggleDrawer(for paneId: UUID) {
        guard let drawerId = graphAtom.paneState(paneId)?.drawer?.drawerId else {
            workspacePaneLogger.warning("toggleDrawer: pane \(paneId) has no drawer")
            return
        }
        drawerCursorAtom.toggleDrawer(drawerId: drawerId)
    }

    func collapseAllDrawers() {
        drawerCursorAtom.collapseAllDrawers()
    }

    @discardableResult
    func orphanPanes(forUnavailableWorktreePathsById unavailablePathByWorktreeId: [UUID: String]) -> [UUID] {
        graphAtom.orphanPanes(forUnavailableWorktreePathsById: unavailablePathByWorktreeId)
    }

    @discardableResult
    func orphanPanesForWorktree(_ worktreeId: UUID, path: String) -> [UUID] {
        graphAtom.orphanPanesForWorktree(worktreeId, path: path)
    }

    @discardableResult
    func restoreOrphanedPaneResidency(
        forWorktreeIds worktreeIds: Set<UUID>,
        activeLayoutPaneIds: Set<UUID>
    ) -> Bool {
        graphAtom.restoreOrphanedPaneResidency(forWorktreeIds: worktreeIds, activeLayoutPaneIds: activeLayoutPaneIds)
    }

    func snapshotPanes(with ids: [UUID]) -> [Pane] {
        ids.compactMap { pane($0) }
    }

    @discardableResult
    func restoreDrawerPane(_ drawerPane: Pane, to parentPaneId: UUID) -> Bool {
        let didRestore = graphAtom.restoreDrawerPane(drawerPane, to: parentPaneId)
        if didRestore, let drawerId = graphAtom.paneState(parentPaneId)?.drawer?.drawerId {
            drawerCursorAtom.expandDrawer(drawerId: drawerId)
        }
        return didRestore
    }

    private func inheritedDrawerMetadata(from parentPaneId: UUID, parentFallbackCWD: URL?) -> PaneMetadata? {
        guard let parentPane = pane(parentPaneId) else { return nil }

        let inheritedCWD =
            parentPane.metadata.facets.cwd
            ?? parentPane.metadata.launchDirectory
            ?? parentFallbackCWD

        let inheritedSource: PaneMetadata.PaneMetadataSource
        if let worktreeId = parentPane.worktreeId, let repoId = parentPane.repoId, let inheritedCWD {
            inheritedSource = .worktree(
                worktreeId: worktreeId,
                repoId: repoId,
                launchDirectory: inheritedCWD
            )
        } else {
            inheritedSource = .floating(launchDirectory: inheritedCWD, title: nil)
        }

        let inheritedFacets = parentPane.metadata.facets.fillingNilFields(
            from: PaneContextFacets(cwd: inheritedCWD)
        )

        return PaneMetadata(
            source: inheritedSource,
            title: "Drawer",
            facets: inheritedFacets
        )
    }

    private func zmxSessionId(for source: TerminalSource, paneId: UUID) -> String? {
        switch source {
        case .worktree(let worktreeId, let repoId, _):
            guard
                let repositoryTopologyAtom,
                let repo = repositoryTopologyAtom.repo(repoId),
                let worktree = repositoryTopologyAtom.worktree(worktreeId)
            else { return nil }
            return ZmxBackend.sessionId(
                repoStableKey: repo.stableKey,
                worktreeStableKey: worktree.stableKey,
                paneId: paneId
            )
        case .floating(let launchDirectory, _):
            return ZmxBackend.floatingSessionId(
                launchDirectory: launchDirectory ?? FileManager.default.homeDirectoryForCurrentUser,
                paneId: paneId
            )
        }
    }

    private func anchorDrawerZmxSessionIfNeeded(parentPaneId: UUID, drawerPaneId: UUID) {
        let sessionId = ZmxBackend.drawerSessionId(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)
        graphAtom.setTerminalZmxSessionId(drawerPaneId, sessionId: sessionId)
    }
}
