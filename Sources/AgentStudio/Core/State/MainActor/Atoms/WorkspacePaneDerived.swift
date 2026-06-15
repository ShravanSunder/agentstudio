import Foundation

@MainActor
struct WorkspacePaneDerived {
    let graphAtom: WorkspacePaneGraphAtom
    let drawerCursorAtom: WorkspaceDrawerCursorAtom
    let repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom?
    let repoEnrichmentCacheAtom: RepoEnrichmentCacheAtom?

    init(
        graphAtom: WorkspacePaneGraphAtom,
        drawerCursorAtom: WorkspaceDrawerCursorAtom,
        repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom? = nil,
        repoEnrichmentCacheAtom: RepoEnrichmentCacheAtom? = nil
    ) {
        self.graphAtom = graphAtom
        self.drawerCursorAtom = drawerCursorAtom
        self.repositoryTopologyAtom = repositoryTopologyAtom
        self.repoEnrichmentCacheAtom = repoEnrichmentCacheAtom
    }

    var panes: [UUID: Pane] {
        Dictionary(
            uniqueKeysWithValues: graphAtom.paneStates.map { paneId, state in
                (paneId, pane(from: state))
            }
        )
    }

    func pane(_ id: UUID) -> Pane? {
        guard let state = graphAtom.paneState(id) else { return nil }
        return pane(from: state)
    }

    func panes(for worktreeId: UUID) -> [Pane] {
        panes.values.filter { $0.worktreeId == worktreeId }
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
        var facets = PaneGraphFacets(contextFacets: durableFacets).paneContextFacets
        guard let resolvedContext = resolvedWorkspaceContext(for: facets) else {
            return facets
        }

        facets.repoId = resolvedContext.repo.id
        facets.worktreeId = resolvedContext.worktree.id
        facets.repoName = resolvedContext.repo.name
        facets.worktreeName = resolvedContext.worktree.name
        facets.parentFolder = parentFolderName(for: resolvedContext.repo.repoPath)

        if let enrichment = repoEnrichmentCacheAtom?.repoEnrichment(for: resolvedContext.repo.id) {
            facets.organizationName = enrichment.organizationName
            facets.origin = enrichment.origin
            facets.upstream = enrichment.upstream
        }

        return facets
    }

    private func resolvedWorkspaceContext(
        for facets: PaneContextFacets
    ) -> (repo: Repo, worktree: Worktree)? {
        guard let repositoryTopologyAtom else { return nil }

        if let repoId = facets.repoId,
            let worktreeId = facets.worktreeId,
            let repo = repositoryTopologyAtom.repo(repoId),
            let worktree = repositoryTopologyAtom.worktree(worktreeId)
        {
            return (repo, worktree)
        }

        return repositoryTopologyAtom.repoAndWorktree(containing: facets.cwd)
    }

    private func parentFolderName(for repoPath: URL) -> String? {
        let parentName = repoPath.deletingLastPathComponent().lastPathComponent
        return parentName.isEmpty ? nil : parentName
    }
}
