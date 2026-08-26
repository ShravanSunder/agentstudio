import Foundation

package struct FSEventBatch: Sendable {
    let worktreeId: UUID
    let paths: [String]
}

package struct FSEventOverflowRecovery: Equatable, Sendable {
    package let worktreeId: UUID
    package let paths: Set<String>?

    package init(worktreeId: UUID, paths: Set<String>?) {
        self.worktreeId = worktreeId
        self.paths = paths
    }
}

package protocol FSEventStreamClient: Sendable {
    func events() -> AsyncStream<FSEventBatch>
    func consumeOverflowRecoveries() -> [FSEventOverflowRecovery]
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL)
    func unregister(worktreeId: UUID)
    func shutdown()
}
