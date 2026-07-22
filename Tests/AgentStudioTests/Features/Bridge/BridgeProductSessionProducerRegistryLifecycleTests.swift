import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product session producer lifecycle")
struct BridgeProductSessionProducerRegistryLifecycleTests {
    @Test("exact scoped stop preserves other producers and old-epoch cleanup")
    func exactScopedStopAllowsOldEpochCleanup() async throws {
        // Arrange
        let registry = BridgeProductProducerRegistryTestHarness()
        let metadataRequest = try producerRegistryMetadataStreamRequest()
        let producerRegistryContentRequest = try producerRegistryContentRequest(workerDerivationEpoch: 2)
        let metadataOperation = BridgeProductProducerOperationGate()
        let contentOperation = BridgeProductProducerOperationGate()
        let metadataRegistration = await registry.registerMetadataProducer(
            request: metadataRequest
        ) { lease in
            await metadataOperation.run(lease)
        }
        let contentRegistration = await registry.registerContentProducer(
            request: producerRegistryContentRequest
        ) { lease in
            await contentOperation.run(lease)
        }
        _ = try #require(metadataRegistration.lease)
        let contentLease = try #require(contentRegistration.lease)
        _ = await metadataOperation.waitUntilStarted()
        _ = await contentOperation.waitUntilStarted()
        _ = try await registry.enqueueRequiredOpeningFrame(
            for: contentLease,
            build: { _ in producerRegistryContentOpeningFrame(for: producerRegistryContentRequest) }
        )
        _ = await registry.consumeNextFrame(for: contentLease)

        // Act
        let stoppedLeases = await registry.stop([contentLease])
        let oldEpochCleanup = try await registry.enqueueTerminalFrame(
            for: contentLease,
            build: { sequence in try producerRegistryContentTerminalFrame(sequence: sequence) }
        )
        let stoppedSnapshot = await registry.snapshot()

        // Assert
        #expect(stoppedLeases == [contentLease])
        #expect(oldEpochCleanup.enqueuedFrame?.terminal == true)
        #expect(oldEpochCleanup.enqueuedFrame?.sequence == 1)
        #expect(stoppedSnapshot.activeProducerTaskCount == 1)
        #expect(stoppedSnapshot.activeProducerCount == 2)
        #expect(await registry.consumeNextFrame(for: contentLease)?.sequence == 1)
        let acknowledgement = try #require(await registry.unregister(contentLease))
        #expect(await registry.acknowledgeLifecycle(acknowledgement))
        try await closeAllProducerRegistryProducers(in: registry)
    }

    @Test("lifecycle requires stop then unregister then acknowledgement")
    func lifecycleTransitionsAreExplicitAndOrdered() async throws {
        // Arrange
        let registry = BridgeProductProducerRegistryTestHarness()
        let request = try producerRegistryMetadataStreamRequest()
        let operation = BridgeProductProducerOperationGate()
        let registration = await registry.registerMetadataProducer(request: request) { lease in
            await operation.run(lease)
        }
        let lease = try #require(registration.lease)
        _ = await operation.waitUntilStarted()

        // Act and assert
        #expect(await registry.unregister(lease) == nil)
        #expect(await registry.stop(lease))
        let acknowledgement = try #require(await registry.unregister(lease))
        #expect(!(await registry.snapshot().hasZeroResidue))
        #expect(await registry.acknowledgeLifecycle(acknowledgement))
        #expect(await registry.snapshot().hasZeroResidue)
    }

    @Test("revoke requires real unregister and acknowledgement before zero residue")
    func revokeRequiresExplicitLifecycleAcknowledgements() async throws {
        // Arrange
        let registry = BridgeProductProducerRegistryTestHarness()
        let metadataRequest = try producerRegistryMetadataStreamRequest()
        let producerRegistryContentRequest = try producerRegistryContentRequest(workerDerivationEpoch: 2)
        let metadataOperation = BridgeProductProducerOperationGate()
        let contentOperation = BridgeProductProducerOperationGate()
        let metadataRegistration = await registry.registerMetadataProducer(
            request: metadataRequest
        ) { lease in
            await metadataOperation.run(lease)
        }
        let contentRegistration = await registry.registerContentProducer(
            request: producerRegistryContentRequest
        ) { lease in
            await contentOperation.run(lease)
        }
        _ = await metadataOperation.waitUntilStarted()
        _ = await contentOperation.waitUntilStarted()
        let metadataLease = try #require(metadataRegistration.lease)
        let contentLease = try #require(contentRegistration.lease)
        let zeroResidueWaiter = Task { await registry.waitUntilZeroProducerResidue() }

        // Act
        let stoppedLeases = await registry.revoke()
        let stoppedSnapshot = await registry.snapshot()
        var acknowledgements: [BridgeProductProducerLifecycleAcknowledgement] = []
        for lease in stoppedLeases {
            acknowledgements.append(try #require(await registry.unregister(lease)))
        }
        let unregisteredSnapshot = await registry.snapshot()

        // Assert
        #expect(Set(stoppedLeases) == Set([metadataLease, contentLease]))
        #expect(!stoppedSnapshot.hasZeroResidue)
        #expect(stoppedSnapshot.activeProducerCount == 2)
        #expect(unregisteredSnapshot.pendingLifecycleAcknowledgementCount == 2)
        #expect(!unregisteredSnapshot.hasZeroResidue)
        let rejectedRegistration = await registry.registerMetadataProducer(
            request: metadataRequest
        ) { _ in }
        #expect(rejectedRegistration == .rejected(.revoked))
        for acknowledgement in acknowledgements {
            #expect(await registry.acknowledgeLifecycle(acknowledgement))
        }
        #expect(await zeroResidueWaiter.value)
        #expect(await registry.snapshot().hasZeroResidue)
        #expect(await registry.snapshot().isRevoked)
    }
}

extension BridgeProductProducerRegistration {
    fileprivate var lease: BridgeProductProducerLease? {
        guard case .accepted(let lease) = self else { return nil }
        return lease
    }
}

extension BridgeProductProducerEnqueueResult {
    fileprivate var enqueuedFrame: BridgeProductQueuedProducerFrame? {
        switch self {
        case .enqueued(let frame), .queueReset(let frame, _, _):
            frame
        case .rejected:
            nil
        }
    }
}
