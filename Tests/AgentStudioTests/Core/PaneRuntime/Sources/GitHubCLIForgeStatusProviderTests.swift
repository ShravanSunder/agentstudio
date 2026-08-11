import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("GitHub CLI Forge status provider")
struct GitHubCLIForgeStatusProviderTests {
    @Test("queries one repository-wide page with branch names and URLs")
    func queriesOneRepositoryWidePage() async {
        let processExecutor = MockProcessExecutor()
        processExecutor.enqueueSuccess(
            """
            [
              {"headRefName":"feature/toolbar","url":"https://github.com/acme/studio/pull/42"},
              {"headRefName":"feature/sidebar","url":"https://github.com/acme/studio/pull/43"}
            ]
            """
        )
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)

        let outcome = await provider.pullRequests(origin: "git@github.com:acme/studio.git")

        #expect(
            processExecutor.calls == [
                .init(
                    command: "gh",
                    args: [
                        "pr", "list",
                        "--repo", "acme/studio",
                        "--state", "open",
                        "--json", "headRefName,url",
                        "--limit", String(AppPolicies.Forge.pullRequestResultLimit),
                    ],
                    environment: nil
                )
            ]
        )
        #expect(
            outcome
                == .complete([
                    ForgePullRequest(
                        headRefName: "feature/toolbar",
                        url: URL(string: "https://github.com/acme/studio/pull/42")!
                    ),
                    ForgePullRequest(
                        headRefName: "feature/sidebar",
                        url: URL(string: "https://github.com/acme/studio/pull/43")!
                    ),
                ])
        )
    }

    @Test("a response below the cap is complete")
    func belowCapIsComplete() async {
        let processExecutor = MockProcessExecutor()
        let belowCapCount = AppPolicies.Forge.pullRequestResultLimit - 1
        let rows = (0..<belowCapCount).map { index in
            "{\"headRefName\":\"branch-\(index)\",\"url\":\"https://github.com/acme/studio/pull/\(index + 1)\"}"
        }
        processExecutor.enqueueSuccess("[\(rows.joined(separator: ","))]")
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)

        let outcome = await provider.pullRequests(origin: "https://github.com/acme/studio.git")

        guard case .complete(let pullRequests) = outcome else {
            Issue.record("Expected a complete result below the explicit cap")
            return
        }
        #expect(pullRequests.count == belowCapCount)
    }

    @Test("a response at the cap is potentially truncated")
    func atCapIsPotentiallyTruncated() async {
        let processExecutor = MockProcessExecutor()
        let rows = (0..<AppPolicies.Forge.pullRequestResultLimit).map { index in
            "{\"headRefName\":\"branch-\(index)\",\"url\":\"https://github.com/acme/studio/pull/\(index + 1)\"}"
        }
        processExecutor.enqueueSuccess("[\(rows.joined(separator: ","))]")
        let provider = GitHubCLIForgeStatusProvider(processExecutor: processExecutor)

        let outcome = await provider.pullRequests(origin: "https://github.com/acme/studio.git")

        #expect(outcome == .truncated)
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
}
