import Foundation

actor BridgeGitReadScheduler {
    private enum OperationPhase {
        case queued
        case running(BridgeGitReadSlotID)
        case draining(BridgeGitReadSlotID)
    }

    private struct OperationIdentity: Hashable {
        let worktreeKey: BridgeGitReadWorktreeKey
        let operationClass: BridgeGitReadOperationClass
        let coalescingKey: BridgeGitReadCoalescingKey
        let freshnessKey: BridgeGitReadFreshnessKey
        let resultTypeName: String
    }

    private struct PaneActivity {
        let worktreeKey: BridgeGitReadWorktreeKey
        let rank: BridgeGitReadActivityRank
    }

    private struct ErasedValue: @unchecked Sendable {
        let value: Any
    }

    private struct ErasedError: Error, @unchecked Sendable {
        let error: Error
    }

    private typealias ErasedResult = Result<ErasedValue, ErasedError>
    private typealias OperationBody = @Sendable () async -> ErasedResult

    private struct LogicalWaiter {
        let id: UInt64
        let succeed: @Sendable (ErasedValue) -> Void
        let fail: @Sendable (Error) -> Void
        var deadline: BridgeGitReadScheduledDeadline?
    }

    private struct OperationState {
        let id: UInt64
        let identity: OperationIdentity
        let enqueueOrder: UInt64
        let enqueueInstant: ContinuousClock.Instant
        let body: OperationBody
        var phase: OperationPhase
        var waiters: [UInt64: LogicalWaiter]
        var totalWaiterCount: Int
    }

    private let topology: BridgeGitReadSchedulerTopology
    private let deadlineScheduler: any BridgeGitReadDeadlineScheduling
    private let eventSink: BridgeGitReadSchedulerEventSink?
    private var lifecycle: BridgeGitReadSchedulerLifecycle = .active
    private var nextOperationId: UInt64 = 1
    private var nextWaiterId: UInt64 = 1
    private var nextOrder: UInt64 = 1
    private var operationsByIdentity: [OperationIdentity: OperationState] = [:]
    private var identityByOperationId: [UInt64: OperationIdentity] = [:]
    private var operationIdentityByWaiterId: [UInt64: OperationIdentity] = [:]
    private var operationIdBySlotId: [BridgeGitReadSlotID: UInt64] = [:]
    private var operationTasksById: [UInt64: Task<Void, Never>] = [:]
    private var paneActivityByPaneKey: [BridgeGitReadPaneKey: PaneActivity] = [:]
    private var lastStartOrderByWorktreeAndClass: [BridgeGitReadOperationClass: [BridgeGitReadWorktreeKey: UInt64]] =
        [:]
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        topology: BridgeGitReadSchedulerTopology,
        deadlineScheduler: any BridgeGitReadDeadlineScheduling = DispatchBridgeGitReadDeadlineScheduler(),
        eventSink: BridgeGitReadSchedulerEventSink? = nil
    ) {
        self.topology = topology
        self.deadlineScheduler = deadlineScheduler
        self.eventSink = eventSink
    }

    func updatePaneActivity(
        paneKey: BridgeGitReadPaneKey,
        worktreeKey: BridgeGitReadWorktreeKey,
        rank: BridgeGitReadActivityRank
    ) {
        guard lifecycle == .active else { return }
        paneActivityByPaneKey[paneKey] = PaneActivity(worktreeKey: worktreeKey, rank: rank)
        drainQueuedOperations()
    }

    func removePaneActivity(paneKey: BridgeGitReadPaneKey) {
        paneActivityByPaneKey.removeValue(forKey: paneKey)
        drainQueuedOperations()
    }

    func read<ReturnValue: Sendable>(
        request: BridgeGitReadRequest,
        operation: @escaping @Sendable () async throws -> ReturnValue
    ) async throws -> ReturnValue {
        guard lifecycle == .active else { throw BridgeGitReadSchedulerError.closed }
        try Task.checkCancellation()
        let waiterId = nextWaiterId
        nextWaiterId &+= 1
        let identity = OperationIdentity(
            worktreeKey: request.worktreeKey,
            operationClass: request.operationClass,
            coalescingKey: request.coalescingKey,
            freshnessKey: request.freshnessKey,
            resultTypeName: String(reflecting: ReturnValue.self)
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let waiter = LogicalWaiter(
                    id: waiterId,
                    succeed: { erasedValue in
                        guard let value = erasedValue.value as? ReturnValue else {
                            continuation.resume(throwing: BridgeGitReadSchedulerError.resultTypeMismatch)
                            return
                        }
                        continuation.resume(returning: value)
                    },
                    fail: { error in
                        continuation.resume(throwing: error)
                    }
                )
                enqueue(
                    waiter: waiter,
                    identity: identity,
                    request: request,
                    operation: operation
                )
            }
        } onCancel: {
            Task {
                await self.cancelLogicalWaiter(waiterId)
            }
        }
    }

    func snapshot() -> BridgeGitReadSchedulerSnapshot {
        var queued: [BridgeGitReadOperationClass: Int] = [:]
        var running: [BridgeGitReadOperationClass: Int] = [:]
        var draining: [BridgeGitReadOperationClass: Int] = [:]
        var waiterCount = 0
        var coalescedWaiterCount = 0
        var deadlineCount = 0
        var worktreeKeys: Set<BridgeGitReadWorktreeKey> = []

        for operation in operationsByIdentity.values {
            switch operation.phase {
            case .queued:
                queued[operation.identity.operationClass, default: 0] += 1
            case .running:
                running[operation.identity.operationClass, default: 0] += 1
            case .draining:
                draining[operation.identity.operationClass, default: 0] += 1
            }
            waiterCount += operation.waiters.count
            coalescedWaiterCount += max(0, operation.totalWaiterCount - 1)
            deadlineCount += operation.waiters.values.count { $0.deadline != nil }
            worktreeKeys.insert(operation.identity.worktreeKey)
        }

        return BridgeGitReadSchedulerSnapshot(
            lifecycle: lifecycle,
            queuedCountByOperationClass: queued,
            runningCountByOperationClass: running,
            drainingCountByOperationClass: draining,
            activeOperationIds: Set(identityByOperationId.keys),
            occupiedSlotIds: Set(operationIdBySlotId.keys),
            logicalWaiterCount: waiterCount,
            coalescedLogicalWaiterCount: coalescedWaiterCount,
            scheduledDeadlineCount: deadlineCount,
            admittedWorktreeKeys: worktreeKeys,
            paneActivityCount: paneActivityByPaneKey.count,
            fairnessHistoryCount: lastStartOrderByWorktreeAndClass.values.reduce(0) {
                $0 + $1.count
            }
        )
    }

    func shutdown() async {
        guard lifecycle != .closed else { return }
        if lifecycle == .active {
            lifecycle = .closing
            paneActivityByPaneKey.removeAll(keepingCapacity: false)
            lastStartOrderByWorktreeAndClass.removeAll(keepingCapacity: false)
            failQueuedOperationsForShutdown()
            abandonRunningWaitersForShutdown()
            finishShutdownIfDrained()
        }
        guard lifecycle != .closed else { return }
        await withCheckedContinuation { continuation in
            shutdownWaiters.append(continuation)
        }
    }

    private func enqueue<ReturnValue: Sendable>(
        waiter: LogicalWaiter,
        identity: OperationIdentity,
        request: BridgeGitReadRequest,
        operation: @escaping @Sendable () async throws -> ReturnValue
    ) {
        guard lifecycle == .active else {
            waiter.fail(BridgeGitReadSchedulerError.closed)
            return
        }
        if var existing = operationsByIdentity[identity] {
            guard existing.waiters.count < topology.maximumLogicalWaiterCountPerOperation else {
                waiter.fail(BridgeGitReadSchedulerError.capacityReached)
                return
            }
            let scheduledWaiter = scheduleDeadline(for: waiter, request: request)
            operationIdentityByWaiterId[waiter.id] = identity
            existing.waiters[waiter.id] = scheduledWaiter
            existing.totalWaiterCount += 1
            operationsByIdentity[identity] = existing
            emit(.coalesced, operation: existing)
            return
        }

        let queuedOperationCount = operationsByIdentity.values.count { operation in
            guard operation.identity.operationClass == request.operationClass else { return false }
            if case .queued = operation.phase { return true }
            return false
        }
        guard
            queuedOperationCount
                < (topology.maximumQueuedOperationCountByClass[request.operationClass] ?? 0)
        else {
            waiter.fail(BridgeGitReadSchedulerError.capacityReached)
            return
        }

        let scheduledWaiter = scheduleDeadline(for: waiter, request: request)
        operationIdentityByWaiterId[waiter.id] = identity

        let operationId = nextOperationId
        nextOperationId &+= 1
        let enqueueOrder = nextOrder
        nextOrder &+= 1
        let body: OperationBody = {
            do {
                return .success(ErasedValue(value: try await operation()))
            } catch {
                return .failure(ErasedError(error: error))
            }
        }
        let operationState = OperationState(
            id: operationId,
            identity: identity,
            enqueueOrder: enqueueOrder,
            enqueueInstant: ContinuousClock().now,
            body: body,
            phase: .queued,
            waiters: [waiter.id: scheduledWaiter],
            totalWaiterCount: 1
        )
        operationsByIdentity[identity] = operationState
        identityByOperationId[operationId] = identity
        emit(.queued, operation: operationState)
        drainQueuedOperations()
    }

    private func scheduleDeadline(
        for waiter: LogicalWaiter,
        request: BridgeGitReadRequest
    ) -> LogicalWaiter {
        var scheduledWaiter = waiter
        scheduledWaiter.deadline = deadlineScheduler.schedule(after: request.deadline) { [weak self] in
            guard let self else { return }
            Task {
                await self.timeoutLogicalWaiter(waiter.id)
            }
        }
        return scheduledWaiter
    }

    private func timeoutLogicalWaiter(_ waiterId: UInt64) {
        finishLogicalWaiter(waiterId, error: BridgeGitReadSchedulerError.timedOut, eventKind: .logicalTimeout)
    }

    private func cancelLogicalWaiter(_ waiterId: UInt64) {
        guard operationIdentityByWaiterId[waiterId] != nil else { return }
        finishLogicalWaiter(waiterId, error: CancellationError(), eventKind: .logicalCancellation)
    }

    private func finishLogicalWaiter(
        _ waiterId: UInt64,
        error: Error,
        eventKind: BridgeGitReadSchedulerEventKind
    ) {
        guard let identity = operationIdentityByWaiterId.removeValue(forKey: waiterId),
            var operation = operationsByIdentity[identity],
            let waiter = operation.waiters.removeValue(forKey: waiterId)
        else { return }

        waiter.deadline?.cancel()
        waiter.fail(error)
        operationsByIdentity[identity] = operation
        emit(eventKind, operation: operation)

        guard operation.waiters.isEmpty else {
            return
        }

        switch operation.phase {
        case .queued:
            removeOperation(operation)
            drainQueuedOperations()
        case .running(let slotId):
            operation.phase = .draining(slotId)
            operationsByIdentity[identity] = operation
            emit(.draining, operation: operation, slotId: slotId)
        case .draining:
            operationsByIdentity[identity] = operation
        }
    }

    private func drainQueuedOperations() {
        guard lifecycle == .active else { return }
        for operationClass in BridgeGitReadOperationClass.allCases {
            for slotId in freeSlots(for: operationClass) {
                guard let identity = nextQueuedIdentity(for: operationClass),
                    var operation = operationsByIdentity[identity]
                else { break }
                operation.phase = .running(slotId)
                operationsByIdentity[identity] = operation
                operationIdBySlotId[slotId] = operation.id
                lastStartOrderByWorktreeAndClass[operationClass, default: [:]][identity.worktreeKey] = nextOrder
                nextOrder &+= 1
                emit(.started, operation: operation, slotId: slotId)
                let body = operation.body
                let operationId = operation.id
                operationTasksById[operationId] = Task {
                    let result = await body()
                    self.physicalOperationReturned(operationId: operationId, result: result)
                }
            }
        }
    }

    private func freeSlots(for operationClass: BridgeGitReadOperationClass) -> [BridgeGitReadSlotID] {
        (topology.slotsByOperationClass[operationClass] ?? []).filter {
            operationIdBySlotId[$0] == nil
        }
    }

    private func nextQueuedIdentity(for operationClass: BridgeGitReadOperationClass) -> OperationIdentity? {
        let runningWorktrees = Set(
            operationsByIdentity.values.compactMap { operation -> BridgeGitReadWorktreeKey? in
                guard operation.identity.operationClass == operationClass else { return nil }
                switch operation.phase {
                case .running, .draining:
                    return operation.identity.worktreeKey
                case .queued:
                    return nil
                }
            }
        )
        let lastStarts = lastStartOrderByWorktreeAndClass[operationClass] ?? [:]
        return operationsByIdentity.values
            .filter { operation in
                guard operation.identity.operationClass == operationClass,
                    !operation.waiters.isEmpty,
                    !runningWorktrees.contains(operation.identity.worktreeKey)
                else { return false }
                if case .queued = operation.phase { return true }
                return false
            }
            .min { lhs, rhs in
                let lhsRank = activityRank(for: lhs.identity.worktreeKey)
                let rhsRank = activityRank(for: rhs.identity.worktreeKey)
                if lhsRank != rhsRank { return lhsRank > rhsRank }
                let lhsLastStart = lastStarts[lhs.identity.worktreeKey]
                let rhsLastStart = lastStarts[rhs.identity.worktreeKey]
                if lhsLastStart != rhsLastStart {
                    return (lhsLastStart ?? 0) < (rhsLastStart ?? 0)
                }
                return lhs.enqueueOrder < rhs.enqueueOrder
            }?.identity
    }

    private func activityRank(for worktreeKey: BridgeGitReadWorktreeKey) -> BridgeGitReadActivityRank {
        paneActivityByPaneKey.values
            .filter { $0.worktreeKey == worktreeKey }
            .map(\.rank)
            .max() ?? .unranked
    }

    private func physicalOperationReturned(operationId: UInt64, result: ErasedResult) {
        guard let identity = identityByOperationId[operationId],
            let operation = operationsByIdentity[identity]
        else { return }
        emit(.physicallyReturned, operation: operation, slotId: slotId(for: operation.phase))
        operationTasksById.removeValue(forKey: operationId)

        for waiter in operation.waiters.values {
            waiter.deadline?.cancel()
            operationIdentityByWaiterId.removeValue(forKey: waiter.id)
            switch result {
            case .success(let value):
                waiter.succeed(value)
            case .failure(let error):
                waiter.fail(error.error)
            }
        }

        if let slotId = slotId(for: operation.phase) {
            operationIdBySlotId.removeValue(forKey: slotId)
            removeOperation(operation)
            emit(.slotReleased, operation: operation, slotId: slotId)
        } else {
            removeOperation(operation)
        }
        if lifecycle == .active {
            drainQueuedOperations()
        } else {
            finishShutdownIfDrained()
        }
    }

    private func slotId(for phase: OperationPhase) -> BridgeGitReadSlotID? {
        switch phase {
        case .queued:
            return nil
        case .running(let slotId), .draining(let slotId):
            return slotId
        }
    }

    private func removeOperation(_ operation: OperationState) {
        operationsByIdentity.removeValue(forKey: operation.identity)
        identityByOperationId.removeValue(forKey: operation.id)
        for waiter in operation.waiters.values {
            waiter.deadline?.cancel()
            operationIdentityByWaiterId.removeValue(forKey: waiter.id)
        }
    }

    private func failQueuedOperationsForShutdown() {
        let queuedOperations = operationsByIdentity.values.filter {
            if case .queued = $0.phase { return true }
            return false
        }
        for operation in queuedOperations {
            for waiter in operation.waiters.values {
                waiter.fail(BridgeGitReadSchedulerError.closed)
            }
            removeOperation(operation)
        }
    }

    private func abandonRunningWaitersForShutdown() {
        let activeIdentities = Array(operationsByIdentity.keys)
        for identity in activeIdentities {
            guard var operation = operationsByIdentity[identity] else { continue }
            guard let slotId = slotId(for: operation.phase) else { continue }
            for waiter in operation.waiters.values {
                waiter.deadline?.cancel()
                operationIdentityByWaiterId.removeValue(forKey: waiter.id)
                waiter.fail(BridgeGitReadSchedulerError.closed)
            }
            operation.waiters.removeAll()
            operation.phase = .draining(slotId)
            operationsByIdentity[identity] = operation
            emit(.draining, operation: operation, slotId: slotId)
        }
    }

    private func finishShutdownIfDrained() {
        guard lifecycle == .closing, operationsByIdentity.isEmpty else { return }
        lifecycle = .closed
        let waiters = shutdownWaiters
        shutdownWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func emit(
        _ kind: BridgeGitReadSchedulerEventKind,
        operation: OperationState,
        slotId: BridgeGitReadSlotID? = nil
    ) {
        guard let eventSink else { return }
        let queueWait: Duration? =
            switch kind {
            case .started:
                operation.enqueueInstant.duration(to: ContinuousClock().now)
            case .queued, .coalesced, .logicalTimeout, .logicalCancellation, .draining,
                .physicallyReturned, .slotReleased:
                nil
            }
        eventSink(
            BridgeGitReadSchedulerEvent(
                kind: kind,
                operationId: operation.id,
                slotId: slotId,
                operationClass: operation.identity.operationClass,
                worktreeKey: operation.identity.worktreeKey,
                activityRank: activityRank(for: operation.identity.worktreeKey),
                queueWait: queueWait,
                snapshot: snapshot()
            )
        )
    }
}
