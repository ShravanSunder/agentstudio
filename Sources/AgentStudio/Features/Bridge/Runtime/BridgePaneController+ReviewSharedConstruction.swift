import Foundation

extension BridgePaneController {
    static func makeReviewSharedConstructionBinder(
        coordinator: BridgeWorktreeProductConstructionCoordinator?,
        pipeline: BridgeReviewPipeline,
        provider: any BridgeReviewSourceProvider,
        state: BridgePaneState
    ) -> BridgePaneReviewSharedConstructionBinder? {
        guard let coordinator,
            provider is any BridgeSharedReviewConstructionSourceProvider,
            case .workspace(let rootPath, _) = state.source
        else { return nil }
        return BridgePaneReviewSharedConstructionBinder(
            coordinator: coordinator,
            pipeline: pipeline,
            repositoryPath: URL(fileURLWithPath: rootPath)
        )
    }

    func acquireReviewPackage(
        _ request: BridgeReviewPipelineRequest
    ) async throws -> BridgeReviewPackageConstructionResult {
        guard let reviewSharedConstructionBinder else {
            return BridgeReviewPackageConstructionResult(
                result: try await reviewPipeline.loadPackage(request),
                artifactPin: nil
            )
        }
        let binding = try await reviewSharedConstructionBinder.acquire(request)
        return BridgeReviewPackageConstructionResult(
            result: binding.result,
            artifactPin: binding.artifactPin
        )
    }

    func consumePendingReviewPackageBuildReason(
        default defaultReason: BridgeReviewPackageBuildReason
    ) -> BridgeReviewPackageBuildReason {
        let reasonPriority: [BridgeReviewPackageBuildReason] = [
            .fallbackUnresolvedHead,
            .initialIntake,
            .productResync,
            .filesystemRefresh,
        ]
        let selected = reasonPriority.first { pendingReviewPackageBuildReasons.contains($0) } ?? defaultReason
        pendingReviewPackageBuildReasons.removeAll()
        return selected
    }
}
