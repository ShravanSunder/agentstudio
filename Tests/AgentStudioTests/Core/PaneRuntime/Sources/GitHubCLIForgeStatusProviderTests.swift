import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("GitHub CLI Forge status provider")
struct GitHubCLIForgeStatusProviderTests {
    @Test("queries only demanded branches through stable aliases")
    func queriesOnlyDemandedBranchesThroughStableAliases() async {
        let processExecutor = MockProcessExecutor()
        processExecutor.enqueueSuccess(
            """
            {
              "data": {
                "repository": {
                  "branch0": {
                    "nodes": [
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
                  },
                  "branch1": {
                    "nodes": [
                      {
                        "headRefName": "feature/toolbar",
                        "url": "https://github.com/acme/studio/pull/42",
                        "isDraft": false,
                        "reviewDecision": "APPROVED",
                        "mergeable": "MERGEABLE",
                        "mergeStateStatus": "CLEAN",
                        "statusCheckRollup": {"state": "SUCCESS"}
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

        let outcome = await provider.pullRequests(
            origin: "git@github.com:acme/studio.git",
            demandedBranches: ["feature/toolbar", "feature/sidebar"]
        )

        #expect(processExecutor.calls.count == 1)
        guard let call = processExecutor.calls.first else {
            Issue.record("Expected one GitHub CLI call")
            return
        }
        #expect(call.command == "gh")
        #expect(call.args.prefix(2) == ["api", "graphql"])
        #expect(call.args.contains("owner=acme"))
        #expect(call.args.contains("name=studio"))
        #expect(call.args.contains("branch0=feature/sidebar"))
        #expect(call.args.contains("branch1=feature/toolbar"))
        let queryArgument = call.args.first(where: { $0.hasPrefix("query=") }) ?? ""
        #expect(queryArgument.contains("branch0: pullRequests"))
        #expect(queryArgument.contains("branch1: pullRequests"))
        #expect(queryArgument.contains("headRefName: $branch0"))
        #expect(!queryArgument.contains("repository-wide"))
        #expect(queryArgument.contains("statusCheckRollup"))
        #expect(queryArgument.contains("isDraft"))
        #expect(queryArgument.contains("reviewDecision"))
        #expect(queryArgument.contains("mergeStateStatus"))
        #expect(
            outcome
                == .complete([
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

        let outcome = await provider.pullRequests(
            origin: "https://github.com/acme/studio.git",
            demandedBranches: ["feature/unknown"]
        )

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

    @Test("paginates one demanded branch through its stable cursor variable")
    func paginatesDemandedBranch() async {
        let processExecutor = MockProcessExecutor()
        processExecutor.enqueueSuccess(
            graphqlResponse(
                nodes: pullRequestNode(branch: "feature/paginated", index: 0),
                hasNextPage: true,
                endCursor: "cursor-1"
            )
        )
        processExecutor.enqueueSuccess(graphqlResponse(nodes: ""))
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)

        let outcome = await provider.pullRequests(
            origin: "https://github.com/acme/studio.git",
            demandedBranches: ["feature/paginated"]
        )

        guard case .complete(let pullRequests) = outcome else {
            Issue.record("Expected a complete demanded-branch result")
            return
        }
        #expect(pullRequests.count == 1)
        #expect(processExecutor.calls.count == 2)
        #expect(processExecutor.calls[1].args.contains("after0=cursor-1"))
    }

    @Test("rejects a demanded branch that exceeds the declared page bound")
    func excessiveDemandedBranchPaginationIsTruncated() async {
        let processExecutor = MockProcessExecutor()
        for pageIndex in 0..<AppPolicies.ForgeRefresh.maximumPagesPerBranch {
            processExecutor.enqueueSuccess(
                graphqlResponse(
                    nodes: pullRequestNode(branch: "feature/unbounded", index: pageIndex),
                    hasNextPage: true,
                    endCursor: "cursor-\(pageIndex + 1)"
                )
            )
        }
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)

        let outcome = await provider.pullRequests(
            origin: "https://github.com/acme/studio.git",
            demandedBranches: ["feature/unbounded"]
        )

        #expect(outcome == .truncated)
        #expect(processExecutor.calls.count == AppPolicies.ForgeRefresh.maximumPagesPerBranch)
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

        let outcome = await provider.pullRequests(
            origin: "git@github.com:acme/studio.git",
            demandedBranches: ["main"]
        )

        #expect(outcome == .rateLimited(retryAfterSeconds: 75))
    }

    @Test("a later alias batch failure rejects the complete repository plan")
    func laterAliasBatchFailureRejectsCompletePlan() async {
        let processExecutor = MockProcessExecutor()
        processExecutor.enqueueSuccess(
            emptyGraphQLResponse(aliasCount: AppPolicies.ForgeRefresh.maximumBranchAliasesPerBatch)
        )
        processExecutor.enqueue(
            ProcessResult(exitCode: 1, stdout: "", stderr: "offline")
        )
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)
        let demandedBranches = Set(
            (0...AppPolicies.ForgeRefresh.maximumBranchAliasesPerBatch).map { index in
                "feature/branch-\(index)"
            }
        )

        let outcome = await provider.pullRequests(
            origin: "git@github.com:acme/studio.git",
            demandedBranches: demandedBranches
        )

        #expect(outcome == .failed(message: "offline"))
        #expect(processExecutor.calls.count == 2)
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
                  "branch0": {
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

    private func pullRequestNode(branch: String, index: Int) -> String {
        """
        {
          "headRefName": "\(branch)",
          "url": "https://github.com/acme/studio/pull/\(index + 1)",
          "isDraft": false,
          "reviewDecision": null,
          "mergeable": "UNKNOWN",
          "mergeStateStatus": "UNKNOWN",
          "statusCheckRollup": null
        }
        """
    }

    private func emptyGraphQLResponse(aliasCount: Int) -> String {
        let connections = (0..<aliasCount).map { index in
            """
            "branch\(index)": {
              "nodes": [],
              "pageInfo": {"hasNextPage": false, "endCursor": null}
            }
            """
        }.joined(separator: ",")
        return """
            {
              "data": {
                "repository": {
                  \(connections)
                }
              }
            }
            """
    }
}
