import AgentStudioCore
import Foundation

/// Resolves drawer Git presentation from the existing keyed cache facts. This introduces no source
/// observation, scheduling, or refresh path; `RepoCacheAtom` remains the publication owner.
@MainActor
enum PaneGitStatusToolbarResolver {
    static func resolve(
        paneId: UUID,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom
    ) -> PaneSurfaceGitStatusPresentation? {
        guard
            let pane = store.paneAtom.pane(paneId),
            let association = store.repositoryTopologyAtom.validatedAssociation(
                repoId: pane.repoId,
                worktreeId: pane.worktreeId
            ),
            let enrichment = repoCache.worktreeEnrichment(for: association.worktree.id)
        else { return nil }

        let branchStatus = GitBranchStatus.status(
            enrichment: enrichment,
            pullRequestFacts: nil
        )
        return PaneSurfaceGitStatusPresentation.resolve(branchStatus: branchStatus)
    }
}
