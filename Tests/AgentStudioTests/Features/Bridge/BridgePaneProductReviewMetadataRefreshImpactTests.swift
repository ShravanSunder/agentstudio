import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Bridge pane product Review metadata refresh impact")
struct BridgePaneProductReviewMetadataRefreshImpactTests {
    @Test("same-looking unclassified successor remains a replacement")
    func sameLookingUnclassifiedSuccessorRemainsReplacement() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let initialPackage = makeReviewPackage(itemCount: 2)
        let changedItemId = try #require(initialPackage.orderedItemIds.first)
        let unclassifiedSuccessor = replacingReviewItem(
            in: initialPackage,
            itemId: changedItemId,
            fileClass: .config,
            revision: initialPackage.revision + 1
        )
        let source = BridgePaneProductReviewMetadataSource()
        let collector = RefreshImpactReviewMetadataEventCollector()
        try await source.open(
            subscription: try refreshImpactReviewSubscription(),
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event.event)
        }
        _ = try await deliverReviewPackage(
            initialPackage,
            through: source,
            productAdmission: productAdmission.context
        )
        await collector.removeAll()

        _ = try await deliverReviewPackage(
            unclassifiedSuccessor,
            through: source,
            productAdmission: productAdmission.context
        )

        let events = await collector.events
        guard case .reset(let reset) = events.first else {
            Issue.record("Expected unclassified same-looking successor to reset")
            return
        }
        #expect(reset.refreshImpact == nil)
        #expect(!events.contains { if case .delta = $0 { true } else { false } })
    }

    @Test("initial Review windows omit same-source refresh classification")
    func initialReviewWindowsOmitSameSourceRefreshClassification() async throws {
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let package = makeReviewPackage(itemCount: 130)
        let impact = BridgeReviewRefreshImpact.exact(
            newlyImportedCommitCount: 10,
            affectedFileCount: 2,
            addedLineCount: 4,
            deletedLineCount: 3,
            affectedStableFileIdentities: ["review-item-00000", "review-item-00001"]
        )
        let source = BridgePaneProductReviewMetadataSource()
        let collector = RefreshImpactReviewMetadataEventCollector()
        try await source.open(
            subscription: try refreshImpactReviewSubscription(),
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event.event)
        }

        _ = try await deliverReviewPackage(
            package,
            classifiedRefreshImpact: impact,
            through: source,
            productAdmission: productAdmission.context
        )

        let windowCount = await collector.events.filter { event in
            if case .snapshot = event { return true }
            if case .window = event { return true }
            return false
        }.count
        #expect(windowCount > 1)
    }

    @Test("promoted unknown remains encodable beyond one metadata-window identity limit")
    func carriesSymbolicUnknownForLargeReview() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let package = makeReviewPackage(itemCount: 4097)
        let impact = BridgeReviewRefreshImpact.unknown(
            displayedPackage: package,
            candidatePackage: package
        )
        let source = BridgePaneProductReviewMetadataSource()
        let collector = RefreshImpactReviewMetadataEventCollector()
        try await source.open(
            subscription: try refreshImpactReviewSubscription(),
            productAdmission: productAdmission.context
        ) { event, _ in
            try await collector.append(event.event)
        }

        // Act
        _ = try await deliverReviewPackage(
            package,
            classifiedRefreshImpact: impact,
            through: source,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(impact.affectedStableFileIdentities.isEmpty)
    }
}

private actor RefreshImpactReviewMetadataEventCollector {
    private(set) var events: [BridgeProductReviewMetadataEvent] = []
    private var nextSequence = 0

    func append(_ event: BridgeProductReviewMetadataEvent) throws -> BridgeProductProducerEnqueueResult {
        nextSequence += 1
        events.append(event)
        return try reviewMetadataEnqueueResult(event, sequence: nextSequence)
    }

    func removeAll() {
        events.removeAll()
    }
}

private func refreshImpactReviewSubscription() throws -> BridgeProductSubscriptionSnapshot {
    let interestState = BridgeProductSubscriptionInterestState.reviewMetadata(interests: [])
    return BridgeProductSubscriptionSnapshot(
        subscription: .reviewMetadata,
        subscriptionId: "review-refresh-impact-subscription-1",
        subscriptionKind: .reviewMetadata,
        workerDerivationEpoch: 1,
        interestRevision: 0,
        interestSha256: try interestState.sha256Hex(),
        interestState: interestState,
        hasStagedUpdate: false
    )
}
