import AgentStudioInfrastructure
import Foundation

enum BridgePaneProductWorktreeAnnotationSourceError: Error, Equatable {
    case unavailable
}

actor BridgePaneProductWorktreeAnnotationSource {
    private struct ProjectionProducer {
        let producerID: UUID
        let task: Task<Void, Never>
    }

    static let unavailable = BridgePaneProductWorktreeAnnotationSource(
        projection: nil,
        contextID: "",
        worktreeID: ""
    )

    let projection: WorktreeAnnotationProjectionAtom?
    let contextID: String
    let worktreeID: String
    private var producerBySubscriptionID: [String: ProjectionProducer] = [:]

    init(
        projection: WorktreeAnnotationProjectionAtom?,
        contextID: String,
        worktreeID: String
    ) {
        self.projection = projection
        self.contextID = contextID
        self.worktreeID = worktreeID
    }

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        surface: BridgeProductSurface,
        emit: @escaping @Sendable (BridgeProductWorktreeAnnotationEvent) async throws -> Void
    ) async throws {
        guard let projection,
            subscription.subscriptionKind
                == (surface == .file ? .fileAnnotations : .reviewAnnotations)
        else {
            throw BridgePaneProductWorktreeAnnotationSourceError.unavailable
        }
        await cancel(subscriptionId: subscription.subscriptionId)
        let snapshots = await MainActor.run {
            projection.snapshots(
                worktreeID: worktreeID,
                contextID: contextID,
                surface: surface
            )
        }
        let producerID = UUIDv7.generate()
        let task = Task { [weak self] in
            do {
                for await snapshot in snapshots {
                    try Task.checkCancellation()
                    for event in try BridgeProductWorktreeAnnotationProjectionPacker.events(
                        snapshot: snapshot,
                        surface: surface
                    ) {
                        try await emit(event)
                    }
                }
            } catch {
                // The coordinator owns subscription recovery. This task only
                // retires the exact source producer after cancellation or an
                // enqueue/construction failure.
            }
            await self?.producerFinished(
                subscriptionID: subscription.subscriptionId,
                producerID: producerID
            )
        }
        producerBySubscriptionID[subscription.subscriptionId] = ProjectionProducer(
            producerID: producerID,
            task: task
        )
    }

    func update(subscription: BridgeProductSubscriptionSnapshot) throws {
        guard
            subscription.subscriptionKind == .fileAnnotations
                || subscription.subscriptionKind == .reviewAnnotations
        else {
            throw BridgePaneProductWorktreeAnnotationSourceError.unavailable
        }
    }

    func cancel(subscriptionId: String) async {
        guard let producer = producerBySubscriptionID.removeValue(forKey: subscriptionId) else {
            return
        }
        producer.task.cancel()
        await producer.task.value
    }

    private func producerFinished(subscriptionID: String, producerID: UUID) {
        guard producerBySubscriptionID[subscriptionID]?.producerID == producerID else { return }
        producerBySubscriptionID.removeValue(forKey: subscriptionID)
    }
}
