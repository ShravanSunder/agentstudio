import AgentStudioTestHarness
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("File metadata preparation and post-open enrichment")
struct BridgePaneProductFileMetadataPreparationTests {
    @Test("source acceptance does not wait for ignore-policy preparation")
    func sourceAcceptancePrecedesIgnorePolicyPreparation() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let preparationGate = ProductFileMaterializationGate()
        let source = fixture.makeSource(ignorePolicyLoader: { _ in
            await preparationGate.markStarted()
            await preparationGate.waitUntilReleased()
            return .empty
        })
        let collector = ProductFileMetadataEventCollector()

        // Act
        let openTask = Task {
            try await source.open(
                subscription: fixture.openSnapshot(),
                productAdmission: fixture.productAdmission.context
            ) { event in
                await collector.append(event)
            }
        }
        await preparationGate.waitUntilStarted()
        let eventsBeforePreparationFinished = await collector.events
        await preparationGate.release()
        try await openTask.value

        // Assert
        #expect(
            eventsBeforePreparationFinished.contains {
                if case .sourceAccepted = $0 { true } else { false }
            }
        )
    }

    @Test("interest committed during preparation is fulfilled after the manifest is ready")
    func interestCommittedDuringPreparationIsFulfilled() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let preparationGate = ProductFileMaterializationGate()
        let source = fixture.makeSource(ignorePolicyLoader: { _ in
            await preparationGate.markStarted()
            await preparationGate.waitUntilReleased()
            return .empty
        })
        let collector = ProductFileMetadataEventCollector()
        let openSnapshot = try fixture.openSnapshot()
        let openTask = Task {
            try await source.open(
                subscription: openSnapshot,
                productAdmission: fixture.productAdmission.context
            ) { event in
                await collector.append(event)
            }
        }
        await preparationGate.waitUntilStarted()

        // Act
        try await source.applyViewDemand(
            subscriptionId: openSnapshot.subscriptionId,
            demand: fixture.viewDemand(),
            productAdmission: fixture.productAdmission.context,
            forceRecapture: false
        ) { event in
            await collector.append(event)
        }
        await preparationGate.release()
        try await openTask.value

        #expect((await collector.events).compactMap(\.availableDescriptorForTest).isEmpty)
        let demand = try fixture.viewDemand()
        let capture = try #require(
            await source.captureKeyedSnapshot(
                subscriptionId: openSnapshot.subscriptionId, demand: demand,
                productAdmission: fixture.productAdmission.context))
        let certificate = try sealProductFileSourceCapture(capture, demand: demand)
        #expect(certificate.mode == .snapshot)
        #expect(productFileBatchDescriptorCount(certificate) == 0)
        let batchFacts = LocalFactSource<String, BridgeProductSealedViewBatch>(
            vocabulary: .init(
                describeScope: { $0 }, describeFact: { "\($0.mode.rawValue):\($0.targetRevision)" },
                isClosing: { _, _ in false }))
        let recorder = try batchFacts.attach()
        let emitBatch = batchFacts.sink
        try await source.applyViewDemand(
            subscriptionId: openSnapshot.subscriptionId,
            demand: fixture.viewDemand(),
            productAdmission: fixture.productAdmission.context,
            forceRecapture: true
        ) { event in
            await collector.append(event)
            if case .descriptorReady = event,
                let enrichment = await source.captureKeyedSnapshot(
                    subscriptionId: openSnapshot.subscriptionId, demand: demand,
                    productAdmission: fixture.productAdmission.context)
            {
                emitBatch("File", try sealProductFileSourceCapture(enrichment, demand: demand))
            }
        }
        let enrichment = try await recorder.expectNext(
            in: "File", where: { productFileBatchDescriptorCount($0) == 1 }, "the demanded File descriptor batch")
        #expect(enrichment.mode == .snapshot)
        #expect(enrichment.targetRevision > certificate.targetRevision)
        batchFacts.end()
        try await recorder.finish()
        await source.cancel(subscriptionId: openSnapshot.subscriptionId)

        // Assert
        #expect(
            (await collector.events).contains {
                if case .descriptorReady = $0 { true } else { false }
            }
        )
    }

}
