import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

extension AgentStudioTraceIdentitySnapshot {
    @MainActor
    static func from(
        repos: [Repo],
        panes: [Pane],
        worktreeEnrichments: [UUID: WorktreeEnrichment]
    ) -> Self {
        var worktreeIdentitiesByWorktreeId: [UUID: AgentStudioTraceWorktreeIdentity] = [:]
        for repo in repos {
            for worktree in repo.worktrees {
                worktreeIdentitiesByWorktreeId[worktree.id] = AgentStudioTraceWorktreeIdentity(
                    repoHash: repo.stableKey,
                    worktreeHash: worktree.stableKey,
                    branch: nonEmptyBranch(worktreeEnrichments[worktree.id]?.branch)
                )
            }
        }

        let paneWorktreeIdsByPaneId = Dictionary(
            uniqueKeysWithValues: panes.compactMap { pane -> (UUID, UUID)? in
                guard let worktreeId = pane.worktreeId else { return nil }
                return (pane.id, worktreeId)
            }
        )

        return Self(
            worktreeIdentitiesByWorktreeId: worktreeIdentitiesByWorktreeId,
            paneWorktreeIdsByPaneId: paneWorktreeIdsByPaneId
        )
    }

    private static func nonEmptyBranch(_ branch: String?) -> String? {
        let trimmedBranch = branch?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedBranch, !trimmedBranch.isEmpty else { return nil }
        return trimmedBranch
    }
}
