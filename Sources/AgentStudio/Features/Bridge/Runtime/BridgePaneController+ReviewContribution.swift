import AgentStudioCore
import Foundation

@MainActor
extension BridgePaneController {
    func adoptInitialContributionTargetIfEligible(
        reset: ReviewPackageLoadReset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws {
        guard case .workspace(_, nil) = bridgePaneState.source else { return }
        guard let branchName = try await reviewSourceProvider.localDefaultBranch() else { return }
        guard
            isReviewPackageLoadCurrent(
                reset: reset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            ),
            let initialContributionTargetCommit
        else { return }
        let mutationResult = initialContributionTargetCommit(
            .localDefaultBranch(branchName: branchName)
        )
        guard
            isReviewPackageLoadCurrent(
                reset: reset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return }
        switch mutationResult {
        case .applied(let canonicalState), .unchanged(let canonicalState):
            bridgePaneState = canonicalState
        case .paneMissing, .notBridgePane, .notWorkspaceSource:
            break
        }
    }

    func resolveContributionRequestIfNeeded(
        _ request: BridgeReviewPipelineRequest
    ) async throws -> BridgeReviewPipelineRequest {
        guard case .workspace(_, let baseline) = bridgePaneState.source else { return request }
        guard let baseline else {
            throw BridgeProviderFailure.providerFailed(
                message: "Contribution target selection required"
            )
        }
        guard let symbolicTarget = baseline.contributionTarget else { return request }
        let capture = try await reviewSourceProvider.captureContributionComparison(
            BridgeContributionComparisonRequest(
                symbolicTarget: symbolicTarget,
                baseEndpoint: request.baseEndpoint,
                headEndpoint: request.headEndpoint,
                reviewGenerationValue: request.reviewGeneration.rawValue
            )
        )
        return try BridgeResolvedContributionRequestBuilder.build(
            request: request,
            symbolicTarget: symbolicTarget,
            capture: capture,
            reviewedSubjectLabel: reviewedSubjectLabel
        )
    }

    private var reviewedSubjectLabel: String? {
        normalizedReviewedSubject(runtime.metadata.facets.worktreeName)
            ?? normalizedReviewedSubject(runtime.metadata.checkoutRef)
    }

    private func normalizedReviewedSubject(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !normalized.isEmpty
        else { return nil }
        return normalized
    }
}
