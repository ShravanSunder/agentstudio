import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("GitHub CLI Forge status provider")
struct GitHubCLIForgeStatusProviderTests {
    @Test("queries one compact repository-wide page with PR readiness scalars")
    func queriesOneRepositoryWidePage() async {
        let processExecutor = MockProcessExecutor()
        processExecutor.enqueueSuccess(
            """
            {
              "data": {
                "repository": {
                  "pullRequests": {
                    "nodes": [
                      {
                        "headRefName": "feature/toolbar",
                        "url": "https://github.com/acme/studio/pull/42",
                        "isDraft": false,
                        "reviewDecision": "APPROVED",
                        "mergeable": "MERGEABLE",
                        "mergeStateStatus": "CLEAN",
                        "statusCheckRollup": {"state": "SUCCESS"}
                      },
                      {
                        "headRefName": "feature/sidebar",
                        "url": "https://github.com/acme/studio/pull/43",
                        "isDraft": true,
                        "reviewDecision": "CHANGES_REQUESTED",
                        "mergeable": "CONFLICTING",
                        "mergeStateStatus": "DIRTY",
                        "statusCheckRollup": {"state": "FAILURE"}
                      }
                    ],
                    "pageInfo": {"hasNextPage": false, "endCursor": null}
                  }
                }
              }
            }
            """
        )
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)

        let outcome = await provider.pullRequests(origin: "git@github.com:acme/studio.git")

        #expect(processExecutor.calls.count == 1)
        guard let call = processExecutor.calls.first else {
            Issue.record("Expected one GitHub CLI call")
            return
        }
        #expect(call.command == "gh")
        #expect(call.args.prefix(2) == ["api", "graphql"])
        #expect(call.args.contains("owner=acme"))
        #expect(call.args.contains("name=studio"))
        let queryArgument = call.args.first(where: { $0.hasPrefix("query=") }) ?? ""
        #expect(queryArgument.contains("statusCheckRollup"))
        #expect(queryArgument.contains("isDraft"))
        #expect(queryArgument.contains("reviewDecision"))
        #expect(queryArgument.contains("mergeStateStatus"))
        #expect(
            outcome
                == .complete([
                    ForgePullRequest(
                        headRefName: "feature/toolbar",
                        url: URL(string: "https://github.com/acme/studio/pull/42")!,
                        readiness: PullRequestReadiness(
                            isDraft: false,
                            checkStatus: .passed,
                            reviewStatus: .approved,
                            mergeability: .mergeable,
                            mergeState: .clean
                        )
                    ),
                    ForgePullRequest(
                        headRefName: "feature/sidebar",
                        url: URL(string: "https://github.com/acme/studio/pull/43")!,
                        readiness: PullRequestReadiness(
                            isDraft: true,
                            checkStatus: .failed,
                            reviewStatus: .changesRequested,
                            mergeability: .conflicting,
                            mergeState: .dirty
                        )
                    ),
                ])
        )
    }

    @Test("missing rollup and decisions decode as unknown without per-check expansion")
    func missingReadinessScalarsAreUnknown() async {
        let processExecutor = MockProcessExecutor()
        processExecutor.enqueueSuccess(
            graphqlResponse(
                nodes: """
                    {
                      "headRefName": "feature/unknown",
                      "url": "https://github.com/acme/studio/pull/42",
                      "isDraft": false,
                      "reviewDecision": null,
                      "mergeable": "UNKNOWN",
                      "mergeStateStatus": "UNKNOWN",
                      "statusCheckRollup": null
                    }
                    """
            )
        )
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)

        let outcome = await provider.pullRequests(origin: "https://github.com/acme/studio.git")

        #expect(
            outcome
                == .complete([
                    ForgePullRequest(
                        headRefName: "feature/unknown",
                        url: URL(string: "https://github.com/acme/studio/pull/42")!,
                        readiness: PullRequestReadiness(
                            isDraft: false,
                            checkStatus: .unknown,
                            reviewStatus: .unknown,
                            mergeability: .unknown,
                            mergeState: .unknown
                        )
                    )
                ])
        )
    }

    @Test("follows one bounded second page and treats a full cap as truncated")
    func boundedSecondPageAtCapIsTruncated() async {
        let processExecutor = MockProcessExecutor()
        let firstPageRows = (0..<100).map { index in
            pullRequestNode(index: index)
        }
        let secondPageRows = (100..<AppPolicies.Forge.pullRequestResultLimit).map { index in
            pullRequestNode(index: index)
        }
        processExecutor.enqueueSuccess(
            graphqlResponse(
                nodes: firstPageRows.joined(separator: ","),
                hasNextPage: true,
                endCursor: "cursor-100"
            )
        )
        processExecutor.enqueueSuccess(
            graphqlResponse(
                nodes: secondPageRows.joined(separator: ","),
                hasNextPage: true,
                endCursor: "cursor-200"
            )
        )
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)

        let outcome = await provider.pullRequests(origin: "https://github.com/acme/studio.git")

        #expect(outcome == .truncated)
        #expect(processExecutor.calls.count == 2)
        #expect(processExecutor.calls[1].args.contains("after=cursor-100"))
    }

    @Test("treats exactly the configured result cap as potentially truncated")
    func exactResultCapIsTruncated() async {
        let processExecutor = MockProcessExecutor()
        let firstPageRows = (0..<100).map { index in
            pullRequestNode(index: index)
        }
        let secondPageRows = (100..<AppPolicies.Forge.pullRequestResultLimit).map { index in
            pullRequestNode(index: index)
        }
        processExecutor.enqueueSuccess(
            graphqlResponse(
                nodes: firstPageRows.joined(separator: ","),
                hasNextPage: true,
                endCursor: "cursor-100"
            )
        )
        processExecutor.enqueueSuccess(
            graphqlResponse(nodes: secondPageRows.joined(separator: ","))
        )
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)

        let outcome = await provider.pullRequests(origin: "https://github.com/acme/studio.git")

        #expect(outcome == .truncated)
        #expect(processExecutor.calls.count == 2)
    }

    @Test("GitHub rate limiting is a typed result with retry-after")
    func rateLimitIsTyped() async {
        let processExecutor = MockProcessExecutor()
        processExecutor.enqueue(
            ProcessResult(
                exitCode: 1,
                stdout: "",
                stderr: "HTTP 403: secondary rate limit. retry-after: 75"
            )
        )
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)

        let outcome = await provider.pullRequests(origin: "git@github.com:acme/studio.git")

        #expect(outcome == .rateLimited(retryAfterSeconds: 75))
    }

    private func graphqlResponse(
        nodes: String,
        hasNextPage: Bool = false,
        endCursor: String? = nil
    ) -> String {
        let encodedCursor = endCursor.map { "\"\($0)\"" } ?? "null"
        return """
            {
              "data": {
                "repository": {
                  "pullRequests": {
                    "nodes": [\(nodes)],
                    "pageInfo": {
                      "hasNextPage": \(hasNextPage),
                      "endCursor": \(encodedCursor)
                    }
                  }
                }
              }
            }
            """
    }

    private func pullRequestNode(index: Int) -> String {
        """
        {
          "headRefName": "branch-\(index)",
          "url": "https://github.com/acme/studio/pull/\(index + 1)",
          "isDraft": false,
          "reviewDecision": null,
          "mergeable": "UNKNOWN",
          "mergeStateStatus": "UNKNOWN",
          "statusCheckRollup": null
        }
        """
    }
}
