import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Forge pull request facts projector")
struct ForgePullRequestFactsProjectorTests {
    @Test("readiness belongs only to an exact single pull request")
    func readinessRequiresExactSinglePullRequest() {
        let readiness = PullRequestReadiness(
            isDraft: false,
            checkStatus: .passed,
            reviewStatus: .approved,
            mergeability: .mergeable,
            mergeState: .clean
        )
        let exactURL = URL(string: "https://github.com/acme/studio/pull/1")!
        let secondURL = URL(string: "https://github.com/acme/studio/pull/2")!

        let factsByBranch = ForgePullRequestFactsProjector.project(
            pullRequests: [
                ForgePullRequest(headRefName: "exact", url: exactURL, readiness: readiness),
                ForgePullRequest(headRefName: "ambiguous", url: exactURL, readiness: readiness),
                ForgePullRequest(headRefName: "ambiguous", url: secondURL, readiness: readiness),
            ],
            demandedBranches: ["exact", "ambiguous", "missing"]
        )

        #expect(
            factsByBranch["exact"]
                == PullRequestFacts(
                    openCount: 1,
                    exactOpenURL: exactURL,
                    exactReadiness: readiness
                )
        )
        #expect(factsByBranch["ambiguous"] == PullRequestFacts(openCount: 2, exactOpenURL: nil))
        #expect(factsByBranch["missing"] == PullRequestFacts(openCount: 0, exactOpenURL: nil))
    }
}
