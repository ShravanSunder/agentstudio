import AgentStudioInfrastructure
import Foundation

private enum BridgePaneCommentBatchNotification: Sendable {
    case invalidation(Set<WorktreeAnnotationCatalogRange>)
    case resnapshot
    case unavailable

    func merging(displaced: Self) -> Self {
        switch (self, displaced) {
        case (.unavailable, _), (_, .unavailable): .unavailable
        case (.resnapshot, _), (_, .resnapshot): .resnapshot
        case (.invalidation(let newest), .invalidation(let older)):
            .invalidation(newest.union(older))
        }
    }
}

struct BridgePaneAnnotationNotificationDelivery: Sendable {
    typealias Enqueue =
        @Sendable (BridgeProductWorktreeAnnotationEvent, String) async throws ->
        BridgeProductProducerEnqueueResult
    typealias MakeProspectiveMetadataFrame =
        @Sendable (BridgeProductWorktreeAnnotationEvent, String) throws -> BridgeProductMetadataFrame
    typealias WaitUntilObserved = @Sendable (Int) async -> Bool

    let enqueue: Enqueue
    let makeProspectiveMetadataFrame: MakeProspectiveMetadataFrame
    let waitUntilObserved: WaitUntilObserved
}

actor BridgePaneAnnotationNotificationSource {
    private struct DeliveryLifecycleContext {
        let deliveryAttempt: Int
        let deliveryStartWasRecorded: Bool
        let operationCorrelationID: String
        let sourceGeneration: Int
        let surface: BridgeProductSurface
    }

    private let service: WorktreeAnnotationServiceActor?
    private let worktreeID: String
    private let lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)?
    private var batchNotificationByHandle: [String: AsyncStream<BridgePaneCommentBatchNotification>.Continuation] = [:]
    private var pendingResnapshotHandles: Set<String> = []

    static let unavailable = BridgePaneAnnotationNotificationSource(
        service: nil,
        worktreeID: "",
        lifecycleTraceRecorder: nil
    )

    init(
        service: WorktreeAnnotationServiceActor?,
        worktreeID: String,
        lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)? = nil
    ) {
        self.service = service
        self.worktreeID = worktreeID
        self.lifecycleTraceRecorder = lifecycleTraceRecorder
    }

    func admittedWorktreeID() -> String? {
        service == nil ? nil : worktreeID
    }

    func requestBatchResnapshot(handle: String) {
        guard let continuation = batchNotificationByHandle[handle] else {
            pendingResnapshotHandles.insert(handle)
            return
        }
        enqueueBatchNotification(.resnapshot, into: continuation)
    }

    /// N10 observes invalidations before its first current-row capture. Each
    /// complete range read installs through one publisher before the next read.
    func openBatch(
        handle: String,
        deliver: @Sendable (BridgeProductCommentCatalogBatch, BridgeProductBatchMode) async throws -> Void
    ) async throws {
        guard let service else { throw WorktreeAnnotationServiceError.unavailable }
        let capturedWorktreeID = worktreeID
        let observer = await service.registerCatalogInvalidationObserver(worktreeID: capturedWorktreeID)
        let (notifications, notificationContinuation) = AsyncStream.makeStream(
            of: BridgePaneCommentBatchNotification.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        batchNotificationByHandle[handle] = notificationContinuation
        if pendingResnapshotHandles.remove(handle) != nil {
            enqueueBatchNotification(.resnapshot, into: notificationContinuation)
        }
        let forwarder = Task {
            for await invalidation in observer.stream {
                guard invalidation.worktreeID == capturedWorktreeID else {
                    enqueueBatchNotification(.unavailable, into: notificationContinuation)
                    break
                }
                enqueueBatchNotification(.invalidation(invalidation.ranges), into: notificationContinuation)
            }
        }
        let publisher = BridgeProductCommentCatalogPublisher(
            handle: handle,
            readCurrent: { range in
                try await service.captureCurrentCatalogRange(
                    worktreeID: capturedWorktreeID,
                    range: range
                )
            }
        )
        do {
            if let snapshot = try await publisher.captureSnapshot() {
                try await deliver(snapshot, .snapshot)
            }
            for await notification in notifications {
                try Task.checkCancellation()
                switch notification {
                case .resnapshot:
                    guard let snapshot = try await publisher.captureSnapshot() else {
                        throw WorktreeAnnotationServiceError.staleSourceEpoch
                    }
                    try await deliver(snapshot, .snapshot)
                case .invalidation(let ranges):
                    for range in ranges { await publisher.invalidate(range) }
                    while await publisher.pendingDirtyRangeCount() > 0 {
                        guard let batch = try await publisher.captureDirty() else {
                            throw WorktreeAnnotationServiceError.staleSourceEpoch
                        }
                        try await deliver(batch, .change)
                    }
                case .unavailable:
                    throw WorktreeAnnotationServiceError.unavailable
                }
            }
            batchNotificationByHandle.removeValue(forKey: handle)
            notificationContinuation.finish()
            await service.removeCatalogInvalidationObserver(token: observer.token)
            forwarder.cancel()
            await forwarder.value
        } catch {
            batchNotificationByHandle.removeValue(forKey: handle)
            notificationContinuation.finish()
            await service.removeCatalogInvalidationObserver(token: observer.token)
            forwarder.cancel()
            await forwarder.value
            throw error
        }
    }

    private func enqueueBatchNotification(
        _ notification: BridgePaneCommentBatchNotification,
        into continuation: AsyncStream<BridgePaneCommentBatchNotification>.Continuation
    ) {
        if case .dropped(let displaced) = continuation.yield(notification) {
            _ = continuation.yield(notification.merging(displaced: displaced))
        }
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        surface: BridgeProductSurface,
        delivery: BridgePaneAnnotationNotificationDelivery
    ) async throws {
        guard let service else { throw WorktreeAnnotationServiceError.unavailable }
        let observer = await service.registerChangeObserver(worktreeID: worktreeID)
        do {
            let bootstrapContext = DeliveryLifecycleContext(
                deliveryAttempt: 0,
                deliveryStartWasRecorded: false,
                operationCorrelationID: BridgeOperationCorrelation.mintScrubbedID(),
                sourceGeneration: 0,
                surface: surface
            )
            var publishedApplicationSourceGeneration = try await publishCurrentCatalog(
                context: bootstrapContext,
                delivery: delivery,
                service: service
            )

            for await change in observer.stream {
                try Task.checkCancellation()
                guard change.worktreeID == worktreeID else {
                    throw WorktreeAnnotationServiceError.unavailable
                }
                guard change.applicationSourceGeneration > publishedApplicationSourceGeneration else {
                    continue
                }
                let context = DeliveryLifecycleContext(
                    deliveryAttempt: change.deliveryAttempt,
                    deliveryStartWasRecorded: true,
                    operationCorrelationID: change.operationCorrelationID,
                    sourceGeneration: change.applicationSourceGeneration,
                    surface: surface
                )
                switch change.disposition {
                case .catalog:
                    publishedApplicationSourceGeneration = try await publishCurrentCatalog(
                        context: context,
                        delivery: delivery,
                        service: service
                    )
                case .control(let reason):
                    let event = BridgeProductWorktreeAnnotationEvent.controlChanged(
                        .init(
                            authority: try eventAuthority(
                                applicationSourceGeneration: change.applicationSourceGeneration
                            ),
                            reason: controlChangedReason(reason)
                        )
                    )
                    try await deliver(context: context) {
                        _ = try Self.requireEnqueued(
                            try await delivery.enqueue(event, change.operationCorrelationID)
                        )
                    }
                    publishedApplicationSourceGeneration = change.applicationSourceGeneration
                case .content:
                    let orderedSessionRevisions = change.sessionSemanticRevisionByID.sorted {
                        $0.key.rawValue.uuidString < $1.key.rawValue.uuidString
                    }
                    guard !orderedSessionRevisions.isEmpty else {
                        throw WorktreeAnnotationServiceError.unavailable
                    }
                    try await deliver(context: context) {
                        for (sessionID, semanticRevision) in orderedSessionRevisions {
                            let event = BridgeProductWorktreeAnnotationEvent.sessionChanged(
                                try .init(
                                    authority: eventAuthority(
                                        applicationSourceGeneration: change.applicationSourceGeneration
                                    ),
                                    sessionID: sessionID,
                                    semanticRevision: semanticRevision
                                )
                            )
                            _ = try Self.requireEnqueued(
                                try await delivery.enqueue(event, change.operationCorrelationID)
                            )
                        }
                    }
                    publishedApplicationSourceGeneration = change.applicationSourceGeneration
                }
            }
            await service.removeChangeObserver(token: observer.token)
        } catch {
            await service.removeChangeObserver(token: observer.token)
            throw error
        }
    }

    func update(subscription _: BridgeProductSubscriptionSnapshot) throws {}

    func cancel(subscriptionID _: String) async {}

    func closeAndDrain() async {}

    private func publishCurrentCatalog(
        context: DeliveryLifecycleContext,
        delivery: BridgePaneAnnotationNotificationDelivery,
        service: WorktreeAnnotationServiceActor
    ) async throws -> Int {
        let capture = try await captureCurrentCatalog(service: service)
        let publicationContext = DeliveryLifecycleContext(
            deliveryAttempt: context.deliveryAttempt,
            deliveryStartWasRecorded: context.deliveryStartWasRecorded,
            operationCorrelationID: context.operationCorrelationID,
            sourceGeneration: capture.applicationSourceGeneration,
            surface: context.surface
        )
        let authority = try eventAuthority(
            applicationSourceGeneration: capture.applicationSourceGeneration
        )
        let entries = try Self.catalogEntries(from: capture.repositoryCapture)
        let transferID = UUIDv7.generate().uuidString.lowercased()
        try await deliver(context: publicationContext) {
            _ = try await BridgeProductMetadataCatalogWriter<WorktreeAnnotationCatalogEntry>().write(
                entries: entries,
                catalogRevision: capture.applicationSourceGeneration,
                transferID: transferID,
                makeProspectiveMetadataFrame: { transfer in
                    try delivery.makeProspectiveMetadataFrame(
                        .catalog(try .init(authority: authority, transfer: transfer)),
                        context.operationCorrelationID
                    )
                },
                enqueue: { transfer in
                    try await delivery.enqueue(
                        .catalog(try .init(authority: authority, transfer: transfer)),
                        context.operationCorrelationID
                    )
                },
                waitUntilObserved: delivery.waitUntilObserved
            )
        }
        return capture.applicationSourceGeneration
    }

    private func captureCurrentCatalog(
        service: WorktreeAnnotationServiceActor
    ) async throws -> WorktreeAnnotationServiceCatalogCapture {
        while true {
            do {
                return try await service.captureCatalog(worktreeID: worktreeID)
            } catch WorktreeAnnotationServiceError.staleSourceEpoch {
                try Task.checkCancellation()
            }
        }
    }

    private func eventAuthority(
        applicationSourceGeneration: Int
    ) throws -> BridgeProductWorktreeAnnotationEvent.Authority {
        try .init(
            worktreeID: worktreeID,
            applicationSourceGeneration: applicationSourceGeneration
        )
    }

    private static func catalogEntries(
        from capture: WorktreeAnnotationCatalogCapture
    ) throws -> [WorktreeAnnotationCatalogEntry] {
        var entries: [WorktreeAnnotationCatalogEntry] = []
        entries.reserveCapacity(capture.sessions.count + capture.threads.count + capture.messages.count)
        entries.append(
            contentsOf: try capture.sessions.map {
                .session(try .init(sessionID: $0.sessionID, semanticRevision: $0.semanticRevision))
            }
        )
        entries.append(
            contentsOf: try capture.threads.map {
                .thread(
                    try .init(
                        threadID: $0.threadID,
                        sessionID: $0.sessionID,
                        scope: $0.scope,
                        createdOrdinal: $0.createdOrdinal
                    )
                )
            }
        )
        entries.append(
            contentsOf: try capture.messages.map {
                .message(
                    try .init(
                        messageID: $0.messageID,
                        threadID: $0.threadID,
                        ordinal: $0.ordinal
                    )
                )
            }
        )
        return entries
    }

    private func controlChangedReason(
        _ reason: WorktreeAnnotationControlChangeReason
    ) -> BridgeProductWorktreeAnnotationEvent.ControlChangedReason {
        switch reason {
        case .discovery: .discovery
        case .recovery: .recovery
        }
    }

    private static func requireEnqueued(
        _ result: BridgeProductProducerEnqueueResult
    ) throws -> BridgeProductQueuedProducerFrame {
        switch result {
        case .enqueued(let frame):
            frame
        case .queueReset:
            throw BridgeProductMetadataCatalogWriterError.frameQueueReset
        case .rejected(let rejection):
            throw BridgeProductMetadataCatalogWriterError.frameRejected(rejection)
        }
    }

    private func deliver(
        context: DeliveryLifecycleContext,
        operation: () async throws -> Void
    ) async throws {
        if !context.deliveryStartWasRecorded {
            await lifecycleTraceRecorder?.record(
                .init(
                    operationCorrelationID: context.operationCorrelationID,
                    result: .started,
                    sourceGeneration: context.sourceGeneration,
                    stageAttempt: context.deliveryAttempt,
                    stage: .notificationDeliveryStarted,
                    surface: context.surface
                )
            )
        }
        do {
            try await operation()
            await lifecycleTraceRecorder?.record(
                .init(
                    operationCorrelationID: context.operationCorrelationID,
                    result: .success,
                    sourceGeneration: context.sourceGeneration,
                    stageAttempt: context.deliveryAttempt,
                    stage: .notificationDeliveryTerminal,
                    surface: context.surface
                )
            )
        } catch {
            await lifecycleTraceRecorder?.record(
                .init(
                    operationCorrelationID: context.operationCorrelationID,
                    result: .failure,
                    sourceGeneration: context.sourceGeneration,
                    stageAttempt: context.deliveryAttempt,
                    stage: .notificationDeliveryTerminal,
                    surface: context.surface
                )
            )
            throw error
        }
    }
}
