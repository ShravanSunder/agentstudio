import AgentStudioInfrastructure
import Foundation

actor BridgePaneAnnotationNotificationSource {
    typealias EventSink = @Sendable (BridgeProductWorktreeAnnotationEvent) async throws -> Void

    private let service: WorktreeAnnotationServiceActor?
    private let worktreeID: String
    private let lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)?

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

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        surface: BridgeProductSurface,
        emit: @escaping EventSink
    ) async throws {
        guard let service else { throw WorktreeAnnotationServiceError.unavailable }
        let observer = await service.registerChangeObserver(worktreeID: worktreeID)
        do {
            var sourceGeneration = 0
            let bootstrapEvent = try BridgeProductWorktreeAnnotationEvent(
                operationCorrelationID: BridgeOperationCorrelation.mintScrubbedID(),
                sourceGeneration: sourceGeneration,
                worktreeID: worktreeID
            )
            try await emitLifecycleEvent(
                bootstrapEvent,
                deliveryAttempt: 0,
                deliveryStartWasRecorded: false,
                subscription: subscription,
                surface: surface,
                emit: emit
            )
            for await change in observer.stream {
                try Task.checkCancellation()
                guard
                    case .snapshotRequired(
                        let changedWorktreeID,
                        let operationCorrelationID,
                        let deliveryAttempt
                    ) = change,
                    changedWorktreeID == worktreeID,
                    sourceGeneration < BridgeProductWireContract.maximumSafeInteger
                else {
                    throw WorktreeAnnotationServiceError.unavailable
                }
                sourceGeneration += 1
                let event = try BridgeProductWorktreeAnnotationEvent(
                    operationCorrelationID: operationCorrelationID,
                    sourceGeneration: sourceGeneration,
                    worktreeID: worktreeID
                )
                try await emitLifecycleEvent(
                    event,
                    deliveryAttempt: deliveryAttempt,
                    deliveryStartWasRecorded: true,
                    subscription: subscription,
                    surface: surface,
                    emit: emit
                )
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

    private func emitLifecycleEvent(
        _ event: BridgeProductWorktreeAnnotationEvent,
        deliveryAttempt: Int,
        deliveryStartWasRecorded: Bool,
        subscription: BridgeProductSubscriptionSnapshot,
        surface: BridgeProductSurface,
        emit: EventSink
    ) async throws {
        if !deliveryStartWasRecorded {
            await lifecycleTraceRecorder?.record(
                .init(
                    operationCorrelationID: event.operationCorrelationID,
                    result: .started,
                    sourceGeneration: event.sourceGeneration,
                    stageAttempt: deliveryAttempt,
                    stage: .notificationDeliveryStarted,
                    surface: surface
                )
            )
        }
        do {
            try await emit(event)
            await lifecycleTraceRecorder?.record(
                .init(
                    operationCorrelationID: event.operationCorrelationID,
                    result: .success,
                    sourceGeneration: event.sourceGeneration,
                    stageAttempt: deliveryAttempt,
                    stage: .notificationDeliveryTerminal,
                    surface: surface
                )
            )
        } catch {
            await lifecycleTraceRecorder?.record(
                .init(
                    operationCorrelationID: event.operationCorrelationID,
                    result: .failure,
                    sourceGeneration: event.sourceGeneration,
                    stageAttempt: deliveryAttempt,
                    stage: .notificationDeliveryTerminal,
                    surface: surface
                )
            )
            throw error
        }
    }
}
