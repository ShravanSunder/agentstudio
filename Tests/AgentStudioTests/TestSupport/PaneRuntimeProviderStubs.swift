import Foundation

@testable import AgentStudio

struct StubGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    let resultHandler: @Sendable (URL) async -> GitWorkingTreeStatusResult

    init(handler: @escaping @Sendable (URL) async -> GitWorkingTreeStatus?) {
        self.resultHandler = { rootPath in
            guard let status = await handler(rootPath) else {
                return .unavailable(GitWorkingTreeStatusUnavailable(reason: .providerReturnedNil))
            }
            return .available(status)
        }
    }

    init(resultHandler: @escaping @Sendable (URL) async -> GitWorkingTreeStatusResult) {
        self.resultHandler = resultHandler
    }

    func statusResult(for rootPath: URL) async -> GitWorkingTreeStatusResult {
        await resultHandler(rootPath)
    }

    func status(for rootPath: URL) async -> GitWorkingTreeStatus? {
        switch await resultHandler(rootPath) {
        case .available(let status):
            status
        case .unavailable:
            nil
        }
    }
}

extension GitWorkingTreeStatusProvider where Self == StubGitWorkingTreeStatusProvider {
    static func stub(
        _ handler: @escaping @Sendable (URL) async -> GitWorkingTreeStatus?
    ) -> StubGitWorkingTreeStatusProvider {
        StubGitWorkingTreeStatusProvider(handler: handler)
    }

    static func stubResult(
        _ resultHandler: @escaping @Sendable (URL) async -> GitWorkingTreeStatusResult
    ) -> StubGitWorkingTreeStatusProvider {
        StubGitWorkingTreeStatusProvider(resultHandler: resultHandler)
    }
}

struct StubForgeStatusProvider: ForgeStatusProvider {
    let handler: @Sendable (String, Set<String>) async throws -> [String: Int]

    init(handler: @escaping @Sendable (String, Set<String>) async throws -> [String: Int]) {
        self.handler = handler
    }

    func pullRequestCounts(origin: String, branches: Set<String>) async throws -> [String: Int] {
        try await handler(origin, branches)
    }
}

extension ForgeStatusProvider where Self == StubForgeStatusProvider {
    static func stub(
        _ handler: @escaping @Sendable (String, Set<String>) async throws -> [String: Int]
    ) -> StubForgeStatusProvider {
        StubForgeStatusProvider(handler: handler)
    }
}
