import Foundation

actor BridgeReviewPipeline {
    private let provider: any BridgeReviewSourceProvider
    private let contentStore: BridgeContentStore

    init(
        provider: any BridgeReviewSourceProvider,
        contentStore: BridgeContentStore = BridgeContentStore()
    ) {
        self.provider = provider
        self.contentStore = contentStore
    }

    func loadPackage(_ request: BridgeReviewPipelineRequest) async throws -> BridgeReviewPipelineResult {
        let comparison = try await provider.compareEndpoints(
            BridgeEndpointComparisonRequest(
                query: request.query,
                baseEndpoint: request.baseEndpoint,
                headEndpoint: request.headEndpoint,
                reviewGeneration: request.reviewGeneration
            )
        )
        let package = try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: request.packageId,
                query: request.query,
                comparison: comparison,
                checkpointIds: request.checkpointIds,
                reviewGeneration: request.reviewGeneration,
                generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
            )
        )

        var registeredContentHandles: [BridgeContentHandle] = []
        for descriptor in package.itemsById.values {
            for handle in descriptor.contentRoles.allHandles {
                let result = try await provider.loadContent(
                    BridgeContentLoadRequest(
                        handle: handle,
                        requestedGeneration: request.reviewGeneration
                    )
                )
                await contentStore.register(result)
                registeredContentHandles.append(handle)
            }
        }

        return BridgeReviewPipelineResult(
            package: package,
            registeredContentHandles: registeredContentHandles
        )
    }
}
