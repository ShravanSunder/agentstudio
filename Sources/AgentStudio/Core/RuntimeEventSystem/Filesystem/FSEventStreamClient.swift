import Foundation

package struct FSEventBatch: Sendable {
    let worktreeId: UUID
    let paths: [String]
    let requiresFullGitRefresh: Bool

    package init(
        worktreeId: UUID,
        paths: [String],
        requiresFullGitRefresh: Bool = false
    ) {
        self.worktreeId = worktreeId
        self.paths = paths
        self.requiresFullGitRefresh = requiresFullGitRefresh
    }
}

package struct FSEventOverflowRecovery: Equatable, Sendable {
    package let worktreeId: UUID
    package let paths: Set<String>?
    package let containsGitTopologyPath: Bool
    package let requiresFullGitRefresh: Bool

    package init(
        worktreeId: UUID,
        paths: Set<String>?,
        containsGitTopologyPath: Bool = false,
        requiresFullGitRefresh: Bool = false
    ) {
        self.worktreeId = worktreeId
        self.paths = paths
        self.containsGitTopologyPath = containsGitTopologyPath
        self.requiresFullGitRefresh = requiresFullGitRefresh
    }
}

package protocol FSEventStreamClient: Sendable {
    func events() -> AsyncStream<FSEventBatch>
    func consumeOverflowRecoveries() -> [FSEventOverflowRecovery]
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL)
    func unregister(worktreeId: UUID)
    func shutdown()
}
