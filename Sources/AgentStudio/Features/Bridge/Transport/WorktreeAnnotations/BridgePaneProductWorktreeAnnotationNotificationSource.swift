import AgentStudioInfrastructure
import Foundation

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
    private let scope: WorktreeAnnotationSourceResolver.Scope
    private let lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)?

    static let unavailable = BridgePaneAnnotationNotificationSource(
        service: nil,
        scope: { _ in throw WorktreeAnnotationServiceError.unavailable },
        lifecycleTraceRecorder: nil
    )

    init(
        service: WorktreeAnnotationServiceActor?,
        scope: @escaping WorktreeAnnotationSourceResolver.Scope,
        lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)? = nil
    ) {
        self.service = service
        self.scope = scope
        self.lifecycleTraceRecorder = lifecycleTraceRecorder
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        surface: BridgeProductSurface,
        delivery: BridgePaneAnnotationNotificationDelivery
    ) async throws {
        guard let service else { throw WorktreeAnnotationServiceError.unavailable }
        let openedScope = try await scope(surface)
        let observer = await service.registerChangeObserver(scope: openedScope)
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
                service: service,
                scopeKey: openedScope.key
            )

            for await change in observer.stream {
                try Task.checkCancellation()
                guard change.scopeKey == openedScope.key else {
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
                        service: service,
                        scopeKey: openedScope.key
                    )
                case .control(let reason):
                    let event = BridgeProductWorktreeAnnotationEvent.controlChanged(
                        .init(
                            authority: try .init(
                                scopeKey: openedScope.key,
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
                                    authority: .init(
                                        scopeKey: openedScope.key,
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
        service: WorktreeAnnotationServiceActor,
        scopeKey: String
    ) async throws -> Int {
        let capture = try await captureCurrentCatalog(
            service: service,
            surface: context.surface,
            scopeKey: scopeKey
        )
        let publicationContext = DeliveryLifecycleContext(
            deliveryAttempt: context.deliveryAttempt,
            deliveryStartWasRecorded: context.deliveryStartWasRecorded,
            operationCorrelationID: context.operationCorrelationID,
            sourceGeneration: capture.applicationSourceGeneration,
            surface: context.surface
        )
        let authority = try BridgeProductWorktreeAnnotationEvent.Authority(
            scopeKey: scopeKey,
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

    /// Reads the surface's current subjects on every capture, so a Files
    /// membership change is captured under the same scope key.
    private func captureCurrentCatalog(
        service: WorktreeAnnotationServiceActor,
        surface: BridgeProductSurface,
        scopeKey: String
    ) async throws -> WorktreeAnnotationServiceCatalogCapture {
        while true {
            let currentScope = try await scope(surface)
            guard currentScope.key == scopeKey else { throw WorktreeAnnotationServiceError.unavailable }
            do {
                return try await service.captureCatalog(subjects: currentScope.subjects)
            } catch WorktreeAnnotationServiceError.staleSourceEpoch {
                try Task.checkCancellation()
            }
        }
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
