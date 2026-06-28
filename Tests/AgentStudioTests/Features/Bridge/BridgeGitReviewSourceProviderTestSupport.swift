import Foundation

@testable import AgentStudio

func buildPackage(
    provider: BridgeGitReviewSourceProvider,
    query: BridgeReviewQuery,
    baseEndpoint: BridgeSourceEndpoint,
    headEndpoint: BridgeSourceEndpoint,
    reviewGeneration: BridgeReviewGeneration
) async throws -> BridgeReviewPackage {
    let comparison = try await provider.compareEndpoints(
        BridgeEndpointComparisonRequest(
            query: query,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            reviewGeneration: reviewGeneration
        )
    )
    return try BridgeReviewPackageBuilder.build(
        request: BridgeReviewPackageBuildRequest(
            packageId: "package-\(reviewGeneration.rawValue)",
            query: query,
            comparison: comparison,
            checkpointIds: [],
            reviewGeneration: reviewGeneration,
            generatedAtUnixMilliseconds: Int64(reviewGeneration.rawValue)
        )
    )
}
