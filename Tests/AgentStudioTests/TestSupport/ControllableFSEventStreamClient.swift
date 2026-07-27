import Foundation

@testable import AgentStudio

/// Controllable FSEvent stream client for tests.
/// Tracks registrations/unregistrations and lets tests inject batches explicitly.
final class ControllableFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private let lock = NSLock()
    private var registeredIds: [UUID] = []
    private var unregisteredIds: [UUID] = []
    private var continuation: AsyncStream<FSEventBatch>.Continuation?
    private var stream: AsyncStream<FSEventBatch>?

    init() {
        let (stream, continuation) = AsyncStream<FSEventBatch>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.stream = stream
        self.continuation = continuation
    }

    var registeredWorktreeIds: [UUID] {
        lock.withLock { registeredIds }
    }

    var unregisteredWorktreeIds: [UUID] {
        lock.withLock { unregisteredIds }
    }

    func events() -> AsyncStream<FSEventBatch> {
        lock.withLock { stream! }
    }

    func register(worktreeId: UUID, repoId: UUID, rootPath: URL) {
        lock.withLock { registeredIds.append(worktreeId) }
    }

    func unregister(worktreeId: UUID) {
        lock.withLock { unregisteredIds.append(worktreeId) }
    }

    func shutdown() {
        continuation?.finish()
    }

    func send(_ batch: FSEventBatch) {
        continuation?.yield(batch)
    }
}
