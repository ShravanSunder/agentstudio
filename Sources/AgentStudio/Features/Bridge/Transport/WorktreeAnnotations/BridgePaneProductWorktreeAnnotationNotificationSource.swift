import Foundation

actor BridgePaneAnnotationNotificationSource {
    typealias EventSink = @Sendable (BridgeProductWorktreeAnnotationEvent) async throws -> Void

    private let service: WorktreeAnnotationServiceActor?
    private let worktreeID: String

    static let unavailable = BridgePaneAnnotationNotificationSource(service: nil, worktreeID: "")

    init(service: WorktreeAnnotationServiceActor?, worktreeID: String) {
        self.service = service
        self.worktreeID = worktreeID
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
            try await emit(
                BridgeProductWorktreeAnnotationEvent(
                    sourceGeneration: sourceGeneration,
                    worktreeID: worktreeID
                )
            )
            for await change in observer.stream {
                try Task.checkCancellation()
                guard case .snapshotRequired(let changedWorktreeID) = change,
                    changedWorktreeID == worktreeID,
                    sourceGeneration < BridgeProductWireContract.maximumSafeInteger
                else {
                    throw WorktreeAnnotationServiceError.unavailable
                }
                sourceGeneration += 1
                try await emit(
                    BridgeProductWorktreeAnnotationEvent(
                        sourceGeneration: sourceGeneration,
                        worktreeID: worktreeID
                    )
                )
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
}
