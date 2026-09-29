import AgentStudioInfrastructure
import Foundation

package enum GitProjectorIdleOutcome: Equatable, Sendable {
    case idle(droppedEnvelopes: UInt64)
    case shutdown
    case cancelled
}

struct GitProjectorIdleWaiter {
    let lifetime: UInt64
    let targetCheckpoint: EventBusDeliveryCheckpoint
    let continuation: CheckedContinuation<GitProjectorIdleOutcome, Never>
}

extension GitWorkingDirectoryProjector {
    func resumeShutdownsWaitingForSubscriptionStart() {
        let waitingShutdowns = startCompletionWaiters
        startCompletionWaiters.removeAll(keepingCapacity: false)
        for waiter in waitingShutdowns {
            waiter.resume()
        }
    }

    func waitForSubscriptionStartBeforeShutdown() async {
        guard isStarting else { return }
        await withCheckedContinuation { continuation in
            startCompletionWaiters.append(continuation)
        }
    }

    /// Waits for intake and all accepted projector work to settle. Work newly
    /// admitted while waiting also extends the wait. A future periodic refresh
    /// with no accepted debt does not. Callers claiming complete delivery must
    /// require `.idle(droppedEnvelopes: 0)`.
    package func waitUntilIdle() async -> GitProjectorIdleOutcome {
        guard !isShuttingDown, let subscriptionHandle else { return .shutdown }
        let lifetime = subscriptionLifetime
        let targetCheckpoint = subscriptionHandle.deliveryCheckpoint()
        let waiterID = UUIDv7.generate()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .cancelled)
                    return
                }
                guard !isShuttingDown, lifetime == subscriptionLifetime else {
                    continuation.resume(returning: .shutdown)
                    return
                }
                idleWaiters[waiterID] = GitProjectorIdleWaiter(
                    lifetime: lifetime,
                    targetCheckpoint: targetCheckpoint,
                    continuation: continuation
                )
                resolveIdleWaitersIfPossible()
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelIdleWaiter(waiterID)
            }
        }
    }

    func didHandleRuntimeEnvelope(lifetime: UInt64) {
        guard lifetime == subscriptionLifetime else { return }
        handledEnvelopeCount &+= 1
        resolveIdleWaitersIfPossible()
    }

    func subscriptionStreamDidEnd(lifetime: UInt64) {
        guard lifetime == subscriptionLifetime, !isShuttingDown else { return }
        isShuttingDown = true
        resolveAllIdleWaiters(as: .shutdown)
        // The subscription task cannot join itself. Schedule shutdown after its
        // loop returns, so restart cannot overlap the old lifetime's cleanup.
        Task { [weak self] in
            await self?.shutdown()
        }
    }

    func drainTaskDidExit(taskGeneration: UInt64) {
        outstandingDrainTasks.removeValue(forKey: taskGeneration)
        resolveIdleWaitersIfPossible()
    }

    func resolveIdleWaitersIfPossible() {
        guard !idleWaiters.isEmpty else { return }
        guard !isShuttingDown, let subscriptionHandle else {
            resolveAllIdleWaiters(as: .shutdown)
            return
        }
        let currentCheckpoint = subscriptionHandle.deliveryCheckpoint()
        guard handledEnvelopeCount >= currentCheckpoint.enqueuedCount else { return }
        guard pendingByWorktreeId.isEmpty,
            coalescingWorktreeIds.isEmpty,
            immediateRefreshWorktreeIds.isEmpty,
            explicitRefreshWorktreeIds.isEmpty,
            deferredStatusBackoffChangesetByWorktreeId.isEmpty,
            capacityRetryWorktreeIds.isEmpty,
            capacityRearmedWorktreeIds.isEmpty,
            pendingVisibilityDeltaWorktreeIds.isEmpty,
            visibilityAdmissionTask == nil,
            capacityCompletionTask == nil,
            outstandingDrainTasks.isEmpty,
            activeDeadlineHandlerCount == 0,
            !hasDueRefreshDeadline
        else { return }

        let readyIDs = idleWaiters.compactMap { waiterID, waiter in
            waiter.lifetime == subscriptionLifetime
                && handledEnvelopeCount >= waiter.targetCheckpoint.enqueuedCount ? waiterID : nil
        }
        for waiterID in readyIDs {
            idleWaiters.removeValue(forKey: waiterID)?.continuation.resume(
                returning: .idle(droppedEnvelopes: currentCheckpoint.droppedCount)
            )
        }
    }

    func resolveAllIdleWaiters(as outcome: GitProjectorIdleOutcome) {
        let waiters = Array(idleWaiters.values)
        idleWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.continuation.resume(returning: outcome)
        }
    }

    private func cancelIdleWaiter(_ waiterID: UUID) {
        idleWaiters.removeValue(forKey: waiterID)?.continuation.resume(returning: .cancelled)
    }
}
