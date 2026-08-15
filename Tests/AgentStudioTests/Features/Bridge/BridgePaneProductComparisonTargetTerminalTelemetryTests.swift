import Foundation
import Testing

@testable import AgentStudioBridge

extension BridgeComparisonTargetContentLifecycleTests {
    @Test("claimed comparison invalidated before production records one cancelled terminal")
    @MainActor
    func claimedComparisonInvalidatedBeforeProductionRecordsOneCancelledTerminal() async throws {
        let capture = try makeCapture(
            body: Data("comparison-target-body".utf8),
            suffix: "claimed-before-production"
        )
        let catalogSource = ComparisonTargetFixtureSource(fixtures: [capture])
        let traceProbe = ComparisonTargetCatalogTraceProbe()
        let admissionCoordinator = BridgePaneRefreshAdmissionCoordinator(
            initialActivity: .foreground
        )
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            authorizeReviewComparisonTargets: { await catalogSource.nextAuthorization() },
            reviewComparisonTargetCatalogProducer: catalogSource,
            comparisonTargetCatalogTraceRecorder: traceProbe,
            refreshWorkAdmissionSource: admissionCoordinator.workAdmissionSource
        )
        _ = await provider.response(for: try queryRequest())
        admissionCoordinator.applyActivity(.loadedHidden)
        let harness = try await BridgeProductSessionLifecycleHarness.opened()

        await provider.runContentProducer(
            request: try contentRequest(
                descriptor: capture.descriptor,
                suffix: "claimed-before-production"
            ),
            lease: BridgeProductProducerLease(
                id: try #require(UUID(uuidString: "019FEEC5-A29D-7858-A3BD-AB969E228489"))
            ),
            productAdmission: harness.productAdmission.context,
            session: harness.session
        )

        await traceProbe.waitForEventCount(3)
        let traceEvents = await traceProbe.events
        let terminalEvents = traceEvents.filter { $0.stage == .terminal }
        #expect(traceEvents.first { $0.stage == .reservationClaim }?.outcome == .claimed)
        #expect(terminalEvents.count == 1)
        #expect(terminalEvents.first?.outcome == .cancelled)
        #expect(await catalogSource.productionAttemptCount == 0)
        #expect(await provider.pendingComparisonTargetReservation == nil)
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
    }

    @Test("ordinary producer error after task cancellation records one cancelled terminal")
    func ordinaryProducerErrorAfterTaskCancellationRecordsOneCancelledTerminal() async throws {
        let capture = try makeCapture(
            body: Data("comparison-target-body".utf8),
            suffix: "ordinary-error-after-cancellation"
        )
        let producer = CancelledErrorCatalogProducer()
        let traceProbe = ComparisonTargetCatalogTraceProbe()
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            reviewComparisonTargetCatalogProducer: producer,
            comparisonTargetCatalogTraceRecorder: traceProbe,
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        let reservation = try #require(
            BridgeProductReviewComparisonTargetsReservation(
                authorization: capture.authorization,
                issuing: try queryRequest()
            )
        )
        let harness = try await BridgeProductSessionLifecycleHarness.opened()

        let productionTask = Task {
            try await provider.runComparisonTargetContentProducer(
                reservation: reservation,
                lease: BridgeProductProducerLease(
                    id: try #require(UUID(uuidString: "019FEEC5-A29D-7858-A3BD-AB969E22848A"))
                ),
                productAdmission: harness.productAdmission.context,
                foregroundWorkAdmission: refreshWorkAdmission.admission,
                session: harness.session
            )
        }
        try await productionTask.value

        await traceProbe.waitForEventCount(1)
        let terminalEvents = await traceProbe.events.filter { $0.stage == .terminal }
        #expect(terminalEvents.count == 1)
        #expect(terminalEvents.first?.outcome == .cancelled)
        #expect(await producer.productionAttemptCount == 1)
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
    }

    @Test("cancelled buffered delivery returns a cancelled disposition")
    func cancelledBufferedDeliveryReturnsCancelledDisposition() async throws {
        let capture = try makeCapture(
            body: Data("comparison-target-body".utf8),
            suffix: "delivery-cancelled"
        )
        let provider = await makeProvider(capture: capture)
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()

        let deliveryTask = Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await provider.runBufferedContentProducer(
                BridgePaneProductSchemeProvider.BufferedContentBody(
                    data: capture.body,
                    endOfSource: true,
                    sha256: capture.sha256
                ),
                lease: BridgeProductProducerLease(
                    id: try #require(
                        UUID(uuidString: "019FEEC5-A29D-7858-A3BD-AB969E228488")
                    )
                ),
                productAdmission: harness.productAdmission.context,
                foregroundWorkAdmission: refreshWorkAdmission.admission,
                session: harness.session
            )
        }

        let deliveryDisposition = try await deliveryTask.value

        #expect(deliveryDisposition == .cancelled)
    }

    @Test("rejected catalog terminal delivery does not report complete")
    func rejectedCatalogTerminalDeliveryDoesNotReportComplete() async throws {
        let capture = try makeCapture(body: Data(), suffix: "delivery-rejected")
        let traceProbe = ComparisonTargetCatalogTraceProbe()
        let provider = await makeProvider(capture: capture, traceRecorder: traceProbe)
        let reservation = try #require(
            BridgeProductReviewComparisonTargetsReservation(
                authorization: capture.authorization,
                issuing: try queryRequest()
            )
        )
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()

        try await provider.runComparisonTargetContentProducer(
            reservation: reservation,
            lease: BridgeProductProducerLease(
                id: try #require(UUID(uuidString: "019FEEC5-A29D-7858-A3BD-AB969E228486"))
            ),
            productAdmission: harness.productAdmission.context,
            foregroundWorkAdmission: refreshWorkAdmission.admission,
            session: harness.session
        )

        await traceProbe.waitForEventCount(1)
        let terminalEvent = try #require(
            await traceProbe.events.first { $0.stage == .terminal }
        )
        #expect(terminalEvent.outcome == .productionFailed)
        #expect(terminalEvent.observedByteCount == nil)
    }

    @Test("foreground admission loss does not report a complete terminal")
    @MainActor
    func foregroundAdmissionLossDoesNotReportCompleteTerminal() async throws {
        let capture = try makeCapture(
            body: Data("comparison-target-body".utf8),
            suffix: "admission-lost"
        )
        let traceProbe = ComparisonTargetCatalogTraceProbe()
        let provider = await makeProvider(capture: capture, traceRecorder: traceProbe)
        let reservation = try #require(
            BridgeProductReviewComparisonTargetsReservation(
                authorization: capture.authorization,
                issuing: try queryRequest()
            )
        )
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let admissionCoordinator = BridgePaneRefreshAdmissionCoordinator(
            initialActivity: .foreground
        )
        let foregroundWorkAdmission = try #require(
            admissionCoordinator.acquireForegroundWork()
        )
        admissionCoordinator.applyActivity(.loadedHidden)

        try await provider.runComparisonTargetContentProducer(
            reservation: reservation,
            lease: BridgeProductProducerLease(
                id: try #require(UUID(uuidString: "019FEEC5-A29D-7858-A3BD-AB969E228487"))
            ),
            productAdmission: harness.productAdmission.context,
            foregroundWorkAdmission: foregroundWorkAdmission,
            session: harness.session
        )

        await traceProbe.waitForEventCount(1)
        let terminalEvent = try #require(
            await traceProbe.events.first { $0.stage == .terminal }
        )
        #expect(terminalEvent.outcome == .cancelled)
        #expect(terminalEvent.observedByteCount == nil)
    }
}

private actor CancelledErrorCatalogProducer: BridgeReviewComparisonTargetCatalogProducing {
    private(set) var productionAttemptCount = 0

    func produceComparisonTargetCatalog(
        for reservation: BridgeProductReviewComparisonTargetsReservation
    ) throws -> BridgeReviewComparisonTargetProducedCatalog {
        _ = reservation
        productionAttemptCount += 1
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        throw BridgeReviewComparisonTargetCatalogProducerError.unavailable
    }
}
