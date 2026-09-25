import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product session producer lifecycle")
struct BridgeProductSessionProducerRegistryLifecycleTests {
    @Test("live metadata prevents reload admission")
    func liveMetadataPreventsReloadAdmission() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let operation = HeldStep<BridgeProductProducerLease>("operation")
        let registration = await harness.session.registerMetadataProducer(
            request: try bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-live-reload-admission",
                resumeFromStreamSequence: nil
            ),
            productAdmission: harness.productAdmission
        ) { lease in
            try? await operation.arrive(lease)
        }
        let lease = try #require(registration.lease)
        _ = try await operation.firstArrival()

        // Act
        let retirementBarriers = await harness.session.metadataRetirementBarriersForReload()

        // Assert
        #expect(retirementBarriers == nil)
        let retirement = await harness.session.beginProducerRetirement(
            lease,
            acknowledgeLifecycle: { _ in true },
            stopRequest: nil,
            abandonOutstandingDelivery: true
        )
        #expect(await retirement.wait())
    }

    @Test("reload admission joins metadata retirement already in flight")
    func reloadAdmissionJoinsMetadataRetirementAlreadyInFlight() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let operation = HeldStep<BridgeProductProducerLease>("operation")
        let acknowledgementGate = BridgeProductProducerLifecycleAcknowledgementGate()
        let registration = await harness.session.registerMetadataProducer(
            request: try bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-retiring-reload-admission",
                resumeFromStreamSequence: nil
            ),
            productAdmission: harness.productAdmission
        ) { lease in
            try? await operation.arrive(lease)
        }
        let lease = try #require(registration.lease)
        _ = try await operation.firstArrival()
        let retirement = await harness.session.beginProducerRetirement(
            lease,
            acknowledgeLifecycle: { acknowledgement in
                await acknowledgementGate.acknowledge(acknowledgement)
            },
            stopRequest: nil,
            abandonOutstandingDelivery: true
        )
        _ = await acknowledgementGate.waitUntilInvoked()

        // Act
        let retirementBarriers = await harness.session.metadataRetirementBarriersForReload()
        await acknowledgementGate.release(result: true)

        // Assert
        var barrierResults: [Bool] = []
        for barrier in retirementBarriers ?? [] {
            barrierResults.append(await barrier.wait())
        }
        #expect(retirementBarriers?.count == 1)
        #expect(barrierResults == [true])
        #expect(await retirement.wait())
        #expect(await harness.session.producerSnapshot().hasZeroResidue)
    }

    @Test("failed metadata retirement prevents reload admission")
    func failedMetadataRetirementPreventsReloadAdmission() async throws {
        // Arrange
        let harness = try await BridgeProductSessionProducerHarness.opened()
        let operation = HeldStep<BridgeProductProducerLease>("operation")
        let acknowledgementGate = BridgeProductProducerLifecycleAcknowledgementGate()
        let registration = await harness.session.registerMetadataProducer(
            request: try bridgeProductMetadataStreamRequest(
                metadataStreamId: "metadata-failed-reload-admission",
                resumeFromStreamSequence: nil
            ),
            productAdmission: harness.productAdmission
        ) { lease in
            try? await operation.arrive(lease)
        }
        let lease = try #require(registration.lease)
        _ = try await operation.firstArrival()
        let retirement = await harness.session.beginProducerRetirement(
            lease,
            acknowledgeLifecycle: { acknowledgement in
                await acknowledgementGate.acknowledge(acknowledgement)
            },
            stopRequest: nil,
            abandonOutstandingDelivery: true
        )
        _ = await acknowledgementGate.waitUntilInvoked()

        // Act
        let retirementBarriers = await harness.session.metadataRetirementBarriersForReload()
        await acknowledgementGate.release(result: false)

        // Assert
        var barrierResults: [Bool] = []
        for barrier in retirementBarriers ?? [] {
            barrierResults.append(await barrier.wait())
        }
        #expect(retirementBarriers?.count == 1)
        #expect(barrierResults == [false])
        #expect(!(await retirement.wait()))
        let cleanup = await harness.session.beginProducerRetirement(
            lease,
            acknowledgeLifecycle: { _ in true },
            stopRequest: nil,
            abandonOutstandingDelivery: true
        )
        #expect(await cleanup.wait())
    }

    @Test("exact scoped stop preserves other producers and old-epoch cleanup")
    func exactScopedStopAllowsOldEpochCleanup() async throws {
        // Arrange
        let registry = BridgeProductProducerRegistryTestHarness()
        let metadataRequest = try producerRegistryMetadataStreamRequest()
        let producerRegistryContentRequest = try producerRegistryContentRequest(workerDerivationEpoch: 2)
        let metadataOperation = HeldStep<BridgeProductProducerLease>("metadataOperation")
        let contentOperation = HeldStep<BridgeProductProducerLease>("contentOperation")
        let metadataRegistration = await registry.registerMetadataProducer(
            request: metadataRequest
        ) { lease in
            try? await metadataOperation.arrive(lease)
        }
        let contentRegistration = await registry.registerContentProducer(
            request: producerRegistryContentRequest
        ) { lease in
            try? await contentOperation.arrive(lease)
        }
        _ = try #require(metadataRegistration.lease)
        let contentLease = try #require(contentRegistration.lease)
        _ = try await metadataOperation.firstArrival()
        _ = try await contentOperation.firstArrival()
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
        let operation = HeldStep<BridgeProductProducerLease>("operation")
        let registration = await registry.registerMetadataProducer(request: request) { lease in
            try? await operation.arrive(lease)
        }
        let lease = try #require(registration.lease)
        _ = try await operation.firstArrival()

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
        let metadataOperation = HeldStep<BridgeProductProducerLease>("metadataOperation")
        let contentOperation = HeldStep<BridgeProductProducerLease>("contentOperation")
        let metadataRegistration = await registry.registerMetadataProducer(
            request: metadataRequest
        ) { lease in
            try? await metadataOperation.arrive(lease)
        }
        let contentRegistration = await registry.registerContentProducer(
            request: producerRegistryContentRequest
        ) { lease in
            try? await contentOperation.arrive(lease)
        }
        _ = try await metadataOperation.firstArrival()
        _ = try await contentOperation.firstArrival()
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
