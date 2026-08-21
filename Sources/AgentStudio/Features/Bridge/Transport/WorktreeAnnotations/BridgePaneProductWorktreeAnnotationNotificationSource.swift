import AgentStudioInfrastructure
import CryptoKit
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
        emit: @escaping EventSink
    ) async throws {
        guard let service,
            subscription.subscriptionKind == .fileAnnotations
                || subscription.subscriptionKind == .reviewAnnotations
        else { throw WorktreeAnnotationServiceError.unavailable }
        let observer = await service.registerChangeObserver(worktreeID: worktreeID)
        do {
            var sourceGeneration = 0
            let bootstrapEvent = try BridgeProductWorktreeAnnotationEvent(
                operationCorrelationID: Self.makeOperationCorrelationID(),
                sourceGeneration: sourceGeneration,
                worktreeID: worktreeID
            )
            try await emitLifecycleEvent(bootstrapEvent, subscription: subscription, emit: emit)
            for await change in observer.stream {
                try Task.checkCancellation()
                guard case .snapshotRequired(let changedWorktreeID) = change,
                    changedWorktreeID == worktreeID,
                    sourceGeneration < BridgeProductWireContract.maximumSafeInteger
                else {
                    throw WorktreeAnnotationServiceError.unavailable
                }
                sourceGeneration += 1
                let event = try BridgeProductWorktreeAnnotationEvent(
                    operationCorrelationID: Self.makeOperationCorrelationID(),
                    sourceGeneration: sourceGeneration,
                    worktreeID: worktreeID
                )
                try await emitLifecycleEvent(event, subscription: subscription, emit: emit)
            }
            await service.removeChangeObserver(token: observer.token)
        } catch {
            await service.removeChangeObserver(token: observer.token)
            throw error
        }
    }

    func update(subscription: BridgeProductSubscriptionSnapshot) throws {
        guard
            subscription.subscriptionKind == .fileAnnotations
                || subscription.subscriptionKind == .reviewAnnotations
        else {
            throw WorktreeAnnotationServiceError.unavailable
        }
    }

    func cancel(subscriptionID _: String) async {}

    func closeAndDrain() async {}

    private static func makeOperationCorrelationID() -> String {
        SHA256.hash(data: Data(UUIDv7.generate().uuidString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func emitLifecycleEvent(
        _ event: BridgeProductWorktreeAnnotationEvent,
        subscription: BridgeProductSubscriptionSnapshot,
        emit: EventSink
    ) async throws {
        let surface: BridgeProductSurface =
            subscription.subscriptionKind == .fileAnnotations ? .file : .review
        await lifecycleTraceRecorder?.record(
            .init(
                operationCorrelationID: event.operationCorrelationID,
                result: .success,
                sourceGeneration: event.sourceGeneration,
                stage: .invalidationAdmitted,
                surface: surface
            )
        )
        do {
            try await emit(event)
            await lifecycleTraceRecorder?.record(
                .init(
                    operationCorrelationID: event.operationCorrelationID,
                    result: .success,
                    sourceGeneration: event.sourceGeneration,
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
                    stage: .notificationDeliveryTerminal,
                    surface: surface
                )
            )
            throw error
        }
    }
}
