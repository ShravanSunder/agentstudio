import Testing

@testable import AgentStudio

@Suite("Bridge product producer capacity")
struct BridgeProductProducerCapacityTests {
    @Test("content producer lifecycle residue limit is positive and contract bounded")
    func lifecycleResidueLimitConstructorGuards() throws {
        // Arrange
        let productLimits = BridgeProductProducerQueueLimits.productContract

        // Act and assert
        #expect(throws: BridgeProductProducerQueueLimitsError.invalidContentProducerResidueLimit) {
            _ = try capacityLimits(
                maximumLifecycleResidueCount: 0,
                productLimits: productLimits
            )
        }
        #expect(
            throws: BridgeProductProducerQueueLimitsError
                .contentProducerResidueLimitExceedsProductContract
        ) {
            _ = try capacityLimits(
                maximumLifecycleResidueCount:
                    BridgeProductProducerQueueLimits
                    .maximumProductContentProducerLifecycleResidueCount + 1,
                productLimits: productLimits
            )
        }
    }

    @Test("pending lifecycle acknowledgement retains capacity until residue is removed")
    func pendingAcknowledgementRetainsContentProducerCapacity() async throws {
        // Arrange
        let productLimits = BridgeProductProducerQueueLimits.productContract
        let limits = try capacityLimits(
            maximumLifecycleResidueCount: 2,
            productLimits: productLimits
        )
        let registry = BridgeProductProducerRegistryTestHarness(limits: limits)
        let firstOperation = BridgeProductProducerOperationGate()
        let secondOperation = BridgeProductProducerOperationGate()
        let firstRequest = try producerRegistryContentRequest(workerDerivationEpoch: 1)
        let secondRequest = try producerRegistryContentRequest(workerDerivationEpoch: 2)
        let firstRegistration = await registry.registerContentProducer(
            request: firstRequest
        ) { lease in
            await firstOperation.run(lease)
        }
        let secondRegistration = await registry.registerContentProducer(
            request: secondRequest
        ) { lease in
            await secondOperation.run(lease)
        }
        let firstLease = try bridgeProductAcceptedLease(firstRegistration)
        _ = try bridgeProductAcceptedLease(secondRegistration)
        _ = await firstOperation.waitUntilStarted()
        _ = await secondOperation.waitUntilStarted()

        // Act and assert: two active producers consume the complete capacity.
        let thirdInvocation = BridgeProductProducerInvocationCounter()
        let thirdRegistration = await registry.registerContentProducer(
            request: try producerRegistryContentRequest(workerDerivationEpoch: 3)
        ) { _ in
            await thirdInvocation.recordInvocation()
        }
        #expect(
            thirdRegistration
                == .rejected(
                    .contentProducerCapacityReached(
                        maximumLifecycleResidueCount: 2
                    )
                )
        )
        #expect(!(await thirdInvocation.wasInvoked))

        // Act and assert: unregistering retains the slot until acknowledgement.
        #expect(await registry.stop(firstLease))
        guard let firstAcknowledgement = await registry.unregister(firstLease) else {
            Issue.record("Expected the stopped producer to unregister")
            return
        }
        let pendingSnapshot = await registry.snapshot()
        let pendingInvocation = BridgeProductProducerInvocationCounter()
        let pendingRegistration = await registry.registerContentProducer(
            request: try producerRegistryContentRequest(workerDerivationEpoch: 4)
        ) { _ in
            await pendingInvocation.recordInvocation()
        }
        #expect(pendingSnapshot.activeContentLeaseCount == 1)
        #expect(pendingSnapshot.pendingLifecycleAcknowledgementCount == 1)
        #expect(
            pendingRegistration
                == .rejected(
                    .contentProducerCapacityReached(
                        maximumLifecycleResidueCount: 2
                    )
                )
        )
        #expect(!(await pendingInvocation.wasInvoked))

        // Act and assert: acknowledgement removes residue and reopens one slot.
        #expect(await registry.acknowledgeLifecycle(firstAcknowledgement))
        let replacementOperation = BridgeProductProducerOperationGate()
        let replacementRegistration = await registry.registerContentProducer(
            request: try producerRegistryContentRequest(workerDerivationEpoch: 5)
        ) { lease in
            await replacementOperation.run(lease)
        }
        #expect(replacementRegistration.lease != nil)
        _ = await replacementOperation.waitUntilStarted()
        #expect((await registry.snapshot()).activeContentLeaseCount == 2)

        try await closeAllProducerRegistryProducers(in: registry)
        #expect((await registry.snapshot()).hasZeroResidue)
    }
}

private func capacityLimits(
    maximumLifecycleResidueCount: Int,
    productLimits: BridgeProductProducerQueueLimits
) throws -> BridgeProductProducerQueueLimits {
    try BridgeProductProducerQueueLimits(
        maximumContentProducerLifecycleResidueCount: maximumLifecycleResidueCount,
        maximumQueuedFrameCount: productLimits.maximumQueuedFrameCount,
        maximumQueuedByteCount: productLimits.maximumQueuedByteCount,
        maximumEncodedFrameByteCount: productLimits.maximumEncodedFrameByteCount,
        terminalFrameReserve: productLimits.terminalFrameReserve
    )
}

extension BridgeProductProducerRegistration {
    fileprivate var lease: BridgeProductProducerLease? {
        guard case .accepted(let lease) = self else { return nil }
        return lease
    }
}
