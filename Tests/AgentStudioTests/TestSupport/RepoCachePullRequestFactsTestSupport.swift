import AgentStudioCore
import Foundation

@MainActor
extension RepoCacheAtom {
    package func pullRequestFactsForTest(worktreeId: UUID) -> PullRequestFacts? {
        guard
            let enrichment = worktreeEnrichment(for: worktreeId),
            let key = RepoBranchKey(repoId: enrichment.repoId, branch: enrichment.branch)
        else {
            return nil
        }
        return pullRequestFacts(for: key)
    }

    package func setPullRequestFactsForTest(
        openCount: Int,
        exactOpenURL: URL? = nil,
        worktreeId: UUID
    ) {
        guard let enrichment = worktreeEnrichment(for: worktreeId) else {
            preconditionFailure("Worktree enrichment must establish repository and branch identity first")
        }
        applyPullRequestFacts(
            repoId: enrichment.repoId,
            factsByBranch: [
                enrichment.branch: PullRequestFacts(
                    openCount: openCount,
                    exactOpenURL: exactOpenURL
                )
            ]
        )
    }
}
