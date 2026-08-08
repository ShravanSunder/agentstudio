import Foundation

@MainActor
package struct WorkspacePaneDerived {
    let graphAtom: WorkspacePaneGraphAtom
    let drawerCursorAtom: WorkspaceDrawerCursorAtom
    let repositoryTopologyAtom: RepositoryTopologyAtom?
    let repoEnrichmentCacheAtom: RepoEnrichmentCacheAtom?

    init(
        graphAtom: WorkspacePaneGraphAtom,
        drawerCursorAtom: WorkspaceDrawerCursorAtom,
        repositoryTopologyAtom: RepositoryTopologyAtom? = nil,
        repoEnrichmentCacheAtom: RepoEnrichmentCacheAtom? = nil
    ) {
        self.graphAtom = graphAtom
        self.drawerCursorAtom = drawerCursorAtom
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.repoEnrichmentCacheAtom = repoEnrichmentCacheAtom
    }

    func paneSnapshot() -> [UUID: Pane] {
        Dictionary(
            uniqueKeysWithValues: graphAtom.paneStateSnapshot().map { paneId, state in
                (paneId, pane(from: state))
            }
        )
    }

    func pane(_ id: UUID) -> Pane? {
        guard let state = graphAtom.paneState(id) else { return nil }
        return pane(from: state)
    }

    func panes(for worktreeId: UUID) -> [Pane] {
        paneSnapshot().values.filter { $0.worktreeId == worktreeId }
    }

    private func pane(from state: PaneGraphState) -> Pane {
        let drawerId = state.drawer?.drawerId
        var pane = state.pane(
            isDrawerExpanded: drawerId.map { drawerCursorAtom.isExpanded(drawerId: $0) } ?? false
        )
        pane.metadata.updateFacets(displayFacets(for: pane.metadata.facets))
        return pane
    }

    private func displayFacets(for durableFacets: PaneContextFacets) -> PaneContextFacets {
        let resolvedContext = resolvedWorkspaceContext(for: durableFacets)
        let repoEnrichment = resolvedContext.flatMap {
            repoEnrichmentCacheAtom?.repoEnrichment(for: $0.repo.id)
        }
        return Self.displayFacets(
            for: durableFacets,
            resolvedContext: resolvedContext,
            repoEnrichment: repoEnrichment
        )
    }

    private func resolvedWorkspaceContext(
        for facets: PaneContextFacets
    ) -> (repo: Repo, worktree: Worktree)? {
        guard let repositoryTopologyAtom else { return nil }

        return repositoryTopologyAtom.repoAndWorktree(containing: facets.cwd)
    }

    nonisolated package static func displayFacets(
        for durableFacets: PaneContextFacets,
        resolvedContext: (repo: Repo, worktree: Worktree)?,
        repoEnrichment: RepoEnrichment?
    ) -> PaneContextFacets {
        var facets = PaneContextFacets(cwd: durableFacets.cwd)
        guard let resolvedContext else { return facets }

        facets.repoId = resolvedContext.repo.id
        facets.worktreeId = resolvedContext.worktree.id
        facets.repoName = resolvedContext.repo.name
        facets.worktreeName = resolvedContext.worktree.name
        let parentName = resolvedContext.repo.repoPath.deletingLastPathComponent().lastPathComponent
        facets.parentFolder = parentName.isEmpty ? nil : parentName

        if let repoEnrichment {
            facets.organizationName = repoEnrichment.organizationName
            facets.origin = repoEnrichment.origin
            facets.upstream = repoEnrichment.upstream
        }
        return facets
    }
}
