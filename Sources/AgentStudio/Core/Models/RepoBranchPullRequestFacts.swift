import Foundation

package struct RepoBranchKey: Hashable, Sendable {
    package let repoId: UUID
    package let branch: String

    package init?(repoId: UUID, branch: String) {
        guard !branch.isEmpty else { return nil }
        self.repoId = repoId
        self.branch = branch
    }
}

package enum PullRequestCheckStatus: Equatable, Sendable {
    case passed
    case running
    case failed
    case unknown
}

package enum PullRequestReviewStatus: Equatable, Sendable {
    case approved
    case changesRequested
    case reviewRequired
    case unknown
}

package enum PullRequestMergeability: Equatable, Sendable {
    case mergeable
    case conflicting
    case unknown
}

package enum PullRequestMergeState: Equatable, Sendable {
    case clean
    case blocked
    case behind
    case dirty
    case draft
    case hasHooks
    case unstable
    case unknown
}

package struct PullRequestReadiness: Equatable, Sendable {
    package let isDraft: Bool
    package let checkStatus: PullRequestCheckStatus
    package let reviewStatus: PullRequestReviewStatus
    package let mergeability: PullRequestMergeability
    package let mergeState: PullRequestMergeState

    package init(
        isDraft: Bool,
        checkStatus: PullRequestCheckStatus,
        reviewStatus: PullRequestReviewStatus,
        mergeability: PullRequestMergeability,
        mergeState: PullRequestMergeState
    ) {
        self.isDraft = isDraft
        self.checkStatus = checkStatus
        self.reviewStatus = reviewStatus
        self.mergeability = mergeability
        self.mergeState = mergeState
    }
}

package struct PullRequestFacts: Equatable, Sendable {
    package let openCount: Int
    package let exactOpenURL: URL?
    package let exactReadiness: PullRequestReadiness?

    package init(
        openCount: Int,
        exactOpenURL: URL?,
        exactReadiness: PullRequestReadiness? = nil
    ) {
        precondition(openCount >= 0, "Pull request count cannot be negative")
        precondition(
            exactReadiness == nil || exactOpenURL != nil,
            "Exact pull request readiness requires an exact URL"
        )
        self.openCount = openCount
        self.exactOpenURL = exactOpenURL
        self.exactReadiness = exactReadiness
    }
}
