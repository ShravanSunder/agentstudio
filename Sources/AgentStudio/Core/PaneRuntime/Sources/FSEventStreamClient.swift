import Foundation

struct FSEventBatch: Sendable {
    let worktreeId: UUID
    let paths: [String]
}

protocol FSEventStreamClient: Sendable {
    func events() -> AsyncStream<FSEventBatch>
    func register(worktreeId: UUID, rootPath: URL) async
    func unregister(worktreeId: UUID) async
    func shutdown() async
}

/// Default no-op stream client used until the concrete macOS FSEvents bridge is wired.
struct NoopFSEventStreamClient: FSEventStreamClient {
    func events() -> AsyncStream<FSEventBatch> {
        AsyncStream { _ in }
    }

    func register(worktreeId _: UUID, rootPath _: URL) async {}

    func unregister(worktreeId _: UUID) async {}

    func shutdown() async {}
}
