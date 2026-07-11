import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product session producer lifecycle boundaries")
struct BridgeProductSessionProducerLifecycleBoundaryTests {
    @Test("actor boundary reserves terminal capacity and tears down with zero residue")
    func actorBoundaryPreservesTerminalReserveThroughTeardown() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-terminal-reserve",
            resumeFromStreamSequence: nil
        )
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(request: request) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()
        _ = try await harness.session.enqueueRequiredProducerOpeningFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataAcceptedFrame(
                    request: request,
                    streamSequence: sequence,
                    resumeDisposition: .snapshotRequired
                )
            }
        )
        #expect(
            await consumeNextBridgeProductProducerFrame(
                for: lease,
                from: harness.session
            )?.sequence == 0
        )
        let nonterminalCapacity =
            BridgeProductWireContract.maximumQueuedStreamFrames
            - BridgeProductWireContract.terminalFrameReserve
        for expectedSequence in 1...nonterminalCapacity {
            let result = try await harness.session.enqueueProducerFrame(
                for: lease,
                build: { sequence in
                    try bridgeProductMetadataProgressFrame(
                        request: request,
                        streamSequence: sequence,
                        identitySuffix: "terminal-reserve-\(sequence)"
                    )
                },
                overflowReset: { sequence in
                    try bridgeProductMetadataTerminalFrame(
                        request: request,
                        streamSequence: sequence
                    )
                }
            )
            #expect(bridgeProductEnqueuedFrame(result)?.sequence == expectedSequence)
        }
        let saturatedSnapshot = await harness.session.producerSnapshot()

        // Act
        let overflowResult = try await harness.session.enqueueProducerFrame(
            for: lease,
            build: { sequence in
                try bridgeProductMetadataProgressFrame(
                    request: request,
                    streamSequence: sequence,
                    identitySuffix: "terminal-reserve-overflow"
                )
            },
            overflowReset: { sequence in
                try bridgeProductMetadataTerminalFrame(
                    request: request,
                    streamSequence: sequence
                )
            }
        )
        let resetReceipt = terminalResetReceipt(overflowResult)
        let resetSnapshot = await harness.session.producerSnapshot()
        let deliveredReset = await consumeNextBridgeProductProducerFrame(
            for: lease,
            from: harness.session
        )
        try await closeBridgeProductSessionProducer(lease, in: harness.session)
        await operation.waitUntilCancelled()
        let finalSnapshot = await harness.session.producerSnapshot()

        // Assert
        #expect(saturatedSnapshot.queuedFrameCount == nonterminalCapacity)
        #expect(saturatedSnapshot.nextMetadataStreamSequence == nonterminalCapacity + 1)
        #expect(resetReceipt?.frame.sequence == 1)
        #expect(resetReceipt?.frame.terminal == true)
        #expect(resetReceipt?.discardedFrameCount == nonterminalCapacity)
        #expect(resetReceipt?.discardedByteCount == saturatedSnapshot.queuedByteCount)
        #expect(resetSnapshot.queuedFrameCount == 1)
        #expect(resetSnapshot.nextMetadataStreamSequence == 2)
        #expect(deliveredReset?.sequence == 1)
        #expect(deliveredReset?.terminal == true)
        #expect(finalSnapshot.hasZeroResidue)
        #expect(finalSnapshot.nextMetadataStreamSequence == 2)
    }

    @Test("revoke owns lifecycle acknowledgement when normal unregister races its await")
    func revokeArbitratesConcurrentNormalUnregister() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-revoke-unregister-arbitration",
            resumeFromStreamSequence: nil
        )
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(request: request) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()
        #expect(await harness.session.stopProducer(lease))
        await operation.waitUntilCancelled()
        let acknowledgementGate = BridgeProductSessionLifecycleAcknowledgementGate()

        // Act
        let revocation = await harness.session.revoke { acknowledgement in
            await acknowledgementGate.acknowledge(acknowledgement)
        }
        let revokeAcknowledgement = await acknowledgementGate.waitUntilInvoked()
        let normalUnregister = await harness.session.unregisterProducer(lease)
        let suspendedSnapshot = await harness.session.producerSnapshot()

        // Assert
        #expect(revokeAcknowledgement.producerLease == lease)
        #expect(normalUnregister == nil)
        #expect(suspendedSnapshot.activeProducerCount == 0)
        #expect(suspendedSnapshot.pendingLifecycleAcknowledgementCount == 1)
        #expect(!suspendedSnapshot.hasZeroResidue)

        await acknowledgementGate.release()
        #expect(await revocation.wait())
        let finalSnapshot = await harness.session.producerSnapshot()
        #expect(finalSnapshot.hasZeroResidue)
        #expect(finalSnapshot.isRevoked)
        #expect((await harness.session.snapshot).lifecycle == .revoked)
    }

    @Test("revoke claims stopped producers before awaiting running producer cancellation")
    func revokeClaimsLifecycleBeforeItsFirstSuspension() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let stoppedOperation = BridgeProductSessionProducerOperationGate()
        let stoppedRegistration = await harness.session.registerMetadataProducer(
            request: try bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-revoke-stopped",
                resumeFromStreamSequence: nil
            )
        ) { lease in
            await stoppedOperation.run(lease)
        }
        let stoppedLease = try bridgeProductAcceptedLease(stoppedRegistration)
        _ = await stoppedOperation.waitUntilStarted()
        #expect(await harness.session.stopProducer(stoppedLease))
        await stoppedOperation.waitUntilCancelled()

        let heldOperation = BridgeProductSessionProducerCancellationHoldGate()
        let heldRegistration = await harness.session.registerContentProducer(
            request: try bridgeProductFileContentRequest(identitySuffix: "revoke-held")
        ) { lease in
            await heldOperation.run(lease)
        }
        let heldLease = try bridgeProductAcceptedLease(heldRegistration)
        _ = await heldOperation.waitUntilStarted()

        // Act
        let revocation = await harness.session.revoke(acknowledgeLifecycle: { _ in true })
        await heldOperation.waitUntilCancellationRequested()
        let competingUnregister = await harness.session.unregisterProducer(stoppedLease)
        await heldOperation.release()
        let didRevoke = await revocation.wait()

        // Assert
        #expect(competingUnregister == nil)
        #expect(didRevoke)
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
        #expect((await harness.session.snapshot).lifecycle == .revoked)
        _ = heldLease
    }

    @Test("revoke settles acknowledgements pending before revocation")
    func revokeClaimsPreexistingLifecycleAcknowledgement() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(
            request: try bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-revoke-pending-ack",
                resumeFromStreamSequence: nil
            )
        ) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()
        #expect(await harness.session.stopProducer(lease))
        await operation.waitUntilCancelled()
        let pendingAcknowledgement = try #require(
            await harness.session.unregisterProducer(lease)
        )
        let acknowledgementProbe = BridgeProductSessionLifecycleAcknowledgementProbe()

        // Act
        let revocation = await harness.session.revoke { acknowledgement in
            await acknowledgementProbe.record(acknowledgement)
            return true
        }
        let didRevoke = await revocation.wait()

        // Assert
        #expect(didRevoke)
        #expect(await acknowledgementProbe.recorded == [pendingAcknowledgement])
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
        #expect((await harness.session.snapshot).lifecycle == .revoked)
    }

    @Test("concurrent revoke callers share one lifecycle acknowledgement flight")
    func concurrentRevokeCallersJoinOneLifecycleFlight() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(
            request: try bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-concurrent-revoke",
                resumeFromStreamSequence: nil
            )
        ) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()
        #expect(await harness.session.stopProducer(lease))
        await operation.waitUntilCancelled()
        let pendingAcknowledgement = try #require(
            await harness.session.unregisterProducer(lease)
        )
        let acknowledgementGate = BridgeProductSessionLifecycleAcknowledgementGate()
        let firstRevocation = await harness.session.revoke { acknowledgement in
            await acknowledgementGate.acknowledge(acknowledgement)
        }
        _ = await acknowledgementGate.waitUntilInvoked()

        // Act
        let secondRevocation = await harness.session.revoke { acknowledgement in
            await acknowledgementGate.acknowledge(acknowledgement)
        }
        let invocationCountBeforeRelease = await acknowledgementGate.invocationCount
        let recordedAcknowledgements = await acknowledgementGate.recordedAcknowledgements
        let cancelledWaiter = Task {
            await secondRevocation.wait()
        }
        cancelledWaiter.cancel()
        await acknowledgementGate.release()
        let firstResult = await firstRevocation.wait()
        let secondResult = await cancelledWaiter.value

        // Assert
        #expect(firstRevocation == secondRevocation)
        #expect(invocationCountBeforeRelease == 1)
        #expect(recordedAcknowledgements == [pendingAcknowledgement])
        #expect(firstResult)
        #expect(secondResult)
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
        #expect((await harness.session.snapshot).lifecycle == .revoked)
    }

    @Test("failed revoke flight retries pending residue and caches success")
    func failedRevokeFlightRetriesPendingResidueAndCachesSuccess() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let operation = BridgeProductSessionProducerOperationGate()
        let registration = await harness.session.registerMetadataProducer(
            request: try bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-revoke-retry",
                resumeFromStreamSequence: nil
            )
        ) { lease in
            await operation.run(lease)
        }
        let lease = try bridgeProductAcceptedLease(registration)
        _ = await operation.waitUntilStarted()
        #expect(await harness.session.stopProducer(lease))
        await operation.waitUntilCancelled()
        let pendingAcknowledgement = try #require(
            await harness.session.unregisterProducer(lease)
        )
        let acknowledgementProbe = BridgeProductSessionLifecycleAcknowledgementProbe()

        // Act
        let failedRevocation = await harness.session.revoke { acknowledgement in
            await acknowledgementProbe.record(acknowledgement)
            return false
        }
        let firstResult = await failedRevocation.wait()
        let failedSnapshot = await harness.session.producerSnapshot()
        let successfulRevocation = await harness.session.revoke { acknowledgement in
            await acknowledgementProbe.record(acknowledgement)
            return true
        }
        let secondResult = await successfulRevocation.wait()
        let unexpectedCallbackProbe = BridgeProductSessionLifecycleAcknowledgementProbe()
        let completedRevocation = await harness.session.revoke { acknowledgement in
            await unexpectedCallbackProbe.record(acknowledgement)
            return false
        }
        let completedResult = await completedRevocation.wait()

        // Assert
        #expect(!firstResult)
        #expect(failedSnapshot.pendingLifecycleAcknowledgementCount == 1)
        #expect(!failedSnapshot.hasZeroResidue)
        #expect(failedRevocation != successfulRevocation)
        #expect(secondResult)
        #expect(completedResult)
        #expect(completedRevocation == successfulRevocation)
        #expect(
            await acknowledgementProbe.recorded
                == [pendingAcknowledgement, pendingAcknowledgement]
        )
        #expect(await unexpectedCallbackProbe.recorded.isEmpty)
        #expect((await harness.session.producerSnapshot()).hasZeroResidue)
        #expect((await harness.session.snapshot).lifecycle == .revoked)
    }
}

private struct TerminalResetReceipt {
    let discardedByteCount: Int
    let discardedFrameCount: Int
    let frame: BridgeProductQueuedProducerFrame
}

private actor BridgeProductSessionLifecycleAcknowledgementGate {
    private var acknowledgements: [BridgeProductProducerLifecycleAcknowledgement] = []
    private var invocationWaiters: [CheckedContinuation<BridgeProductProducerLifecycleAcknowledgement, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Bool, Never>] = []
    private var isReleased = false

    var invocationCount: Int {
        acknowledgements.count
    }

    var recordedAcknowledgements: [BridgeProductProducerLifecycleAcknowledgement] {
        acknowledgements
    }

    func acknowledge(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool {
        acknowledgements.append(acknowledgement)
        let waiters = invocationWaiters
        invocationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: acknowledgement)
        }
        return await withCheckedContinuation { continuation in
            if isReleased {
                continuation.resume(returning: true)
            } else {
                releaseContinuations.append(continuation)
            }
        }
    }

    func waitUntilInvoked() async -> BridgeProductProducerLifecycleAcknowledgement {
        if let acknowledgement = acknowledgements.first { return acknowledgement }
        return await withCheckedContinuation { continuation in
            invocationWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: true)
        }
    }
}

private actor BridgeProductSessionLifecycleAcknowledgementProbe {
    private(set) var recorded: [BridgeProductProducerLifecycleAcknowledgement] = []

    func record(_ acknowledgement: BridgeProductProducerLifecycleAcknowledgement) {
        recorded.append(acknowledgement)
    }
}

private actor BridgeProductSessionProducerCancellationHoldGate {
    private var cancellationRequested = false
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var operationContinuation: CheckedContinuation<Void, Never>?
    private var releaseCredit = false
    private var startedLease: BridgeProductProducerLease?
    private var startWaiters: [CheckedContinuation<BridgeProductProducerLease, Never>] = []

    func run(_ lease: BridgeProductProducerLease) async {
        startedLease = lease
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: lease)
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if releaseCredit {
                    releaseCredit = false
                    continuation.resume()
                } else {
                    operationContinuation = continuation
                }
            }
        } onCancel: {
            Task { await self.markCancellationRequested() }
        }
    }

    func waitUntilStarted() async -> BridgeProductProducerLease {
        if let startedLease { return startedLease }
        return await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilCancellationRequested() async {
        if cancellationRequested { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    func release() {
        guard let operationContinuation else {
            releaseCredit = true
            return
        }
        self.operationContinuation = nil
        operationContinuation.resume()
    }

    private func markCancellationRequested() {
        cancellationRequested = true
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private func terminalResetReceipt(
    _ result: BridgeProductProducerEnqueueResult
) -> TerminalResetReceipt? {
    guard case .queueReset(let frame, let discardedFrameCount, let discardedByteCount) = result else {
        Issue.record("Expected terminal queue reset, received \(result)")
        return nil
    }
    return TerminalResetReceipt(
        discardedByteCount: discardedByteCount,
        discardedFrameCount: discardedFrameCount,
        frame: frame
    )
}
