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

package struct PullRequestFacts: Equatable, Sendable {
    package let openCount: Int
    package let exactOpenURL: URL?

    package init(openCount: Int, exactOpenURL: URL?) {
        precondition(openCount >= 0, "Pull request count cannot be negative")
        self.openCount = openCount
        self.exactOpenURL = exactOpenURL
    }
}
