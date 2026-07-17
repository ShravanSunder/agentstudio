import Foundation

@testable import AgentStudio

actor CoordinatorTrackingReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    private let source = BridgePaneProductReviewMetadataSource()
    private var didRegisterOpen = false
    private var openWaiters: [CheckedContinuation<Void, Never>] = []
    private var publicationReceipt: BridgeReviewMetadataPublicationReceipt?
    private var publicationReceiptWaiters: [CheckedContinuation<BridgeReviewMetadataPublicationReceipt, Never>] = []

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        try await source.open(
            subscription: subscription,
            productAdmission: productAdmission,
            emit: emit
        )
        didRegisterOpen = true
        let waiters = openWaiters
        openWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        try await source.update(
            subscription: subscription,
            productAdmission: productAdmission,
            emit: emit
        )
    }

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        try await source.reserve(
            package: package,
            publicationId: publicationId,
            productAdmission: productAdmission
        )
    }

    func deliver(
        package: BridgeReviewPackage,
        reservation: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        let outcome = try await source.deliver(
            package: package,
            reservation: reservation,
            productAdmission: productAdmission
        )
        if case .delivered(let receipt) = outcome {
            publicationReceipt = receipt
            let waiters = publicationReceiptWaiters
            publicationReceiptWaiters.removeAll(keepingCapacity: false)
            for waiter in waiters { waiter.resume(returning: receipt) }
        }
        return outcome
    }

    func cancel(subscriptionId: String) async {
        await source.cancel(subscriptionId: subscriptionId)
    }

    func waitUntilOpenRegistered() async {
        guard !didRegisterOpen else { return }
        await withCheckedContinuation { continuation in
            openWaiters.append(continuation)
        }
    }

    func waitUntilPublicationReceipt() async -> BridgeReviewMetadataPublicationReceipt {
        if let publicationReceipt { return publicationReceipt }
        return await withCheckedContinuation { continuation in
            publicationReceiptWaiters.append(continuation)
        }
    }
}

actor CoordinatorReviewDeliveryDispositionProbe {
    private(set) var disposition: BridgeReviewPublicationDeliveryDisposition?

    func record(_ disposition: BridgeReviewPublicationDeliveryDisposition) {
        self.disposition = disposition
    }
}

@MainActor
final class CoordinatorCurrentReviewPublication {
    var publicationId: UUID

    init(publicationId: UUID) {
        self.publicationId = publicationId
    }

    func matches(
        _ publicationId: UUID,
        productAdmission _: BridgeProductAdmissionContext
    ) -> Bool {
        self.publicationId == publicationId
    }
}

actor CoordinatorSupersededDeliveryReviewMetadataSource:
    BridgePaneProductReviewMetadataProducing
{
    private var deliveryRelease: CheckedContinuation<Void, Never>?
    private var deliveryStarted = false
    private var deliveryStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var emit: BridgePaneProductReviewMetadataEventSink?

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) {
        self.emit = emit
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) {
        self.emit = emit
    }

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgeReviewMetadataPublicationReservation {
        coordinatorReviewReservation(for: package, publicationId: publicationId)
    }

    func deliver(
        package: BridgeReviewPackage,
        reservation _: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        deliveryStarted = true
        let waiters = deliveryStartedWaiters
        deliveryStartedWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            deliveryRelease = continuation
        }
        guard let emit else {
            throw CoordinatorReviewPublicationTestError.missingSink
        }
        let enqueueResult = try await emit(
            coordinatorReviewMetadataEvent(for: package),
            productAdmission
        )
        guard case .enqueued(let frame) = enqueueResult else {
            throw CoordinatorReviewPublicationTestError.enqueueRejected
        }
        return .delivered(
            .init(
                retained: 1,
                publishedSubscriptions: 1,
                emittedEvents: 1,
                superseded: 0,
                finalFrames: [
                    .init(sequence: frame.sequence, subscriptionId: "review-subscription-1")
                ]
            ))
    }

    func cancel(subscriptionId _: String) {
        releaseDelivery()
    }

    func releaseDelivery() {
        deliveryRelease?.resume()
        deliveryRelease = nil
    }

    func waitUntilDeliveryStarted() async {
        guard !deliveryStarted else { return }
        await withCheckedContinuation { continuation in
            deliveryStartedWaiters.append(continuation)
        }
    }
}

actor CoordinatorRepairingReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    private var deliverAttemptCount = 0
    private var deliverAttemptWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var emit: BridgePaneProductReviewMetadataEventSink?

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) {
        self.emit = emit
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) {
        self.emit = emit
    }

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgeReviewMetadataPublicationReservation {
        coordinatorReviewReservation(for: package, publicationId: publicationId)
    }

    func deliver(
        package: BridgeReviewPackage,
        reservation _: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        deliverAttemptCount += 1
        let attempt = deliverAttemptCount
        for waiter in deliverAttemptWaiters.removeValue(forKey: attempt) ?? [] {
            waiter.resume()
        }
        if attempt == 1 {
            throw BridgePaneProductMetadataCoordinatorError.producerQueueReset
        }
        guard let emit else {
            throw CoordinatorReviewPublicationTestError.missingSink
        }
        let enqueueResult = try await emit(
            coordinatorReviewMetadataEvent(for: package),
            productAdmission
        )
        guard case .enqueued(let frame) = enqueueResult else {
            throw CoordinatorReviewPublicationTestError.enqueueRejected
        }
        return .delivered(
            .init(
                retained: 1,
                publishedSubscriptions: 1,
                emittedEvents: 1,
                superseded: 0,
                finalFrames: [
                    .init(sequence: frame.sequence, subscriptionId: "review-subscription-1")
                ]
            ))
    }

    func cancel(subscriptionId _: String) {}

    func waitUntilDeliverAttempt(_ attempt: Int) async {
        guard deliverAttemptCount < attempt else { return }
        await withCheckedContinuation { continuation in
            deliverAttemptWaiters[attempt, default: []].append(continuation)
        }
    }

    var deliveryAttempts: Int { deliverAttemptCount }
}

actor CoordinatorEarlyFinalFramesSource:
    BridgePaneProductReviewMetadataProducing
{
    private var deliveryRelease: CheckedContinuation<Void, Never>?
    private var finalFrames: [BridgeReviewMetadataFinalFrame]?
    private var finalFramesWaiters: [CheckedContinuation<Void, Never>] = []
    private var emit: BridgePaneProductReviewMetadataEventSink?

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) {
        self.emit = emit
    }

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) {
        self.emit = emit
    }

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission _: BridgeProductAdmissionContext
    ) -> BridgeReviewMetadataPublicationReservation {
        coordinatorReviewReservation(for: package, publicationId: publicationId)
    }

    func deliver(
        package: BridgeReviewPackage,
        reservation _: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        guard let emit else {
            throw CoordinatorReviewPublicationTestError.missingSink
        }
        let firstResult = try await emit(
            coordinatorReviewMetadataEvent(for: package),
            productAdmission
        )
        let secondResult = try await emit(
            coordinatorReviewMetadataEvent(for: package),
            productAdmission
        )
        guard case .enqueued(let firstFrame) = firstResult,
            case .enqueued(let secondFrame) = secondResult
        else {
            throw CoordinatorReviewPublicationTestError.enqueueRejected
        }
        let deliveredFinalFrames = [
            BridgeReviewMetadataFinalFrame(
                sequence: firstFrame.sequence,
                subscriptionId: "review-subscription-1"
            ),
            BridgeReviewMetadataFinalFrame(
                sequence: secondFrame.sequence,
                subscriptionId: "review-subscription-1"
            ),
        ]
        finalFrames = deliveredFinalFrames
        let waiters = finalFramesWaiters
        finalFramesWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            deliveryRelease = continuation
        }
        return .delivered(
            .init(
                retained: 1,
                publishedSubscriptions: 1,
                emittedEvents: 2,
                superseded: 0,
                finalFrames: deliveredFinalFrames
            ))
    }

    func cancel(subscriptionId _: String) {
        releaseDeliveryReceipt()
    }

    func releaseDeliveryReceipt() {
        deliveryRelease?.resume()
        deliveryRelease = nil
    }

    func waitUntilFinalFramesEnqueued() async {
        guard finalFrames == nil else { return }
        await withCheckedContinuation { continuation in
            finalFramesWaiters.append(continuation)
        }
    }
}

func coordinatorReviewPackageFixture() throws -> BridgeReviewPackage {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let fixtureURL = projectRoot.appending(
        path: "Tests/BridgeContractFixtures/valid/bridge-review-package.json"
    )
    return try JSONDecoder().decode(
        BridgeReviewPackage.self,
        from: Data(contentsOf: fixtureURL)
    )
}

func coordinatorCommittedReviewPublication(
    _ package: BridgeReviewPackage
) -> BridgeReviewCommittedPublication {
    BridgeReviewCommittedPublication(
        publicationId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        package: package,
        delta: nil,
        contentHandles: []
    )
}

func coordinatorReviewReservation(
    for package: BridgeReviewPackage,
    publicationId: UUID
) -> BridgeReviewMetadataPublicationReservation {
    BridgeReviewMetadataPublicationReservation(
        reservationId: UUID(uuidString: "22222222-2222-7222-8222-222222222222")!,
        packageId: package.packageId,
        publicationId: publicationId,
        reviewGeneration: package.reviewGeneration,
        revision: package.revision
    )
}

private enum CoordinatorReviewPublicationTestError: Error {
    case enqueueRejected
    case missingSink
}

private func coordinatorReviewMetadataEvent(
    for package: BridgeReviewPackage
) throws -> BridgeProductReviewMetadataEvent {
    try .init(
        generation: package.reviewGeneration.rawValue,
        packageId: package.packageId,
        publicationId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        revision: package.revision,
        sourceIdentity: package.query.queryId
    )
}
