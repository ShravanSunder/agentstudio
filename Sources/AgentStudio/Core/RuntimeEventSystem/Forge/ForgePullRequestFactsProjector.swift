import Foundation

enum ForgePullRequestFactsProjector {
    static func project(
        pullRequests: [ForgePullRequest],
        demandedBranches: Set<String>
    ) -> [String: PullRequestFacts] {
        var urlsByBranch: [String: [URL]] = [:]
        for pullRequest in pullRequests where demandedBranches.contains(pullRequest.headRefName) {
            urlsByBranch[pullRequest.headRefName, default: []].append(pullRequest.url)
        }
        return Dictionary(
            uniqueKeysWithValues: demandedBranches.map { branch in
                let urls = urlsByBranch[branch] ?? []
                return (
                    branch,
                    PullRequestFacts(openCount: urls.count, exactOpenURL: urls.first)
                )
            })
    }
}
