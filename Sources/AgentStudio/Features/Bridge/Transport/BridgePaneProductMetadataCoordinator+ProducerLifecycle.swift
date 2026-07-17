import Foundation

struct BridgePaneProductMetadataProducerExecutionContext: Sendable {
    let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    let productAdmission: BridgeProductAdmissionContext
    let session: BridgeProductSession
}

struct BridgePaneProductMetadataProducerTaskLifecycle {
    private enum ProducerTaskKind: Sendable {
        case bootstrap
        case interest
    }

    private struct BootstrapProducerTask: Sendable {
        let taskId: UUID
        let task: Task<Void, Never>
    }

    private struct ProducerTaskStart {
        let kind: ProducerTaskKind
        let subscriptionId: String
        let subscriptionKind: BridgeProductSubscriptionKind
        let executionContext: BridgePaneProductMetadataProducerExecutionContext
        let taskFinished: @Sendable (String, UUID) async -> Void
        let operation: @Sendable (BridgeTraceContext?) async throws -> Void
    }

    private let lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)?
    private var bootstrapTaskBySubscriptionId: [String: BootstrapProducerTask] = [:]
    private var interestTasksBySubscriptionId: [String: [UUID: Task<Void, Never>]] = [:]

    init(lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)?) {
        self.lifecycleTraceRecorder = lifecycleTraceRecorder
    }

    func hasBootstrapTask(subscriptionId: String) -> Bool {
        bootstrapTaskBySubscriptionId[subscriptionId] != nil
    }

    mutating func startBootstrapTask(
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind,
        executionContext: BridgePaneProductMetadataProducerExecutionContext,
        taskFinished: @escaping @Sendable (String, UUID) async -> Void,
        operation: @escaping @Sendable (BridgeTraceContext?) async throws -> Void
    ) {
        startTask(
            ProducerTaskStart(
                kind: .bootstrap,
                subscriptionId: subscriptionId,
                subscriptionKind: subscriptionKind,
                executionContext: executionContext,
                taskFinished: taskFinished,
                operation: operation
            )
        )
    }

    mutating func startInterestTask(
        subscriptionId: String,
        subscriptionKind: BridgeProductSubscriptionKind,
        executionContext: BridgePaneProductMetadataProducerExecutionContext,
        taskFinished: @escaping @Sendable (String, UUID) async -> Void,
        operation: @escaping @Sendable (BridgeTraceContext?) async throws -> Void
    ) {
        startTask(
            ProducerTaskStart(
                kind: .interest,
                subscriptionId: subscriptionId,
                subscriptionKind: subscriptionKind,
                executionContext: executionContext,
                taskFinished: taskFinished,
                operation: operation
            )
        )
    }

    private mutating func startTask(_ request: ProducerTaskStart) {
        let kind = request.kind
        let subscriptionId = request.subscriptionId
        let subscriptionKind = request.subscriptionKind
        let productAdmission = request.executionContext.productAdmission
        let foregroundWorkAdmission = request.executionContext.foregroundWorkAdmission
        let session = request.executionContext.session
        let taskFinished = request.taskFinished
        let operation = request.operation
        let taskId = UUID()
        let bootstrapPredecessor =
            kind == .interest ? bootstrapTaskBySubscriptionId[subscriptionId]?.task : nil
        let lifecycleTraceRecorder = lifecycleTraceRecorder
        let task = Task {
            let traceContext = BridgeTraceContextFactory.live.makeRootContext()
            var terminalResult = BridgeProductMetadataLifecycleTraceEvent.Result.success
            await lifecycleTraceRecorder?.record(
                .init(
                    stage: .bootstrapStarted,
                    subscriptionKind: subscriptionKind,
                    result: .success,
                    traceContext: traceContext
                )
            )
            do {
                if let bootstrapPredecessor {
                    await bootstrapPredecessor.value
                    try Task.checkCancellation()
                }
                try await operation(traceContext)
            } catch {
                terminalResult = .failure
                let foregroundWorkWasInvalidated =
                    BridgePaneProductMetadataCoordinator.isForegroundWorkInvalidation(error)
                if Task.isCancelled || foregroundWorkWasInvalidated {
                    await lifecycleTraceRecorder?.record(
                        .init(
                            stage: .producerCancelled,
                            subscriptionKind: subscriptionKind,
                            result: .failure,
                            failureReason: Task.isCancelled ? .taskCancellation : .cancellation,
                            traceContext: traceContext
                        )
                    )
                } else {
                    await lifecycleTraceRecorder?.record(
                        .init(
                            stage: .producerFailed,
                            subscriptionKind: subscriptionKind,
                            result: .failure,
                            failureReason: BridgePaneProductMetadataCoordinator.producerFailureReason(
                                for: error
                            ),
                            traceContext: traceContext
                        )
                    )
                    let resetResult = try? await session.enqueueSubscriptionReset(
                        subscriptionId: subscriptionId,
                        reason: .staleSource,
                        productAdmission: productAdmission,
                        foregroundWorkAdmission: foregroundWorkAdmission
                    )
                    if case .enqueued? = resetResult {
                        await lifecycleTraceRecorder?.record(
                            .init(
                                stage: .subscriptionResetEnqueued,
                                subscriptionKind: subscriptionKind,
                                result: .queued,
                                traceContext: traceContext
                            )
                        )
                    }
                }
            }
            await taskFinished(subscriptionId, taskId)
            await lifecycleTraceRecorder?.record(
                .init(
                    stage: .bootstrapFinished,
                    subscriptionKind: subscriptionKind,
                    result: terminalResult,
                    traceContext: traceContext
                )
            )
        }
        switch kind {
        case .bootstrap:
            bootstrapTaskBySubscriptionId[subscriptionId]?.task.cancel()
            bootstrapTaskBySubscriptionId[subscriptionId] = .init(
                taskId: taskId,
                task: task
            )
        case .interest:
            interestTasksBySubscriptionId[subscriptionId, default: [:]][taskId] = task
        }
    }

    func recordEnqueued(
        _ event: BridgeProductFileMetadataEvent,
        traceContext: BridgeTraceContext?
    ) async {
        let traceEvent: BridgeProductMetadataLifecycleTraceEvent
        switch event {
        case .sourceAccepted:
            traceEvent = .init(
                stage: .sourceAcceptedEnqueued,
                subscriptionKind: .fileMetadata,
                result: .queued,
                traceContext: traceContext,
                sourceGeneration: event.sourceGeneration
            )
        case .treeWindow(let window):
            traceEvent = .init(
                stage: .windowEnqueued,
                subscriptionKind: .fileMetadata,
                result: .queued,
                traceContext: traceContext,
                sourceGeneration: event.sourceGeneration,
                rowCount: window.rows.count,
                isFinalWindow: window.finalWindow
            )
        case .treeDelta, .statusPatch, .descriptorReady, .invalidated:
            return
        }
        await lifecycleTraceRecorder?.record(traceEvent)
    }

    func recordEnqueued(
        _ event: BridgeProductReviewMetadataEvent,
        traceContext: BridgeTraceContext?
    ) async {
        let stage: BridgeProductMetadataLifecycleTraceEvent.Stage
        switch event {
        case .sourceAccepted:
            stage = .sourceAcceptedEnqueued
        case .snapshot, .window:
            stage = .windowEnqueued
        case .delta, .invalidated, .reset:
            return
        }
        await lifecycleTraceRecorder?.record(
            .init(
                stage: stage,
                subscriptionKind: .reviewMetadata,
                result: .queued,
                traceContext: traceContext,
                sourceGeneration: event.generation
            )
        )
    }

    mutating func bootstrapTaskFinished(subscriptionId: String, taskId: UUID) {
        guard bootstrapTaskBySubscriptionId[subscriptionId]?.taskId == taskId else { return }
        bootstrapTaskBySubscriptionId.removeValue(forKey: subscriptionId)
    }

    mutating func interestTaskFinished(subscriptionId: String, taskId: UUID) {
        interestTasksBySubscriptionId[subscriptionId]?.removeValue(forKey: taskId)
        if interestTasksBySubscriptionId[subscriptionId]?.isEmpty == true {
            interestTasksBySubscriptionId.removeValue(forKey: subscriptionId)
        }
    }

    mutating func takeAndCancelProducerTasks(
        subscriptionId: String
    ) -> [Task<Void, Never>] {
        var tasks: [Task<Void, Never>] = []
        if let bootstrapTask = bootstrapTaskBySubscriptionId.removeValue(
            forKey: subscriptionId
        )?.task {
            tasks.append(bootstrapTask)
        }
        tasks.append(contentsOf: takeAndCancelInterestTasks(subscriptionId: subscriptionId))
        for task in tasks { task.cancel() }
        return tasks
    }

    mutating func cancelInterestTasks(subscriptionId: String) {
        let tasks = takeAndCancelInterestTasks(subscriptionId: subscriptionId)
        for task in tasks { task.cancel() }
    }

    private mutating func takeAndCancelInterestTasks(
        subscriptionId: String
    ) -> [Task<Void, Never>] {
        let tasks = interestTasksBySubscriptionId.removeValue(forKey: subscriptionId) ?? [:]
        return Array(tasks.values)
    }

    mutating func takeAndCancelEveryProducerTask() -> [Task<Void, Never>] {
        let bootstrapTasks = bootstrapTaskBySubscriptionId.values.map(\.task)
        let interestTasks = interestTasksBySubscriptionId.values.flatMap(\.values)
        bootstrapTaskBySubscriptionId.removeAll(keepingCapacity: false)
        interestTasksBySubscriptionId.removeAll(keepingCapacity: false)
        for task in bootstrapTasks { task.cancel() }
        for task in interestTasks { task.cancel() }
        return bootstrapTasks + interestTasks
    }

    static func drain(_ tasks: [Task<Void, Never>]) async {
        for task in tasks {
            await task.value
        }
    }
}
