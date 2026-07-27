import AgentStudioCore
import Foundation

/// Controllable FSEvent stream client for tests.
/// Tracks registrations/unregistrations and lets tests inject batches explicitly.
package final class ControllableFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private let lock = NSLock()
    private var registeredIds: [UUID] = []
    private var unregisteredIds: [UUID] = []
    private var continuation: AsyncStream<FSEventBatch>.Continuation?
    private var stream: AsyncStream<FSEventBatch>?

    package init() {
        let (stream, continuation) = AsyncStream<FSEventBatch>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.stream = stream
        self.continuation = continuation
    }

    package var registeredWorktreeIds: [UUID] {
        lock.withLock { registeredIds }
    }

    package var unregisteredWorktreeIds: [UUID] {
        lock.withLock { unregisteredIds }
    }

    package func events() -> AsyncStream<FSEventBatch> {
        lock.withLock { stream! }
    }

    package func register(worktreeId: UUID, repoId: UUID, rootPath: URL) {
        lock.withLock { registeredIds.append(worktreeId) }
    }

    package func unregister(worktreeId: UUID) {
        lock.withLock { unregisteredIds.append(worktreeId) }
    }

    package func shutdown() {
        continuation?.finish()
    }

    package func send(_ batch: FSEventBatch) {
        continuation?.yield(batch)
    }
}
