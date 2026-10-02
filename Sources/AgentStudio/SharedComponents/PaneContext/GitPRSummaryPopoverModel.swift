import Foundation

package struct GitPRSummaryPopoverModel: Sendable, Equatable {
    package let state: PullRequestSummaryStateModel
    package let members: [PullRequestMemberModel]

    package init(state: PullRequestSummaryStateModel, members: [PullRequestMemberModel]) {
        self.state = state
        self.members = members
    }

}

package enum PullRequestSummaryStateModel: Sendable, Equatable {
    case needsAttention(count: Int)
    case running
    case allGood
    case noInfo
}
package enum PullRequestMemberModel: Sendable, Equatable {
    case noPullRequest(worktreeId: UUID)
    case unknown(worktreeId: UUID)
    case pullRequest(worktreeId: UUID, number: Int, checks: PullRequestChecksModel, review: PullRequestReviewModel)
}
package enum PullRequestChecksModel: Sendable, Equatable {
    case passed
    case running
    case failed
    case unknown
}
package enum PullRequestReviewModel: Sendable, Equatable {
    case approved
    case changesRequested
    case reviewRequired
    case unknown
}
