import Foundation

package struct FSEventBatch: Sendable {
    let worktreeId: UUID
    let paths: [String]
}

package protocol FSEventStreamClient: Sendable {
    func events() -> AsyncStream<FSEventBatch>
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL)
    func unregister(worktreeId: UUID)
    func shutdown()
}
