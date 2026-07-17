import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product Review metadata availability lifecycle")
struct BridgeProductReviewAvailabilityTests {
    @Test("Review open before package publication stays accepted and emits initial metadata later")
    func reviewOpenBeforePackagePublicationStaysAccepted() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let reviewSource = BridgePaneProductReviewMetadataSource()
        let traceRecorder = AvailabilityReviewPublicationTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: reviewSource,
            lifecycleTraceRecorder: traceRecorder
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )

        // Act
        let acceptedFrame = try await openAvailabilityReviewSubscription(
            coordinator: coordinator,
            harness: harness,
            pump: pump
        )
        for _ in 0..<100 where (await harness.session.producerSnapshot()).queuedFrameCount == 0 {
            await Task.yield()
        }
        let queuedFrameCountBeforePublication =
            (await harness.session.producerSnapshot()).queuedFrameCount
        let reviewPackage = try availabilityReviewPackageFixture()
        let traceContext = try BridgeTraceContext(
            traceId: "55555555555555555555555555555555",
            spanId: "6666666666666666",
            parentSpanId: nil,
            sampled: true
        )
        let reservation = try await coordinator.reserveReviewPublication(
            package: reviewPackage,
            publicationId: availabilityCommittedPublication(reviewPackage).publicationId,
            productAdmission: harness.productAdmission.context
        )
        let publication = availabilityCommittedPublication(reviewPackage)
        let deliveryProbe = AvailabilityDeliveryDispositionProbe()
        let delivery = Task {
            let disposition = await coordinator.deliverReviewPublication(
                publication,
                reservation: reservation,
                productAdmission: harness.productAdmission.context,
                traceContext: traceContext
            )
            await deliveryProbe.record(disposition)
            return disposition
        }
        let sourceAcceptedFrame = try await pullAvailabilityMetadataFrame(from: pump)
        #expect(await deliveryProbe.disposition == nil)
        let snapshotFrame = try await pullAvailabilityMetadataFrame(from: pump)
        let deliveryDisposition = await delivery.value

        // Assert
        guard case .subscriptionAccepted(let accepted) = acceptedFrame,
            case .subscriptionData(let sourceAcceptedData) = sourceAcceptedFrame,
            case .reviewMetadata(.sourceAccepted(let sourceAccepted)) = sourceAcceptedData.data,
            case .subscriptionData(let snapshotData) = snapshotFrame,
            case .reviewMetadata(.snapshot(let snapshot)) = snapshotData.data
        else {
            Issue.record("Expected Review accepted followed by sourceAccepted and snapshot after publication")
            return
        }
        #expect(accepted.frameIdentity.streamSequence == 1)
        #expect(queuedFrameCountBeforePublication == 0)
        #expect(sourceAcceptedData.frameIdentity.streamSequence == 2)
        #expect(snapshotData.frameIdentity.streamSequence == 3)
        #expect(sourceAccepted.identity.packageId == reviewPackage.packageId)
        #expect(snapshot.identity.packageId == reviewPackage.packageId)
        #expect(deliveryDisposition == .transportAcknowledged)
        #expect(
            await traceRecorder.publicationEvents == [
                .started(retainedSubscriptions: 1, traceContext: traceContext),
                .completed(
                    receipt: BridgeReviewMetadataPublicationReceipt(
                        retained: 1,
                        publishedSubscriptions: 1,
                        emittedEvents: 2,
                        superseded: 0,
                        finalFrames: [
                            BridgeReviewMetadataFinalFrame(
                                sequence: 3,
                                subscriptionId: "review-subscription-1"
                            )
                        ]
                    ),
                    traceContext: traceContext
                ),
            ]
        )
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("producer rejection returns failed without claiming observation")
    func producerRejectionReturnsFailedWithoutObservation() async throws {
        let traceContext = try BridgeTraceContext(
            traceId: "77777777777777777777777777777777",
            spanId: "8888888888888888",
            parentSpanId: nil,
            sampled: true
        )

        let result = try await exerciseAvailabilityPublicationFailure(
            .producerRejection,
            traceContext: traceContext
        )

        #expect(!result.reservationFailed)
        #expect(result.deliveryDisposition == .failed)
        #expect(
            result.traceEvents == [
                .started(retainedSubscriptions: 1, traceContext: traceContext),
                .failed(
                    failure: .producerRejection,
                    retainedSubscriptions: 1,
                    traceContext: traceContext
                ),
            ]
        )
    }

    @Test("Review event construction failure rejects reservation before delivery")
    func eventConstructionFailureRejectsReservationBeforeDelivery() async throws {
        let traceContext = try BridgeTraceContext(
            traceId: "99999999999999999999999999999999",
            spanId: "aaaaaaaaaaaaaaaa",
            parentSpanId: nil,
            sampled: true
        )

        let result = try await exerciseAvailabilityPublicationFailure(
            .eventConstruction,
            traceContext: traceContext
        )

        #expect(result.reservationFailed)
        #expect(result.deliveryDisposition == nil)
        #expect(result.traceEvents.isEmpty)
    }

    @Test("Review delivery with zero subscriptions is deferred")
    func reviewDeliveryWithZeroSubscriptionsIsDeferred() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let traceRecorder = AvailabilityReviewPublicationTraceRecorder()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgePaneProductReviewMetadataSource(),
            lifecycleTraceRecorder: traceRecorder
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let reviewPackage = try availabilityReviewPackageFixture()
        let reservation = try await coordinator.reserveReviewPublication(
            package: reviewPackage,
            publicationId: availabilityCommittedPublication(reviewPackage).publicationId,
            productAdmission: harness.productAdmission.context
        )

        // Act
        let disposition = await coordinator.deliverReviewPublication(
            availabilityCommittedPublication(reviewPackage),
            reservation: reservation,
            productAdmission: harness.productAdmission.context
        )

        // Assert
        #expect(disposition == .deferred)
        #expect((await harness.session.producerSnapshot()).queuedFrameCount == 0)
        #expect(
            await traceRecorder.publicationEvents == [
                .started(retainedSubscriptions: 0, traceContext: nil)
            ]
        )
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("committed successor supersedes suspended predecessor delivery before enqueue")
    func committedSuccessorSupersedesSuspendedPredecessorDelivery() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let reviewPackage = try availabilityReviewPackageFixture()
        let predecessor = availabilityCommittedPublication(reviewPackage)
        let successorPublicationId = UUID(uuidString: "33333333-3333-7333-8333-333333333333")!
        let currentPublication = await CoordinatorCurrentReviewPublication(
            publicationId: predecessor.publicationId
        )
        let source = CoordinatorSupersededDeliveryReviewMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: source,
            isReviewPublicationCurrent: { publicationId, productAdmission in
                currentPublication.matches(publicationId, productAdmission: productAdmission)
            }
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        _ = try await openAvailabilityReviewSubscription(
            coordinator: coordinator,
            harness: harness,
            pump: pump
        )
        let reservation = try await coordinator.reserveReviewPublication(
            package: reviewPackage,
            publicationId: predecessor.publicationId,
            productAdmission: harness.productAdmission.context
        )
        let deliveryProbe = CoordinatorReviewDeliveryDispositionProbe()
        let delivery = Task {
            let disposition = await coordinator.deliverReviewPublication(
                predecessor,
                reservation: reservation,
                productAdmission: harness.productAdmission.context
            )
            await deliveryProbe.record(disposition)
            return disposition
        }
        await source.waitUntilDeliveryStarted()

        // Act
        await MainActor.run {
            currentPublication.publicationId = successorPublicationId
        }
        await source.releaseDelivery()
        for _ in 0..<1000 {
            let queuedFrameCount = (await harness.session.producerSnapshot()).queuedFrameCount
            let disposition = await deliveryProbe.disposition
            if queuedFrameCount > 0 || disposition != nil {
                break
            }
            await Task.yield()
        }
        let queuedFrameCountAfterSuccessorCommit =
            (await harness.session.producerSnapshot()).queuedFrameCount
        if queuedFrameCountAfterSuccessorCommit > 0 {
            _ = try await pullAvailabilityMetadataFrame(from: pump)
        }
        let disposition = await delivery.value

        // Assert
        #expect(queuedFrameCountAfterSuccessorCommit == 0)
        #expect(disposition == .deferred)
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("transient queue reset repairs current publication once on the same stream")
    func transientQueueResetRepairsCurrentPublicationOnce() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let reviewPackage = try availabilityReviewPackageFixture()
        let publication = availabilityCommittedPublication(reviewPackage)
        let currentPublication = await CoordinatorCurrentReviewPublication(
            publicationId: publication.publicationId
        )
        let source = CoordinatorRepairingReviewMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: source,
            isReviewPublicationCurrent: { publicationId, productAdmission in
                currentPublication.matches(publicationId, productAdmission: productAdmission)
            }
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        _ = try await openAvailabilityReviewSubscription(
            coordinator: coordinator,
            harness: harness,
            pump: pump
        )
        let reservation = try await coordinator.reserveReviewPublication(
            package: reviewPackage,
            publicationId: publication.publicationId,
            productAdmission: harness.productAdmission.context
        )

        // Act
        let delivery = Task {
            await coordinator.deliverReviewPublication(
                publication,
                reservation: reservation,
                productAdmission: harness.productAdmission.context
            )
        }
        await source.waitUntilDeliverAttempt(2)
        let deliveryAttempts = await source.deliveryAttempts

        #expect(deliveryAttempts == 2)
        guard deliveryAttempts == 2 else {
            await coordinator.uninstall(lease: lease)
            #expect(await pump.cancel())
            return
        }
        _ = try await pullAvailabilityMetadataFrame(from: pump)
        let disposition = await delivery.value

        // Assert
        #expect(disposition == .transportAcknowledged)
        #expect((await harness.session.producerSnapshot()).pendingProducerObservationPacingWaiterCount == 0)
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("maximum final frame observation covers earlier finals acknowledged before waiting")
    func maximumFinalFrameObservationCoversEarlierAcknowledgements() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let source = CoordinatorEarlyFinalFramesSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: source
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        _ = try await openAvailabilityReviewSubscription(
            coordinator: coordinator,
            harness: harness,
            pump: pump
        )
        let reviewPackage = try availabilityReviewPackageFixture()
        let reservation = try await coordinator.reserveReviewPublication(
            package: reviewPackage,
            publicationId: availabilityCommittedPublication(reviewPackage).publicationId,
            productAdmission: harness.productAdmission.context
        )
        let delivery = Task {
            await coordinator.deliverReviewPublication(
                availabilityCommittedPublication(reviewPackage),
                reservation: reservation,
                productAdmission: harness.productAdmission.context
            )
        }
        await source.waitUntilFinalFramesEnqueued()

        // Act
        _ = try await pullAvailabilityMetadataFrame(from: pump)
        _ = try await pullAvailabilityMetadataFrame(from: pump)
        await source.releaseDeliveryReceipt()
        let disposition = await delivery.value
        let producerSnapshot = await harness.session.producerSnapshot()

        // Assert
        #expect(disposition == .transportAcknowledged)
        #expect(producerSnapshot.pendingProducerObservationPacingWaiterCount == 0)
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
    }

    @Test("failing Review publication cannot reset a replacement metadata stream")
    func failingReviewPublicationCannotResetReplacementMetadataStream() async throws {
        // Arrange
        let firstHarness = try await BridgeProductSessionLifecycleHarness.opened()
        let firstLease = try await firstHarness.admitMetadataFrames(through: 0)
        let firstPump = BridgeProductSchemeFramePump(
            session: firstHarness.session,
            producerLease: firstLease,
            productAdmission: firstHarness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let source = AvailabilitySuspendedFailingReviewMetadataSource()
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: source
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: firstLease,
            productAdmission: firstHarness.productAdmission.context,
            session: firstHarness.session
        )
        _ = try await openAvailabilityReviewSubscription(
            coordinator: coordinator,
            harness: firstHarness,
            pump: firstPump
        )
        let reviewPackage = try availabilityReviewPackageFixture()
        let reservation = try await coordinator.reserveReviewPublication(
            package: reviewPackage,
            publicationId: availabilityCommittedPublication(reviewPackage).publicationId,
            productAdmission: firstHarness.productAdmission.context
        )
        let failingPublication = Task {
            await coordinator.deliverReviewPublication(
                availabilityCommittedPublication(reviewPackage),
                reservation: reservation,
                productAdmission: firstHarness.productAdmission.context
            )
        }
        await source.waitUntilDeliverStarted()

        let replacementHarness = try await BridgeProductSessionLifecycleHarness.opened()
        let replacementLease = try await replacementHarness.admitMetadataFrames(through: 0)
        let replacementPump = BridgeProductSchemeFramePump(
            session: replacementHarness.session,
            producerLease: replacementLease,
            productAdmission: replacementHarness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        await coordinator.install(
            request: try availabilityMetadataStreamRequest(),
            lease: replacementLease,
            productAdmission: replacementHarness.productAdmission.context,
            session: replacementHarness.session
        )
        let replacementAcceptedFrame = try await openAvailabilityReviewSubscription(
            coordinator: coordinator,
            harness: replacementHarness,
            pump: replacementPump
        )

        // Act
        await source.releaseDeliverFailure()
        let failingDisposition = await failingPublication.value

        // Assert
        guard case .subscriptionAccepted = replacementAcceptedFrame else {
            Issue.record("Expected the replacement Review subscription to be accepted")
            return
        }
        #expect(failingDisposition == .deferred)
        #expect((await replacementHarness.session.producerSnapshot()).queuedFrameCount == 0)
        await coordinator.uninstall(lease: replacementLease)
        #expect(await firstPump.cancel())
        #expect(await replacementPump.cancel())
    }
}

private enum AvailabilityCoordinatorTestError: Error {
    case expectedFrame
    case publicationFailed
}

private enum AvailabilityReviewPublicationFailureMode: Sendable {
    case eventConstruction
    case producerRejection
}

private struct AvailabilityReviewPublicationFailureResult {
    let reservationFailed: Bool
    let deliveryDisposition: BridgeReviewPublicationDeliveryDisposition?
    let traceEvents: [BridgeProductReviewMetadataPublicationTraceEvent]
}

private actor AvailabilityDeliveryDispositionProbe {
    private(set) var disposition: BridgeReviewPublicationDeliveryDisposition?

    func record(_ disposition: BridgeReviewPublicationDeliveryDisposition) {
        self.disposition = disposition
    }
}

private actor AvailabilityReviewPublicationTraceRecorder:
    BridgeProductMetadataLifecycleTraceRecording
{
    private(set) var publicationEvents: [BridgeProductReviewMetadataPublicationTraceEvent] = []

    func record(_: BridgeProductMetadataLifecycleTraceEvent) {}

    func record(_ event: BridgeProductReviewMetadataPublicationTraceEvent) {
        publicationEvents.append(event)
    }
}

private actor AvailabilityThrowingReviewMetadataSource:
    BridgePaneProductReviewMetadataProducing
{
    private let failureMode: AvailabilityReviewPublicationFailureMode

    init(failureMode: AvailabilityReviewPublicationFailureMode) {
        self.failureMode = failureMode
    }

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        switch failureMode {
        case .eventConstruction:
            throw BridgePaneProductReviewMetadataSourceError.metadataEventExceedsByteLimit
        case .producerRejection:
            return availabilityReservation(for: package, publicationId: publicationId)
        }
    }

    func deliver(
        package _: BridgeReviewPackage,
        reservation _: BridgeReviewMetadataPublicationReservation,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        throw BridgePaneProductMetadataCoordinatorError.producerRejected(.unknownLease)
    }

    func cancel(subscriptionId _: String) {}
}

private actor AvailabilitySuspendedFailingReviewMetadataSource:
    BridgePaneProductReviewMetadataProducing
{
    private var deliverStarted = false
    private var deliverStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var deliverRelease: CheckedContinuation<Void, Never>?

    func open(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func update(
        subscription _: BridgeProductSubscriptionSnapshot,
        productAdmission _: BridgeProductAdmissionContext,
        emit _: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {}

    func reserve(
        package: BridgeReviewPackage,
        publicationId: UUID,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgeReviewMetadataPublicationReservation {
        availabilityReservation(for: package, publicationId: publicationId)
    }

    func deliver(
        package _: BridgeReviewPackage,
        reservation _: BridgeReviewMetadataPublicationReservation,
        productAdmission _: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        deliverStarted = true
        let waiters = deliverStartedWaiters
        deliverStartedWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            deliverRelease = continuation
        }
        throw AvailabilityCoordinatorTestError.publicationFailed
    }

    func cancel(subscriptionId _: String) {}

    func waitUntilDeliverStarted() async {
        if deliverStarted { return }
        await withCheckedContinuation { continuation in
            deliverStartedWaiters.append(continuation)
        }
    }

    func releaseDeliverFailure() {
        deliverRelease?.resume()
        deliverRelease = nil
    }
}

private func openAvailabilityReviewSubscription(
    coordinator: BridgePaneProductMetadataCoordinator,
    harness: BridgeProductSessionLifecycleHarness,
    pump: BridgeProductSchemeFramePump
) async throws -> BridgeProductMetadataFrame {
    let openRequest = try bridgeProductLifecycleControlRequest(
        bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 2, epoch: 1)
    )
    let token = try #require(availabilityControlExecutionToken(try await harness.begin(openRequest)))
    #expect(await harness.session.claimControlProviderDispatch(token: token))
    let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
        correlating: openRequest,
        interestSha256: BridgeProductSubscriptionInterestState.reviewMetadata(interests: []).sha256Hex()
    )
    let effect = try await harness.session.completeControl(
        token: token,
        exactResponseBytes: try JSONEncoder().encode(response)
    )
    let acceptedFrame = try await pullAvailabilityMetadataFrame(from: pump)
    await coordinator.apply(
        effect,
        productAdmission: harness.productAdmission.context
    )
    await harness.session.settleControlProviderDispatch(token: token)
    return acceptedFrame
}

private func pullAvailabilityMetadataFrame(
    from pump: BridgeProductSchemeFramePump
) async throws -> BridgeProductMetadataFrame {
    guard case .frame(let delivery) = await pump.nextFrame() else {
        throw AvailabilityCoordinatorTestError.expectedFrame
    }
    #expect(await pump.acknowledgeFrameConsumed(delivery.receipt))
    let decoder = try BridgeProductMetadataFrameDecoder()
    let frames = try decoder.append(delivery.frame.data)
    return try #require(frames.first)
}

private func exerciseAvailabilityPublicationFailure(
    _ failureMode: AvailabilityReviewPublicationFailureMode,
    traceContext: BridgeTraceContext
) async throws -> AvailabilityReviewPublicationFailureResult {
    let harness = try await BridgeProductSessionLifecycleHarness.opened()
    let lease = try await harness.admitMetadataFrames(through: 0)
    let pump = BridgeProductSchemeFramePump(
        session: harness.session,
        producerLease: lease,
        productAdmission: harness.productAdmission.context,
        acknowledgeLifecycle: { _ in true }
    )
    let traceRecorder = AvailabilityReviewPublicationTraceRecorder()
    let coordinator = BridgePaneProductMetadataCoordinator(
        fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
        reviewMetadataSource: AvailabilityThrowingReviewMetadataSource(failureMode: failureMode),
        lifecycleTraceRecorder: traceRecorder
    )
    await coordinator.install(
        request: try availabilityMetadataStreamRequest(),
        lease: lease,
        productAdmission: harness.productAdmission.context,
        session: harness.session
    )
    _ = try await openAvailabilityReviewSubscription(
        coordinator: coordinator,
        harness: harness,
        pump: pump
    )

    let reviewPackage = try availabilityReviewPackageFixture()
    let reservation: BridgeReviewMetadataPublicationReservation
    do {
        reservation = try await coordinator.reserveReviewPublication(
            package: reviewPackage,
            publicationId: availabilityCommittedPublication(reviewPackage).publicationId,
            productAdmission: harness.productAdmission.context
        )
    } catch {
        let traceEvents = await traceRecorder.publicationEvents
        await coordinator.uninstall(lease: lease)
        #expect(await pump.cancel())
        return AvailabilityReviewPublicationFailureResult(
            reservationFailed: true,
            deliveryDisposition: nil,
            traceEvents: traceEvents
        )
    }
    let deliveryDisposition = await coordinator.deliverReviewPublication(
        availabilityCommittedPublication(reviewPackage),
        reservation: reservation,
        productAdmission: harness.productAdmission.context,
        traceContext: traceContext
    )
    let traceEvents = await traceRecorder.publicationEvents
    await coordinator.uninstall(lease: lease)
    #expect(await pump.cancel())
    return AvailabilityReviewPublicationFailureResult(
        reservationFailed: false,
        deliveryDisposition: deliveryDisposition,
        traceEvents: traceEvents
    )
}

private func availabilityCommittedPublication(
    _ package: BridgeReviewPackage
) -> BridgeReviewCommittedPublication {
    BridgeReviewCommittedPublication(
        publicationId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        package: package,
        delta: nil,
        contentHandles: []
    )
}

private func availabilityReservation(
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

private func availabilityControlExecutionToken(
    _ admission: BridgeProductSessionControlAdmission
) -> BridgeProductControlAdmissionToken? {
    guard case .execute(let token, _) = admission else { return nil }
    return token
}

private func availabilityReviewPackageFixture() throws -> BridgeReviewPackage {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let fixtureURL = projectRoot.appending(
        path: "Tests/BridgeContractFixtures/valid/bridge-review-package.json"
    )
    return try JSONDecoder().decode(
        BridgeReviewPackage.self,
        from: Data(contentsOf: fixtureURL)
    )
}

private func availabilityMetadataStreamRequest() throws -> BridgeProductMetadataStreamRequest {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": "metadata-stream-1",
            "paneSessionId": "pane-session-1",
            "resumeFromStreamSequence": NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": "worker-instance-1",
        ],
        options: [.sortedKeys]
    )
    return try BridgeProductStrictJSON.decode(BridgeProductMetadataStreamRequest.self, from: data)
}
