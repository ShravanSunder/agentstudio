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

    func resolveSharedConstructionRequest(
        _ request: BridgeReviewPipelineRequest,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeReviewPipelineRequest {
        guard let sharedProvider = provider as? any BridgeSharedReviewConstructionSourceProvider else {
            throw unsupportedSharedConstruction()
        }
        let baseEndpoint = try await sharedProvider.resolveEndpoint(
            BridgeEndpointResolutionRequest(endpoint: request.baseEndpoint),
            freshnessKey: freshnessKey
        )
        let headEndpoint = try await sharedProvider.resolveEndpoint(
            BridgeEndpointResolutionRequest(endpoint: request.headEndpoint),
            freshnessKey: freshnessKey
        )
        let query = BridgeReviewQuery(
            queryId: request.query.queryId,
            queryKind: request.query.queryKind,
            repoId: request.query.repoId,
            worktreeId: request.query.worktreeId,
            baseEndpointId: baseEndpoint.endpointId,
            headEndpointId: headEndpoint.endpointId,
            comparisonSemantics: request.query.comparisonSemantics,
            pathScope: request.query.pathScope,
            fileTarget: request.query.fileTarget,
            viewFilter: request.query.viewFilter,
            grouping: request.query.grouping,
            provenanceFilter: request.query.provenanceFilter
        )
        return BridgeReviewPipelineRequest(
            packageId: request.packageId,
            query: query,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            checkpointIds: request.checkpointIds,
            reviewGeneration: request.reviewGeneration,
            generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
        )
    }

    func buildSharedTemplate(
        request: BridgeReviewPipelineRequest,
        baseEndpointKey: BridgeResolvedReviewEndpointKey,
        headEndpointKey: BridgeResolvedReviewEndpointKey,
        freshnessKey: BridgeGitReadFreshnessKey
    ) async throws -> BridgeSharedReviewPackageTemplate {
        guard let sharedProvider = provider as? any BridgeSharedReviewConstructionSourceProvider else {
            throw unsupportedSharedConstruction()
        }
        let result = try await loadPackage(request, freshnessKey: freshnessKey)
        let backing = try await sharedProvider.captureSharedContent(
            handles: result.registeredContentHandles,
            freshnessKey: freshnessKey
        )
        return BridgeSharedReviewPackageTemplate.make(
            result: result,
            baseEndpointKey: baseEndpointKey,
            headEndpointKey: headEndpointKey,
            backing: backing
        )
    }

    func bindSharedTemplate(
        _ template: BridgeSharedReviewPackageTemplate,
        request: BridgeReviewPipelineRequest
    ) async throws -> BridgeReviewPipelineResult {
        guard let sharedProvider = provider as? any BridgeSharedReviewConstructionSourceProvider,
            let backing = template.backing
        else {
            throw BridgeProviderFailure.providerFailed(
                message: "Review provider does not support shared construction"
            )
        }
        let result = try template.bind(request)
        try await sharedProvider.installSharedContent(
            backing: backing,
            handles: result.registeredContentHandles
        )
        return result
    }

    func loadPackage(_ request: BridgeReviewPipelineRequest) async throws -> BridgeReviewPipelineResult {
        try await loadPackage(request, freshnessKey: nil)
    }

    private func loadPackage(
        _ request: BridgeReviewPipelineRequest,
        freshnessKey: BridgeGitReadFreshnessKey?
    ) async throws -> BridgeReviewPipelineResult {
        let package: BridgeReviewPackage
        switch request.query.queryKind {
        case .compare, .filterPackage, .groupPackage:
            let comparison = try await compareEndpoints(
                comparisonRequest(for: request),
                freshnessKey: freshnessKey
            )
            package = try buildPackage(request: request, comparison: comparison)
        case .browseTree:
            let tree = try await readTree(
                request: BridgeTreeReadRequest(
                    endpoint: request.headEndpoint,
                    pathScope: request.query.pathScope,
                    reviewGeneration: request.reviewGeneration
                ),
                freshnessKey: freshnessKey
            )
            package = try buildDescriptorPackage(
                request: request,
                headEndpoint: tree.endpoint,
                descriptors: tree.descriptors
            )
        case .openFile:
            guard let fileTarget = request.query.fileTarget else {
                throw BridgeProviderFailure.providerFailed(message: "openFile query requires fileTarget")
            }
            let comparison = try await compareEndpoints(
                comparisonRequest(for: request),
                freshnessKey: freshnessKey
            )
            if let changedFile = BridgeReviewPipeline.changedFile(in: comparison, matching: fileTarget) {
                package = try buildPackage(
                    request: request,
                    comparison: BridgeEndpointComparison(
                        baseEndpoint: comparison.baseEndpoint,
                        headEndpoint: comparison.headEndpoint,
                        changedFiles: [changedFile]
                    )
                )
            } else {
                let descriptor = try await readReviewItemDescriptor(
                    request: BridgeReviewItemDescriptorRequest(
                        endpoint: request.headEndpoint,
                        path: fileTarget,
                        reviewGeneration: request.reviewGeneration
                    ),
                    freshnessKey: freshnessKey
                )
                package = try buildDescriptorPackage(
                    request: request,
                    headEndpoint: request.headEndpoint,
                    descriptors: [descriptor]
                )
            }
        }
        return pipelineResult(package: package)
    }

    private func compareEndpoints(
        _ request: BridgeEndpointComparisonRequest,
        freshnessKey: BridgeGitReadFreshnessKey?
    ) async throws -> BridgeEndpointComparison {
        guard let freshnessKey else { return try await provider.compareEndpoints(request) }
        guard let sharedProvider = provider as? any BridgeSharedReviewConstructionSourceProvider else {
            throw unsupportedSharedConstruction()
        }
        return try await sharedProvider.compareEndpoints(request, freshnessKey: freshnessKey)
    }

    private func readTree(
        request: BridgeTreeReadRequest,
        freshnessKey: BridgeGitReadFreshnessKey?
    ) async throws -> BridgeTreeReadResult {
        guard let freshnessKey else { return try await provider.readTree(request) }
        guard let sharedProvider = provider as? any BridgeSharedReviewConstructionSourceProvider else {
            throw unsupportedSharedConstruction()
        }
        return try await sharedProvider.readTree(request, freshnessKey: freshnessKey)
    }

    private func readReviewItemDescriptor(
        request: BridgeReviewItemDescriptorRequest,
        freshnessKey: BridgeGitReadFreshnessKey?
    ) async throws -> BridgeReviewItemDescriptor {
        guard let freshnessKey else { return try await provider.readReviewItemDescriptor(request) }
        guard let sharedProvider = provider as? any BridgeSharedReviewConstructionSourceProvider else {
            throw unsupportedSharedConstruction()
        }
        return try await sharedProvider.readReviewItemDescriptor(request, freshnessKey: freshnessKey)
    }

    private func comparisonRequest(
        for request: BridgeReviewPipelineRequest
    ) -> BridgeEndpointComparisonRequest {
        BridgeEndpointComparisonRequest(
            query: request.query,
            baseEndpoint: request.baseEndpoint,
            headEndpoint: request.headEndpoint,
            reviewGeneration: request.reviewGeneration
        )
    }

    private func buildPackage(
        request: BridgeReviewPipelineRequest,
        comparison: BridgeEndpointComparison
    ) throws -> BridgeReviewPackage {
        try BridgeReviewPackageBuilder.build(
            request: BridgeReviewPackageBuildRequest(
                packageId: request.packageId,
                query: request.query,
                comparison: comparison,
                checkpointIds: request.checkpointIds,
                reviewGeneration: request.reviewGeneration,
                generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
            )
        )
    }

    private func buildDescriptorPackage(
        request: BridgeReviewPipelineRequest,
        headEndpoint: BridgeSourceEndpoint,
        descriptors: [BridgeReviewItemDescriptor]
    ) throws -> BridgeReviewPackage {
        try BridgeReviewPackageBuilder.buildFromDescriptors(
            request: BridgeReviewDescriptorPackageBuildRequest(
                packageId: request.packageId,
                query: request.query,
                baseEndpoint: request.baseEndpoint,
                headEndpoint: headEndpoint,
                descriptors: descriptors,
                checkpointIds: request.checkpointIds,
                reviewGeneration: request.reviewGeneration,
                generatedAtUnixMilliseconds: request.generatedAtUnixMilliseconds
            )
        )
    }

    private func pipelineResult(package: BridgeReviewPackage) -> BridgeReviewPipelineResult {
        BridgeReviewPipelineResult(
            package: package,
            registeredContentHandles: package.itemsById.values
                .sorted { $0.itemId < $1.itemId }
                .flatMap { $0.contentRoles.allHandles }
        )
    }

    private func unsupportedSharedConstruction() -> BridgeProviderFailure {
        BridgeProviderFailure.providerFailed(
            message: "Review provider does not support shared construction"
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
