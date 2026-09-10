import AgentStudioCore
import Foundation

package struct StubGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    package let resultHandler: @Sendable (URL, [String]?) async -> GitWorkingTreeStatusResult
    private let materializer = StubGitWorkingTreeStatusMaterializer()

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

    package func statusFactsResult(
        for rootPath: URL,
        pathspecs: [String]?
    ) async -> GitWorkingTreeStatusFactsResult {
        switch await resultHandler(rootPath, pathspecs) {
        case .available(let status):
            await materializer.capture(status, for: rootPath)
            return .available(GitWorkingTreeStatusFacts(status: status))
        case .unavailable(let unavailable):
            await materializer.clear(for: rootPath)
            return .unavailable(unavailable)
        }
    }

    package func lineDetailResult(for rootPath: URL) async -> GitWorkingTreeLineDetailResult {
        guard let detail = await materializer.lineDetail(for: rootPath) else {
            return .unavailable(GitWorkingTreeStatusUnavailable(reason: .providerReturnedNil))
        }
        return .available(detail)
    }
}

private actor StubGitWorkingTreeStatusMaterializer {
    private var lineDetailByRootPath: [URL: GitWorkingTreeLineDetail] = [:]

    func capture(_ status: GitWorkingTreeStatus, for rootPath: URL) {
        lineDetailByRootPath[rootPath.standardizedFileURL] = GitWorkingTreeLineDetail(status: status)
    }

    func clear(for rootPath: URL) {
        lineDetailByRootPath.removeValue(forKey: rootPath.standardizedFileURL)
    }

    func lineDetail(for rootPath: URL) -> GitWorkingTreeLineDetail? {
        lineDetailByRootPath[rootPath.standardizedFileURL]
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
    package let handler: @Sendable (String) async -> ForgePullRequestQueryOutcome

    package init(handler: @escaping @Sendable (String) async -> ForgePullRequestQueryOutcome) {
        self.handler = handler
    }

    package func pullRequests(
        origin: String,
        demandedBranches _: Set<String>
    ) async -> ForgePullRequestQueryOutcome {
        await handler(origin)
    }
}

extension ForgeStatusProvider where Self == StubForgeStatusProvider {
    package static func stub(
        _ handler: @escaping @Sendable (String) async -> ForgePullRequestQueryOutcome
    ) -> StubForgeStatusProvider {
        StubForgeStatusProvider(handler: handler)
    }
}
