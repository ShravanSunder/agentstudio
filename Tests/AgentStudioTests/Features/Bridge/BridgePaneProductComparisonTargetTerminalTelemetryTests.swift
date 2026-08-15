import Foundation
import Testing

@testable import AgentStudioBridge

extension BridgeComparisonTargetContentLifecycleTests {
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
