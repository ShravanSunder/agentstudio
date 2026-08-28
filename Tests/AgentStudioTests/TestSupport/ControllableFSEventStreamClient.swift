import AgentStudioCore
import Foundation

/// Controllable FSEvent stream client for tests.
/// Tracks registrations/unregistrations and lets tests inject batches explicitly.
package final class ControllableFSEventStreamClient: FSEventStreamClient, @unchecked Sendable {
    private let lock = NSLock()
    private var registeredIds: [UUID] = []
    private var unregisteredIds: [UUID] = []
    private var continuation: AsyncStream<FSEventIngressItem>.Continuation?
    private var stream: AsyncStream<FSEventIngressItem>?
    private var overflowRecoveryByWorktreeId: [UUID: FSEventOverflowRecovery] = [:]

    package init() {
        let (stream, continuation) = AsyncStream<FSEventIngressItem>.makeStream(
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

    package func events() -> AsyncStream<FSEventIngressItem> {
        lock.withLock { stream! }
    }

    package func consumeOverflowRecoveries() -> [FSEventOverflowRecovery] {
        lock.withLock {
            defer { overflowRecoveryByWorktreeId.removeAll(keepingCapacity: true) }
            return overflowRecoveryByWorktreeId.values.sorted {
                $0.worktreeId.uuidString < $1.worktreeId.uuidString
            }
        }
    }

    package func sendOverflowRecovery(
        worktreeId: UUID,
        paths: Set<String>? = nil,
        containsGitTopologyPath: Bool = false,
        requiresFullGitRefresh: Bool = false
    ) {
        lock.withLock {
            let existing = overflowRecoveryByWorktreeId[worktreeId]
            let mergedPaths = paths.map {
                (existing?.paths ?? []).union($0)
            }
            overflowRecoveryByWorktreeId[worktreeId] = FSEventOverflowRecovery(
                worktreeId: worktreeId,
                paths: existing?.paths == nil && existing != nil ? nil : mergedPaths,
                containsGitTopologyPath: existing?.containsGitTopologyPath == true
                    || containsGitTopologyPath,
                requiresFullGitRefresh: existing?.requiresFullGitRefresh == true
                    || requiresFullGitRefresh
            )
        }
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
        continuation?.yield(.batch(batch))
    }
}
