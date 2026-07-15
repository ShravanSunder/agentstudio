import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product producer observation pacing")
struct BridgeProductProducerObservationPacingTests {
    @Test("an acknowledgement observed before waiter registration replays exactly once")
    func earlyObservationReplaysExactlyOnce() async throws {
        // Arrange
        let fixture = try await ProducerObservationPacingFixture.opened(
            identifier: "early-replay",
            sourceByte: 0x61
        )

        // Act
        #expect(
            await fixture.harness.session.acknowledgeContentFrameObservation(
                try producerPacingContentFrameAcknowledgement(
                    for: fixture.request.admission,
                    contentSequence: fixture.delivery.frame.sequence
                )
            )
        )
        let firstReplay = await fixture.harness.session.waitUntilProducerFrameSequenceObserved(
            for: fixture.lease,
            sequence: fixture.opening.sequence
        )
        let secondReplay = await fixture.harness.session.waitUntilProducerFrameSequenceObserved(
            for: fixture.lease,
            sequence: fixture.opening.sequence
        )

        // Assert
        #expect(firstReplay)
        #expect(!secondReplay)
        #expect(
            (await fixture.harness.session.producerSnapshot())
                .pendingProducerObservationPacingWaiterCount == 0
        )
        try await fixture.close()
    }

    @Test("a wrong receipt cannot release producer pacing")
    func wrongReceiptCannotReleaseProducerPacing() async throws {
        // Arrange
        let fixture = try await ProducerObservationPacingFixture.opened(
            identifier: "wrong-receipt",
            sourceByte: 0x61
        )
        let waitTask = fixture.startWaitingForOpeningObservation()
        #expect(await waitForProducerPacingWaiterCount(1, session: fixture.harness.session))
        let wrongReceipt = BridgeProductProducerFrameReceipt(
            producerLease: fixture.lease,
            requiresWorkerObservation: fixture.delivery.receipt.requiresWorkerObservation,
            sequence: fixture.delivery.receipt.sequence,
            nonce: UUID()
        )

        // Act
        let wrongReceiptAccepted = await fixture.harness.session.acknowledgeProducerFrameObserved(wrongReceipt)
        let snapshotAfterWrongReceipt = await fixture.harness.session.producerSnapshot()
        let exactReceiptAccepted = await fixture.harness.session.acknowledgeProducerFrameObserved(
            fixture.delivery.receipt
        )

        // Assert
        #expect(!wrongReceiptAccepted)
        #expect(snapshotAfterWrongReceipt.pendingProducerObservationPacingWaiterCount == 1)
        #expect(snapshotAfterWrongReceipt.inFlightFrameReceiptCount == 1)
        #expect(exactReceiptAccepted)
        #expect(await waitTask.value)
        try await fixture.close()
    }

    @Test("cancellation resolves a pacing waiter false and clears its residue")
    func cancellationClearsPacingWaiterResidue() async throws {
        // Arrange
        let fixture = try await ProducerObservationPacingFixture.opened(
            identifier: "cancelled-waiter",
            sourceByte: 0x61
        )
        let waitTask = fixture.startWaitingForOpeningObservation()
        #expect(await waitForProducerPacingWaiterCount(1, session: fixture.harness.session))

        // Act
        waitTask.cancel()
        let waitResult = await waitTask.value
        let waiterCleared = await waitForProducerPacingWaiterCount(
            0,
            session: fixture.harness.session
        )

        // Assert
        #expect(!waitResult)
        #expect(waiterCleared)
        #expect(
            await fixture.harness.session.acknowledgeProducerFrameObserved(
                fixture.delivery.receipt
            )
        )
        try await fixture.close()
    }

    @Test("concurrent leases release their pacing waiters independently")
    func concurrentLeasesReleaseIndependently() async throws {
        // Arrange
        let fixtureA = try await ProducerObservationPacingFixture.opened(
            identifier: "independent-a",
            sourceByte: 0x61
        )
        let fixtureB = try await ProducerObservationPacingFixture.opened(
            identifier: "independent-b",
            sourceByte: 0x62,
            harness: fixtureA.harness
        )
        let waitTaskA = fixtureA.startWaitingForOpeningObservation()
        let waitTaskB = fixtureB.startWaitingForOpeningObservation()
        #expect(await waitForProducerPacingWaiterCount(2, session: fixtureA.harness.session))

        // Act / Assert
        #expect(
            await fixtureA.harness.session.acknowledgeProducerFrameObserved(
                fixtureA.delivery.receipt
            )
        )
        #expect(await waitTaskA.value)
        #expect(
            (await fixtureA.harness.session.producerSnapshot())
                .pendingProducerObservationPacingWaiterCount == 1
        )
        #expect(
            await fixtureB.harness.session.acknowledgeProducerFrameObserved(
                fixtureB.delivery.receipt
            )
        )
        #expect(await waitTaskB.value)
        #expect(
            (await fixtureA.harness.session.producerSnapshot())
                .pendingProducerObservationPacingWaiterCount == 0
        )
        try await fixtureA.close()
        try await fixtureB.close()
    }
}

private struct ProducerObservationPacingFixture {
    let delivery: BridgeProductProducerFrameDelivery
    let harness: BridgeProductSessionLifecycleHarness
    let lease: BridgeProductProducerLease
    let opening: BridgeProductQueuedProducerFrame
    let request: BridgeProductContentRequest

    static func opened(
        identifier: String,
        sourceByte: UInt8,
        harness: BridgeProductSessionLifecycleHarness? = nil
    ) async throws -> Self {
        let request = try producerPacingContentRequest(
            identifier: identifier,
            sourceByte: sourceByte
        )
        let resolvedHarness: BridgeProductSessionLifecycleHarness
        if let harness {
            resolvedHarness = harness
        } else {
            resolvedHarness = try await BridgeProductSessionLifecycleHarness.opened()
        }
        let operationGate = BridgeProductSessionProducerOperationGate()
        let lease = try bridgeProductAcceptedLease(
            await resolvedHarness.session.registerContentProducer(request: request) { lease in
                await operationGate.run(lease)
            }
        )
        _ = await operationGate.waitUntilStarted()
        let opening = try await producerPacingAcceptedFrame(
            request: request,
            lease: lease,
            session: resolvedHarness.session
        )
        let delivery = try await producerPacingFrameDelivery(
            for: lease,
            from: resolvedHarness.session
        )
        return Self(
            delivery: delivery,
            harness: resolvedHarness,
            lease: lease,
            opening: opening,
            request: request
        )
    }

    func startWaitingForOpeningObservation() -> Task<Bool, Never> {
        Task {
            await harness.session.waitUntilProducerFrameSequenceObserved(
                for: lease,
                sequence: opening.sequence
            )
        }
    }

    func close() async throws {
        try await harness.closeProducer(lease)
        if await harness.session.producerSnapshot().activeProducerCount == 0 {
            #expect((await harness.session.producerSnapshot()).hasZeroResidue)
        }
    }
}

private func producerPacingContentRequest(
    identifier: String,
    sourceByte: UInt8
) throws -> BridgeProductContentRequest {
    let expectedSHA256 = SHA256.hash(data: Data([sourceByte]))
        .map { String(format: "%02x", $0) }
        .joined()
    let requestObject: [String: Any] = [
        "contentKind": "file.content",
        "contentRequestId": "content-request-\(identifier)",
        "descriptor": [
            "contentKind": "file.content",
            "declaredByteLength": 1,
            "descriptorId": "file-descriptor-\(identifier)",
            "encoding": "utf-8",
            "expectedSha256": expectedSHA256,
            "fileId": "file-\(identifier)",
            "maximumBytes": 1,
            "source": [
                "repoId": "00000000-0000-4000-8000-000000000001",
                "rootRevisionToken": NSNull(),
                "sourceCursor": "source-cursor-\(identifier)",
                "sourceId": "source-\(identifier)",
                "subscriptionGeneration": 1,
                "worktreeId": "00000000-0000-4000-8000-000000000002",
            ],
            "window": [
                "kind": "prefix",
                "maximumBytes": 1,
                "maximumLines": BridgeProductWireContract.maximumContentLines,
                "startByte": 0,
            ],
        ],
        "kind": "content.open",
        "leaseId": "lease-\(identifier)",
        "paneSessionId": "pane-session-1",
        "wireVersion": BridgeProductWireContract.version,
        "workerDerivationEpoch": 1,
        "workerInstanceId": "worker-instance-1",
    ]
    return try BridgeProductStrictJSON.decode(
        BridgeProductContentRequest.self,
        from: JSONSerialization.data(withJSONObject: requestObject, options: [.sortedKeys])
    )
}

private func producerPacingAcceptedFrame(
    request: BridgeProductContentRequest,
    lease: BridgeProductProducerLease,
    session: BridgeProductSession
) async throws -> BridgeProductQueuedProducerFrame {
    let result = try await session.enqueueRequiredProducerOpeningFrame(
        for: lease,
        build: { _ in
            .content(.init(header: .accepted(for: request.admission), payload: Data()))
        }
    )
    guard case .enqueued(let frame) = result else {
        throw ProducerObservationPacingTestError.expectedEnqueuedFrame
    }
    return frame
}

private func producerPacingFrameDelivery(
    for lease: BridgeProductProducerLease,
    from session: BridgeProductSession
) async throws -> BridgeProductProducerFrameDelivery {
    guard case .frame(let delivery) = await session.pullProducerFrame(for: lease) else {
        throw ProducerObservationPacingTestError.expectedProducerFrame
    }
    return delivery
}

private func producerPacingContentFrameAcknowledgement(
    for admission: BridgeProductContentAdmission,
    contentSequence: Int
) throws -> BridgeProductContentFrameAcknowledgement {
    let acknowledgementData = try JSONSerialization.data(
        withJSONObject: [
            "contentRequestId": admission.contentRequestId,
            "contentSequence": contentSequence,
            "kind": "stream.frameObserved",
            "leaseId": admission.leaseId,
            "paneSessionId": admission.paneSessionId,
            "streamKind": "content",
            "wireVersion": admission.wireVersion,
            "workerInstanceId": admission.workerInstanceId,
        ],
        options: [.sortedKeys]
    )
    return try BridgeProductStrictJSON.decode(
        BridgeProductContentFrameAcknowledgement.self,
        from: acknowledgementData
    )
}

private func waitForProducerPacingWaiterCount(
    _ expectedCount: Int,
    session: BridgeProductSession
) async -> Bool {
    for _ in 0..<1000 {
        if await session.producerSnapshot().pendingProducerObservationPacingWaiterCount
            == expectedCount
        {
            return true
        }
        await Task.yield()
    }
    return false
}

private enum ProducerObservationPacingTestError: Error {
    case expectedEnqueuedFrame
    case expectedProducerFrame
}
