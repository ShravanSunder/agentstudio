import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product metadata capacity admission")
struct BridgeProductMetadataCapacityAdmissionTests {
    @Test("ordinary metadata waits in one FIFO and acknowledgement admits only consecutive heads")
    func ordinaryMetadataAdmissionIsFIFO() async throws {
        // Arrange
        let fixture = try await makeMetadataCapacityFixture()
        _ = try await fixture.session.enqueueOrdinaryMetadataFrame(
            for: fixture.lease,
            productAdmission: fixture.productAdmission,
            build: fixture.progressFrame(identitySuffix: "queued-first")
        )
        _ = try await fixture.session.enqueueOrdinaryMetadataFrame(
            for: fixture.lease,
            productAdmission: fixture.productAdmission,
            build: fixture.progressFrame(identitySuffix: "queued-second")
        )

        let firstWaiting = Task {
            try await fixture.session.enqueueOrdinaryMetadataFrame(
                for: fixture.lease,
                productAdmission: fixture.productAdmission,
                build: fixture.progressFrame(identitySuffix: "waiting-first")
            )
        }
        await waitForPendingMetadataAdmissions(1, in: fixture.session)
        let secondWaiting = Task {
            try await fixture.session.enqueueOrdinaryMetadataFrame(
                for: fixture.lease,
                productAdmission: fixture.productAdmission,
                build: fixture.progressFrame(identitySuffix: "waiting-second")
            )
        }
        await waitForPendingMetadataAdmissions(2, in: fixture.session)

        // Act
        let firstQueuedDelivery = try #require(
            await pullAndAcknowledgeMetadataFrame(in: fixture)
        )
        let firstAdmission = try await firstWaiting.value
        let afterFirstAdmission = await fixture.session.producerSnapshot()
        let secondQueuedDelivery = try #require(
            await pullAndAcknowledgeMetadataFrame(in: fixture)
        )
        let secondAdmission = try await secondWaiting.value

        // Assert
        #expect(firstQueuedDelivery.sequence == 1)
        #expect(firstAdmission.enqueuedFrame?.sequence == 3)
        #expect(afterFirstAdmission.pendingMetadataAdmissionCount == 1)
        #expect(secondQueuedDelivery.sequence == 2)
        #expect(secondAdmission.enqueuedFrame?.sequence == 4)
        #expect(await fixture.session.producerSnapshot().pendingMetadataAdmissionCount == 0)
        try await closeMetadataCapacityFixture(fixture)
    }

    @Test("cancelling one metadata waiter removes only its exact FIFO token")
    func cancellingMetadataAdmissionPreservesOtherWaiters() async throws {
        // Arrange
        let fixture = try await makeMetadataCapacityFixture()
        _ = try await fixture.session.enqueueOrdinaryMetadataFrame(
            for: fixture.lease,
            productAdmission: fixture.productAdmission,
            build: fixture.progressFrame(identitySuffix: "queued-first")
        )
        _ = try await fixture.session.enqueueOrdinaryMetadataFrame(
            for: fixture.lease,
            productAdmission: fixture.productAdmission,
            build: fixture.progressFrame(identitySuffix: "queued-second")
        )
        let cancelledWaiting = Task {
            try await fixture.session.enqueueOrdinaryMetadataFrame(
                for: fixture.lease,
                productAdmission: fixture.productAdmission,
                build: fixture.progressFrame(identitySuffix: "cancelled")
            )
        }
        await waitForPendingMetadataAdmissions(1, in: fixture.session)
        let survivingWaiting = Task {
            try await fixture.session.enqueueOrdinaryMetadataFrame(
                for: fixture.lease,
                productAdmission: fixture.productAdmission,
                build: fixture.progressFrame(identitySuffix: "surviving")
            )
        }
        await waitForPendingMetadataAdmissions(2, in: fixture.session)

        // Act
        cancelledWaiting.cancel()
        let cancelledResult = await cancelledWaiting.result
        await waitForPendingMetadataAdmissions(1, in: fixture.session)
        _ = try #require(await pullAndAcknowledgeMetadataFrame(in: fixture))
        let survivingAdmission = try await survivingWaiting.value

        // Assert
        guard case .failure(let cancellationError) = cancelledResult else {
            Issue.record("Expected the cancelled admission to fail")
            return
        }
        #expect(cancellationError is CancellationError)
        #expect(survivingAdmission.enqueuedFrame?.sequence == 3)
        #expect(await fixture.session.producerSnapshot().pendingMetadataAdmissionCount == 0)
        try await closeMetadataCapacityFixture(fixture)
    }
}

private struct BridgeProductMetadataCapacityFixture: Sendable {
    let lease: BridgeProductProducerLease
    let operation: BridgeProductSessionProducerOperationGate
    let productAdmission: BridgeProductAdmissionContext
    let request: BridgeProductMetadataStreamRequest
    let session: BridgeProductSession

    func progressFrame(
        identitySuffix: String
    ) -> BridgeProductProducerRegistry.FrameBuilder {
        { streamSequence in
            try bridgeProductMetadataProgressFrame(
                request: request,
                streamSequence: streamSequence,
                identitySuffix: identitySuffix
            )
        }
    }
}

private func makeMetadataCapacityFixture() async throws -> BridgeProductMetadataCapacityFixture {
    let limits = try BridgeProductProducerQueueLimits(
        maximumQueuedFrameCount: 3,
        maximumQueuedByteCount: BridgeProductWireContract.maximumQueuedStreamBytes,
        maximumEncodedFrameByteCount:
            BridgeProductProducerQueueLimits.maximumProductEncodedFrameByteCount,
        terminalFrameReserve: 1
    )
    let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
    let session = try BridgeProductSession(
        paneSessionId: bridgeProductTestPaneSessionId,
        workerInstanceId: bridgeProductTestWorkerInstanceId,
        capabilityBytes: capabilityBytes,
        producerQueueLimits: limits
    )
    let harness = try await BridgeProductSessionProducerHarness.opened(session: session)
    let request = try bridgeProductMetadataStreamRequest(
        metadataStreamId: "metadata-capacity",
        resumeFromStreamSequence: nil
    )
    let operation = BridgeProductSessionProducerOperationGate()
    let registration = await session.registerMetadataProducer(
        request: request,
        productAdmission: harness.productAdmission
    ) { lease in
        await operation.run(lease)
    }
    let lease = try bridgeProductAcceptedLease(registration)
    _ = await operation.waitUntilStarted()
    _ = try await session.enqueueRequiredProducerOpeningFrame(
        for: lease,
        productAdmission: harness.productAdmission,
        build: { streamSequence in
            try bridgeProductMetadataAcceptedFrame(
                request: request,
                streamSequence: streamSequence,
                resumeDisposition: .snapshotRequired
            )
        }
    )
    _ = try #require(
        await consumeNextBridgeProductProducerFrame(
            for: lease,
            from: session,
            productAdmission: harness.productAdmission
        )
    )
    return BridgeProductMetadataCapacityFixture(
        lease: lease,
        operation: operation,
        productAdmission: harness.productAdmission,
        request: request,
        session: session
    )
}

private func pullAndAcknowledgeMetadataFrame(
    in fixture: BridgeProductMetadataCapacityFixture
) async -> BridgeProductQueuedProducerFrame? {
    await consumeNextBridgeProductProducerFrame(
        for: fixture.lease,
        from: fixture.session,
        productAdmission: fixture.productAdmission
    )
}

private func waitForPendingMetadataAdmissions(
    _ expectedCount: Int,
    in session: BridgeProductSession
) async {
    for _ in 0..<1000 {
        if await session.producerSnapshot().pendingMetadataAdmissionCount == expectedCount {
            return
        }
        await Task.yield()
    }
    Issue.record("Pending metadata admission count did not reach \(expectedCount)")
}

private func closeMetadataCapacityFixture(
    _ fixture: BridgeProductMetadataCapacityFixture
) async throws {
    while await fixture.session.producerSnapshot().queuedFrameCount > 0 {
        _ = await pullAndAcknowledgeMetadataFrame(in: fixture)
    }
    try await closeBridgeProductSessionProducer(fixture.lease, in: fixture.session)
    #expect(await fixture.session.producerSnapshot().hasZeroResidue)
}

extension BridgeProductProducerEnqueueResult {
    fileprivate var enqueuedFrame: BridgeProductQueuedProducerFrame? {
        guard case .enqueued(let frame) = self else { return nil }
        return frame
    }
}
