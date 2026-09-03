import AgentStudioCore
import Foundation

@MainActor
extension BridgePaneController {
    func handleCommittedProductReviewComparisonUpdate(
        _ request: BridgeProductReviewComparisonUpdateRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> Bool {
        guard productAdmission.withValidAdmission({ true }) == true,
            let contributionTargetCommit
        else {
            productAdmissionGate.close()
            refreshAdmissionCoordinator.close()
            return false
        }
        let mutationResult = contributionTargetCommit(request.target)
        guard productAdmission.withValidAdmission({ true }) == true else { return false }
        let canonicalState: BridgePaneState
        switch mutationResult {
        case .applied(let state), .unchanged(let state):
            canonicalState = state
        case .paneMissing, .notBridgePane, .notWorkspaceSource:
            productAdmissionGate.close()
            refreshAdmissionCoordinator.close()
            return false
        }
        guard case .workspace(_, let canonicalBaseline) = canonicalState.source,
            canonicalBaseline?.contributionTarget == request.target
        else {
            productAdmissionGate.close()
            refreshAdmissionCoordinator.close()
            return false
        }

        bridgePaneState = canonicalState
        reviewComparisonTargetProjection.update(state: canonicalState)
        let reviewGeneration = nextReviewGeneration.next()
        nextReviewGeneration = reviewGeneration
        pendingComparisonReviewGeneration = reviewGeneration
        refreshAdmissionCoordinator.beginReviewComparisonAttempt(
            activeTarget: request.target,
            reviewGeneration: reviewGeneration.rawValue
        )
        _ = scheduleProductPresentationPublication()
        pendingReviewPackageBuildReasons.insert(.productResync)
        refreshAdmissionCoordinator.advanceAuthority(for: .review)
        retireActiveReviewRefreshTask()
        scheduleRetainedReviewPackageBuildIfPossible()
        return true
    }

    func adoptInitialContributionTargetIfEligible(
        reset: ReviewPackageLoadReset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws {
        guard case .workspace(_, let baseline) = bridgePaneState.source else { return }
        let resolvedDefaultTarget = try await resolveAndPublishReviewComparisonDefaultTargetIfCurrent(
            reset: reset,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
        guard baseline == nil else { return }
        guard
            let resolvedDefaultTarget,
            let initialContributionTargetCommit
        else { return }
        let mutationResult = initialContributionTargetCommit(
            .originDefaultBranch(
                remoteName: resolvedDefaultTarget.remoteName,
                branchName: resolvedDefaultTarget.branchName,
                basis: .commonCommit
            )
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
            reviewComparisonTargetProjection.update(state: canonicalState)
            guard case .workspace(_, let canonicalBaseline) = canonicalState.source,
                let activeTarget = canonicalBaseline?.contributionTarget
            else { return }
            refreshAdmissionCoordinator.beginReviewComparisonAttempt(
                activeTarget: activeTarget,
                reviewGeneration: reset.reviewGeneration.rawValue
            )
            _ = scheduleProductPresentationPublication()
        case .paneMissing, .notBridgePane, .notWorkspaceSource:
            break
        }
    }

    func resolveAndPublishReviewComparisonDefaultTargetIfCurrent(
        reset: ReviewPackageLoadReset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> BridgeReviewComparisonDefaultTargetIdentity? {
        guard
            isReviewPackageLoadCurrent(
                reset: reset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return nil }
        let resolvedDefaultTarget: BridgeReviewComparisonDefaultTargetIdentity?
        do {
            resolvedDefaultTarget = try await reviewSourceProvider.resolveReviewDefaultTarget()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            resolvedDefaultTarget = nil
        }
        guard
            isReviewPackageLoadCurrent(
                reset: reset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return nil }
        refreshAdmissionCoordinator.publishReviewComparisonDefaultTarget(resolvedDefaultTarget)
        _ = scheduleProductPresentationPublication()
        return resolvedDefaultTarget
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
