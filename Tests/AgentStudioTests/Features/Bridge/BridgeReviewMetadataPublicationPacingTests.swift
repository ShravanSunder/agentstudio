import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite(
    "Bridge Review metadata publication pacing",
    .serialized,
    .timeLimit(.minutes(1))
)
struct BridgeReviewMetadataPublicationPacingTests {
    @Test("slow metadata consumer receives every Review window without producer rejection")
    func slowMetadataConsumerReceivesCompleteReviewPublication() async throws {
        let fixture = try await ReviewMetadataPacingFixture.make()
        do {
            try await fixture.requireCompleteSlowConsumerDelivery()
            await fixture.shutdown()
        } catch {
            await fixture.shutdown()
            throw error
        }
    }

    @Test("foreground suspension during a nonfinal Review window defers and replays completely")
    func foregroundSuspensionDuringNonfinalWindowReplaysCompletely() async throws {
        let fixture = try await ReviewMetadataPacingFixture.make()
        do {
            try await fixture.requireNonfinalSuspensionAndCompleteReplay()
            await fixture.shutdown()
        } catch {
            await fixture.shutdown()
            throw error
        }
    }

    @Test("foreground invalidation before waiter registration defers without a late waiter")
    func foregroundInvalidationBeforeWaiterRegistrationDefersWithoutLateWaiter() async throws {
        let pause = PausingReviewLifecycleRecorder.make()
        let fixture = try await ReviewMetadataPacingFixture.make(lifecycleTraceRecorder: pause.recorder)
        do {
            try await fixture.requireInvalidationBeforeRegistrationDefers(pause: pause)
            await fixture.shutdown()
        } catch {
            await fixture.shutdown()
            throw error
        }
    }
}

private struct ReviewMetadataPacingFixture {
    let activityCoordinator: BridgePaneRefreshAdmissionCoordinator
    let coordinator: BridgePaneProductMetadataCoordinator
    let deliveryEvents: AsyncStream<ReviewMetadataDeliveryEvent>
    let deliveryEventContinuation: AsyncStream<ReviewMetadataDeliveryEvent>.Continuation
    let foregroundAdmission: BridgePaneRefreshWorkAdmission
    let harness: BridgeProductSessionLifecycleHarness
    let heldPresentation: BridgeProductProducerFrameDelivery
    let lease: BridgeProductProducerLease
    let openToken: BridgeProductControlAdmissionToken
    let pump: BridgeProductSchemeFramePump
    let publication: BridgeReviewCommittedPublication
    let reservation: BridgeReviewMetadataPublicationReservation

    @MainActor
    static func make(
        lifecycleTraceRecorder: (any BridgeProductMetadataLifecycleTraceRecording)? = nil
    ) async throws -> Self {
        let (deliveryEvents, deliveryEventContinuation) =
            AsyncStream<ReviewMetadataDeliveryEvent>.makeStream()
        let harness = try await BridgeProductSessionLifecycleHarness.opened(
            producerQueueLimits: try pacingQueueLimits(),
            producerObservationPacingRegistrationObserver: { lease, sequence in
                deliveryEventContinuation.yield(
                    .observationRequested(lease: lease, sequence: sequence)
                )
            }
        )
        let lease = try await harness.admitMetadataFrames(through: 0)
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            productAdmission: harness.productAdmission.context,
            acknowledgeLifecycle: { _ in true }
        )
        let activityCoordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        let foregroundAdmission = try #require(activityCoordinator.acquireForegroundWork())
        let (sourceOpenedEvents, sourceOpenedContinuation) = AsyncStream<Void>.makeStream()
        let replayProvider = PacingReviewPublicationProvider()
        let reviewSource = PacingReviewMetadataSource(
            deliveryEventContinuation: deliveryEventContinuation,
            sourceOpenedContinuation: sourceOpenedContinuation
        )
        let coordinator = BridgePaneProductMetadataCoordinator(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: reviewSource,
            reviewPublicationReplay: { _ in replayProvider.publication },
            refreshWorkAdmissionSource: activityCoordinator.workAdmissionSource,
            lifecycleTraceRecorder: lifecycleTraceRecorder
        )
        await coordinator.install(
            request: try coordinatorMetadataStreamRequest(),
            lease: lease,
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )
        let openToken = try await openPacingReviewSubscription(
            coordinator: coordinator,
            harness: harness,
            pump: pump
        )
        do {
            var sourceOpenedIterator = sourceOpenedEvents.makeAsyncIterator()
            guard await sourceOpenedIterator.next() != nil else {
                throw ReviewMetadataPacingTestError.sourceDidNotOpen
            }
            sourceOpenedContinuation.finish()
            let heldPresentation = try await holdPacingPanePresentation(
                coordinator: coordinator,
                pump: pump
            )
            let reviewPackage = try makePacingReviewPackage(itemCount: 130)
            let publication = coordinatorCommittedReviewPublication(reviewPackage)
            let reservation = try await coordinator.reserveReviewPublication(
                package: reviewPackage,
                publicationId: publication.publicationId,
                productAdmission: harness.productAdmission.context,
                foregroundWorkAdmission: foregroundAdmission
            )
            replayProvider.publication = publication
            return Self(
                activityCoordinator: activityCoordinator,
                coordinator: coordinator,
                deliveryEvents: deliveryEvents,
                deliveryEventContinuation: deliveryEventContinuation,
                foregroundAdmission: foregroundAdmission,
                harness: harness,
                heldPresentation: heldPresentation,
                lease: lease,
                openToken: openToken,
                pump: pump,
                publication: publication,
                reservation: reservation
            )
        } catch {
            sourceOpenedContinuation.finish()
            deliveryEventContinuation.finish()
            await harness.session.settleControlProviderDispatch(token: openToken)
            await coordinator.uninstall(lease: lease)
            _ = await pump.cancel()
            throw error
        }
    }

    @MainActor
    func requireCompleteSlowConsumerDelivery() async throws {
        let deliveryTask = Task {
            let disposition = await coordinator.deliverReviewPublication(
                publication,
                reservation: reservation,
                productAdmission: harness.productAdmission.context,
                foregroundWorkAdmission: foregroundAdmission
            )
            deliveryEventContinuation.yield(.deliveryCompleted(disposition))
            return disposition
        }
        do {
            let received = try await consumePacedReviewFrames()
            #expect(received.sourceAccepted)
            #expect(received.finalWindow)
            #expect(received.itemCount == publication.package.orderedItemIds.count)
            #expect(received.orderedItemIds == publication.package.orderedItemIds)
            #expect(await deliveryTask.value == .transportAcknowledged)
            let producerSnapshot = await harness.session.producerSnapshot()
            #expect(producerSnapshot.queuedFrameCount == 0)
            #expect(producerSnapshot.inFlightFrameReceiptCount == 0)
            #expect(producerSnapshot.pendingProducerObservationPacingWaiterCount == 0)
        } catch {
            deliveryTask.cancel()
            _ = await deliveryTask.value
            throw error
        }
    }

    @MainActor
    func requireNonfinalSuspensionAndCompleteReplay() async throws {
        #expect(await pump.acknowledgeFrameConsumed(heldPresentation.receipt))
        let interruptedDelivery = Task {
            await coordinator.deliverReviewPublication(
                publication,
                reservation: reservation,
                productAdmission: harness.productAdmission.context,
                foregroundWorkAdmission: foregroundAdmission
            )
        }
        var deliveryEventIterator = deliveryEvents.makeAsyncIterator()
        let sourceRegistration = try await requireObservationRequest(from: &deliveryEventIterator)
        let sourceDelivery = try await requireMetadataFrameDelivery(from: pump)
        #expect(sourceRegistration.lease == lease)
        #expect(sourceRegistration.sequence == sourceDelivery.receipt.sequence)
        #expect(await pump.acknowledgeFrameConsumed(sourceDelivery.receipt))

        let nonfinalRegistration = try await requireObservationRequest(from: &deliveryEventIterator)
        let nonfinalDelivery = try await requireMetadataFrameDelivery(from: pump)
        #expect(nonfinalRegistration.lease == lease)
        #expect(nonfinalRegistration.sequence == nonfinalDelivery.receipt.sequence)
        guard case .subscriptionData(let nonfinalData) = try decodeMetadataFrame(nonfinalDelivery),
            case .snapshot(let nonfinalWindow)? = nonfinalData.data.reviewMetadataEvent
        else {
            throw ReviewMetadataPacingTestError.expectedNonfinalWindow
        }
        #expect(!nonfinalWindow.itemWindow.finalWindow)
        #expect(!nonfinalWindow.treeWindow.finalWindow)

        activityCoordinator.applyActivity(.loadedHidden)
        await coordinator.suspendForegroundWork()
        #expect(await interruptedDelivery.value == .deferred)
        let suspendedSnapshot = await harness.session.producerSnapshot()
        #expect(suspendedSnapshot.pendingProducerObservationPacingWaiterCount == 0)
        #expect(await pump.acknowledgeFrameConsumed(nonfinalDelivery.receipt))

        activityCoordinator.applyActivity(.foreground)
        await coordinator.resumeForegroundWork()
        var replayed = ReceivedReviewMetadata()
        while !replayed.finalWindow {
            let registration = try await requireObservationRequest(from: &deliveryEventIterator)
            let delivery = try await requireMetadataFrameDelivery(from: pump)
            #expect(registration.lease == lease)
            #expect(registration.sequence == delivery.receipt.sequence)
            replayed.accept(try decodeMetadataFrame(delivery))
            #expect(await pump.acknowledgeFrameConsumed(delivery.receipt))
        }
        #expect(replayed.sourceAccepted)
        #expect(replayed.itemCount == publication.package.orderedItemIds.count)
        #expect(replayed.orderedItemIds == publication.package.orderedItemIds)
        #expect((await harness.session.producerSnapshot()).pendingProducerObservationPacingWaiterCount == 0)
    }

    @MainActor
    func requireInvalidationBeforeRegistrationDefers(
        pause: PausingReviewLifecycleRecorder.Fixture
    ) async throws {
        #expect(await pump.acknowledgeFrameConsumed(heldPresentation.receipt))
        let deliveryTask = Task {
            let disposition = await coordinator.deliverReviewPublication(
                publication,
                reservation: reservation,
                productAdmission: harness.productAdmission.context,
                foregroundWorkAdmission: foregroundAdmission
            )
            deliveryEventContinuation.yield(.deliveryCompleted(disposition))
            return disposition
        }
        do {
            var deliveryIterator = deliveryEvents.makeAsyncIterator()
            let sourceRegistration = try await requireObservationRequest(from: &deliveryIterator)
            let sourceDelivery = try await requireMetadataFrameDelivery(from: pump)
            #expect(sourceRegistration.sequence == sourceDelivery.receipt.sequence)
            #expect(await pump.acknowledgeFrameConsumed(sourceDelivery.receipt))

            var pauseIterator = pause.pausedEvents.makeAsyncIterator()
            guard await pauseIterator.next(isolation: #isolation) != nil else {
                throw ReviewMetadataPacingTestError.lifecyclePauseDidNotStart
            }
            activityCoordinator.applyActivity(.loadedHidden)
            await coordinator.suspendForegroundWork()
            pause.releaseContinuation.yield()

            guard let terminalEvent = await deliveryIterator.next(isolation: #isolation) else {
                throw ReviewMetadataPacingTestError.deliveryEventStreamEnded
            }
            guard case .deliveryCompleted(let disposition) = terminalEvent else {
                throw ReviewMetadataPacingTestError.lateObservationRegistration(terminalEvent)
            }
            #expect(disposition == .deferred)
            #expect((await harness.session.producerSnapshot()).pendingProducerObservationPacingWaiterCount == 0)
            let nonfinalDelivery = try await requireMetadataFrameDelivery(from: pump)
            try requireNonfinalSnapshot(try decodeMetadataFrame(nonfinalDelivery))
            #expect(await pump.acknowledgeFrameConsumed(nonfinalDelivery.receipt))

            activityCoordinator.applyActivity(.foreground)
            await coordinator.resumeForegroundWork()
            let replayed = try await consumeReplayFrames(iterator: &deliveryIterator)
            #expect(replayed.sourceAccepted)
            #expect(replayed.orderedItemIds == publication.package.orderedItemIds)
            #expect(await deliveryTask.value == .deferred)
        } catch {
            pause.releaseContinuation.yield()
            deliveryTask.cancel()
            _ = await deliveryTask.value
            throw error
        }
    }

    @MainActor
    private func consumeReplayFrames(
        iterator: inout AsyncStream<ReviewMetadataDeliveryEvent>.Iterator
    ) async throws -> ReceivedReviewMetadata {
        var received = ReceivedReviewMetadata()
        while !received.finalWindow {
            let registration = try await requireObservationRequest(from: &iterator)
            let delivery = try await requireMetadataFrameDelivery(from: pump)
            #expect(registration.lease == lease)
            #expect(registration.sequence == delivery.receipt.sequence)
            received.accept(try decodeMetadataFrame(delivery))
            #expect(await pump.acknowledgeFrameConsumed(delivery.receipt))
        }
        return received
    }

    @MainActor
    private func consumePacedReviewFrames() async throws -> ReceivedReviewMetadata {
        var deliveryEventIterator = deliveryEvents.makeAsyncIterator()
        var received = ReceivedReviewMetadata()
        var releasedHeldPresentation = false
        while !received.finalWindow {
            guard let event = await deliveryEventIterator.next() else {
                throw ReviewMetadataPacingTestError.deliveryEventStreamEnded
            }
            switch event {
            case .deliveryRejected(let rejection):
                throw ReviewMetadataPacingTestError.deliveryRejectedBeforeConsumerResumed(rejection)
            case .deliveryCompleted(let disposition):
                throw ReviewMetadataPacingTestError.deliveryCompletedBeforeFinalWindow(disposition)
            case .observationRequested(let observedLease, let observedSequence):
                if !releasedHeldPresentation {
                    #expect(await pump.acknowledgeFrameConsumed(heldPresentation.receipt))
                    releasedHeldPresentation = true
                }
                let delivery = try await requireMetadataFrameDelivery(from: pump)
                #expect(observedLease == lease)
                #expect(delivery.receipt.sequence == observedSequence)
                received.accept(try decodeMetadataFrame(delivery))
                #expect(await pump.acknowledgeFrameConsumed(delivery.receipt))
            }
        }
        return received
    }

    @MainActor
    func shutdown() async {
        deliveryEventContinuation.finish()
        await harness.session.settleControlProviderDispatch(token: openToken)
        await coordinator.uninstall(lease: lease)
        _ = await pump.cancel()
    }
}

private actor PacingReviewMetadataSource: BridgePaneProductReviewMetadataProducing {
    private let deliveryEventContinuation: AsyncStream<ReviewMetadataDeliveryEvent>.Continuation
    private let source = BridgePaneProductReviewMetadataSource()
    private let sourceOpenedContinuation: AsyncStream<Void>.Continuation

    init(
        deliveryEventContinuation: AsyncStream<ReviewMetadataDeliveryEvent>.Continuation,
        sourceOpenedContinuation: AsyncStream<Void>.Continuation
    ) {
        self.deliveryEventContinuation = deliveryEventContinuation
        self.sourceOpenedContinuation = sourceOpenedContinuation
    }

    func open(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        try await source.open(subscription: subscription, productAdmission: productAdmission, emit: emit)
        sourceOpenedContinuation.yield()
    }

    func update(
        subscription: BridgeProductSubscriptionSnapshot,
        productAdmission: BridgeProductAdmissionContext,
        emit: @escaping BridgePaneProductReviewMetadataEventSink
    ) async throws {
        try await source.update(subscription: subscription, productAdmission: productAdmission, emit: emit)
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
        publication: BridgeReviewCommittedPublication,
        reservation: BridgeReviewMetadataPublicationReservation,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgePaneProductReviewMetadataPublicationOutcome {
        do {
            return try await source.deliver(
                publication: publication,
                reservation: reservation,
                productAdmission: productAdmission
            )
        } catch let error as BridgePaneProductMetadataCoordinatorError {
            if case .producerRejected(let rejection) = error {
                deliveryEventContinuation.yield(.deliveryRejected(rejection))
            }
            throw error
        }
    }

    func cancel(subscriptionId: String) async {
        await source.cancel(subscriptionId: subscriptionId)
    }
}

@MainActor
private final class PacingReviewPublicationProvider {
    var publication: BridgeReviewCommittedPublication?
}

private enum ReviewMetadataDeliveryEvent: Sendable {
    case observationRequested(lease: BridgeProductProducerLease, sequence: Int)
    case deliveryRejected(BridgeProductProducerEnqueueRejection)
    case deliveryCompleted(BridgeReviewPublicationDeliveryDisposition)
}

private struct ReceivedReviewMetadata {
    var finalWindow = false
    var itemCount = 0
    var orderedItemIds: [String] = []
    var sourceAccepted = false

    mutating func accept(_ frame: BridgeProductMetadataFrame) {
        guard case .subscriptionData(let data) = frame,
            let event = data.data.reviewMetadataEvent
        else { return }
        switch event {
        case .sourceAccepted:
            sourceAccepted = true
        case .snapshot(let snapshot):
            itemCount += snapshot.itemMetadata.count
            orderedItemIds.append(contentsOf: snapshot.itemMetadata.map(\.itemId))
            finalWindow = snapshot.itemWindow.finalWindow && snapshot.treeWindow.finalWindow
        case .window(let window):
            itemCount += window.itemMetadata.count
            orderedItemIds.append(contentsOf: window.itemMetadata.map(\.itemId))
            finalWindow = window.itemWindow.finalWindow && window.treeWindow.finalWindow
        case .delta, .invalidated, .reset:
            Issue.record("Unexpected Review event while delivering the initial publication")
        }
    }
}

private enum ReviewMetadataPacingTestError: Error {
    case deliveryCompletedBeforeFinalWindow(BridgeReviewPublicationDeliveryDisposition)
    case deliveryEventStreamEnded
    case deliveryRejectedBeforeConsumerResumed(BridgeProductProducerEnqueueRejection)
    case expectedMetadataFrame
    case expectedNonfinalWindow
    case expectedObservationRequest
    case expectedPanePresentation
    case lateObservationRegistration(ReviewMetadataDeliveryEvent)
    case lifecyclePauseDidNotStart
    case sourceDidNotOpen
}

private func requireNonfinalSnapshot(_ frame: BridgeProductMetadataFrame) throws {
    guard case .subscriptionData(let data) = frame,
        case .snapshot(let window)? = data.data.reviewMetadataEvent,
        !window.itemWindow.finalWindow,
        !window.treeWindow.finalWindow
    else {
        throw ReviewMetadataPacingTestError.expectedNonfinalWindow
    }
}

@MainActor
private func requireObservationRequest(
    from iterator: inout AsyncStream<ReviewMetadataDeliveryEvent>.Iterator
) async throws -> (lease: BridgeProductProducerLease, sequence: Int) {
    guard case .observationRequested(let lease, let sequence)? = await iterator.next(isolation: #isolation) else {
        throw ReviewMetadataPacingTestError.expectedObservationRequest
    }
    return (lease, sequence)
}

@MainActor
private func openPacingReviewSubscription(
    coordinator: BridgePaneProductMetadataCoordinator,
    harness: BridgeProductSessionLifecycleHarness,
    pump: BridgeProductSchemeFramePump
) async throws -> BridgeProductControlAdmissionToken {
    let request = try bridgeProductLifecycleControlRequest(
        bridgeProductLifecycleReviewSubscriptionOpenObject(requestSequence: 2, epoch: 1)
    )
    let token = try #require(controlExecutionToken(try await harness.begin(request)))
    #expect(await harness.session.claimControlProviderDispatch(token: token))
    let response = try BridgeProductControlResponse.subscriptionOpenAccepted(
        correlating: request,
        interestSha256: BridgeProductSubscriptionInterestState.reviewMetadata(interests: []).sha256Hex()
    )
    let effect = try await harness.session.completeControl(
        token: token,
        exactResponseBytes: try JSONEncoder().encode(response)
    )
    _ = try await pullMetadataFrame(from: pump)
    await coordinator.apply(effect, productAdmission: harness.productAdmission.context)
    return token
}

@MainActor
private func holdPacingPanePresentation(
    coordinator: BridgePaneProductMetadataCoordinator,
    pump: BridgeProductSchemeFramePump
) async throws -> BridgeProductProducerFrameDelivery {
    await coordinator.publishPanePresentation(pacingPanePresentation())
    let delivery = try await requireMetadataFrameDelivery(from: pump)
    guard case .panePresentation = try decodeMetadataFrame(delivery) else {
        throw ReviewMetadataPacingTestError.expectedPanePresentation
    }
    return delivery
}

private func requireMetadataFrameDelivery(
    from pump: BridgeProductSchemeFramePump
) async throws -> BridgeProductProducerFrameDelivery {
    guard case .frame(let delivery) = await pump.nextFrame() else {
        throw ReviewMetadataPacingTestError.expectedMetadataFrame
    }
    return delivery
}

private func decodeMetadataFrame(
    _ delivery: BridgeProductProducerFrameDelivery
) throws -> BridgeProductMetadataFrame {
    let decoder = try BridgeProductMetadataFrameDecoder()
    return try #require(try decoder.append(delivery.frame.data).first)
}

private func pacingQueueLimits() throws -> BridgeProductProducerQueueLimits {
    try BridgeProductProducerQueueLimits(
        maximumQueuedFrameCount: 3,
        maximumQueuedByteCount: BridgeProductWireContract.maximumQueuedStreamBytes,
        maximumEncodedFrameByteCount: BridgeProductProducerQueueLimits.maximumProductEncodedFrameByteCount,
        terminalFrameReserve: BridgeProductWireContract.terminalFrameReserve
    )
}

private func makePacingReviewPackage(itemCount: Int) throws -> BridgeReviewPackage {
    let baseEndpoint = makeBridgeEndpoint(endpointId: "pacing-base", kind: .gitRef)
    let headEndpoint = makeBridgeEndpoint(endpointId: "pacing-head", kind: .workingTree)
    let comparison = BridgeEndpointComparison(
        baseEndpoint: baseEndpoint,
        headEndpoint: headEndpoint,
        changedFiles: (0..<itemCount).map { itemIndex in
            makeBridgeEndpointChangedFile(
                fileId: "pacing-\(itemIndex)",
                path: "Sources/Pacing/File\(itemIndex).swift",
                sizeBytes: 100
            )
        }
    )
    return try BridgeReviewPackageBuilder.build(
        request: BridgeReviewPackageBuildRequest(
            packageId: "pacing-package",
            query: makeBridgeReviewQuery(
                baseEndpointId: baseEndpoint.endpointId,
                headEndpointId: headEndpoint.endpointId
            ),
            comparison: comparison,
            checkpointIds: [],
            reviewGeneration: 1,
            generatedAtUnixMilliseconds: 1
        )
    )
}

private func pacingPanePresentation() -> BridgePaneProductPresentationSnapshot {
    BridgePaneProductPresentationSnapshot(
        nativeActivity: .foreground,
        presentationRevision: 1,
        refreshingLanes: [.review],
        reviewComparison: BridgePaneReviewComparisonPresentation(
            activeTarget: .ref(name: "HEAD"),
            attempt: .pending(reviewGeneration: 1),
            displayedSnapshot: .absent,
            repositoryDefaultTarget: nil
        )
    )
}
