import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Bridge pane product Review metadata bootstrap")
struct BridgePaneProductReviewMetadataBootstrapTests {
    @Test("reopened subscriber bootstraps the complete current package without reset")
    func reopenedSubscriberBootstrapsCompleteCurrentPackageWithoutReset() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        let subscription = try reviewSubscription()
        let package = makeReviewPackage(itemCount: 4)
        try await source.open(
            subscription: subscription,
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event.event)
        }
        _ = try await deliverReviewPackage(
            package,
            through: source,
            productAdmission: productAdmission.context
        )
        await source.cancel(subscriptionId: subscription.subscriptionId)
        await collector.removeAll()

        // Act
        try await source.open(
            subscription: subscription,
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event.event)
        }
        let outcome = try await deliverReviewPackage(
            package,
            through: source,
            productAdmission: productAdmission.context
        )

        // Assert
        let events = await collector.events
        let receipt = try deliveredReviewReceipt(outcome)
        #expect(receipt.emittedEvents == 2)
        guard events.count == 2,
            case .sourceAccepted(let accepted) = events[0],
            case .snapshot(let snapshot) = events[1]
        else {
            Issue.record("Expected reopened sourceAccepted followed by one complete snapshot")
            return
        }
        #expect(accepted.identity == reviewIdentity(for: package))
        #expect(snapshot.identity == reviewIdentity(for: package))
        #expect(snapshot.itemMetadata.map(\.itemId) == package.orderedItemIds)
        #expect(
            events.allSatisfy { event in
                if case .reset = event { return false }
                return true
            })
    }
}
