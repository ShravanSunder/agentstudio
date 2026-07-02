import Foundation

/// Off-main review package assembly boundary for Bridge panes.
///
/// Keep this actor protocol-first unless a backend's public `Sendable` DTOs
/// exactly match Bridge review contracts. When they differ, the mapper belongs
/// behind `BridgeReviewSourceProvider`, not in the pipeline.
actor BridgeReviewPipeline {
    private let provider: any BridgeReviewSourceProvider

    init(provider: any BridgeReviewSourceProvider) {
        self.provider = provider
    }

    func loadPackage(_ request: BridgeReviewPipelineRequest) async throws -> BridgeReviewPipelineResult {
        let package: BridgeReviewPackage
        switch request.query.queryKind {
        case .compare, .filterPackage, .groupPackage:
            let comparison = try await provider.compareEndpoints(
                BridgeEndpointComparisonRequest(
                    query: request.query,
                    baseEndpoint: request.baseEndpoint,
                    headEndpoint: request.headEndpoint,
                    reviewGeneration: request.reviewGeneration
                )
            )
            package = try BridgeReviewPackageBuilder.build(
                request: BridgeReviewPackageBuildRequest(
                    packageId: request.packageId,
                    query: request.query,
                    comparison: comparison,
                    checkpointIds: request.checkpointIds,
                    reviewGeneration: request.reviewGeneration,
                    generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
                )
            )
        case .browseTree:
            let tree = try await provider.readTree(
                BridgeTreeReadRequest(
                    endpoint: request.headEndpoint,
                    pathScope: request.query.pathScope,
                    reviewGeneration: request.reviewGeneration
                )
            )
            package = try BridgeReviewPackageBuilder.buildFromDescriptors(
                request: BridgeReviewDescriptorPackageBuildRequest(
                    packageId: request.packageId,
                    query: request.query,
                    baseEndpoint: request.baseEndpoint,
                    headEndpoint: tree.endpoint,
                    descriptors: tree.descriptors,
                    checkpointIds: request.checkpointIds,
                    reviewGeneration: request.reviewGeneration,
                    generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
                )
            )
        case .openFile:
            guard let fileTarget = request.query.fileTarget else {
                throw BridgeProviderFailure.providerFailed(message: "openFile query requires fileTarget")
            }
            let comparison = try await provider.compareEndpoints(
                BridgeEndpointComparisonRequest(
                    query: request.query,
                    baseEndpoint: request.baseEndpoint,
                    headEndpoint: request.headEndpoint,
                    reviewGeneration: request.reviewGeneration
                )
            )
            if let changedFile = BridgeReviewPipeline.changedFile(in: comparison, matching: fileTarget) {
                package = try BridgeReviewPackageBuilder.build(
                    request: BridgeReviewPackageBuildRequest(
                        packageId: request.packageId,
                        query: request.query,
                        comparison: BridgeEndpointComparison(
                            baseEndpoint: comparison.baseEndpoint,
                            headEndpoint: comparison.headEndpoint,
                            changedFiles: [changedFile]
                        ),
                        checkpointIds: request.checkpointIds,
                        reviewGeneration: request.reviewGeneration,
                        generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
                    )
                )
            } else {
                let descriptor = try await provider.readReviewItemDescriptor(
                    BridgeReviewItemDescriptorRequest(
                        endpoint: request.headEndpoint,
                        path: fileTarget,
                        reviewGeneration: request.reviewGeneration
                    )
                )
                package = try BridgeReviewPackageBuilder.buildFromDescriptors(
                    request: BridgeReviewDescriptorPackageBuildRequest(
                        packageId: request.packageId,
                        query: request.query,
                        baseEndpoint: request.baseEndpoint,
                        headEndpoint: request.headEndpoint,
                        descriptors: [descriptor],
                        checkpointIds: request.checkpointIds,
                        reviewGeneration: request.reviewGeneration,
                        generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
                    )
                )
            }
        }

        let registeredContentHandles = package.itemsById.values
            .sorted { $0.itemId < $1.itemId }
            .flatMap { $0.contentRoles.allHandles }

        return BridgeReviewPipelineResult(
            package: package,
            registeredContentHandles: registeredContentHandles
        )
    }

    private static func changedFile(
        in comparison: BridgeEndpointComparison,
        matching fileTarget: String
    ) -> BridgeEndpointChangedFile? {
        comparison.changedFiles.first { changedFile in
            changedFile.path == fileTarget || changedFile.oldPath == fileTarget
        }
    }
}
