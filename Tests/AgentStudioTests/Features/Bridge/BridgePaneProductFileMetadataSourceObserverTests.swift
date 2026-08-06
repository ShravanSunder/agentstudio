import Foundation
import Testing

@testable import AgentStudioBridge

extension BridgePaneProductFileMetadataSourceTests {
    @Test("accepted-source observer receives the exact emitted File identity")
    func acceptedSourceObserverReceivesEmittedIdentity() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let (observedSources, observedSourceContinuation) =
            AsyncStream<BridgeProductFileSourceIdentity>.makeStream()
        let source = fixture.makeSource(sourceAcceptedObserver: { acceptedSource in
            observedSourceContinuation.yield(acceptedSource)
        })
        let collector = ProductFileMetadataEventCollector()

        // Act
        try await source.open(
            subscription: fixture.openSnapshot(),
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }
        var observedSourceIterator = observedSources.makeAsyncIterator()
        let observedSource = try #require(await observedSourceIterator.next())
        observedSourceContinuation.finish()

        // Assert
        let emittedSource = try #require(
            (await collector.events).compactMap { event -> BridgeProductFileSourceIdentity? in
                guard case .sourceAccepted(let accepted) = event else { return nil }
                return accepted.source
            }.first
        )
        #expect(observedSource == emittedSource)
    }
}
