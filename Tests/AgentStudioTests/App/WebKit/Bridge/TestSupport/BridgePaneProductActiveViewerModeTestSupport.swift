@testable import AgentStudioBridge

func productActiveViewerSuccessorReviewPackage(
    from package: BridgeReviewPackage
) -> BridgeReviewPackage {
    BridgeReviewPackage(
        packageId: "\(package.packageId)-successor",
        schemaVersion: package.schemaVersion,
        reviewGeneration: package.reviewGeneration.next(),
        revision: package.revision + 1,
        query: package.query,
        baseEndpoint: package.baseEndpoint,
        headEndpoint: package.headEndpoint,
        orderedItemIds: [],
        itemsById: [:],
        groups: [],
        summary: BridgeReviewPackageSummary(
            filesChanged: 0,
            additions: 0,
            deletions: 0,
            visibleFileCount: 0,
            hiddenFileCount: 0
        ),
        filterState: package.filterState,
        generatedAtUnixMilliseconds: package.generatedAtUnixMilliseconds + 1,
        changesetCluster: nil
    )
}
