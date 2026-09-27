import Foundation

@testable import AgentStudioBridge

@MainActor
final class AvailabilityReviewPublicationProvider {
    var publication: BridgeReviewCommittedPublication?
}

actor AvailabilityHeldReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    private let source = BridgePaneProductReviewMetadataSource()
    private let holdFirstDelivery: Bool
    private var didStartFirstDelivery = false
    private var firstDeliveryWaiters: [CheckedContinuation<Void, Never>] = []
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
        if holdFirstDelivery && !didStartFirstDelivery {
            didStartFirstDelivery = true
            let waiters = firstDeliveryWaiters
            firstDeliveryWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            await withCheckedContinuation { continuation in
                firstDeliveryRelease = continuation
            }
        }
        return try await source.deliver(
            publication: publication, reservation: reservation, productAdmission: productAdmission
        )
    }

    func waitUntilFirstDeliveryStarted() async {
        if didStartFirstDelivery { return }
        await withCheckedContinuation { continuation in
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
    private var publicationCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var reviewBootstrapFinished = false
    private var reviewBootstrapWaiters: [CheckedContinuation<Void, Never>] = []

    func record(_ event: BridgeProductMetadataLifecycleTraceEvent) {
        guard case .bootstrapFinished = event.stage,
            case .reviewMetadata = event.subscriptionKind,
            case .success = event.result
        else { return }
        reviewBootstrapFinished = true
        let waiters = reviewBootstrapWaiters
        reviewBootstrapWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func waitUntilReviewBootstrapFinished() async {
        if reviewBootstrapFinished { return }
        await withCheckedContinuation { continuation in
            if reviewBootstrapFinished {
                continuation.resume()
            } else {
                reviewBootstrapWaiters.append(continuation)
            }
        }
    }

    func record(_ event: BridgeProductReviewMetadataPublicationTraceEvent) {
        publicationEvents.append(event)
        guard case .completed = event else { return }
        let waiters = publicationCompletionWaiters
        publicationCompletionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilPublicationCompleted() async {
        if hasCompletedPublication { return }
        await withCheckedContinuation { continuation in
            if hasCompletedPublication {
                continuation.resume()
            } else {
                publicationCompletionWaiters.append(continuation)
            }
        }
    }

    private var hasCompletedPublication: Bool {
        publicationEvents.contains { event in
            if case .completed = event { return true }
            return false
        }
    }
}
