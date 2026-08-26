import Foundation

package struct FSEventBatch: Sendable {
    let worktreeId: UUID
    let paths: [String]
}

package struct FSEventOverflowRecovery: Equatable, Sendable {
    package let worktreeId: UUID
    package let paths: Set<String>?
    package let containsGitTopologyPath: Bool

    package init(
        worktreeId: UUID,
        paths: Set<String>?,
        containsGitTopologyPath: Bool = false
    ) {
        self.worktreeId = worktreeId
        self.paths = paths
        self.containsGitTopologyPath = containsGitTopologyPath
    }
}

package protocol FSEventStreamClient: Sendable {
    func events() -> AsyncStream<FSEventBatch>
    func consumeOverflowRecoveries() -> [FSEventOverflowRecovery]
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL)
    func unregister(worktreeId: UUID)
    func shutdown()
}
