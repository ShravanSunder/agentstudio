import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane product metadata resume disposition")
struct BridgePaneProductMetadataResumeDispositionTests {
    @Test("fresh metadata stream opens with snapshot-required through the production provider")
    func freshMetadataStreamRequiresSnapshotThroughProductionProvider() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-fresh-production-provider",
            resumeFromStreamSequence: nil
        )

        // Act
        let observation = try await observeProductionProviderOpening(request: request, harness: harness)

        // Assert
        #expect(observation.providerInvocationCount == 1)
        #expect(observation.didRetireProducer)
        #expect(observation.finalProducerSnapshot.hasZeroResidue)
        guard case .frame(let delivery)? = observation.pullResult else {
            Issue.record("Expected a fresh metadata opening")
            return
        }
        let accepted = try metadataAcceptedFrame(from: delivery)
        #expect(delivery.frame.sequence == 0)
        #expect(accepted.frameIdentity.streamSequence == 0)
        #expect(accepted.resumeDisposition == .snapshotRequired)
    }

    @Test("retired metadata lease cannot enqueue another opening")
    func retiredMetadataLeaseRejectsOpening() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let lease = try await harness.admitMetadataFrames(through: 0)
        try await harness.closeProducer(lease)

        // Act
        let result = try await harness.session.enqueueRequiredMetadataOpeningFrame(
            for: lease,
            productAdmission: harness.productAdmission.context
        )

        // Assert
        #expect(result == .rejected(.unknownLease))
        #expect(await harness.session.producerSnapshot().hasZeroResidue)
    }

    @Test("lagging metadata cursor opens with snapshot-required through the production provider")
    func laggingMetadataCursorRequiresSnapshotThroughProductionProvider() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let retiredLease = try await harness.admitMetadataFrames(through: 3)
        try await harness.closeProducer(retiredLease)
        let highWaterSnapshot = await harness.session.producerSnapshot()
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-lagging-production-provider",
            resumeFromStreamSequence: 1
        )

        // Act
        let observation = try await observeProductionProviderOpening(
            request: request,
            harness: harness
        )

        // Assert
        #expect(highWaterSnapshot.nextMetadataStreamSequence == 4)
        #expect(highWaterSnapshot.hasZeroResidue)
        #expect(observation.providerInvocationCount == 1)
        #expect(observation.didRetireProducer)
        #expect(observation.finalProducerSnapshot.hasZeroResidue)
        guard case .frame(let delivery)? = observation.pullResult else {
            Issue.record(
                "Expected a lagging-cursor metadata opening; received \(String(describing: observation.pullResult))"
            )
            return
        }
        let accepted = try metadataAcceptedFrame(from: delivery)
        #expect(delivery.frame.sequence == 2)
        #expect(accepted.frameIdentity.streamSequence == 2)
        #expect(accepted.resumeDisposition == .snapshotRequired)
    }

    @Test("exact-head metadata cursor resumes through the production provider")
    func exactHeadMetadataCursorResumesThroughProductionProvider() async throws {
        // Arrange
        let harness = try await BridgeProductSessionLifecycleHarness.opened()
        let retiredLease = try await harness.admitMetadataFrames(through: 3)
        try await harness.closeProducer(retiredLease)
        let request = try bridgeProductMetadataStreamRequest(
            metadataStreamId: "metadata-exact-head-production-provider",
            resumeFromStreamSequence: 3
        )

        // Act
        let observation = try await observeProductionProviderOpening(
            request: request,
            harness: harness
        )

        // Assert
        #expect(observation.providerInvocationCount == 1)
        #expect(observation.didRetireProducer)
        #expect(observation.finalProducerSnapshot.hasZeroResidue)
        guard case .frame(let delivery)? = observation.pullResult else {
            Issue.record(
                "Expected an exact-head metadata opening; received \(String(describing: observation.pullResult))"
            )
            return
        }
        let accepted = try metadataAcceptedFrame(from: delivery)
        #expect(delivery.frame.sequence == 4)
        #expect(accepted.frameIdentity.streamSequence == 4)
        #expect(accepted.resumeDisposition == .resumed)
    }
}

private struct ProductionProviderOpeningObservation {
    let didRetireProducer: Bool
    let finalProducerSnapshot: BridgeProductProducerRegistrySnapshot
    let providerInvocationCount: Int
    let pullResult: BridgeProductProducerFramePullResult?
}

private actor ProductionMetadataProviderInvocationProbe {
    private(set) var count = 0

    func recordInvocation() {
        count += 1
    }
}

private func observeProductionProviderOpening(
    request: BridgeProductMetadataStreamRequest,
    harness: BridgeProductSessionLifecycleHarness
) async throws -> ProductionProviderOpeningObservation {
    let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
    let provider = BridgePaneProductSchemeProvider(
        fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
        reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
        reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
        markReviewItemViewed: { _, _ in },
        refreshWorkAdmissionSource: refreshWorkAdmission.source
    )
    let invocationProbe = ProductionMetadataProviderInvocationProbe()
    let session = harness.session
    let productAdmission = harness.productAdmission.context
    let registration = await session.registerMetadataProducer(
        request: request,
        productAdmission: productAdmission
    ) { lease in
        await invocationProbe.recordInvocation()
        await provider.runMetadataProducer(
            request: request,
            lease: lease,
            productAdmission: productAdmission,
            session: session
        )
    }
    guard case .accepted(let lease) = registration else {
        await provider.closeAndDrain()
        throw ProductionProviderOpeningTestError.expectedAcceptedRegistration
    }
    let pump = BridgeProductSchemeFramePump(
        session: session,
        producerLease: lease,
        productAdmission: productAdmission,
        acknowledgeLifecycle: provider.acknowledgeLifecycle
    )
    let openingAvailable = await waitForMetadataOpening(in: session)
    let pullResult = openingAvailable ? await pump.nextFrame() : nil
    let providerInvocationCount = await invocationProbe.count
    let didRetireProducer = await pump.cancel()
    await provider.closeAndDrain()
    let finalProducerSnapshot = await session.producerSnapshot()
    return ProductionProviderOpeningObservation(
        didRetireProducer: didRetireProducer,
        finalProducerSnapshot: finalProducerSnapshot,
        providerInvocationCount: providerInvocationCount,
        pullResult: pullResult
    )
}

private func waitForMetadataOpening(in session: BridgeProductSession) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if await session.producerSnapshot().queuedFrameCount > 0 {
            return true
        }
        await Task.yield()
    }
    return await session.producerSnapshot().queuedFrameCount > 0
}

private func metadataAcceptedFrame(
    from delivery: BridgeProductProducerFrameDelivery
) throws -> BridgeProductMetadataStreamAcceptedFrame {
    let decoder = try BridgeProductMetadataFrameDecoder()
    let frame = try #require(try decoder.append(delivery.frame.data).first)
    guard case .metadataStreamAccepted(let accepted) = frame else {
        throw ProductionProviderOpeningTestError.expectedMetadataAcceptedFrame
    }
    return accepted
}

private enum ProductionProviderOpeningTestError: Error {
    case expectedAcceptedRegistration
    case expectedMetadataAcceptedFrame
}
