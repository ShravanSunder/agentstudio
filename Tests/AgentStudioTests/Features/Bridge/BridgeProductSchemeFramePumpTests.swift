import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product scheme frame pump")
struct BridgeProductSchemeFramePumpTests {
    @Test("claimed queue head remains resident until its exact receipt is consumed")
    func claimedFrameRequiresExactConsumptionReceipt() async throws {
        // Arrange
        let fixture = try await makeFramePumpFixture(identitySuffix: "receipt")
        _ = try await enqueueContentOpening(fixture)
        let pump = BridgeProductSchemeFramePump(
            session: fixture.harness.session,
            producerLease: fixture.lease,
            acknowledgeLifecycle: { _ in true }
        )

        // Act
        let firstPull = await pump.nextFrame()
        let delivery = try #require(frameDelivery(firstPull))
        let claimedSnapshot = await fixture.harness.session.producerSnapshot()
        let forgedReceipt = BridgeProductProducerFrameReceipt(
            producerLease: fixture.lease,
            sequence: delivery.frame.sequence,
            nonce: UUID()
        )
        let forgedAccepted = await pump.acknowledgeFrameConsumed(forgedReceipt)
        let afterForgery = await fixture.harness.session.producerSnapshot()
        let exactAccepted = await pump.acknowledgeFrameConsumed(delivery.receipt)
        let duplicateAccepted = await pump.acknowledgeFrameConsumed(delivery.receipt)
        let afterConsumption = await fixture.harness.session.producerSnapshot()

        // Assert
        #expect(claimedSnapshot.queuedFrameCount == 1)
        #expect(claimedSnapshot.inFlightFrameReceiptCount == 1)
        #expect(!forgedAccepted)
        #expect(afterForgery.queuedFrameCount == 1)
        #expect(afterForgery.inFlightFrameReceiptCount == 1)
        #expect(exactAccepted)
        #expect(!duplicateAccepted)
        #expect(afterConsumption.queuedFrameCount == 0)
        #expect(afterConsumption.inFlightFrameReceiptCount == 0)

        #expect(await pump.cancel())
        await fixture.operation.waitUntilCancelled()
        #expect((await fixture.harness.session.producerSnapshot()).hasZeroResidue)
    }

    @Test("one pending pull and one in-flight receipt are enforced per lease")
    func concurrentPullsHaveOneWaiterAndOneClaim() async throws {
        // Arrange
        let fixture = try await makeFramePumpFixture(identitySuffix: "single-flight")
        let pump = BridgeProductSchemeFramePump(
            session: fixture.harness.session,
            producerLease: fixture.lease,
            acknowledgeLifecycle: { _ in true }
        )

        // Act
        async let firstPull = pump.nextFrame()
        async let competingPull = pump.nextFrame()
        _ = try await enqueueContentOpening(fixture)
        let results = await [firstPull, competingPull]

        // Assert
        let deliveries = results.compactMap(frameDelivery)
        #expect(deliveries.count == 1)
        #expect(
            results.contains(.rejected(.waiterAlreadyRegistered))
                || results.contains(.rejected(.receiptInFlight))
        )
        let delivery = try #require(deliveries.first)
        #expect(await pump.acknowledgeFrameConsumed(delivery.receipt))
        #expect(await pump.cancel())
        #expect((await fixture.harness.session.producerSnapshot()).hasZeroResidue)
    }

    @Test("stopping producer drains its queued prefix before normal zero-residue finish")
    func stoppingProducerDrainsBeforeFinish() async throws {
        // Arrange
        let fixture = try await makeFramePumpFixture(identitySuffix: "drain")
        _ = try await enqueueContentOpening(fixture)
        _ = try await fixture.harness.session.enqueueTerminalProducerFrame(
            for: fixture.lease,
            build: { sequence in
                .content(
                    .init(
                        header: try .reset(
                            contentSequence: sequence,
                            reason: .staleSource
                        ),
                        payload: Data()
                    )
                )
            }
        )
        #expect(await fixture.harness.session.stopProducer(fixture.lease))
        let lifecycleProbe = FramePumpLifecycleAcknowledgementProbe()
        let pump = BridgeProductSchemeFramePump(
            session: fixture.harness.session,
            producerLease: fixture.lease,
            acknowledgeLifecycle: { acknowledgement in
                await lifecycleProbe.acknowledge(acknowledgement)
            }
        )

        // Act
        let openingDelivery = try #require(frameDelivery(await pump.nextFrame()))
        let afterOpeningClaim = await fixture.harness.session.producerSnapshot()
        #expect(await pump.acknowledgeFrameConsumed(openingDelivery.receipt))
        let terminalDelivery = try #require(frameDelivery(await pump.nextFrame()))
        #expect(await pump.acknowledgeFrameConsumed(terminalDelivery.receipt))
        let finishResult = await pump.nextFrame()

        // Assert
        #expect(openingDelivery.frame.sequence == 0)
        #expect(terminalDelivery.frame.sequence == 1)
        #expect(terminalDelivery.frame.terminal)
        #expect(afterOpeningClaim.queuedFrameCount == 2)
        #expect(finishResult == .finished)
        #expect(await lifecycleProbe.invocationCount == 1)
        #expect((await fixture.harness.session.producerSnapshot()).hasZeroResidue)
    }

    @Test("pump cancellation and session revocation share lifecycle ownership")
    func cancellationAndRevocationShareRetirementFlight() async throws {
        // Arrange
        let fixture = try await makeFramePumpFixture(identitySuffix: "revoke-race")
        let lifecycleProbe = FramePumpLifecycleAcknowledgementProbe()
        let acknowledge: BridgeProductSession.ProducerLifecycleAcknowledger = { acknowledgement in
            await lifecycleProbe.acknowledge(acknowledgement)
        }
        let pump = BridgeProductSchemeFramePump(
            session: fixture.harness.session,
            producerLease: fixture.lease,
            acknowledgeLifecycle: acknowledge
        )

        // Act
        async let cancelled = pump.cancel()
        async let revocation = fixture.harness.session.revoke(
            acknowledgeLifecycle: acknowledge
        ).wait()
        let outcomes = await (cancelled, revocation)

        // Assert
        #expect(outcomes.0)
        #expect(outcomes.1)
        #expect(await lifecycleProbe.invocationCount == 1)
        #expect((await fixture.harness.session.producerSnapshot()).hasZeroResidue)
    }

    @Test("reentrant revocation does not acknowledge one lifecycle nonce twice")
    func reentrantRevocationDoesNotDoubleAcknowledgeLifecycle() async throws {
        // Arrange
        let fixture = try await makeFramePumpFixture(identitySuffix: "reentrant-revoke")
        let lifecycleProbe = FramePumpReentrantRevocationLifecycleProbe(
            session: fixture.harness.session
        )
        let pump = BridgeProductSchemeFramePump(
            session: fixture.harness.session,
            producerLease: fixture.lease,
            acknowledgeLifecycle: { acknowledgement in
                await lifecycleProbe.acknowledge(acknowledgement)
            }
        )

        // Act
        let cancellationSucceeded = await pump.cancel()
        let storedRevocationBarrier = await lifecycleProbe.revocationBarrier
        let revocationBarrier = try #require(storedRevocationBarrier)
        let revocationSucceeded = await revocationBarrier.wait()
        let firstAcknowledgementNonce = try #require(
            await lifecycleProbe.firstAcknowledgementNonce
        )
        let providerInvocationCount = await lifecycleProbe.invocationCount(
            for: firstAcknowledgementNonce
        )
        let finalSnapshot = await fixture.harness.session.producerSnapshot()

        // Assert
        #expect(cancellationSucceeded)
        #expect(revocationSucceeded)
        #expect(providerInvocationCount == 1)
        #expect(finalSnapshot.hasZeroResidue)
    }

    @Test("failed lifecycle acknowledgement is retried exactly and later clears residue")
    func failedLifecycleAcknowledgementCanBeRetried() async throws {
        // Arrange
        let fixture = try await makeFramePumpFixture(identitySuffix: "acknowledgement-retry")
        let lifecycleProbe = FramePumpRetryingLifecycleAcknowledgementProbe()
        let pump = BridgeProductSchemeFramePump(
            session: fixture.harness.session,
            producerLease: fixture.lease,
            acknowledgeLifecycle: { acknowledgement in
                await lifecycleProbe.acknowledge(acknowledgement)
            }
        )

        // Act
        let firstCancellation = await pump.cancel()
        let residueAfterFailure = await fixture.harness.session.producerSnapshot()
        let secondCancellation = await pump.cancel()
        let finalSnapshot = await fixture.harness.session.producerSnapshot()
        let acknowledgementAttempts = await lifecycleProbe.acknowledgements

        // Assert
        #expect(!firstCancellation)
        #expect(residueAfterFailure.activeProducerCount == 0)
        #expect(residueAfterFailure.pendingLifecycleAcknowledgementCount == 1)
        #expect(!residueAfterFailure.hasZeroResidue)
        #expect(secondCancellation)
        #expect(acknowledgementAttempts.count == 2)
        #expect(acknowledgementAttempts.first == acknowledgementAttempts.last)
        #expect(finalSnapshot.hasZeroResidue)
    }

    @Test("provider completion without a consumed terminal frame is rejected")
    func producerCannotFinishAfterDataOnlyPrefix() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let request = try bridgeProductFileContentRequest(identitySuffix: "missing-terminal")
        let completionGate = FramePumpProducerCompletionGate()
        let registration = await harness.session.registerContentProducer(request: request) { _ in
            await completionGate.waitForRelease()
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { _ in
                .content(
                    .init(
                        header: .accepted(for: request.admission),
                        payload: Data()
                    )
                )
            }
        )
        _ = try await harness.session.enqueueProducerFrame(
            for: lease,
            build: { sequence in
                .content(
                    .init(
                        header: try .data(
                            contentSequence: sequence,
                            offsetBytes: 0
                        ),
                        payload: Data([0x61])
                    )
                )
            },
            overflowReset: { sequence in
                .content(
                    .init(
                        header: try .reset(
                            contentSequence: sequence,
                            reason: .staleSource
                        ),
                        payload: Data()
                    )
                )
            }
        )
        let pump = BridgeProductSchemeFramePump(
            session: harness.session,
            producerLease: lease,
            acknowledgeLifecycle: { _ in true }
        )

        // Act
        let opening = try #require(frameDelivery(await pump.nextFrame()))
        #expect(await pump.acknowledgeFrameConsumed(opening.receipt))
        let data = try #require(frameDelivery(await pump.nextFrame()))
        #expect(await pump.acknowledgeFrameConsumed(data.receipt))
        await completionGate.release()
        let finishAttempt = await pump.nextFrame()

        // Assert
        #expect(finishAttempt == .rejected(.producerEndedWithoutTerminal))
        #expect(await pump.cancel())
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
    }
}

private struct FramePumpFixture {
    let harness: BridgeProductSessionProducerHarness
    let lease: BridgeProductProducerLease
    let operation: BridgeProductSessionProducerOperationGate
    let request: BridgeProductContentRequest
}

private actor FramePumpLifecycleAcknowledgementProbe {
    private(set) var invocationCount = 0

    func acknowledge(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) -> Bool {
        invocationCount += 1
        return true
    }
}

private actor FramePumpRetryingLifecycleAcknowledgementProbe {
    private(set) var acknowledgements: [BridgeProductProducerLifecycleAcknowledgement] = []

    func acknowledge(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) -> Bool {
        acknowledgements.append(acknowledgement)
        return acknowledgements.count > 1
    }
}

private actor FramePumpReentrantRevocationLifecycleProbe {
    private let session: BridgeProductSession
    private var didStartRevocation = false
    private var invocationCountByNonce: [UUID: Int] = [:]
    private(set) var firstAcknowledgementNonce: UUID?
    private(set) var revocationBarrier: BridgeProductSessionRevocationBarrier?

    init(session: BridgeProductSession) {
        self.session = session
    }

    func acknowledge(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        invocationCountByNonce[acknowledgement.nonce, default: 0] += 1
        if firstAcknowledgementNonce == nil {
            firstAcknowledgementNonce = acknowledgement.nonce
        }
        guard !didStartRevocation else { return true }

        didStartRevocation = true
        revocationBarrier = await session.revoke(
            acknowledgeLifecycle: { acknowledgement in
                await self.acknowledge(acknowledgement)
            }
        )
        return true
    }

    func invocationCount(for nonce: UUID) -> Int {
        invocationCountByNonce[nonce, default: 0]
    }
}

private actor FramePumpProducerCompletionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func waitForRelease() async {
        if isReleased { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

private func makeFramePumpFixture(identitySuffix: String) async throws -> FramePumpFixture {
    let harness = try await BridgeProductSessionProducerHarness.opened()
    let operation = BridgeProductSessionProducerOperationGate()
    let request = try bridgeProductFileContentRequest(identitySuffix: identitySuffix)
    let registration = await harness.session.registerContentProducer(request: request) { lease in
        await operation.run(lease)
    }
    let lease = try bridgeProductAcceptedLease(registration)
    _ = await operation.waitUntilStarted()
    return .init(
        harness: harness,
        lease: lease,
        operation: operation,
        request: request
    )
}

private func enqueueContentOpening(
    _ fixture: FramePumpFixture
) async throws -> BridgeProductProducerEnqueueResult {
    try await fixture.harness.session.enqueueRequiredProducerOpeningFrame(
        for: fixture.lease,
        build: { _ in
            .content(
                .init(
                    header: .accepted(for: fixture.request.admission),
                    payload: Data()
                )
            )
        }
    )
}

private func frameDelivery(
    _ result: BridgeProductProducerFramePullResult
) -> BridgeProductProducerFrameDelivery? {
    guard case .frame(let delivery) = result else { return nil }
    return delivery
}
