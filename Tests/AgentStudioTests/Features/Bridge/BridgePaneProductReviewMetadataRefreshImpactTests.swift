import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Bridge pane product Review metadata refresh impact")
struct BridgePaneProductReviewMetadataRefreshImpactTests {
    @Test("carries refresh impact only on the atomic final Review metadata barrier")
    func carriesRefreshImpactOnlyOnFinalBarrier() async throws {
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
            try await collector.append(event)
        }

        _ = try await deliverReviewPackage(
            package,
            refreshImpact: impact,
            through: source,
            productAdmission: productAdmission.context
        )

        let windowImpacts = await collector.events.compactMap { event -> (BridgeReviewRefreshImpact?)? in
            switch event {
            case .snapshot(let snapshot):
                return snapshot.refreshImpact
            case .window(let window):
                return window.refreshImpact
            default:
                return nil
            }
        }
        #expect(windowImpacts.count > 1)
        #expect(windowImpacts.dropLast().allSatisfy { $0 == nil })
        #expect(windowImpacts.last == impact)
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
