import Foundation

/// Whether a source worktree's location can host a Worktree Fork. The Git SDK owns the
/// rules; the app only carries its answer and the user-facing reason copy.
package enum WorktreeForkEligibility: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

/// Read-only fork eligibility for a source worktree and the directory its new sibling
/// would land in: host and volume facts only, never a tree walk. A later fork
/// rejection stays authoritative even after `.available`.
package protocol WorktreeForkEligibilityChecking: Sendable {
    func forkEligibility(sourceWorktreePath: URL, destinationDirectory: URL) async -> WorktreeForkEligibility
}
