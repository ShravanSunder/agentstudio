import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Review metadata interest update during publication")
struct BridgeReviewMetadataInterestPublicationRaceTests {
    @Test("interest update after reset cannot strand a committed successor")
    func interestUpdateAfterResetPreservesCompletePublication() async throws {
        // Arrange
        let admission = try BridgeProductAdmissionTestContext.make()
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        let updatedSubscription = try reviewSubscription(interestRevision: 1)
        let initialPackage = makeReviewPackage(itemCount: 4)
        try await source.open(
            subscription: try reviewSubscription(),
            productAdmission: admission.context
        ) { event, productAdmission in
            let result = try await collector.append(event.event)
            if case .reset = event.event {
                try await source.update(
                    subscription: updatedSubscription,
                    productAdmission: productAdmission
                ) { nextEvent, _ in
                    try await collector.append(nextEvent.event)
                }
            }
            return result
        }
        _ = try await deliverReviewPackage(
            initialPackage, through: source, productAdmission: admission.context
        )
        await collector.removeAll()
        let successor = replacingReviewSource(
            initialPackage,
            packageId: "review-interest-race-successor",
            queryId: "review-interest-race-query",
            generation: initialPackage.reviewGeneration.rawValue + 1
        )

        // Act
        let outcome = try await deliverReviewPackage(
            successor, through: source, productAdmission: admission.context
        )
        let receipt = try deliveredReviewReceipt(outcome)
        let events = await collector.events

        // Assert
        #expect(receipt.publishedSubscriptions == 1)
        #expect(receipt.superseded == 0)
        #expect(events.count == 3)
        guard events.count == 3,
            case .reset = events[0],
            case .sourceAccepted = events[1],
            case .snapshot(let snapshot) = events[2]
        else {
            Issue.record("Interest update stranded the successor before its complete snapshot")
            return
        }
        #expect(snapshot.itemWindow.finalWindow)
        #expect(snapshot.itemMetadata.count == successor.orderedItemIds.count)
        #expect(snapshot.identity.generation == successor.reviewGeneration.rawValue)
        await collector.removeAll()
        _ = try await deliverReviewPackage(
            successor, through: source, productAdmission: admission.context
        )
        #expect(await collector.events.isEmpty)
        await source.cancel(subscriptionId: updatedSubscription.subscriptionId)
    }
}
