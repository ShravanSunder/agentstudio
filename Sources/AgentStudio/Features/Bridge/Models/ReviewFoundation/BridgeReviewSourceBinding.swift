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

/// The Files input of one Bridge controller: the receiver's known member
/// worktrees in collection order plus its opened documents, published under
/// one collection token that stays stable for the receiver. App derives it from
/// the receiver's navigation record; membership changes update the mounted
/// collection in place.
package struct BridgeFilesSourceBinding: Hashable, Sendable {
    package let collectionToken: String
    package var members: [Worktree]
    package var openedDocuments: [BridgeDocumentLocation]

    package init(collectionToken: String, members: [Worktree], openedDocuments: [BridgeDocumentLocation]) {
        self.collectionToken = collectionToken
        self.members = members
        self.openedDocuments = openedDocuments
    }

    /// The collection token of a receiver: stable across companion
    /// replacement, restart and membership changes.
    package static func collectionToken(forReceiverPaneId paneId: UUID) -> String {
        "receiver-\(paneId.uuidString.lowercased())"
    }
}

/// The source inputs a Bridge controller is constructed from. Review and Files
/// are independent inputs; neither is derived from the pane payload or its
/// runtime metadata.
package struct BridgePaneSourceConfiguration: Hashable, Sendable {
    package var review: BridgeReviewSourceBinding?
    package var files: BridgeFilesSourceBinding?

    package init(review: BridgeReviewSourceBinding?, files: BridgeFilesSourceBinding?) {
        self.review = review
        self.files = files
    }

    package static let unavailable = Self(review: nil, files: nil)
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
