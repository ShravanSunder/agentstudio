import Testing

@testable import AgentStudioBridge

@Suite("Bridge Review metadata publication projection plan")
struct BridgeReviewMetadataPublicationProjectionPlanTests {
    @Test("reservation carries one immutable projection and window plan into delivery")
    func reservationCarriesProjectionPlanIntoDelivery() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let package = makeReviewPackage(itemCount: 3420)
        let source = BridgePaneProductReviewMetadataSource()
        let collector = ReviewMetadataEventCollector()
        try await source.open(
            subscription: try reviewSubscription(),
            productAdmission: productAdmission.context
        ) { sealedEvent, _ in
            try await collector.append(sealedEvent.event)
        }

        // Act
        let reservation = try await source.reserve(
            package: package,
            publicationId: reviewMetadataTestPublicationId,
            productAdmission: productAdmission.context
        )
        let outcome = try await source.deliver(
            publication: reviewMetadataCommittedPublication(package),
            reservation: reservation,
            productAdmission: productAdmission.context
        )

        // Assert
        let plan = reservation.projectionPlan
        #expect(plan.packageId == package.packageId)
        #expect(plan.publicationId == reviewMetadataTestPublicationId)
        #expect(plan.reviewGeneration == package.reviewGeneration)
        #expect(plan.revision == package.revision)
        #expect(plan.itemCount == package.orderedItemIds.count)
        #expect(plan.windows.count > 1)
        #expect(plan.windows.first?.isSnapshot == true)
        #expect(plan.windows.dropFirst().allSatisfy { !$0.isSnapshot })
        #expect(plan.windows.last?.itemRange.upperBound == plan.itemCount)
        #expect(plan.windows.last?.treeRowRange.upperBound == plan.treeRowCount)
        #expect(try deliveredReviewReceipt(outcome).emittedEvents == 1 + plan.windows.count)
        #expect(await collector.events.count == 1 + plan.windows.count)
    }
}
