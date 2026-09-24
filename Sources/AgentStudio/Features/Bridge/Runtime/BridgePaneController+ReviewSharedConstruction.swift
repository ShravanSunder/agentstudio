import AgentStudioCore
import Foundation

extension BridgePaneController {
    static func makeReviewSharedConstructionBinder(
        coordinator: BridgeWorktreeProductConstructionCoordinator?,
        pipeline: BridgeReviewPipeline,
        provider: any BridgeReviewSourceProvider,
        reviewBinding: BridgeReviewSourceBinding?
    ) -> BridgePaneReviewSharedConstructionBinder? {
        guard let coordinator,
            provider is any BridgeSharedReviewConstructionSourceProvider,
            let reviewBinding
        else { return nil }
        return BridgePaneReviewSharedConstructionBinder(
            coordinator: coordinator,
            pipeline: pipeline,
            repositoryPath: URL(fileURLWithPath: reviewBinding.worktreeRootPath)
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
            .initialIntake,
            .productResync,
            .filesystemRefresh,
        ]
        let selected = reasonPriority.first { pendingReviewPackageBuildReasons.contains($0) } ?? defaultReason
        pendingReviewPackageBuildReasons.removeAll()
        return selected
    }
}
