import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Review metadata scope update during publication")
struct BridgeReviewMetadataInterestPublicationRaceTests {
    @Test("a stale scope cannot strand a committed Review successor")
    func staleScopeAfterSuccessorPreservesCompletePublication() async throws {
        let admission = try BridgeProductAdmissionTestContext.make()
        let source = BridgePaneProductReviewMetadataSource()
        let initialPackage = makeReviewPackage(itemCount: 4)
        let successor = replacingReviewSource(
            initialPackage,
            packageId: "review-interest-race-successor",
            queryId: "review-interest-race-query",
            generation: initialPackage.reviewGeneration.rawValue + 1
        )
        let successorPublicationId = UUID(uuidString: "22222222-2222-7222-8222-222222222222")!
        try await source.open(
            subscription: reviewSubscription(),
            productAdmission: admission.context
        )
        _ = try await deliverReviewPackage(
            initialPackage, through: source, productAdmission: admission.context
        )
        let selectedItemId = try #require(initialPackage.orderedItemIds.first)
        let first = try #require(
            try await applyReviewViewDemand(
                through: source, scopeRevision: 1, admissionSequence: 1,
                itemIds: [selectedItemId],
                productAdmission: admission.context
            )
        )
        #expect(first.snapshot.items.map(\.record.itemId) == initialPackage.orderedItemIds)

        let outcome = try await deliverReviewPackage(
            successor, publicationId: successorPublicationId,
            through: source, productAdmission: admission.context
        )
        #expect(try deliveredReviewReceipt(outcome).publishedSubscriptions == 1)
        #expect(
            try await applyReviewViewDemand(
                through: source, handle: "review-stale-handle", scopeRevision: 3,
                admissionSequence: 0, itemIds: initialPackage.orderedItemIds,
                expectedPublicationId: reviewMetadataTestPublicationId,
                productAdmission: admission.context
            ) == nil
        )
        let capture = try #require(
            try await applyReviewViewDemand(
                through: source, scopeRevision: 2, admissionSequence: 2,
                itemIds: successor.orderedItemIds,
                expectedPublicationId: successorPublicationId,
                productAdmission: admission.context
            )
        )
        #expect(capture.publicationId == successorPublicationId)
        #expect(capture.snapshot.publication.displayed?.packageId == successor.packageId)
        #expect(capture.snapshot.items.map(\.record.itemId) == successor.orderedItemIds)
        await source.cancel(subscriptionId: "review-subscription-1")
    }
}
