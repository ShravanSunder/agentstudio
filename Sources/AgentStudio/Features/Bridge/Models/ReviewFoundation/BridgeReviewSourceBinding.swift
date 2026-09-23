import AgentStudioCore
import Foundation

/// The immutable Review input of one Bridge controller: a known member
/// worktree and its retained comparison, derived by App from the receiver's
/// navigation record. `nil` comparison means first-time designation is still
/// pending. Changing the member replaces the controller; comparison commits go
/// back to the navigation record through `BridgeReviewComparisonCommit`.
package struct BridgeReviewSourceBinding: Hashable, Sendable {
    package let worktreeId: UUID
    package let worktreeRootPath: String
    package var comparison: WorkspaceBaseline?

    package init(worktreeId: UUID, worktreeRootPath: String, comparison: WorkspaceBaseline?) {
        self.worktreeId = worktreeId
        self.worktreeRootPath = worktreeRootPath
        self.comparison = comparison
    }
}

/// The source inputs a Bridge controller is constructed from. Review and Files
/// are independent inputs; neither is derived from the pane payload.
package struct BridgePaneSourceConfiguration: Hashable, Sendable {
    package var review: BridgeReviewSourceBinding?

    package init(review: BridgeReviewSourceBinding?) {
        self.review = review
    }

    package static let reviewUnavailable = Self(review: nil)
}

/// Outcome of committing a comparison choice to the receiver's navigation
/// record for the controller's Review member.
package enum BridgeReviewComparisonCommitResult: Equatable, Sendable {
    case applied(WorkspaceBaseline)
    case unchanged(WorkspaceBaseline)
    /// The receiver or its Review member no longer exists; the controller
    /// must stop presenting this comparison lineage.
    case receiverUnavailable
}

package typealias BridgeReviewComparisonCommit =
    @MainActor @Sendable (WorkspaceReviewContributionTarget) -> BridgeReviewComparisonCommitResult
