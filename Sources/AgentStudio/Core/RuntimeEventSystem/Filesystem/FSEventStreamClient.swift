import Foundation

struct FSEventBatch: Sendable {
    let worktreeId: UUID
    let paths: [String]
    let didOverflow: Bool

    init(worktreeId: UUID, paths: [String], didOverflow: Bool = false) {
        self.worktreeId = worktreeId
        self.paths = paths
        self.didOverflow = didOverflow
    }
}

protocol FSEventStreamClient: Sendable {
    func events() -> AsyncStream<FSEventBatch>
    func register(worktreeId: UUID, repoId: UUID, rootPath: URL)
    func unregister(worktreeId: UUID)
    func shutdown()
}
