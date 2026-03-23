import Foundation

@testable import AgentStudio

struct StubGitWorkingTreeStatusProvider: GitWorkingTreeStatusProvider {
    let handler: @Sendable (URL) async -> GitWorkingTreeStatus?

    init(handler: @escaping @Sendable (URL) async -> GitWorkingTreeStatus?) {
        self.handler = handler
    }

    func status(for rootPath: URL) async -> GitWorkingTreeStatus? {
        await handler(rootPath)
    }
}

extension GitWorkingTreeStatusProvider where Self == StubGitWorkingTreeStatusProvider {
    static func stub(
        _ handler: @escaping @Sendable (URL) async -> GitWorkingTreeStatus?
    ) -> StubGitWorkingTreeStatusProvider {
        StubGitWorkingTreeStatusProvider(handler: handler)
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
