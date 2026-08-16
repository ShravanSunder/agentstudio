import Foundation

enum ForgePullRequestFactsProjector {
    static func project(
        pullRequests: [ForgePullRequest],
        demandedBranches: Set<String>
    ) -> [String: PullRequestFacts] {
        var pullRequestsByBranch: [String: [ForgePullRequest]] = [:]
        for pullRequest in pullRequests where demandedBranches.contains(pullRequest.headRefName) {
            pullRequestsByBranch[pullRequest.headRefName, default: []].append(pullRequest)
        }
        return Dictionary(
            uniqueKeysWithValues: demandedBranches.map { branch in
                let matchingPullRequests = pullRequestsByBranch[branch] ?? []
                let exactPullRequest = matchingPullRequests.count == 1 ? matchingPullRequests[0] : nil
                return (
                    branch,
                    PullRequestFacts(
                        openCount: matchingPullRequests.count,
                        exactOpenURL: exactPullRequest?.url,
                        exactReadiness: exactPullRequest?.readiness
                    )
                )
            })
    }
}
