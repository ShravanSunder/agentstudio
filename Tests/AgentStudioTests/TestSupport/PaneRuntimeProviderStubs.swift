import AgentStudioCore
import Foundation

package struct StubGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    package let resultHandler: @Sendable (URL, [String]?) async -> GitWorkingTreeStatusResult

    /// Pathspec-ignoring convenience: the handler sees only the root path.
    package init(handler: @escaping @Sendable (URL) async -> GitWorkingTreeStatus?) {
        self.resultHandler = { rootPath, _ in
            guard let status = await handler(rootPath) else {
                return .unavailable(GitWorkingTreeStatusUnavailable(reason: .providerReturnedNil))
            }
            return .available(status)
        }
    }

    /// Pathspec-ignoring convenience returning a full result.
    package init(resultHandler: @escaping @Sendable (URL) async -> GitWorkingTreeStatusResult) {
        self.resultHandler = { rootPath, _ in await resultHandler(rootPath) }
    }

    /// Pathspec-aware handler: `pathspecs` is `nil` for a full status, otherwise
    /// the scoped repo-relative paths the projector requested.
    package init(
        pathspecAwareResultHandler: @escaping @Sendable (URL, [String]?) async -> GitWorkingTreeStatusResult
    ) {
        self.resultHandler = pathspecAwareResultHandler
    }

    package func statusResult(for rootPath: URL, pathspecs: [String]?) async -> GitWorkingTreeStatusResult {
        await resultHandler(rootPath, pathspecs)
    }
}

extension GitWorkingTreeStatusProvider where Self == StubGitWorkingTreeStatusProvider {
    package static func stub(
        _ handler: @escaping @Sendable (URL) async -> GitWorkingTreeStatus?
    ) -> StubGitWorkingTreeStatusProvider {
        StubGitWorkingTreeStatusProvider(handler: handler)
    }

    package static func stubResult(
        _ resultHandler: @escaping @Sendable (URL) async -> GitWorkingTreeStatusResult
    ) -> StubGitWorkingTreeStatusProvider {
        StubGitWorkingTreeStatusProvider(resultHandler: resultHandler)
    }
}

package struct StubForgeStatusProvider: ForgeStatusProvider {
    package let handler: @Sendable (String, Set<String>) async throws -> [String: [ForgePullRequest]]

    package init(handler: @escaping @Sendable (String, Set<String>) async throws -> [String: Int]) {
        self.handler = { origin, branches in
            let countsByBranch = try await handler(origin, branches)
            return Dictionary(
                uniqueKeysWithValues: branches.map { branch in
                    let count = countsByBranch[branch] ?? 0
                    let pullRequests = (0..<count).map { index in
                        ForgePullRequest(
                            url: URL(string: "https://github.com/test/repository/pull/\(index + 1)")!,
                            isOpen: true
                        )
                    }
                    return (branch, pullRequests)
                })
        }
    }

    package init(
        pullRequestHandler: @escaping @Sendable (String, Set<String>) async throws -> [String: [ForgePullRequest]]
    ) {
        handler = pullRequestHandler
    }

    package func pullRequests(origin: String, branches: Set<String>) async throws -> [String: [ForgePullRequest]] {
        try await handler(origin, branches)
    }
}

extension ForgeStatusProvider where Self == StubForgeStatusProvider {
    package static func stub(
        _ handler: @escaping @Sendable (String, Set<String>) async throws -> [String: Int]
    ) -> StubForgeStatusProvider {
        StubForgeStatusProvider(handler: handler)
    }

    package static func stubPullRequests(
        _ handler: @escaping @Sendable (String, Set<String>) async throws -> [String: [ForgePullRequest]]
    ) -> StubForgeStatusProvider {
        StubForgeStatusProvider(pullRequestHandler: handler)
    }
}
