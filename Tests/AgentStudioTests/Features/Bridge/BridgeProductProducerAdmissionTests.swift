import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product producer admission")
struct BridgeProductProducerAdmissionTests {
    @Test("closed pane rejects visible producer enqueue while cleanup drains")
    func closedPaneRejectsVisibleProducerEnqueueWhileCleanupDrains() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let request = try bridgeProductFileContentRequest(
            identitySuffix: "producer-admission-close"
        )
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerContentProducer(
            request: request,
            productAdmission: harness.productAdmission
        ) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        #expect(await operation.waitUntilStarted() == lease)
        _ = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            productAdmission: harness.productAdmission,
            build: { _ in producerRegistryContentOpeningFrame(for: request) }
        )
        #expect(
            await consumeNextBridgeProductProducerFrame(
                for: lease,
                from: harness.session,
                productAdmission: harness.productAdmission
            )?.sequence == 0
        )
        let beforeClose = await harness.session.producerSnapshot()
        #expect(beforeClose.queuedFrameCount == 0)
        #expect(beforeClose.pendingFrameWaiterCount == 0)
        #expect(beforeClose.inFlightFrameReceiptCount == 0)
        #expect(beforeClose.sessionContentAdmissionCount == 1)
        #expect(beforeClose.sessionProductAdmissionCount == 1)

        // Act
        harness.closeProductAdmission()
        let rejectedEnqueue = try await harness.session.enqueueTerminalProducerFrame(
            for: lease,
            productAdmission: harness.productAdmission,
            build: { sequence in try producerRegistryContentTerminalFrame(sequence: sequence) }
        )
        let afterRejectedEnqueue = await harness.session.producerSnapshot()

        // Assert
        #expect(rejectedEnqueue == .rejected(.lifecycleClosed))
        #expect(afterRejectedEnqueue == beforeClose)

        try await closeBridgeProductSessionProducer(lease, in: harness.session)
        await operation.waitUntilCancelled()
        let afterCleanup = await harness.session.producerSnapshot()
        #expect(afterCleanup.sessionContentAdmissionCount == 0)
        #expect(afterCleanup.sessionProductAdmissionCount == 0)
        #expect(afterCleanup.hasZeroResidue)
    }
}
