import Foundation

@testable import AgentStudioBridge

@MainActor
final class AvailabilityReviewPublicationProvider {
    var publication: BridgeReviewCommittedPublication?
}

actor AvailabilityHeldReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    private let source = BridgePaneProductReviewMetadataSource()
    private let holdFirstDelivery: Bool
    private var firstDeliveryPublicationId: UUID?
    private var firstDeliveryWaiters: [CheckedContinuation<UUID, Never>] = []
    private var firstDeliveryRelease: CheckedContinuation<Void, Never>?

    init(holdFirstDelivery: Bool = false) {
        self.holdFirstDelivery = holdFirstDelivery
    }

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext
    ) async throws {
        try await source.open(subscription: subscription, productAdmission: productAdmission)
    }

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        try await source.reserve(
            package: package, publicationId: publicationId, productAdmission: productAdmission
        )
    }

    func deliver(
        publication: BridgeReviewCommittedPublication,
        reservation: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        if holdFirstDelivery && firstDeliveryPublicationId == nil {
            firstDeliveryPublicationId = reservation.publicationId
            let waiters = firstDeliveryWaiters
            firstDeliveryWaiters.removeAll()
            for waiter in waiters { waiter.resume(returning: reservation.publicationId) }
            await withCheckedContinuation { continuation in
                firstDeliveryRelease = continuation
            }
        }
        return try await source.deliver(
            publication: publication, reservation: reservation, productAdmission: productAdmission
        )
    }

    func waitUntilFirstDeliveryStarted() async -> UUID {
        if let firstDeliveryPublicationId { return firstDeliveryPublicationId }
        return await withCheckedContinuation { continuation in
            firstDeliveryWaiters.append(continuation)
        }
    }

    func releaseFirstDelivery() {
        firstDeliveryRelease?.resume()
        firstDeliveryRelease = nil
    }

    func applyViewDemand(_ request: BridgePaneProductReviewViewDemandRequest) async throws
        -> BridgePaneProductReviewViewCapture?
    {
        try await source.applyViewDemand(request)
    }

    func cancel(subscriptionId: String) async {
        await source.cancel(subscriptionId: subscriptionId)
    }
}

actor AvailabilityReviewPublicationTraceRecorder:
    BridgeProductMetadataLifecycleTraceRecording
{
    private(set) var publicationEvents: [BridgeProductReviewMetadataPublicationTraceEvent] = []
    private var reviewBootstrapFinished: BridgeProductMetadataLifecycleTraceEvent?
    private var reviewBootstrapWaiters: [CheckedContinuation<BridgeProductMetadataLifecycleTraceEvent, Never>] = []

    func record(_ event: BridgeProductMetadataLifecycleTraceEvent) {
        guard case .bootstrapFinished = event.stage,
            case .reviewMetadata = event.subscriptionKind,
            case .success = event.result
        else { return }
        reviewBootstrapFinished = event
        let waiters = reviewBootstrapWaiters
        reviewBootstrapWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: event) }
    }

    func waitUntilReviewBootstrapFinished() async -> BridgeProductMetadataLifecycleTraceEvent {
        if let reviewBootstrapFinished { return reviewBootstrapFinished }
        return await withCheckedContinuation { continuation in
            if let reviewBootstrapFinished {
                continuation.resume(returning: reviewBootstrapFinished)
            } else {
                reviewBootstrapWaiters.append(continuation)
            }
        }
    }

    func record(_ event: BridgeProductReviewMetadataPublicationTraceEvent) {
        publicationEvents.append(event)
    }
}
