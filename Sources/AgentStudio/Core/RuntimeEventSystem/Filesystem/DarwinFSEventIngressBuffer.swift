import AgentStudioInfrastructure
import Foundation

package final class DarwinFSEventIngressBuffer: @unchecked Sendable {
    private struct PendingActivityProcessingFence {
        let id: FSEventActivityProcessingFenceID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let lock = NSLock()
    private let eventsStream: AsyncStream<FSEventIngressItem>
    private let eventsContinuation: AsyncStream<FSEventIngressItem>.Continuation
    private let maximumRetainedOverflowPathsPerRegistration: Int
    private let overflowHandler: @Sendable (UUID) -> Void
    private let performanceAccumulator: DarwinFSEventIngressPerformanceAccumulator
    private var overflowRecoveryByWorktreeId: [UUID: FSEventOverflowRecovery] = [:]
    private var nextActivityProcessingFenceID: UInt64 = 0
    private var pendingActivityProcessingFence: PendingActivityProcessingFence?

    package init(
        capacity: Int,
        maximumRetainedOverflowPathsPerRegistration: Int =
            AppPolicies.FilesystemIngress.maximumRetainedOverflowPathsPerRegistration,
        performanceAccumulator: DarwinFSEventIngressPerformanceAccumulator =
            DarwinFSEventIngressPerformanceAccumulator(),
        overflowHandler: @escaping @Sendable (UUID) -> Void = { _ in }
    ) {
        precondition(capacity > 0)
        precondition(maximumRetainedOverflowPathsPerRegistration > 0)
        let (stream, continuation) = AsyncStream.makeStream(
            of: FSEventIngressItem.self,
            bufferingPolicy: .bufferingOldest(capacity)
        )
        eventsStream = stream
        eventsContinuation = continuation
        self.maximumRetainedOverflowPathsPerRegistration =
            maximumRetainedOverflowPathsPerRegistration
        self.performanceAccumulator = performanceAccumulator
        self.overflowHandler = overflowHandler
    }

    package func events() -> AsyncStream<FSEventIngressItem> {
        eventsStream
    }

    package func yield(
        _ batch: FSEventBatch,
        source: DarwinFSEventIngressSource = .local
    ) {
        lock.withLock {
            switch eventsContinuation.yield(.batch(batch)) {
            case .enqueued:
                performanceAccumulator.recordIngress(
                    source: source,
                    disposition: .accepted,
                    pathCount: batch.paths.count
                )
            case .dropped(.batch(let droppedBatch)):
                performanceAccumulator.recordIngress(
                    source: source,
                    disposition: .dropped,
                    pathCount: droppedBatch.paths.count
                )
                retainOverflowRecovery(droppedBatch)
                overflowHandler(droppedBatch.worktreeId)
            case .dropped(.activityProcessingFence):
                preconditionFailure("batch yield cannot drop a previously buffered fence")
            case .terminated:
                performanceAccumulator.recordIngress(
                    source: source,
                    disposition: .terminated,
                    pathCount: batch.paths.count
                )
            @unknown default:
                performanceAccumulator.recordIngress(
                    source: source,
                    disposition: .dropped,
                    pathCount: batch.paths.count
                )
                retainOverflowRecovery(batch)
                overflowHandler(batch.worktreeId)
            }
        }
    }

    package func enqueueActivityProcessingFence() async -> Bool {
        await withCheckedContinuation { continuation in
            let shouldResumeRejected = lock.withLock { () -> Bool in
                guard pendingActivityProcessingFence == nil else { return true }
                nextActivityProcessingFenceID &+= 1
                let fenceID = FSEventActivityProcessingFenceID(
                    rawValue: nextActivityProcessingFenceID
                )
                switch eventsContinuation.yield(.activityProcessingFence(fenceID)) {
                case .enqueued:
                    pendingActivityProcessingFence = PendingActivityProcessingFence(
                        id: fenceID,
                        continuation: continuation
                    )
                    return false
                case .dropped(.activityProcessingFence):
                    return true
                case .dropped(.batch(let droppedBatch)):
                    retainOverflowRecovery(droppedBatch)
                    overflowHandler(droppedBatch.worktreeId)
                    return true
                case .terminated:
                    return true
                @unknown default:
                    return true
                }
            }
            if shouldResumeRejected {
                continuation.resume(returning: false)
            }
        }
    }

    package func acknowledgeActivityProcessingFence(
        _ fenceID: FSEventActivityProcessingFenceID
    ) {
        let continuation = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            guard pendingActivityProcessingFence?.id == fenceID else { return nil }
            defer { pendingActivityProcessingFence = nil }
            return pendingActivityProcessingFence?.continuation
        }
        continuation?.resume(returning: true)
    }

    package func consumeOverflowRecoveries() -> [FSEventOverflowRecovery] {
        lock.withLock {
            defer { overflowRecoveryByWorktreeId.removeAll(keepingCapacity: true) }
            let recoveries = overflowRecoveryByWorktreeId.values.sorted {
                $0.worktreeId.uuidString < $1.worktreeId.uuidString
            }
            performanceAccumulator.recordOverflowDrain(
                recoveryCount: recoveries.count,
                retainedPathCount: recoveries.reduce(0) { $0 + ($1.paths?.count ?? 0) },
                coarseRecoveryCount: recoveries.count(where: { $0.paths == nil })
            )
            return recoveries
        }
    }

    private func retainOverflowRecovery(_ batch: FSEventBatch) {
        let batchContainsGitTopologyPath = batch.paths.contains(where: Self.isGitTopologyPath)
        if let existing = overflowRecoveryByWorktreeId[batch.worktreeId], existing.paths == nil {
            overflowRecoveryByWorktreeId[batch.worktreeId] = FSEventOverflowRecovery(
                worktreeId: batch.worktreeId,
                paths: nil,
                containsGitTopologyPath: existing.containsGitTopologyPath
                    || batchContainsGitTopologyPath,
                requiresFullGitRefresh: existing.requiresFullGitRefresh
                    || batch.requiresFullGitRefresh
            )
            return
        }
        let existing = overflowRecoveryByWorktreeId[batch.worktreeId]
        var retainedPaths = existing?.paths ?? Set<String>()
        let containsGitTopologyPath =
            existing?.containsGitTopologyPath == true
            || batchContainsGitTopologyPath
        let requiresFullGitRefresh =
            existing?.requiresFullGitRefresh == true
            || batch.requiresFullGitRefresh
        for path in batch.paths {
            if retainedPaths.count >= maximumRetainedOverflowPathsPerRegistration,
                !retainedPaths.contains(path)
            {
                overflowRecoveryByWorktreeId[batch.worktreeId] = FSEventOverflowRecovery(
                    worktreeId: batch.worktreeId,
                    paths: nil,
                    containsGitTopologyPath: containsGitTopologyPath,
                    requiresFullGitRefresh: requiresFullGitRefresh
                )
                return
            }
            retainedPaths.insert(path)
        }
        overflowRecoveryByWorktreeId[batch.worktreeId] = FSEventOverflowRecovery(
            worktreeId: batch.worktreeId,
            paths: retainedPaths,
            containsGitTopologyPath: containsGitTopologyPath,
            requiresFullGitRefresh: requiresFullGitRefresh
        )
    }

    private static func isGitTopologyPath(_ path: String) -> Bool {
        path.contains("/.git/") || path.hasSuffix("/.git")
    }

    package func finish() {
        let continuation = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            eventsContinuation.finish()
            defer { pendingActivityProcessingFence = nil }
            return pendingActivityProcessingFence?.continuation
        }
        continuation?.resume(returning: false)
    }
}
